#requires -Version 5.1
# Catalog.Tests.ps1 - Unit tests for modules/Catalog.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\modules\Common.ps1')
    . (Join-Path $PSScriptRoot '..\modules\Catalog.ps1')

    Mock Write-Log {}

    # ---------------------------------------------------------------------------
    # Minimal catalog JSON written once for all tests
    # ---------------------------------------------------------------------------
    $script:CatalogPath = Join-Path $TestDrive 'catalog_test.json'

    $script:CatalogContent = @'
{
  "version": "1.0",
  "defaults": { "priority": 999 },
  "items": [
    {
      "id": "tweak.ext",
      "type": "script",
      "category": "Tweaks",
      "displayName": "Show extensions",
      "priority": 50,
      "script": {
        "path": "scripts/tweak-show-extensions.ps1",
        "parameters": {},
        "restartExplorer": true
      },
      "requiresReboot": false
    },
    {
      "id": "core.chrome",
      "type": "app",
      "category": "Core",
      "displayName": "Google Chrome",
      "priority": 200,
      "winget": { "id": "Google.Chrome", "source": "winget", "scope": "machine", "override": null },
      "requiresReboot": false
    },
    {
      "id": "dev.vscode",
      "type": "app",
      "category": "Dev",
      "displayName": "VS Code",
      "priority": 300,
      "winget": { "id": "Microsoft.VisualStudioCode", "source": "winget", "scope": "machine", "override": null },
      "requiresReboot": false
    },
    {
      "id": "productivity.npp",
      "type": "app",
      "category": "Productivity",
      "displayName": "Notepad++",
      "priority": 510,
      "winget": { "id": "Notepad++.Notepad++", "source": "winget", "scope": "machine", "override": null },
      "requiresReboot": false
    },
    {
      "id": "nopriority.item",
      "type": "app",
      "category": "Media",
      "displayName": "No Priority App",
      "winget": { "id": "Some.App", "source": "winget", "scope": "user", "override": null },
      "requiresReboot": false
    }
  ]
}
'@
    [System.IO.File]::WriteAllText($script:CatalogPath, $script:CatalogContent, [System.Text.Encoding]::UTF8)
    $script:Items = Import-Catalog -CatalogPath $script:CatalogPath
}

# ---------------------------------------------------------------------------
# Import-Catalog  — loading
# ---------------------------------------------------------------------------

Describe 'Import-Catalog - basic loading' {

    It 'returns an array' {
        $script:Items | Should -Not -BeNullOrEmpty
    }

    It 'loads the correct number of items' {
        $script:Items.Count | Should -Be 5
    }

    It 'throws when the catalog file does not exist' {
        { Import-Catalog -CatalogPath (Join-Path $TestDrive 'nosuch.json') } |
            Should -Throw
    }
}

# ---------------------------------------------------------------------------
# Import-Catalog  — priority assignment
# ---------------------------------------------------------------------------

Describe 'Import-Catalog - effective priority' {

    It 'uses the explicit priority when present' {
        $item = $script:Items | Where-Object { $_.id -eq 'tweak.ext' }
        $item.effectivePriority | Should -Be 50
    }

    It 'defaults missing priority to 999 (catalog default)' {
        $item = $script:Items | Where-Object { $_.id -eq 'nopriority.item' }
        $item.effectivePriority | Should -Be 999
    }

    It 'respects a custom default priority from catalog.defaults' {
        # Create a catalog that overrides the default
        $customPath = Join-Path $TestDrive 'custom_default.json'
        $json = @'
{
  "version": "1.0",
  "defaults": { "priority": 500 },
  "items": [
    { "id": "x.a", "type": "app", "category": "Core", "displayName": "Alpha",
      "winget": { "id": "A.A", "source": "winget", "scope": "machine", "override": null },
      "requiresReboot": false }
  ]
}
'@
        [System.IO.File]::WriteAllText($customPath, $json, [System.Text.Encoding]::UTF8)
        $items = Import-Catalog -CatalogPath $customPath
        $items[0].effectivePriority | Should -Be 500
    }
}

# ---------------------------------------------------------------------------
# Import-Catalog  — sort order
# ---------------------------------------------------------------------------

