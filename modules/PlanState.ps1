#requires -Version 5.1
# PlanState.ps1 - Build plan.json / state.json, load existing state, resume menu

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Plan hash (for detecting plan changes between runs)
# ---------------------------------------------------------------------------

function Get-PlanHash {
    param(
        [Parameter(Mandatory)]
        [array]$Steps
    )

    $ids  = ($Steps | ForEach-Object { $_.id }) -join '|'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($ids)
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $hash  = $sha.ComputeHash($bytes)
    return ([BitConverter]::ToString($hash) -replace '-', '').Substring(0, 12).ToLower()
}

# ---------------------------------------------------------------------------
# Build plan
# ---------------------------------------------------------------------------

function New-Plan {
    <#
    .SYNOPSIS
        Builds a plan object from the selected catalog item IDs.
        Steps are ordered by effectivePriority, then category, then displayName.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'New-Plan builds an in-memory hashtable — no system state is changed.')]
    param(
        [AllowEmptyCollection()]
        [Parameter(Mandatory)]
        [array]$AllItems,

        [AllowEmptyCollection()]
        [Parameter(Mandatory)]
        [string[]]$SelectedIds
    )

    # Filter and sort
    $selected = $AllItems | Where-Object { $SelectedIds -contains $_.id }
    $sorted   = $selected | Sort-Object -Property effectivePriority, category, displayName

    $steps = foreach ($item in $sorted) {
        if ($item.type -eq 'app') {
            [ordered]@{
                id         = $item.id
                type       = 'app'
                parameters = [ordered]@{
                    override = if ($item.winget -and $null -ne $item.winget.override) { $item.winget.override } else { $null }
                }
            }
        } elseif ($item.type -eq 'script') {
            $scriptParams = @{}
            if ($null -ne $item.script -and $null -ne $item.script.PSObject.Properties['parameters'] -and $null -ne $item.script.parameters) {
                foreach ($prop in $item.script.parameters.PSObject.Properties) {
                    $scriptParams[$prop.Name] = $prop.Value
                }
            }
            [ordered]@{
                id         = $item.id
                type       = 'script'
                parameters = $scriptParams
            }
        } else {
            [ordered]@{
                id   = $item.id
                type = $item.type
            }
        }
    }

    $plan = [ordered]@{
        planVersion = '1.0'
        generatedAt = (Get-Date -Format 'o')
        environment = [ordered]@{
            computerName = $env:COMPUTERNAME
            osVersion    = (Get-OsVersion)
        }
        steps = @($steps)
    }

    return $plan
}

# ---------------------------------------------------------------------------
# Build state
# ---------------------------------------------------------------------------

function New-State {
    <#
    .SYNOPSIS
        Creates a fresh state object from a plan. All steps start as Pending.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory state object — does not modify system state.')]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Plan
    )

    $stepStates = foreach ($step in $Plan.steps) {
        [ordered]@{
            id        = $step.id
            status    = 'Pending'
            startedAt = $null
            endedAt   = $null
            error     = $null
            notes     = @()
            command   = $null
            targetPath = $null
        }
    }

    $state = [ordered]@{
        stateVersion = '1.0'
        planHash     = (Get-PlanHash -Steps $Plan.steps)
        startedAt    = (Get-Date -Format 'o')
        steps        = @($stepStates)
    }

    return $state
}

# ---------------------------------------------------------------------------
# State helpers
# ---------------------------------------------------------------------------

function Get-StateStepById {
    param(
        [Parameter(Mandatory)]
        $State,

        [Parameter(Mandatory)]
        [string]$Id
    )

    return $State.steps | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

function Update-StateStep {
    <#
    .SYNOPSIS
        Updates a step in the state hashtable in-place.
        Call Write-JsonAtomic after this to persist.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates an in-memory hashtable — does not modify system state directly.')]
    param(
        [Parameter(Mandatory)]
        $State,

        [Parameter(Mandatory)]
        [string]$Id,

        [string]$Status      = $null,
        [string]$StartedAt   = $null,
        [string]$EndedAt     = $null,
        $ErrorInfo           = $null,
        [string[]]$Notes     = $null,
        [string]$Command     = $null,
        [string]$TargetPath  = $null
    )

    $step = $State.steps | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $step) { throw "State step not found: $Id" }

    if ($Status)    { $step.status    = $Status    }
    if ($StartedAt) { $step.startedAt = $StartedAt }
    if ($EndedAt)   { $step.endedAt   = $EndedAt   }
    if ($null -ne $ErrorInfo)  { $step.error  = $ErrorInfo  }
    if ($null -ne $Notes)      { $step.notes  = $Notes      }
    if ($null -ne $Command)    { $step.command = $Command   }
    if ($null -ne $TargetPath) { $step.targetPath = $TargetPath }
}

