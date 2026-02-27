#requires -Version 5.1
# Catalog.ps1 - Load catalog, compute priorities, determine preselected IDs

Set-StrictMode -Version Latest

# Categories that are pre-checked by default
$script:DefaultSelectedCategories = @('Core', 'Dev', 'Tweaks')

function Import-Catalog {
    <#
    .SYNOPSIS
        Loads catalog.json and returns an ordered list of items with
        effective priorities resolved.
    .OUTPUTS
        [array] of PSCustomObjects sorted by effective priority.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$CatalogPath
    )

    if (-not (Test-Path $CatalogPath)) {
        throw "Catalog file not found: $CatalogPath"
    }

    $catalog = Read-JsonFile -Path $CatalogPath
    $defaultPriority = 999

    if ($catalog.defaults -and $null -ne $catalog.defaults.priority) {
        $defaultPriority = [int]$catalog.defaults.priority
    }

    # Resolve effective priority on each item
    $items = foreach ($item in $catalog.items) {
        $eff = $defaultPriority
        if ($null -ne $item.PSObject.Properties['priority'] -and $null -ne $item.priority) {
            $eff = [int]$item.priority
        }

        # Attach effectivePriority as a new property
        $item | Add-Member -NotePropertyName 'effectivePriority' -NotePropertyValue $eff -Force -PassThru
    }

    # Sort: priority asc, then category, then displayName (stable tie-break)
    $sorted = $items |
        Sort-Object -Property effectivePriority, category, displayName

    Write-SetupLog "Catalog loaded: $($sorted.Count) items from '$CatalogPath'"
    return ,$sorted   # comma forces array return even for 1 item
}

function Get-PreselectedIds {
    <#
    .SYNOPSIS
        Returns the set of item IDs that should be pre-checked in the TUI
        based on DefaultSelectedCategories.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Returns a collection of IDs — plural noun is semantically correct.')]
    param(
        [AllowEmptyCollection()]
        [Parameter(Mandatory)]
        [array]$Items
    )

    $ids = $Items |
        Where-Object { $script:DefaultSelectedCategories -contains $_.category } |
        ForEach-Object { $_.id }

    return @($ids)
}

function Get-CatalogItemById {
    <#
    .SYNOPSIS
        Returns the catalog item with the given ID, or $null.
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Items,

        [Parameter(Mandatory)]
        [string]$Id
    )

    return $Items | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

function Import-Profile {
    <#
    .SYNOPSIS
        Loads a profile JSON file and returns its contents.
    .OUTPUTS
        PSCustomObject with optional 'selectedIds' and 'overrides' properties.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath
    )

    if (-not (Test-Path $ProfilePath)) {
        throw "Profile file not found: $ProfilePath"
    }

    try {
        $profileData = Read-JsonFile -Path $ProfilePath
    } catch {
        throw "Failed to parse profile file '$ProfilePath': $_"
    }

    Write-SetupLog "Profile loaded: '$ProfilePath'"
    return $profileData
}

function Merge-ProfileOverrides {
    <#
    .SYNOPSIS
        Applies per-item winget overrides from a profile to the catalog item list.
        Only 'app' items can be overridden. 'tweak' items are left untouched.
        Returns a new array; original items are not mutated.
    .OUTPUTS
        [array] of PSCustomObjects with profile overrides applied.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Merges multiple overrides — plural noun is semantically correct.')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Items,

        [Parameter(Mandatory)]
        $ProfileData
    )

    # If no overrides section, return items as-is
    $hasOverrides = $null -ne $ProfileData.PSObject.Properties['overrides'] -and $null -ne $ProfileData.overrides
    if (-not $hasOverrides) {
        return ,$Items
    }

    $overrides = $ProfileData.overrides

    $result = foreach ($item in $Items) {
        $id          = $item.id
        $ovProp      = $overrides.PSObject.Properties[$id]

        if ($null -eq $ovProp) {
            # No override for this item — pass through unchanged
            $item
            continue
        }

        if ($item.type -eq 'app') {
            $ov = $ovProp.Value

            # Build patched winget block (only scope and override are overridable)
            $newScope    = if ($null -ne $ov.PSObject.Properties['scope']    -and $null -ne $ov.scope)    { $ov.scope    } else { $item.winget.scope    }
            $newOverride = if ($null -ne $ov.PSObject.Properties['override'])                              { $ov.override } else { $item.winget.override }

            $newWinget = [PSCustomObject]@{
                id       = $item.winget.id
                source   = $item.winget.source
                scope    = $newScope
                override = $newOverride
            }

            # Shallow-clone the item and replace the winget block
            $clone        = $item | Select-Object -Property *
            $clone.winget = $newWinget
            $clone
        } elseif ($item.type -eq 'script') {
            $ov = $ovProp.Value

            # Only 'parameters' is overridable for script items
            if ($null -ne $ov.PSObject.Properties['parameters'] -and $null -ne $ov.parameters) {
                # Shallow-clone the item and merge parameters
                $clone = $item | Select-Object -Property *

                # Build patched script block with merged parameters
                $baseParams = @{}
                if ($null -ne $item.script.PSObject.Properties['parameters'] -and $null -ne $item.script.parameters) {
                    foreach ($prop in $item.script.parameters.PSObject.Properties) {
                        $baseParams[$prop.Name] = $prop.Value
                    }
                }
                foreach ($prop in $ov.parameters.PSObject.Properties) {
                    $baseParams[$prop.Name] = $prop.Value
                }

                $newScript = [PSCustomObject]@{
                    path            = $item.script.path
                    parameters      = [PSCustomObject]$baseParams
                    restartExplorer = if ($null -ne $item.script.PSObject.Properties['restartExplorer']) { $item.script.restartExplorer } else { $false }
                }
                $clone.script = $newScript
                $clone
            } else {
                Write-SetupLog "Profile override for '$id' has no 'parameters' — ignored for script items." -Level WARN
                $item
            }
        } else {
            Write-SetupLog "Profile override for '$id' ignored — overrides are only supported for 'app' and 'script' items." -Level WARN
            $item
        }
    }

    return ,$result
}
