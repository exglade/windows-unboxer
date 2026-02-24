#requires -Version 5.1
# Tweaks.ps1 - Apply registry tweaks; optionally restart Explorer

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Registry path rewriting (Test target)
# ---------------------------------------------------------------------------

function Convert-ToTestRegistryPath {
    <#
    .SYNOPSIS
        Rewrites a registry path to a safe test location under
        HKCU:\Software\KaiSetup\TestTweaks\<original-path>.
    .EXAMPLE
        Convert-ToTestRegistryPath 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        # => HKCU:\Software\KaiSetup\TestTweaks\HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OriginalPath,

        [string]$TestBase = 'HKCU:\Software\KaiSetup\TestTweaks'
    )

    # Normalise: remove trailing backslashes, collapse any double backslashes
    $normalised = $OriginalPath.TrimEnd('\') -replace '\\\\', '\'

    # Remove PowerShell drive-colon form if present (e.g. HKCU:\ -> HKCU\)
    $normalised = $normalised -replace '^([A-Za-z]+):\\', '$1\'

    # Combine with test base (test base already uses PS drive form with colon)
    return "$TestBase\$normalised"
}

# ---------------------------------------------------------------------------
# Low-level registry setter
# ---------------------------------------------------------------------------

function Set-RegistryValue {
    <#
    .SYNOPSIS
        Creates/sets a registry value, creating the key path if required.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,       # PowerShell drive form (HKCU:\...)

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Type,       # 'DWord', 'String', 'QWord', etc.

        [Parameter(Mandatory)]
        $Value
    )

    # Ensure the key exists
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type $Type -Force
}

# ---------------------------------------------------------------------------
# Normalize a catalog registry path to a PS-drive path
# ---------------------------------------------------------------------------

function ConvertTo-PSDrivePath {
    param([Parameter(Mandatory)][string]$Path)

    # Handle HKCU\... or HKCU:\...
    $p = $Path -replace '^HKCU:\\', 'HKCU:\' `
               -replace '^HKCU\\',  'HKCU:\' `
               -replace '^HKLM:\\', 'HKLM:\' `
               -replace '^HKLM\\',  'HKLM:\' `
               -replace '^HKCR:\\', 'HKCR:\' `
               -replace '^HKCR\\',  'HKCR:\' `
               -replace '^HKU:\\',  'HKU:\'  `
               -replace '^HKU\\',   'HKU:\'

    return $p
}

# ---------------------------------------------------------------------------
# Explorer restart
# ---------------------------------------------------------------------------

function Restart-Explorer {
    [CmdletBinding()]
    param()

    Write-Log 'Restarting Explorer...' -Level INFO

    # Stop all explorer instances
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 1000

    # Shell restarts Explorer automatically; if not, start it
    $running = Get-Process -Name explorer -ErrorAction SilentlyContinue
    if (-not $running) {
        Start-Process explorer.exe
        Start-Sleep -Milliseconds 1500
    }

    Write-Log 'Explorer restarted.' -Level INFO
}

# ---------------------------------------------------------------------------
# Apply a single tweak item
# ---------------------------------------------------------------------------

function Invoke-TweakStep {
    <#
    .SYNOPSIS
        Applies registry actions from a tweak catalog item.
        Returns a hashtable: @{ Success=$true; TargetPaths=@(...) }
    #>
    param(
        [Parameter(Mandatory)]
        $CatalogItem,           # full item from catalog, with .tweak block

        [Parameter(Mandatory)]
        [hashtable]$RunContext  # .Mode, .TweakTarget
    )

    $tweak  = $CatalogItem.tweak
    $itemId = $CatalogItem.id

    if ($tweak.kind -ne 'registry') {
        Write-Log "Tweak '$itemId': unsupported kind '$($tweak.kind)' — skipping." -Level WARN
        return @{ Success = $true; TargetPaths = @() }
    }

    $targetPaths      = [System.Collections.Generic.List[string]]::new()
    $explorerNeeded   = $false
    $isTest           = ($RunContext.TweakTarget -eq 'Test')
    $isDryRun         = ($RunContext.Mode -eq 'DryRun')

    foreach ($action in $tweak.actions) {
        $rawPath = $action.path
        $psPath  = ConvertTo-PSDrivePath $rawPath

        if ($isTest) {
            $psPath = Convert-ToTestRegistryPath -OriginalPath $rawPath
        }

        $targetPaths.Add($psPath)

        if ($isDryRun) {
            Write-Log "WOULD SET: $psPath  [$($action.name)] = $($action.value)  (Type: $($action.type))" -Level INFO
        } else {
            Write-Log "Setting registry: $psPath  [$($action.name)] = $($action.value)"
            try {
                Set-RegistryValue -Path $psPath -Name $action.name -Type $action.type -Value $action.value
                Write-Log "  -> OK" -Level INFO
            } catch {
                throw "Registry write failed for $psPath\$($action.name): $_"
            }
        }
    }

    # Explorer restart
    if ($tweak.restartExplorer -eq $true) {
        $explorerNeeded = $true
    }

    if ($explorerNeeded) {
        if ($isDryRun) {
            Write-Log "WOULD restart Explorer (restartExplorer=true on '$itemId')" -Level INFO
        } elseif ($isTest) {
            Write-Log "Would restart Explorer — skipped in Test target mode." -Level INFO
        } else {
            # Deferred: return flag so executor can prompt once at end
            Write-Log "Explorer restart requested by '$itemId'" -Level INFO
        }
    }

    return @{
        Success          = $true
        TargetPaths      = $targetPaths.ToArray()
        ExplorerRequired = $explorerNeeded
    }
}

# ---------------------------------------------------------------------------
# Post-execution Explorer prompt
# ---------------------------------------------------------------------------

function Invoke-ExplorerRestartPrompt {
    <#
    .SYNOPSIS
        Prompts user to restart Explorer after all tweaks are done.
        Skipped in DryRun and when TweakTarget=Test.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$RunContext
    )

    if ($RunContext.Mode -eq 'DryRun' -or $RunContext.TweakTarget -eq 'Test') {
        return
    }

    if ($RunContext.Silent) {
        Write-Log 'Silent mode — restarting Explorer automatically.' -Level INFO
        Restart-Explorer
        return
    }

    Write-Host ''
    Write-Host '  Some tweaks requested an Explorer restart.' -ForegroundColor Yellow
    Write-Host '  Restart Explorer now? (Y/N): ' -NoNewline

    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    Write-Host $key.Character

    if ($key.Character -eq 'Y' -or $key.Character -eq 'y') {
        Restart-Explorer
    } else {
        Write-Log 'Explorer restart deferred by user.' -Level INFO
    }
}