# ---------------------------------------------------------------------------
# Resume menu
# ---------------------------------------------------------------------------

function Invoke-ResumeMenu {
    <#
    .SYNOPSIS
        Shows the resume/start-over menu when an existing state is found.
        Returns a hashtable: @{ Action = 'ResumePending'|'RerunFailed'|'StartOver'|'ViewReport'|'Cancel' }
        or $null on ESC/cancel.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'CLI tool — interactive menu requires coloured console output.')]
    param(
        [Parameter(Mandatory)]
        $State
    )

    $pendingCount    = @($State.steps | Where-Object { $_.status -eq 'Pending'    }).Count
    $inProgressCount = @($State.steps | Where-Object { $_.status -eq 'InProgress' }).Count
    $failedCount     = @($State.steps | Where-Object { $_.status -eq 'Failed'     }).Count
    $succeededCount  = @($State.steps | Where-Object { $_.status -eq 'Succeeded'  }).Count
    $totalCount      = $State.steps.Count

    Write-Host ''
    Write-Host '  ╔══════════════════════════════════════════════╗' -ForegroundColor Cyan
    Write-Host '  ║           Setup State Detected               ║' -ForegroundColor Cyan
    Write-Host '  ╚══════════════════════════════════════════════╝' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "  Total steps   : $totalCount"
    Write-Host "  Succeeded     : $succeededCount" -ForegroundColor Green
    Write-Host "  Pending       : $($pendingCount + $inProgressCount)" -ForegroundColor Yellow
    Write-Host "  Failed        : $failedCount" -ForegroundColor Red
    Write-Host ''
    Write-Host '  What would you like to do?' -ForegroundColor White
    Write-Host ''
    Write-Host '  [1] Resume pending steps'
    Write-Host '  [2] Re-run failed steps only'
    Write-Host '  [3] Start over (archive previous artifacts)'
    Write-Host '  [4] View report'
    Write-Host '  [5] Cancel'
    Write-Host ''

    while ($true) {
        Write-Host '  Enter choice (1-5): ' -NoNewline
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        Write-Host $key.Character

        switch ($key.Character) {
            '1' { return @{ Action = 'ResumePending'  } }
            '2' { return @{ Action = 'RerunFailed'    } }
            '3' { return @{ Action = 'StartOver'      } }
            '4' { return @{ Action = 'ViewReport'     } }
            '5' { return @{ Action = 'Cancel'         } }
            default { Write-Host '  Invalid choice. Try again.' -ForegroundColor Yellow }
        }
    }
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

function Show-Report {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'CLI tool — report display requires coloured console output.')]
    param(
        [Parameter(Mandatory)]
        $State,

        [Parameter(Mandatory)]
        [hashtable]$Paths
    )

    Write-Host ''
    Write-Host '  ════════════════ Setup Report ════════════════' -ForegroundColor Cyan
    Write-Host ''

    $grouped = $State.steps | Group-Object status
    foreach ($g in $grouped) {
        $color = switch ($g.Name) {
            'Succeeded' { 'Green'  }
            'Failed'    { 'Red'    }
            'Skipped'   { 'DarkGray' }
            default     { 'Yellow' }
        }
        Write-Host "  [$($g.Name)] ($($g.Count))" -ForegroundColor $color
        foreach ($s in $g.Group) {
            $err = if ($s.error) { "  ERROR: $($s.error.message)" } else { '' }
            Write-Host "    - $($s.id)$err"
        }
    }

    Write-Host ''
    Write-Host "  Plan  : $($Paths.Plan)"  -ForegroundColor DarkGray
    Write-Host "  State : $($Paths.State)" -ForegroundColor DarkGray
    Write-Host "  Logs  : $($Paths.Logs)"  -ForegroundColor DarkGray
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Plan summary (pre-execution confirmation)
# ---------------------------------------------------------------------------

function Show-PlanSummary {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'CLI tool — plan summary requires coloured console output.')]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Plan,

        [Parameter(Mandatory)]
        [array]$AllItems
    )

    Write-Host ''
    Write-Host '  ══════════════ Execution Plan ══════════════' -ForegroundColor Cyan
    Write-Host ''

    $num = 1
    foreach ($step in $Plan.steps) {
        $item  = $AllItems | Where-Object { $_.id -eq $step.id } | Select-Object -First 1
        $label = if ($item) { $item.displayName } else { $step.id }
        $pri   = if ($item) { $item.effectivePriority } else { '???' }
        Write-Host "  $($num.ToString().PadLeft(2)). [$pri] $label  ($($step.type))"
        $num++
    }

    Write-Host ''
    Write-Host "  Total: $($Plan.steps.Count) step(s)" -ForegroundColor White
    Write-Host ''
}
