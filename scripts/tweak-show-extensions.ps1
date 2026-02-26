<#
.SYNOPSIS
    Shows file extensions in Windows Explorer by setting HideFileExt to 0.
.DESCRIPTION
    Modifies the registry value HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\HideFileExt
    to 0, making file extensions visible in Windows Explorer.
.PARAMETER Parameters
    Optional hashtable of additional parameters (unused by this script).
.PARAMETER DryRun
    When present, logs what would be done without making changes.
#>
param(
    [hashtable]$Parameters = @{},
    [switch]$DryRun
)

$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$name         = 'HideFileExt'
$value        = 0
$type         = 'DWord'

if ($DryRun) {
    Write-Output "WOULD SET: $registryPath [$name] = $value (Type: $type)"
    return
}

if (-not (Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}

Set-ItemProperty -LiteralPath $registryPath -Name $name -Value $value -Type $type -Force
Write-Output "Set: $registryPath [$name] = $value"
