#requires -Version 5.1
# ScriptRunner.ps1 - Run PowerShell scripts from the catalog; update process state

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Resolve script path
# ---------------------------------------------------------------------------

function Resolve-ScriptPath {
    <#
    .SYNOPSIS
        Resolves a relative script path to an absolute path under the project root.
        Throws if the file does not exist.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [string]$RootDir
    )

    $fullPath = Join-Path $RootDir $RelativePath
    if (-not (Test-Path $fullPath)) {
        throw "Script not found: $fullPath"
    }
    return $fullPath
}

# ---------------------------------------------------------------------------
# Convert PSCustomObject parameters to hashtable
# ---------------------------------------------------------------------------

function ConvertTo-ParameterHashtable {
    <#
    .SYNOPSIS
        Converts a PSCustomObject (from JSON) into a plain hashtable.
        Returns an empty hashtable when $null is passed.
    #>
    param($InputObject)

    if ($null -eq $InputObject) { return @{} }
    if ($InputObject -is [hashtable]) { return $InputObject }

    $ht = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $ht[$prop.Name] = $prop.Value
    }
    return $ht
}

# ---------------------------------------------------------------------------
# Invoke a single script step
# ---------------------------------------------------------------------------

function Invoke-ScriptStep {
    <#
    .SYNOPSIS
        Runs a PowerShell script referenced by a catalog item.
        Returns a hashtable: @{ Success=$bool; ScriptPath='...'; ExplorerRequired=$bool; ... }
    .DESCRIPTION
        The target script must accept two parameters:
          -Parameters  [hashtable]  — arbitrary key/value pairs from the catalog or profile.
          -DryRun      [switch]     — when present the script must avoid side-effects.
        The script signals failure by throwing an exception.
    #>
    param(
        [Parameter(Mandatory)]
        $CatalogItem,

        [Parameter(Mandatory)]
        [hashtable]$RunContext
    )

    $scriptConfig = $CatalogItem.script
    $itemId       = $CatalogItem.id
    $isDryRun     = ($RunContext.Mode -eq 'DryRun')
    $isMock       = ($RunContext.Mode -eq 'Mock')

    # Resolve the script file
    $scriptPath = Resolve-ScriptPath -RelativePath $scriptConfig.path -RootDir $RunContext.Paths.Root

    # Merge parameters
    $parameters = ConvertTo-ParameterHashtable $scriptConfig.parameters

    # Explorer restart flag
    $explorerRequired = $false
    if ($null -ne $scriptConfig.PSObject.Properties['restartExplorer'] -and $scriptConfig.restartExplorer -eq $true) {
        $explorerRequired = $true
    }

    # ---- DryRun ----
    if ($isDryRun) {
        Write-Log "WOULD RUN SCRIPT: $scriptPath" -Level INFO
        if ($parameters.Count -gt 0) {
            Write-Log "  Parameters: $($parameters | ConvertTo-Json -Compress)" -Level INFO
        }
        if ($explorerRequired) {
            Write-Log "WOULD restart Explorer (restartExplorer=true on '$itemId')" -Level INFO
        }
        return @{
            Success          = $true
            ScriptPath       = $scriptPath
            ExplorerRequired = $explorerRequired
            Notes            = @('dryRun')
        }
    }

    # ---- Mock ----
    if ($isMock) {
        Write-Log "MOCK RUN SCRIPT: $scriptPath" -Level INFO
        $delay = Get-Random -Minimum 200 -Maximum 800
        Start-Sleep -Milliseconds $delay
        Write-Log "  -> Mock succeeded." -Level INFO
        return @{
            Success          = $true
            ScriptPath       = $scriptPath
            ExplorerRequired = $explorerRequired
            Notes            = @('mock')
        }
    }

    # ---- Real ----
    try {
        Write-Log "Running script: $scriptPath" -Level INFO
        $output = & $scriptPath -Parameters $parameters -DryRun:$false
        if ($output) {
            foreach ($line in @($output)) {
                Write-Log "  $line" -Level INFO
            }
        }
        Write-Log "  -> Script succeeded." -Level INFO
        return @{
            Success          = $true
            ScriptPath       = $scriptPath
            ExplorerRequired = $explorerRequired
            Notes            = @('real')
        }
    } catch {
        Write-Log "  -> Script FAILED: $($_.Exception.Message)" -Level ERROR
        return @{
            Success          = $false
            ScriptPath       = $scriptPath
            ExplorerRequired = $false
            Error            = @{ message = $_.Exception.Message }
            Notes            = @('real')
        }
    }
}
