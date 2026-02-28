<#
.SYNOPSIS
    Sets Visual Studio Code default terminal font to Meslo Nerd Font.
.DESCRIPTION
    Updates VS Code user settings (terminal.integrated.fontFamily) to use
    MesloLGM Nerd Font.
.PARAMETER Parameters
    Optional hashtable of parameters.
    - fontFamily: Font family to set (default: MesloLGM Nerd Font)
.PARAMETER DryRun
    When present, logs what would be done without making changes.
#>
param(
    [hashtable]$Parameters = @{},
    [switch]$DryRun
)

function ConvertFrom-JsonC {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $withoutBlockComments = [regex]::Replace($Content, '/\*.*?\*/', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $withoutLineComments  = [regex]::Replace($withoutBlockComments, '(?m)^\s*//.*$', '')
    $withoutTrailingCommas = [regex]::Replace($withoutLineComments, ',\s*([}\]])', '$1')

    if ([string]::IsNullOrWhiteSpace($withoutTrailingCommas)) {
        return [PSCustomObject]@{}
    }

    return $withoutTrailingCommas | ConvertFrom-Json
}

$fontFamily = 'MesloLGM Nerd Font'
if ($Parameters.ContainsKey('fontFamily') -and $Parameters['fontFamily']) {
    $fontFamily = [string]$Parameters['fontFamily']
}

$settingsPath = Join-Path $env:APPDATA 'Code\User\settings.json'
$settingsDir  = Split-Path -Parent $settingsPath

if ($DryRun) {
    Write-Output "WOULD SET: terminal.integrated.fontFamily = $fontFamily"
    Write-Output "WOULD UPDATE: $settingsPath"
    return
}

if (-not (Test-Path -LiteralPath $settingsDir)) {
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $settingsPath)) {
    Set-Content -LiteralPath $settingsPath -Value '{}' -Encoding UTF8
}

$raw = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction SilentlyContinue
if ($null -eq $raw) { $raw = '{}' }

$settings = ConvertFrom-JsonC -Content $raw
if ($null -eq $settings) {
    $settings = [PSCustomObject]@{}
}

$fontProperty = $settings.PSObject.Properties['terminal.integrated.fontFamily']
if ($null -eq $fontProperty) {
    $settings | Add-Member -NotePropertyName 'terminal.integrated.fontFamily' -NotePropertyValue $fontFamily
} else {
    $fontProperty.Value = $fontFamily
}

$json = $settings | ConvertTo-Json -Depth 20
Set-Content -LiteralPath $settingsPath -Value $json -Encoding UTF8
Write-Output "Set VS Code terminal font to '$fontFamily' in $settingsPath"
