<#
.SYNOPSIS
    Windows 11 Fresh PC Setup tool.
    Interactive checklist -> plan generation -> execution with resume support.

.PARAMETER DryRun
    Exercise everything except side effects.
    Logs would-be commands; marks steps Succeeded without running winget/registry.

.PARAMETER Mock
    Full execution flow with fake actions (no real winget or registry writes).
    Useful for testing resume behaviour and state transitions.

.PARAMETER FailStepId
    (Only with -Mock) Simulate a failure on the step with this ID.

.PARAMETER ProfilePath
    Optional path to a profile JSON file.
    Overrides which items are pre-checked in the Main Menu and can override 'scope' / 'override'
    for individual app items. See config\profile.example.json for the file format.

.PARAMETER Silent
    Run without any user interaction. Skips the Main Menu checklist (uses pre-selected items
    from the catalog or profile), auto-confirms the execution prompt, auto-handles
    resume choices, and auto-restarts Explorer when required by tweaks.
    Pair with -ProfilePath to drive the selection from a profile file.

.EXAMPLE
    .\Setup.ps1                                          # Normal interactive run
    .\Setup.ps1 -DryRun                                  # Preview only
    .\Setup.ps1 -Mock                                    # Fake execution
    .\Setup.ps1 -Mock -FailStepId dev.vscode             # Simulate failure on VS Code step
    .\Setup.ps1 -ProfilePath .\config\profile.example.json      # Load a profile
    .\Setup.ps1 -Silent                                  # No-prompt run with default selection
    .\Setup.ps1 -Silent -ProfilePath .\config\profile.example.json  # No-prompt run with profile
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'CLI setup tool — requires coloured console output via Write-Host.')]
[CmdletBinding()]
param(
    [switch]$DryRun,

    [switch]$Mock,

    [string]$FailStepId = $null,

    [string]$ProfilePath = $null,

    [switch]$Silent
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Determine root directory (location of this script)
# ---------------------------------------------------------------------------
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) {
    $ScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

# ---------------------------------------------------------------------------
# 1. Load modules
# ---------------------------------------------------------------------------
$moduleFiles = @(
    'Common.ps1',
    'Catalog.ps1',
    'MainMenu.ps1',
    'PlanState.ps1',
    'ScriptRunner.ps1',
    'Executor.ps1'
)

foreach ($mod in $moduleFiles) {
    $modPath = Join-Path $ScriptRoot "modules\$mod"
    if (-not (Test-Path $modPath)) {
        Write-Error "Required module not found: $modPath"
        exit 1
    }
    . $modPath
}

# ---------------------------------------------------------------------------
# 2. Build RunContext
# ---------------------------------------------------------------------------
$mode = 'Real'
if ($DryRun)  { $mode = 'DryRun' }
elseif ($Mock){ $mode = 'Mock'   }

$Paths = Get-ArtifactPaths -RootDir $ScriptRoot

$RunContext = @{
    Mode       = $mode
    FailStepId = $FailStepId
    Paths      = $Paths
    Silent     = $Silent.IsPresent
}

# ---------------------------------------------------------------------------
# 3. Initialize directories and logging
# ---------------------------------------------------------------------------
Initialize-ArtifactDirectories -Paths $Paths
Initialize-Log -LogDir $Paths.Logs

Write-SetupLog "=== PC Setup starting ==="
Write-SetupLog "Mode=$mode  Silent=$($Silent.IsPresent)  FailStepId=$(if($FailStepId) { $FailStepId } else { '<none>' })  ProfilePath=$(if($ProfilePath) { $ProfilePath } else { '<none>' })"

# Mode banner
switch ($mode) {
    'DryRun' {
        Write-Host ''
        Write-Host '  *** DRY RUN MODE — no changes will be made ***' -ForegroundColor Magenta
    }
    'Mock' {
        Write-Host ''
        Write-Host '  *** MOCK MODE — fake execution, no real installs/registry changes ***' -ForegroundColor Magenta
        if ($FailStepId) {
            Write-Host "  *** Will simulate failure on step: $FailStepId ***" -ForegroundColor Yellow
        }
    }
}
if ($Silent) {
    Write-Host ''
    Write-Host '  *** SILENT MODE — running without user interaction ***' -ForegroundColor Cyan
}
Write-Host ''

# ---------------------------------------------------------------------------
# 4. Prerequisite checks
# ---------------------------------------------------------------------------
Assert-Prerequisites -RunContext $RunContext

# ---------------------------------------------------------------------------
# 5. Load catalog
# ---------------------------------------------------------------------------
Write-SetupLog "Loading catalog: $($Paths.Catalog)"
$catalogItems   = Import-Catalog -CatalogPath $Paths.Catalog
$preselectedIds = Get-PreselectedIds -Items $catalogItems

# Apply profile if supplied
if ($ProfilePath) {
    $profileData  = Import-Profile -ProfilePath $ProfilePath
    $catalogItems = Merge-ProfileOverrides -Items $catalogItems -ProfileData $profileData

    $profileHasSelectedIds = $null -ne $profileData.PSObject.Properties['selectedIds'] -and
                             $null -ne $profileData.selectedIds
    if ($profileHasSelectedIds) {
        $preselectedIds = @($profileData.selectedIds)
        Write-SetupLog "Profile pre-selection ($($preselectedIds.Count) item(s)): $($preselectedIds -join ', ')"
    } else {
        $preselectedIds = @()
        Write-SetupLog 'Profile loaded without selectedIds — no items pre-selected.'
    }
}

# ---------------------------------------------------------------------------
# 6. Resume check
# ---------------------------------------------------------------------------
$resumeOption = 'All'   # default for fresh start

if ((Test-Path $Paths.State) -and (Test-Path $Paths.Plan)) {
    Write-SetupLog 'Existing state found — showing resume menu.'

    try {
        $existingState = Read-JsonFile -Path $Paths.State
        $existingPlan  = Read-JsonFile -Path $Paths.Plan

        # Check if any step is not Succeeded
        $incompletePart = $existingState.steps | Where-Object { $_.status -ne 'Succeeded' -and $_.status -ne 'Skipped' }

        if ($incompletePart) {
            if ($Silent) {
                Write-SetupLog 'Silent mode — auto-resuming pending steps.'
                $stateToUse = ConvertTo-MutableState -StateObj $existingState
                $planToUse  = ConvertTo-MutablePlan  -PlanObj  $existingPlan

                Write-SetupLog "Resuming pending steps..."
                Invoke-Plan -Plan $planToUse -State $stateToUse `
                    -CatalogItems $catalogItems `
                    -RunContext   $RunContext `
                    -ResumeOption 'ResumePending'
                Show-Report -State $stateToUse -Paths $Paths
                exit 0
            }

            $menuResult = Invoke-ResumeMenu -State $existingState

            if (-not $menuResult -or $menuResult.Action -eq 'Cancel') {
                Write-SetupLog 'User cancelled.'
                exit 0
            }

            switch ($menuResult.Action) {

                'ViewReport' {
                    Show-Report -State $existingState -Paths $Paths
                    Write-Host '  Press any key to exit...' -NoNewline
                    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                    exit 0
                }

                'StartOver' {
                    Write-SetupLog 'Starting over — archiving previous artifacts.'
                    Invoke-ArchiveArtifacts -Paths $Paths
                    # Fall through to plan mode below
                }

                'ResumePending' {
                    $resumeOption  = 'ResumePending'

                    # Convert PSCustomObject state to mutable hashtable
                    $stateToUse = ConvertTo-MutableState -StateObj $existingState
                    $planToUse  = ConvertTo-MutablePlan  -PlanObj  $existingPlan

                    Write-SetupLog "Resuming pending steps..."
                    Invoke-Plan -Plan $planToUse -State $stateToUse `
                        -CatalogItems $catalogItems `
                        -RunContext   $RunContext `
                        -ResumeOption $resumeOption
                    Show-Report -State $stateToUse -Paths $Paths
                    exit 0
                }

                'RerunFailed' {
                    $resumeOption  = 'RerunFailed'

                    $stateToUse = ConvertTo-MutableState -StateObj $existingState
                    $planToUse  = ConvertTo-MutablePlan  -PlanObj  $existingPlan

                    Write-SetupLog "Re-running failed steps..."
                    Invoke-Plan -Plan $planToUse -State $stateToUse `
                        -CatalogItems $catalogItems `
                        -RunContext   $RunContext `
                        -ResumeOption $resumeOption
                    Show-Report -State $stateToUse -Paths $Paths
                    exit 0
                }
            }
            # If we reach here it was StartOver — fall through to plan mode
        } else {
            Write-SetupLog 'All steps already succeeded. Nothing to resume.'
            Show-Report -State $existingState -Paths $Paths

            if ($Silent) {
                Write-SetupLog 'Silent mode — exiting (all steps already complete).'
                exit 0
            }

            Write-Host '  All steps are already complete. Start over? (Y/N): ' -NoNewline
            $k = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            Write-Host $k.Character
            if ($k.Character -ne 'Y' -and $k.Character -ne 'y') { exit 0 }

            Invoke-ArchiveArtifacts -Paths $Paths
        }
    } catch {
        Write-SetupLog "Failed to load existing state/plan: $_  — will start fresh." -Level WARN
    }
}

# ---------------------------------------------------------------------------
# 7. Plan mode — checklist -> plan -> state -> confirmation
# ---------------------------------------------------------------------------
Write-SetupLog 'Starting plan mode — showing checklist.'

if ($Silent) {
    Write-SetupLog 'Silent mode — skipping Main Menu checklist, using pre-selected items.'
    $selectedIds = @($preselectedIds | Where-Object { $_ })
} else {
    $selectedIds = Invoke-MainMenu -Items $catalogItems -PreselectedIds $preselectedIds `
        -Title 'Windows 11 PC Setup — select items to install/configure'

    if ($null -eq $selectedIds) {
        Write-SetupLog 'User cancelled checklist (ESC).'
        Write-Host ''
        Write-Host '  Setup cancelled.' -ForegroundColor Yellow
        exit 0
    }

    $selectedIds = @($selectedIds)
}

if ($selectedIds.Count -eq 0) {
    Write-Host ''
    Write-Host '  No items selected. Nothing to do.' -ForegroundColor Yellow
    exit 0
}

Write-SetupLog "Selected $($selectedIds.Count) item(s): $($selectedIds -join ', ')"

# Build and persist plan
$plan = New-Plan -AllItems $catalogItems -SelectedIds $selectedIds
Write-JsonAtomic -Path $Paths.Plan -InputObject $plan
Write-SetupLog "Plan written: $($Paths.Plan)"

# Build and persist initial state
$state = New-State -Plan $plan
Write-JsonAtomic -Path $Paths.State -InputObject $state
Write-SetupLog "State written: $($Paths.State)"

# Show plan summary and confirm
Clear-Host
Show-PlanSummary -Plan $plan -AllItems $catalogItems

Write-Host "  Artifacts will be saved to: $($Paths.Artifacts)" -ForegroundColor DarkGray
Write-Host ''

if ($mode -eq 'DryRun') {
    Write-Host '  [DRY RUN] Proceeding without confirmation...' -ForegroundColor Magenta
} elseif ($Silent) {
    Write-Host '  [SILENT] Proceeding without confirmation...' -ForegroundColor Cyan
} else {
    Write-Host '  Proceed with installation? (Y/N): ' -NoNewline
    $confirm = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    Write-Host $confirm.Character

    if ($confirm.Character -ne 'Y' -and $confirm.Character -ne 'y') {
        Write-SetupLog 'User declined confirmation.'
        Write-Host '  Setup cancelled.' -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ''
Write-SetupLog 'Executing plan...'

# ---------------------------------------------------------------------------
# 8. Execute
# ---------------------------------------------------------------------------
Invoke-Plan -Plan $plan -State $state `
    -CatalogItems $catalogItems `
    -RunContext   $RunContext `
    -ResumeOption 'All'

# ---------------------------------------------------------------------------
# 9. Final report
# ---------------------------------------------------------------------------
Show-Report -State $state -Paths $Paths

Write-SetupLog '=== PC Setup finished ==='

# ---------------------------------------------------------------------------
# Helper: Convert PSCustomObject -> mutable hashtable for state/plan
# ---------------------------------------------------------------------------

function ConvertTo-MutableState {
    param($StateObj)

    $steps = foreach ($s in $StateObj.steps) {
        [ordered]@{
            id         = $s.id
            status     = $s.status
            startedAt  = $s.startedAt
            endedAt    = $s.endedAt
            error      = $s.error
            notes      = if ($s.notes)      { @($s.notes)      } else { @() }
            command    = $s.command
            targetPath = $s.targetPath
        }
    }

    return [ordered]@{
        stateVersion = $StateObj.stateVersion
        planHash     = $StateObj.planHash
        startedAt    = $StateObj.startedAt
        steps        = @($steps)
    }
}

function ConvertTo-MutablePlan {
    param($PlanObj)

    $steps = foreach ($s in $PlanObj.steps) {
        $step = [ordered]@{
            id   = $s.id
            type = $s.type
        }
        if ($null -ne $s.PSObject.Properties['parameters'] -and $null -ne $s.parameters) {
            $step.parameters = @{ override = $s.parameters.override }
        }
        $step
    }

    return [ordered]@{
        planVersion = $PlanObj.planVersion
        generatedAt = $PlanObj.generatedAt
        environment = [ordered]@{
            computerName = $PlanObj.environment.computerName
            osVersion    = $PlanObj.environment.osVersion
        }
        steps = @($steps)
    }
}
