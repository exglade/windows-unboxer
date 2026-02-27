#requires -Version 5.1
# Executor.ps1 - Execute plan steps, update state, log results

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Winget runner
# ---------------------------------------------------------------------------

function Build-WingetCommand {
    <#
    .SYNOPSIS
        Builds the winget install command string for a catalog item.
    #>
    param(
        [Parameter(Mandatory)]
        $CatalogItem
    )

    $w    = $CatalogItem.winget
    $cmd  = "winget install --id $($w.id) --exact --accept-package-agreements --accept-source-agreements"

    if ($w.source)   { $cmd += " --source $($w.source)" }
    if ($w.scope)    { $cmd += " --scope $($w.scope)"   }
    if ($w.override) { $cmd += " --override `"$($w.override)`"" }

    return $cmd
}

function Invoke-WingetInstall {
    <#
    .SYNOPSIS
        Runs a winget install command. Returns @{ Success=$bool; Output='...' }.
        Treats "already installed" as success.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$LogDir
    )

    $ts      = Get-Date -Format 'HHmmss_fff'
    $logFile = Join-Path $LogDir "winget_$ts.log"

    Write-Log "EXEC: $Command"

    # Launch via cmd /c to capture both stdout+stderr
    $pInfo                        = [System.Diagnostics.ProcessStartInfo]::new('cmd.exe', "/c $Command")
    $pInfo.RedirectStandardOutput = $true
    $pInfo.RedirectStandardError  = $true
    $pInfo.UseShellExecute        = $false
    $pInfo.CreateNoWindow         = $true

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $pInfo

    $sbOut = [System.Text.StringBuilder]::new()
    $sbErr = [System.Text.StringBuilder]::new()

    $proc.OutputDataReceived += { param($s, $e); if ($null -ne $e.Data) { [void]$sbOut.AppendLine($e.Data) } }
    $proc.ErrorDataReceived  += { param($s, $e); if ($null -ne $e.Data) { [void]$sbErr.AppendLine($e.Data) } }

    [void]$proc.Start()
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
    $proc.WaitForExit()

    $exitCode  = $proc.ExitCode
    $combined  = $sbOut.ToString() + $sbErr.ToString()

    # Save to per-step log
    try { [System.IO.File]::WriteAllText($logFile, $combined, [System.Text.Encoding]::UTF8) } catch {}

    # winget exit codes:
    #   0       = success
    #   0x8A15002B (-1978335189) = already installed (APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED)
    # Also catch textual "already installed" strings for older winget versions
    $alreadyInstalled = (
        $exitCode -eq -1978335189 -or
        $exitCode -eq 0x8A150046  -or
        ($combined -match 'already installed')
    )

    if ($exitCode -eq 0 -or $alreadyInstalled) {
        if ($alreadyInstalled -and $exitCode -ne 0) {
            Write-Log "  -> Already installed (treated as success). Exit: $exitCode"
        } else {
            Write-Log "  -> Succeeded. Exit: $exitCode"
        }
        return @{ Success = $true;  Output = $combined; ExitCode = $exitCode }
    } else {
        Write-Log "  -> FAILED. Exit: $exitCode" -Level ERROR
        return @{ Success = $false; Output = $combined; ExitCode = $exitCode }
    }
}

# ---------------------------------------------------------------------------
# App step
# ---------------------------------------------------------------------------

function Invoke-AppStep {
    <#
    .SYNOPSIS
        Handles a single 'app' step. Returns @{ Success=...; Command=...; Error=... }
    #>
    param(
        [Parameter(Mandatory)]
        $Step,

        [Parameter(Mandatory)]
        $CatalogItem,

        [Parameter(Mandatory)]
        [hashtable]$RunContext,

        [Parameter(Mandatory)]
        [hashtable]$Paths
    )

    $cmd = Build-WingetCommand -CatalogItem $CatalogItem

    switch ($RunContext.Mode) {

        'DryRun' {
            Write-Log "WOULD RUN: $cmd" -Level INFO
            return @{ Success = $true; Command = $cmd; Error = $null; Notes = @('dryRun'); TargetPaths = @() }
        }

        'Mock' {
            # Simulated failure?
            if ($RunContext.FailStepId -and $RunContext.FailStepId -eq $Step.id) {
                Write-Log "MOCK FAIL: $($Step.id) (simulated failure)" -Level WARN
                return @{
                    Success     = $false
                    Command     = $cmd
                    Error       = @{ message = 'Simulated failure for testing'; exitCode = -1 }
                    Notes       = @('mock', 'simulatedFailure')
                    TargetPaths = @()
                }
            }

            # Simulate work
            $delay = Get-Random -Minimum 200 -Maximum 800
            Write-Log "MOCK: $cmd  (sleeping ${delay}ms)"
            Start-Sleep -Milliseconds $delay
            Write-Log "  -> Mock succeeded."
            return @{ Success = $true; Command = $cmd; Error = $null; Notes = @('mock'); TargetPaths = @() }
        }

        'Real' {
            $result = Invoke-WingetInstall -Command $cmd -LogDir $Paths.Logs
            if ($result.Success) {
                return @{ Success = $true;  Command = $cmd; Error = $null;    Notes = @('real'); TargetPaths = @() }
            } else {
                return @{
                    Success     = $false
                    Command     = $cmd
                    Error       = @{ message = "winget exited with code $($result.ExitCode)"; exitCode = $result.ExitCode }
                    Notes       = @('real')
                    TargetPaths = @()
                }
            }
        }

        default {
            throw "Unknown run mode: $($RunContext.Mode)"
        }
    }
}

# ---------------------------------------------------------------------------
# Script step
# ---------------------------------------------------------------------------

function Invoke-ScriptStepDispatch {
    <#
    .SYNOPSIS
        Handles a single 'script' step. Returns @{ Success=...; ScriptPath=...; Error=...; ExplorerRequired=... }
    #>
    param(
        [Parameter(Mandatory)]
        $Step,

        [Parameter(Mandatory)]
        $CatalogItem,

        [Parameter(Mandatory)]
        [hashtable]$RunContext
    )

    if ($RunContext.Mode -eq 'Mock' -and $RunContext.FailStepId -and $RunContext.FailStepId -eq $Step.id) {
        Write-Log "MOCK FAIL: $($Step.id) (simulated failure on script)" -Level WARN
        return @{
            Success          = $false
            ScriptPath       = $null
            ExplorerRequired = $false
            Error            = @{ message = 'Simulated failure for testing' }
            Notes            = @('mock', 'simulatedFailure')
        }
    }

    try {
        $result = Invoke-ScriptStep -CatalogItem $CatalogItem -RunContext $RunContext

        return @{
            Success          = $result['Success']
            ScriptPath       = $result['ScriptPath']
            ExplorerRequired = if ($result['ExplorerRequired']) { $result['ExplorerRequired'] } else { $false }
            Error            = if ($result['Error']) { $result['Error'] } else { $null }
            Notes            = $result['Notes']
        }
    } catch {
        return @{
            Success          = $false
            ScriptPath       = $null
            ExplorerRequired = $false
            Error            = @{ message = $_.Exception.Message }
            Notes            = @($RunContext.Mode.ToLower())
        }
    }
}

# ---------------------------------------------------------------------------
# Main plan executor
# ---------------------------------------------------------------------------

function Invoke-Plan {
    <#
    .SYNOPSIS
        Executes all eligible steps from the plan, updating state after each one.
        Stops on first failure (stop-on-failure policy).

    .PARAMETER Plan
        The loaded plan hashtable.

    .PARAMETER State
        The state hashtable (mutated in place; persisted after each step).

    .PARAMETER CatalogItems
        All catalog items for lookup.

    .PARAMETER RunContext
        Hashtable: Mode, TweakTarget, FailStepId, Paths, ...

    .PARAMETER ResumeOption
        'ResumePending' | 'RerunFailed' | 'All'
    #>
    param(
        [Parameter(Mandatory)]
        $Plan,

        [Parameter(Mandatory)]
        $State,

        [Parameter(Mandatory)]
        [array]$CatalogItems,

        [Parameter(Mandatory)]
        [hashtable]$RunContext,

        [string]$ResumeOption = 'All'
    )

    $statePath = $RunContext.Paths.State

    # Determine which statuses qualify for this run
    $eligibleStatuses = switch ($ResumeOption) {
        'ResumePending' { @('Pending', 'InProgress') }
        'RerunFailed'   { @('Failed')                }
        default         { @('Pending', 'InProgress', 'Failed') }
    }

    $explorerRestartNeeded = $false
    $totalSteps            = 0
    $succeededSteps        = 0
    $failedSteps           = 0

    foreach ($step in $Plan.steps) {
        $stateStep = $State.steps | Where-Object { $_.id -eq $step.id } | Select-Object -First 1

        if (-not $stateStep) {
            Write-Log "Step '$($step.id)' not found in state — skipping." -Level WARN
            continue
        }

        # Skip steps not in eligible statuses
        if ($eligibleStatuses -notcontains $stateStep.status) {
            Write-Log "Step '$($step.id)' status='$($stateStep.status)' — skipping (not eligible for '$ResumeOption')."
            continue
        }

        $totalSteps++
        $catalogItem = $CatalogItems | Where-Object { $_.id -eq $step.id } | Select-Object -First 1

        if (-not $catalogItem) {
            Write-Log "Catalog item not found for '$($step.id)' — marking Failed." -Level WARN
            Update-StateStep -State $State -Id $step.id `
                -Status 'Failed' -StartedAt (Get-Date -Format 'o') -EndedAt (Get-Date -Format 'o') `
                -ErrorInfo @{ message = "Catalog item not found: $($step.id)" }
            Write-JsonAtomic -Path $statePath -InputObject $State
            $failedSteps++
            break
        }

        # Mark InProgress
        Write-Log "--- Starting step: $($step.id) ($($step.type)) ---"
        Update-StateStep -State $State -Id $step.id `
            -Status 'InProgress' -StartedAt (Get-Date -Format 'o')
        Write-JsonAtomic -Path $statePath -InputObject $State

        # Dispatch by type
        $result = $null
        try {
            if ($step.type -eq 'app') {
                $result = Invoke-AppStep -Step $step -CatalogItem $catalogItem -RunContext $RunContext -Paths $RunContext.Paths
            } elseif ($step.type -eq 'script') {
                $result = Invoke-ScriptStepDispatch -Step $step -CatalogItem $catalogItem -RunContext $RunContext
                if ($result.ExplorerRequired -and $result.Success) {
                    $explorerRestartNeeded = $true
                }
            } else {
                throw "Unknown step type: $($step.type)"
            }
        } catch {
            $result = @{
                Success     = $false
                Error       = @{ message = $_.Exception.Message }
                Notes       = @('exception')
                TargetPaths = @()
            }
        }

        # Update state
        $endedAt    = Get-Date -Format 'o'
        $targetPath = if ($result['TargetPaths']) { $result['TargetPaths'] -join '; ' } else { $null }
        if ($result.Success) {
            $succeededSteps++
            Update-StateStep -State $State -Id $step.id `
                -Status    'Succeeded' `
                -EndedAt   $endedAt `
                -ErrorInfo $null `
                -Notes     ($result.Notes) `
                -Command   ($result['Command']) `
                -TargetPath $targetPath
            Write-Log "Step '$($step.id)' SUCCEEDED."
        } else {
            $failedSteps++
            Update-StateStep -State $State -Id $step.id `
                -Status    'Failed' `
                -EndedAt   $endedAt `
                -ErrorInfo ($result['Error']) `
                -Notes     ($result.Notes) `
                -Command   ($result['Command'])
            Write-Log "Step '$($step.id)' FAILED: $(if ($result['Error']) { $result['Error'].message } else { 'Unknown error' })" -Level ERROR

            # Stop on first failure
            Write-Log 'Stopping execution due to step failure (stop-on-failure policy).' -Level WARN
            Write-JsonAtomic -Path $statePath -InputObject $State
            break
        }

        Write-JsonAtomic -Path $statePath -InputObject $State
    }

    # Explorer restart post-loop
    if ($explorerRestartNeeded) {
        Invoke-ExplorerRestartPrompt -RunContext $RunContext
    }

    # Final summary
    Write-Host ''
    Write-Host '  ════════════════ Execution Complete ════════════════' -ForegroundColor Cyan
    Write-Host "  Steps run      : $totalSteps"
    Write-Host "  Succeeded      : $succeededSteps" -ForegroundColor Green
    if ($failedSteps -gt 0) {
        Write-Host "  Failed         : $failedSteps" -ForegroundColor Red
    } else {
        Write-Host "  Failed         : $failedSteps"
    }

    $pendingLeft = @($State.steps | Where-Object { $_.status -eq 'Pending' }).Count
    if ($pendingLeft -gt 0) {
        Write-Host "  Still pending  : $pendingLeft (re-run to resume)" -ForegroundColor Yellow
    }

    Write-Host ''
}
