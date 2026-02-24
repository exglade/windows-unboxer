#requires -Version 5.1
# Tweaks.Tests.ps1 - Unit tests for modules/Tweaks.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\modules\Common.ps1')
    . (Join-Path $PSScriptRoot '..\modules\Tweaks.ps1')

    Mock Write-Log {}

    # ---------------------------------------------------------------------------
    # Reusable catalog items
    # ---------------------------------------------------------------------------
    function script:New-TweakItem {
        param(
            [string]$Id            = 'tweak.ext',
            [string]$Kind          = 'registry',
            [bool]  $RestartExp    = $false,
            [array] $Actions       = @(
                [PSCustomObject]@{
                    path  = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
                    name  = 'HideFileExt'
                    type  = 'DWord'
                    value = 0
                }
            )
        )
        [PSCustomObject]@{
            id   = $Id
            type = 'tweak'
            tweak = [PSCustomObject]@{
                kind            = $Kind
                actions         = $Actions
                restartExplorer = $RestartExp
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Convert-ToTestRegistryPath
# ---------------------------------------------------------------------------

Describe 'Convert-ToTestRegistryPath' {

    It 'converts HKCU\ form to test base path' {
        $result = Convert-ToTestRegistryPath 'HKCU\Software\Foo'
        $result | Should -Be 'HKCU:\Software\KaiSetup\TestTweaks\HKCU\Software\Foo'
    }

    It 'strips the PS-drive colon from the original path before embedding' {
        $result = Convert-ToTestRegistryPath 'HKCU:\Software\Foo'
        # Original colon form should be normalised — no "HKCU:\" inside the path
        $result | Should -Be 'HKCU:\Software\KaiSetup\TestTweaks\HKCU\Software\Foo'
    }

    It 'does not double a trailing backslash from the original' {
        $result = Convert-ToTestRegistryPath 'HKCU\Software\Foo\'
        $result | Should -Not -Match '\\\\'
    }

    It 'uses the default test base HKCU:\Software\KaiSetup\TestTweaks' {
        $result = Convert-ToTestRegistryPath 'HKCU\Anything'
        $result | Should -BeLike 'HKCU:\Software\KaiSetup\TestTweaks\*'
    }

    It 'respects a custom TestBase parameter' {
        $result = Convert-ToTestRegistryPath 'HKCU\Foo' -TestBase 'HKCU:\MyCustomBase'
        $result | Should -BeLike 'HKCU:\MyCustomBase\*'
    }

    It 'preserves the full tail of the original path' {
        $longPath = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        $result   = Convert-ToTestRegistryPath $longPath
        $result   | Should -BeLike '*\HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    }
}

# ---------------------------------------------------------------------------
# ConvertTo-PSDrivePath
# ---------------------------------------------------------------------------

Describe 'ConvertTo-PSDrivePath' {

    It 'converts HKCU\ to HKCU:\' {
        ConvertTo-PSDrivePath 'HKCU\Software\Foo' | Should -BeLike 'HKCU:\*'
    }

    It 'leaves HKCU:\ unchanged' {
        ConvertTo-PSDrivePath 'HKCU:\Software\Foo' | Should -Be 'HKCU:\Software\Foo'
    }

    It 'converts HKLM\ to HKLM:\' {
        ConvertTo-PSDrivePath 'HKLM\Software\Bar' | Should -BeLike 'HKLM:\*'
    }

    It 'leaves HKLM:\ unchanged' {
        ConvertTo-PSDrivePath 'HKLM:\SOFTWARE\Bar' | Should -Be 'HKLM:\SOFTWARE\Bar'
    }

    It 'converts HKCR\ to HKCR:\' {
        ConvertTo-PSDrivePath 'HKCR\SomeClass' | Should -BeLike 'HKCR:\*'
    }

    It 'converts HKU\ to HKU:\' {
        ConvertTo-PSDrivePath 'HKU\.Default' | Should -BeLike 'HKU:\*'
    }
}

# ---------------------------------------------------------------------------
# Invoke-TweakStep  — DryRun mode (no real registry writes)
# ---------------------------------------------------------------------------

