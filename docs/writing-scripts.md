# Writing Scripts for Windows Unboxer

This guide explains how to write PowerShell scripts that work with the Windows Unboxer script runner.

## Script Contract

Every script **must** accept two parameters:

```powershell
param(
    [hashtable]$Parameters = @{},
    [switch]$DryRun
)
```

| Parameter | Type | Description |
| --- | --- | --- |
| `$Parameters` | `hashtable` | Key/value pairs from the catalog `script.parameters` (merged with any profile overrides). |
| `$DryRun` | `switch` | When present, the script must **not** make any changes. Log what _would_ happen instead. |

## Success and Failure

- **Success** — the script exits normally (no exception).
- **Failure** — the script throws an exception. The runner catches it, marks the step as `Failed`, and logs the error message.

Do **not** use `exit` codes to signal failure; use `throw`:

```powershell
if (-not $ok) {
    throw "Something went wrong: $detail"
}
```

## DryRun Mode

When `$DryRun` is set, the script must avoid all side-effects (registry writes, file system changes, network calls, etc.) and instead output what it _would_ do:

```powershell
if ($DryRun) {
    Write-Output "WOULD SET: HKCU:\...\HideFileExt = 0"
    return
}
```

The runner relies on DryRun for safe previews and for the `tools/Test-Script.ps1` validator.

## Using Parameters

Parameters are passed as a hashtable. Access them with standard hashtable syntax:

```powershell
$fontName = $Parameters['fontName']
if (-not $fontName) { $fontName = 'FiraCode' }
```

Parameters are defined in the catalog:

```json
{
  "script": {
    "path": "scripts/install-nerd-font.ps1",
    "parameters": { "fontName": "FiraCode" }
  }
}
```

And can be overridden per-profile:

```json
{
  "overrides": {
    "dev.nerdfont": {
      "parameters": { "fontName": "CascadiaCode" }
    }
  }
}
```

## Output

Use `Write-Output` for informational messages. The runner logs each line:

```powershell
Write-Output "Installed font: $fontName"
```

Avoid `Write-Host` inside scripts — it bypasses the runner's output capture.

## Explorer Restart

If your script modifies Explorer-visible settings (e.g. registry tweaks for file visibility), set `restartExplorer` to `true` in the catalog entry. The runner handles the restart prompt — the script itself should **not** restart Explorer.

```json
{
  "script": {
    "path": "scripts/explorer-show-extensions.ps1",
    "restartExplorer": true
  }
}
```

## Catalog Entry

Add your script to `config/catalog.json`:

```json
{
  "id": "dev.nerdfont",
  "type": "script",
  "category": "Dev",
  "displayName": "Install Nerd Font",
  "priority": 340,
  "script": {
    "path": "scripts/install-nerd-font.ps1",
    "parameters": { "fontName": "FiraCode" },
    "restartExplorer": false
  },
  "requiresReboot": false
}
```

| Field | Required | Description |
| --- | --- | --- |
| `path` | Yes | Relative path to the `.ps1` file from the project root. |
| `parameters` | No | Default parameters passed to the script. |
| `restartExplorer` | No | Set `true` if the script changes Explorer settings. Defaults to `false`. |

## Testing Your Script

Use the built-in script validator:

```powershell
.\tools\Test-Script.ps1 -ScriptPath .\scripts\my-script.ps1
```

The validator checks:

1. The script file exists and is a `.ps1` file.
2. The script runs with `-DryRun` without error.
3. The runner reports `Succeeded` status in DryRun mode.
4. (Optional) The script runs normally and reaches the end state.

Add `-SkipRealRun` to skip the real execution test (useful when the script has system-wide side-effects):

```powershell
.\tools\Test-Script.ps1 -ScriptPath .\scripts\my-script.ps1 -SkipRealRun
```

Pass custom parameters:

```powershell
.\tools\Test-Script.ps1 -ScriptPath .\scripts\my-script.ps1 -Parameters @{ fontName = 'CascadiaCode' }
```

## Example: Registry Tweak Script

```powershell
<#
.SYNOPSIS
    Shows file extensions in Windows Explorer.
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
```

## Example: Post-Install Setup Script

```powershell
<#
.SYNOPSIS
    Installs Oh My Posh default Nerd Font and configures $PROFILE.
#>
param(
    [hashtable]$Parameters = @{},
    [switch]$DryRun
)

$fontName = if ($Parameters['fontName']) { $Parameters['fontName'] } else { 'FiraCode' }

if ($DryRun) {
    Write-Output "WOULD install Nerd Font: $fontName"
    Write-Output "WOULD add oh-my-posh init to `$PROFILE"
    return
}

# Install font
oh-my-posh font install $fontName
Write-Output "Installed Nerd Font: $fontName"

# Add to profile
$initLine = 'oh-my-posh init pwsh | Invoke-Expression'
$profilePath = $PROFILE.CurrentUserCurrentHost

if (-not (Test-Path $profilePath)) {
    New-Item -Path $profilePath -ItemType File -Force | Out-Null
}

$content = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
if ($content -notmatch [regex]::Escape($initLine)) {
    $initLine + "`n" + $content | Set-Content $profilePath -Force
    Write-Output "Prepended oh-my-posh init to $profilePath"
} else {
    Write-Output "oh-my-posh init already in $profilePath — skipped"
}
```
