<#
.SYNOPSIS
    Installs a recommended Nerd Font for Oh My Posh and prepends init to PowerShell profile.
.DESCRIPTION
    Installs a Nerd Font via `oh-my-posh font install`, then prepends
    `oh-my-posh init pwsh | Invoke-Expression` to `$PROFILE.CurrentUserCurrentHost`
    when the init line does not already exist.
.PARAMETER Parameters
    Optional parameters.
    - fontName: Nerd Font name for `oh-my-posh font install` (default: meslo).
.PARAMETER DryRun
    When present, logs what would be done without making changes.
#>
param(
    [hashtable]$Parameters = @{},
    [switch]$DryRun
)

$fontName = 'meslo'
if ($Parameters.ContainsKey('fontName') -and $Parameters['fontName']) {
    $fontName = [string]$Parameters['fontName']
}

$initLine    = 'oh-my-posh init pwsh | Invoke-Expression'
$profilePath = $PROFILE.CurrentUserCurrentHost

if ($DryRun) {
    Write-Output "WOULD RUN: oh-my-posh font install $fontName"
    Write-Output "WOULD PREPEND: $initLine"
    Write-Output "WOULD UPDATE: $profilePath"
    return
}

if (-not (Get-Command 'oh-my-posh' -ErrorAction SilentlyContinue)) {
    throw 'oh-my-posh is not installed or not available in PATH.'
}

& oh-my-posh font install $fontName
if ($LASTEXITCODE -ne 0) {
    throw "oh-my-posh font install $fontName failed (exit code $LASTEXITCODE)."
}

$profileDir = Split-Path -Parent $profilePath
if (-not (Test-Path -LiteralPath $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

$content = Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue
if ($null -eq $content) {
    $content = ''
}

if ($content -match [regex]::Escape($initLine)) {
    Write-Output "oh-my-posh init already present in $profilePath — skipped"
    return
}

$newContent = if ([string]::IsNullOrWhiteSpace($content)) {
    "$initLine`r`n"
} else {
    "$initLine`r`n$content"
}

Set-Content -LiteralPath $profilePath -Value $newContent -Encoding UTF8
Write-Output "Prepended oh-my-posh init to $profilePath"