Describe 'Invoke-TweakStep - DryRun mode' {

    BeforeAll {
        Mock Set-RegistryValue {}
        Mock New-Item {}
        Mock Set-ItemProperty {}
    }

    It 'returns Success=$true' {
        $ctx    = @{ Mode = 'DryRun'; TweakTarget = 'Real' }
        $item   = script:New-TweakItem
        $result = Invoke-TweakStep -CatalogItem $item -RunContext $ctx
        $result.Success | Should -BeTrue
    }

    It 'does NOT call Set-RegistryValue in DryRun' {
        $ctx  = @{ Mode = 'DryRun'; TweakTarget = 'Real' }
        $item = script:New-TweakItem
        Invoke-TweakStep -CatalogItem $item -RunContext $ctx | Out-Null
        Should -Invoke Set-RegistryValue -Times 0
    }

    It 'returns ExplorerRequired=$true when restartExplorer=true' {
        $ctx    = @{ Mode = 'DryRun'; TweakTarget = 'Real' }
        $item   = script:New-TweakItem -RestartExp $true
        $result = Invoke-TweakStep -CatalogItem $item -RunContext $ctx
        $result.ExplorerRequired | Should -BeTrue
    }

    It 'returns ExplorerRequired=$false when restartExplorer=false' {
        $ctx    = @{ Mode = 'DryRun'; TweakTarget = 'Real' }
        $item   = script:New-TweakItem -RestartExp $false
        $result = Invoke-TweakStep -CatalogItem $item -RunContext $ctx
        $result.ExplorerRequired | Should -BeFalse
    }

    It 'handles unsupported kind gracefully — returns Success=$true' {
        $ctx  = @{ Mode = 'DryRun'; TweakTarget = 'Real' }
        $item = script:New-TweakItem -Kind 'unsupported'
        $result = Invoke-TweakStep -CatalogItem $item -RunContext $ctx
        $result.Success | Should -BeTrue
    }
}

# ---------------------------------------------------------------------------
# Invoke-TweakStep  — Mock + Test target (writes to test registry path)
# ---------------------------------------------------------------------------

Describe 'Invoke-TweakStep - Mock mode with Test target' {

    BeforeAll {
        # Capture calls to Set-RegistryValue so we can inspect the path
        Mock Set-RegistryValue {}
    }

    It 'returns Success=$true' {
        $ctx    = @{ Mode = 'Mock'; TweakTarget = 'Test' }
        $item   = script:New-TweakItem
        $result = Invoke-TweakStep -CatalogItem $item -RunContext $ctx
        $result.Success | Should -BeTrue
    }

    It 'calls Set-RegistryValue exactly once for a single-action tweak' {
        $ctx  = @{ Mode = 'Mock'; TweakTarget = 'Test' }
        $item = script:New-TweakItem
        Invoke-TweakStep -CatalogItem $item -RunContext $ctx | Out-Null
        Should -Invoke Set-RegistryValue -Times 1
    }

    It 'calls Set-RegistryValue with a test-base path (not the real Explorer key)' {
        $ctx  = @{ Mode = 'Mock'; TweakTarget = 'Test' }
        $item = script:New-TweakItem
        Invoke-TweakStep -CatalogItem $item -RunContext $ctx | Out-Null
        Should -Invoke Set-RegistryValue -Times 1 -ParameterFilter {
            $Path -like 'HKCU:\Software\KaiSetup\TestTweaks\*'
        }
    }

    It 'calls Set-RegistryValue twice for a two-action tweak' {
        $twoActions = @(
            [PSCustomObject]@{ path = 'HKCU\Foo'; name = 'A'; type = 'DWord'; value = 1 },
            [PSCustomObject]@{ path = 'HKCU\Foo'; name = 'B'; type = 'DWord'; value = 2 }
        )
        $ctx  = @{ Mode = 'Mock'; TweakTarget = 'Test' }
        $item = script:New-TweakItem -Actions $twoActions
        Invoke-TweakStep -CatalogItem $item -RunContext $ctx | Out-Null
        Should -Invoke Set-RegistryValue -Times 2
    }

    It 'returns correct TargetPaths array' {
        $ctx    = @{ Mode = 'Mock'; TweakTarget = 'Test' }
        $item   = script:New-TweakItem
        $result = Invoke-TweakStep -CatalogItem $item -RunContext $ctx
        $result.TargetPaths.Count | Should -Be 1
        $result.TargetPaths[0]    | Should -BeLike 'HKCU:\Software\KaiSetup\TestTweaks\*'
    }
}

# ---------------------------------------------------------------------------
# Invoke-TweakStep  — Mock + Real target
# ---------------------------------------------------------------------------

Describe 'Invoke-TweakStep - Mock mode with Real target' {

    BeforeAll {
        Mock Set-RegistryValue {}
    }

    It 'calls Set-RegistryValue with the real (PS-drive) path' {
        $ctx  = @{ Mode = 'Mock'; TweakTarget = 'Real' }
        $item = script:New-TweakItem
        Invoke-TweakStep -CatalogItem $item -RunContext $ctx | Out-Null
        Should -Invoke Set-RegistryValue -Times 1 -ParameterFilter {
            $Path -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        }
    }

    It 'does NOT use the KaiSetup\TestTweaks base path' {
        $ctx  = @{ Mode = 'Mock'; TweakTarget = 'Real' }
        $item = script:New-TweakItem
        Invoke-TweakStep -CatalogItem $item -RunContext $ctx | Out-Null
        Should -Invoke Set-RegistryValue -Times 0 -ParameterFilter {
            $Path -like '*KaiSetup*'
        }
    }
}