Describe 'Import-Catalog - sort order' {

    It 'first item has the lowest effectivePriority' {
        $script:Items[0].effectivePriority | Should -BeLessOrEqual $script:Items[-1].effectivePriority
    }

    It 'items are sorted ascending by effectivePriority' {
        $priorities = $script:Items | ForEach-Object { $_.effectivePriority }
        $sorted     = $priorities | Sort-Object
        $priorities | Should -Be $sorted
    }

    It 'tweak (priority 50) comes before core app (priority 200)' {
        $tweakIdx = [array]::IndexOf(($script:Items | ForEach-Object { $_.id }), 'tweak.ext')
        $chromeIdx= [array]::IndexOf(($script:Items | ForEach-Object { $_.id }), 'core.chrome')
        $tweakIdx | Should -BeLessThan $chromeIdx
    }

    It 'items with equal priority are sub-sorted by category then displayName' {
        # Build a catalog with two items at the same priority, different categories
        $tiedPath = Join-Path $TestDrive 'tied.json'
        $json = @'
{
  "version": "1.0",
  "defaults": { "priority": 999 },
  "items": [
    { "id": "z.z", "type": "app", "category": "Zebra", "displayName": "Zig",
      "priority": 100,
      "winget": { "id": "Z.Z", "source": "winget", "scope": "machine", "override": null },
      "requiresReboot": false },
    { "id": "a.a", "type": "app", "category": "Alpha", "displayName": "Able",
      "priority": 100,
      "winget": { "id": "A.A", "source": "winget", "scope": "machine", "override": null },
      "requiresReboot": false }
  ]
}
'@
        [System.IO.File]::WriteAllText($tiedPath, $json, [System.Text.Encoding]::UTF8)
        $items = Import-Catalog -CatalogPath $tiedPath
        $items[0].id | Should -Be 'a.a'
        $items[1].id | Should -Be 'z.z'
    }
}

# ---------------------------------------------------------------------------
# Get-PreselectedIds
# ---------------------------------------------------------------------------

