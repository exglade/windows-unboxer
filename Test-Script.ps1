<#
.SYNOPSIS
    Validates that a PowerShell script conforms to the script runner contract.

.DESCRIPTION
    Runs the following checks on a target script:
      1. The script file exists and is a .ps1 file.
      2. The script can run with -DryRun without throwing (non-destructive).
      3. The script can run normally and reach the end state (exit without error).
      4. The runner correctly reports the script's final status (Succeeded / Failed).

    Results are printed to the console with PASS/FAIL indicators.

.PARAMETER ScriptPath
    Path to the PowerShell script to validate.

.PARAMETER Parameters
    Optional hashtable of parameters to pass to the script.

.PARAMETER SkipRealRun
    When set, only the DryRun test is executed. Use this to avoid side-effects
    (e.g. registry writes) when testing on a real system.

.EXAMPLE
    .\Test-Script.ps1 -ScriptPath .\scripts\explorer-show-extensions.ps1
    .\Test-Script.ps1 -ScriptPath .\scripts\explorer-show-extensions.ps1 -SkipRealRun
    .\Test-Script.ps1 -ScriptPath .\scripts\explorer-show-extensions.ps1 -Parameters @{ key = 'value' }
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'CLI validation tool — requires coloured console output via Write-Host.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ScriptPath,

    [hashtable]$Parameters = @{},

    [switch]$SkipRealRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Load modules needed by the runner
# ---------------------------------------------------------------------------
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) {
    $ScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
. (Join-Path $ScriptRoot 'modules\Common.ps1')
. (Join-Path $ScriptRoot 'modules\ScriptRunner.ps1')

# Suppress log file creation
$script:LogFile = $null

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
$totalTests  = 0
$passedTests = 0
$failedTests = 0

function Write-TestResult {
    param([string]$Name, [bool]$Passed, [string]$Detail = '')
    $script:totalTests++
    if ($Passed) {
        $script:passedTests++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } else {
        $script:failedTests++
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
    }
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkGray }
}

# ---------------------------------------------------------------------------
# Resolve script path
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '  ══════════ Script Validation ══════════' -ForegroundColor Cyan
Write-Host "  Script: $ScriptPath" -ForegroundColor DarkGray
Write-Host ''

$resolvedPath = $null
try {
    $resolvedPath = Resolve-Path $ScriptPath -ErrorAction Stop | Select-Object -ExpandProperty Path
} catch {
    $null = $_ # Intentionally ignored — failure is detected in test 1
}

# ---------------------------------------------------------------------------
# Test 1: File exists and is .ps1
# ---------------------------------------------------------------------------
$exists = ($null -ne $resolvedPath) -and (Test-Path $resolvedPath) -and ($resolvedPath -like '*.ps1')
Write-TestResult -Name 'Script file exists and is .ps1' -Passed $exists -Detail $(if (-not $exists) { "Path: $ScriptPath" } else { '' })

if (-not $exists) {
    Write-Host ''
    Write-Host "  Cannot continue — script file not found." -ForegroundColor Red
    Write-Host ''
    exit 1
}

# ---------------------------------------------------------------------------
# Test 2: DryRun completes without error
# ---------------------------------------------------------------------------
$dryRunPassed = $false
$dryRunError  = ''
try {
    $null = & $resolvedPath -Parameters $Parameters -DryRun 2>&1
    $dryRunPassed = $true
} catch {
    $dryRunError = $_.Exception.Message
}
Write-TestResult -Name 'DryRun completes without error' -Passed $dryRunPassed -Detail $dryRunError

# ---------------------------------------------------------------------------
# Test 3: DryRun status via script runner
# ---------------------------------------------------------------------------
$dryRunStatusPassed = $false
$dryRunStatusError  = ''
try {
    $mockItem = [PSCustomObject]@{
        id     = 'test.script'
        type   = 'script'
        script = [PSCustomObject]@{
            path            = $resolvedPath
            parameters      = [PSCustomObject]$Parameters
            restartExplorer = $false
        }
    }
    $ctx = @{
        Mode       = 'DryRun'
        FailStepId = $null
        Paths      = @{ Root = (Split-Path $resolvedPath -Parent) }
    }
    # Override the script path to be just the filename since Root is the parent dir
    $mockItem.script.path = (Split-Path $resolvedPath -Leaf)
    $result = Invoke-ScriptStep -CatalogItem $mockItem -RunContext $ctx
    $dryRunStatusPassed = $result.Success -eq $true
    if (-not $dryRunStatusPassed) { $dryRunStatusError = 'Runner reported Success=$false in DryRun' }
} catch {
    $dryRunStatusError = $_.Exception.Message
}
Write-TestResult -Name 'Runner reports Succeeded in DryRun mode' -Passed $dryRunStatusPassed -Detail $dryRunStatusError

# ---------------------------------------------------------------------------
# Test 4: Real run completes and runner reports end state (optional)
# ---------------------------------------------------------------------------
if (-not $SkipRealRun) {
    $realRunPassed = $false
    $realRunError  = ''
    try {
        $mockItem = [PSCustomObject]@{
            id     = 'test.script'
            type   = 'script'
            script = [PSCustomObject]@{
                path            = (Split-Path $resolvedPath -Leaf)
                parameters      = [PSCustomObject]$Parameters
                restartExplorer = $false
            }
        }
        $ctx = @{
            Mode       = 'Real'
            FailStepId = $null
            Paths      = @{ Root = (Split-Path $resolvedPath -Parent) }
        }
        $result = Invoke-ScriptStep -CatalogItem $mockItem -RunContext $ctx
        $realRunPassed = $result.Success -eq $true
        if (-not $realRunPassed) { $realRunError = "Runner reported failure: $($result.Error.message)" }
    } catch {
        $realRunError = $_.Exception.Message
    }
    Write-TestResult -Name 'Real run completes and runner reports Succeeded' -Passed $realRunPassed -Detail $realRunError
} else {
    Write-Host '  [SKIP] Real run (--SkipRealRun)' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ''
if ($failedTests -gt 0) {
    Write-Host "  RESULT: $failedTests/$totalTests test(s) FAILED." -ForegroundColor Red
} else {
    Write-Host "  RESULT: $passedTests/$totalTests test(s) PASSED." -ForegroundColor Green
}
Write-Host ''

exit $(if ($failedTests -gt 0) { 1 } else { 0 })
