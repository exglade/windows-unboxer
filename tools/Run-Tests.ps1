<#
.SYNOPSIS
    Runs all Pester unit tests for the PC Setup tool.

.PARAMETER TestPath
    Optional path to a single test file or directory. Defaults to .\tests\.

.PARAMETER Output
    Pester output verbosity: Normal (default), Detailed, Diagnostic, Minimal, None.

.PARAMETER PassThru
    Return the Pester result object (useful for CI pipelines).

.EXAMPLE
    .\tools\Run-Tests.ps1
    .\tools\Run-Tests.ps1 -Output Detailed
    .\tools\Run-Tests.ps1 -TestPath .\tests\Common.Tests.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Test runner — requires coloured console output via Write-Host.')]
[CmdletBinding()]
param(
    [string]$TestPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tests'),

    [ValidateSet('Normal', 'Detailed', 'Diagnostic', 'Minimal', 'None')]
    [string]$Output = 'Normal',

    [switch]$PassThru
)

Set-StrictMode -Off  # Relax strict mode here; individual test files set their own

# ---------------------------------------------------------------------------
# Require Pester 5
# ---------------------------------------------------------------------------
$pester = Get-Module Pester -ListAvailable |
    Where-Object { $_.Version -ge [Version]'5.0.0' } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $pester) {
    Write-Error 'Pester 5.0+ is required. Run: Install-Module Pester -MinimumVersion 5.0 -Force -Scope CurrentUser'
    exit 1
}

Import-Module $pester.Path -Force

# ---------------------------------------------------------------------------
# Configure and run
# ---------------------------------------------------------------------------
$cfg                      = New-PesterConfiguration
$cfg.Run.Path             = $TestPath
$cfg.Output.Verbosity     = $Output
$cfg.Run.PassThru         = $true           # always capture result internally

# Show code coverage summary in Detailed mode
if ($Output -eq 'Detailed' -or $Output -eq 'Diagnostic') {
    $cfg.CodeCoverage.Enabled = $true
    $cfg.CodeCoverage.Path    = (Join-Path (Split-Path $PSScriptRoot -Parent) 'modules\*.ps1')
}

Write-Host ''
Write-Host '  Running PC Setup unit tests...' -ForegroundColor Cyan
Write-Host "  Test path : $TestPath" -ForegroundColor DarkGray
Write-Host "  Verbosity : $Output"   -ForegroundColor DarkGray
Write-Host ''

$result = Invoke-Pester -Configuration $cfg

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ''
if ($result.FailedCount -gt 0) {
    Write-Host "  FAILED: $($result.FailedCount) test(s) failed out of $($result.TotalCount)." -ForegroundColor Red
} else {
    Write-Host "  PASSED: $($result.PassedCount)/$($result.TotalCount) test(s) passed." -ForegroundColor Green
}
Write-Host ''

if ($PassThru) { return $result }

# Exit non-zero for CI pipelines
if ($result.FailedCount -gt 0) { exit 1 } else { exit 0 }