Describe 'Get-PreselectedIds' {

    It 'returns an array' {
        $ids = Get-PreselectedIds -Items $script:Items
        $ids | Should -Not -BeNullOrEmpty
    }

    It 'includes Core category items' {
        $ids = Get-PreselectedIds -Items $script:Items
        $ids | Should -Contain 'core.chrome'
    }

    It 'includes Dev category items' {
        $ids = Get-PreselectedIds -Items $script:Items
        $ids | Should -Contain 'dev.vscode'
    }

    It 'includes Tweaks category items' {
        $ids = Get-PreselectedIds -Items $script:Items
        $ids | Should -Contain 'tweak.ext'
    }

    It 'excludes Productivity category items' {
        $ids = Get-PreselectedIds -Items $script:Items
        $ids | Should -Not -Contain 'productivity.npp'
    }

    It 'excludes Media category items' {
        $ids = Get-PreselectedIds -Items $script:Items
        $ids | Should -Not -Contain 'nopriority.item'
    }

    It 'returns only 3 items for the test catalog (Core:1 Dev:1 Tweaks:1)' {
        $ids = Get-PreselectedIds -Items $script:Items
        $ids.Count | Should -Be 3
    }

    It 'returns empty array for empty input' {
        $ids = @(Get-PreselectedIds -Items ([array]@()))
        $ids.Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# Get-CatalogItemById
# ---------------------------------------------------------------------------

Describe 'Get-CatalogItemById' {

    It 'returns the matching item' {
        $item = Get-CatalogItemById -Items $script:Items -Id 'dev.vscode'
        $item | Should -Not -BeNullOrEmpty
        $item.id | Should -Be 'dev.vscode'
    }

    It 'returns null when the ID does not exist' {
        $item = Get-CatalogItemById -Items $script:Items -Id 'not.real'
        $item | Should -BeNullOrEmpty
    }

    It 'returns the correct item among several' {
        $item = Get-CatalogItemById -Items $script:Items -Id 'core.chrome'
        $item.displayName | Should -Be 'Google Chrome'
    }
}

# ---------------------------------------------------------------------------
# Import-Profile
# ---------------------------------------------------------------------------

Describe 'Import-Profile' {

    It 'throws when the profile file does not exist' {
        { Import-Profile -ProfilePath (Join-Path $TestDrive 'nosuch.profile.json') } |
            Should -Throw
    }

    It 'returns an object when the file is valid' {
        $path = Join-Path $TestDrive 'profile_valid.json'
        $json = '{ "selectedIds": ["core.chrome"], "overrides": {} }'
        [System.IO.File]::WriteAllText($path, $json, [System.Text.Encoding]::UTF8)

        $result = Import-Profile -ProfilePath $path
        $result | Should -Not -BeNullOrEmpty
    }

    It 'returns selectedIds when present' {
        $path = Join-Path $TestDrive 'profile_ids.json'
        $json = '{ "selectedIds": ["core.chrome", "dev.vscode"] }'
        [System.IO.File]::WriteAllText($path, $json, [System.Text.Encoding]::UTF8)

        $result = Import-Profile -ProfilePath $path
        $result.selectedIds | Should -Contain 'core.chrome'
        $result.selectedIds | Should -Contain 'dev.vscode'
    }

    It 'tolerates a profile with no selectedIds property' {
        $path = Join-Path $TestDrive 'profile_no_ids.json'
        $json = '{ "overrides": { "core.chrome": { "scope": "user" } } }'
        [System.IO.File]::WriteAllText($path, $json, [System.Text.Encoding]::UTF8)

        { Import-Profile -ProfilePath $path } | Should -Not -Throw
    }

    It 'tolerates a profile with no overrides property' {
        $path = Join-Path $TestDrive 'profile_no_overrides.json'
        $json = '{ "selectedIds": ["core.chrome"] }'
        [System.IO.File]::WriteAllText($path, $json, [System.Text.Encoding]::UTF8)

        { Import-Profile -ProfilePath $path } | Should -Not -Throw
    }

    It 'throws on malformed JSON' {
        $path = Join-Path $TestDrive 'profile_bad.json'
        [System.IO.File]::WriteAllText($path, '{ not valid json', [System.Text.Encoding]::UTF8)

        { Import-Profile -ProfilePath $path } | Should -Throw
    }
}

# ---------------------------------------------------------------------------
# Merge-ProfileOverrides
# ---------------------------------------------------------------------------

Describe 'Merge-ProfileOverrides' {

    BeforeAll {
        # Use the shared $script:Items from the top-level BeforeAll
        $script:ChromeItem = $script:Items | Where-Object { $_.id -eq 'core.chrome' }
        $script:TweakItem  = $script:Items | Where-Object { $_.id -eq 'tweak.ext'   }
    }

    It 'applies a scope override to an app item' {
        $profile = [PSCustomObject]@{
            overrides = [PSCustomObject]@{
                'core.chrome' = [PSCustomObject]@{ scope = 'user' }
            }
        }
        $result = Merge-ProfileOverrides -Items $script:Items -Profile $profile
        $chrome = $result | Where-Object { $_.id -eq 'core.chrome' }
        $chrome.winget.scope | Should -Be 'user'
    }

    It 'applies an override-arg override to an app item' {
        $profile = [PSCustomObject]@{
            overrides = [PSCustomObject]@{
                'dev.vscode' = [PSCustomObject]@{ override = '/SILENT' }
            }
        }
        $result = Merge-ProfileOverrides -Items $script:Items -Profile $profile
        $vscode = $result | Where-Object { $_.id -eq 'dev.vscode' }
        $vscode.winget.override | Should -Be '/SILENT'
    }

    It 'does not mutate the original catalog item' {
        $originalScope = $script:ChromeItem.winget.scope
        $profile = [PSCustomObject]@{
            overrides = [PSCustomObject]@{
                'core.chrome' = [PSCustomObject]@{ scope = 'user' }
            }
        }
        $null = Merge-ProfileOverrides -Items $script:Items -Profile $profile
        $script:ChromeItem.winget.scope | Should -Be $originalScope
    }

    It 'leaves script items unchanged and emits a warning when non-parameter override is used' {
        $profile = [PSCustomObject]@{
            overrides = [PSCustomObject]@{
                'tweak.ext' = [PSCustomObject]@{ scope = 'user' }
            }
        }
        Mock Write-Log {}
        $result = Merge-ProfileOverrides -Items $script:Items -Profile $profile
        $tweak  = $result | Where-Object { $_.id -eq 'tweak.ext' }
        $tweak.type | Should -Be 'script'
        Should -Invoke Write-Log -ParameterFilter { $Message -like "*no 'parameters'*ignored*" }
    }

    It 'ignores override entries for IDs not present in the catalog' {
        $profile = [PSCustomObject]@{
            overrides = [PSCustomObject]@{
                'unknown.app' = [PSCustomObject]@{ scope = 'user' }
            }
        }
        $result = Merge-ProfileOverrides -Items $script:Items -Profile $profile
        $result.Count | Should -Be $script:Items.Count
    }

    It 'returns all items unchanged when profile has no overrides property' {
        $profile = [PSCustomObject]@{ selectedIds = @('core.chrome') }
        $result  = Merge-ProfileOverrides -Items $script:Items -Profile $profile
        $result.Count | Should -Be $script:Items.Count
        ($result | Where-Object { $_.id -eq 'core.chrome' }).winget.scope |
            Should -Be $script:ChromeItem.winget.scope
    }

    It 'preserves unaffected app items without changes' {
        $profile = [PSCustomObject]@{
            overrides = [PSCustomObject]@{
                'core.chrome' = [PSCustomObject]@{ scope = 'user' }
            }
        }
        $result = Merge-ProfileOverrides -Items $script:Items -Profile $profile
        $vscode = $result | Where-Object { $_.id -eq 'dev.vscode' }
        $vscode.winget.scope | Should -Be 'machine'
    }
}
