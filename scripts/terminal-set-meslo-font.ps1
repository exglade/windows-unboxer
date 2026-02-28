<#
.SYNOPSIS
    Sets Windows Terminal default font to Meslo Nerd Font.
.DESCRIPTION
    Updates Windows Terminal settings (profiles.defaults.font.face) to use
    MesloLGM Nerd Font. Supports both stable and preview package paths.
.PARAMETER Parameters
    Optional hashtable of parameters.
    - fontFace: Font face to set (default: MesloLGM Nerd Font)
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

function Get-OrCreateObjectProperty {
    param(
        [Parameter(Mandatory)]
        [object]$Object,
        [Parameter(Mandatory)]
        [string]$Name
    )

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) {
        $value = [PSCustomObject]@{}
        if ($null -eq $prop) {
            $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $value
        } else {
            $prop.Value = $value
        }
        return $value
    }

    return $prop.Value
}

$fontFace = 'MesloLGM Nerd Font'
if ($Parameters.ContainsKey('fontFace') -and $Parameters['fontFace']) {
    $fontFace = [string]$Parameters['fontFace']
}

$terminalPackageCandidates = @(
    'Microsoft.WindowsTerminal_8wekyb3d8bbwe',
    'Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe'
)

$settingsPath = $null
foreach ($packageName in $terminalPackageCandidates) {
    $candidate = Join-Path $env:LOCALAPPDATA "Packages\$packageName\LocalState\settings.json"
    if (Test-Path -LiteralPath $candidate) {
        $settingsPath = $candidate
        break
    }
}

if (-not $settingsPath) {
    throw 'Windows Terminal settings.json not found. Launch Windows Terminal at least once, then retry.'
}

if ($DryRun) {
    Write-Output "WOULD SET: profiles.defaults.font.face = $fontFace"
    Write-Output "WOULD UPDATE: $settingsPath"
    return
}

$raw = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction SilentlyContinue
if ($null -eq $raw) { $raw = '{}' }

$settings = ConvertFrom-JsonC -Content $raw
if ($null -eq $settings) {
    $settings = [PSCustomObject]@{}
}

$profiles = Get-OrCreateObjectProperty -Object $settings -Name 'profiles'
$defaults = Get-OrCreateObjectProperty -Object $profiles -Name 'defaults'
$font     = Get-OrCreateObjectProperty -Object $defaults -Name 'font'

$faceProperty = $font.PSObject.Properties['face']
if ($null -eq $faceProperty) {
    $font | Add-Member -NotePropertyName 'face' -NotePropertyValue $fontFace
} else {
    $faceProperty.Value = $fontFace
}

$json = $settings | ConvertTo-Json -Depth 20
Set-Content -LiteralPath $settingsPath -Value $json -Encoding UTF8
Write-Output "Set Windows Terminal default font to '$fontFace' in $settingsPath"
