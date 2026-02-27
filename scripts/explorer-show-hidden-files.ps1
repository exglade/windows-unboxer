<#
.SYNOPSIS
    Shows hidden files and protected operating system files in Windows Explorer.
.DESCRIPTION
    Modifies two registry values under HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced:
    - Hidden = 1 (show hidden files)
    - ShowSuperHidden = 1 (show protected OS files)
.PARAMETER Parameters
    Optional hashtable of additional parameters (unused by this script).
.PARAMETER DryRun
    When present, logs what would be done without making changes.
#>
# PSScriptAnalyzer: $Parameters is required by the script runner contract even
# when unused by this particular script.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Parameters',
    Justification = 'Required by the script runner contract.')]
param(
    [hashtable]$Parameters = @{},
    [switch]$DryRun
)

$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$actions = @(
    @{ Name = 'Hidden';        Value = 1; Type = 'DWord' },
    @{ Name = 'ShowSuperHidden'; Value = 1; Type = 'DWord' }
)

foreach ($action in $actions) {
    if ($DryRun) {
        Write-Output "WOULD SET: $registryPath [$($action.Name)] = $($action.Value) (Type: $($action.Type))"
        continue
    }

    if (-not (Test-Path $registryPath)) {
        New-Item -Path $registryPath -Force | Out-Null
    }

    Set-ItemProperty -LiteralPath $registryPath -Name $action.Name -Value $action.Value -Type $action.Type -Force
    Write-Output "Set: $registryPath [$($action.Name)] = $($action.Value)"
}
