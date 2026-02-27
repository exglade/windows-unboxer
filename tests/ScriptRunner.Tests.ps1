#requires -Version 5.1
# ScriptRunner.Tests.ps1 - Unit tests for modules/ScriptRunner.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\modules\Common.ps1')
    . (Join-Path $PSScriptRoot '..\modules\ScriptRunner.ps1')

    Mock Write-SetupLog {}

    # ---------------------------------------------------------------------------
    # Helpers
    # ---------------------------------------------------------------------------
    function script:New-TestPaths {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
        param()
        return @{
            Root      = $TestDrive
            Artifacts = $TestDrive
            Logs      = $TestDrive
            Plan      = (Join-Path $TestDrive 'plan.json')
            State     = (Join-Path $TestDrive 'state.json')
        }
    }

    function script:New-Ctx {
        param(
            [string]$Mode = 'DryRun'
        )
        @{
            Mode       = $Mode
            FailStepId = $null
            Paths      = (script:New-TestPaths)
        }
    }

    function script:New-ScriptItem {
        param(
            [string]$Id               = 'tweak.ext',
            [string]$ScriptPath       = 'test-script.ps1',
            [hashtable]$Parameters    = @{},
            [bool]$RestartExplorer    = $false
        )
        [PSCustomObject]@{
            id     = $Id
            type   = 'script'
            script = [PSCustomObject]@{
                path            = $ScriptPath
                parameters      = [PSCustomObject]$Parameters
                restartExplorer = $RestartExplorer
            }
        }
    }

    # Create test scripts in $TestDrive
    $script:SuccessScript = Join-Path $TestDrive 'test-script.ps1'
    Set-Content -Path $script:SuccessScript -Value @'
param(
    [hashtable]$Parameters = @{},
    [switch]$DryRun
)
if ($DryRun) {
    Write-Output "WOULD RUN: test-script"
    return
}
Write-Output "Ran: test-script"
'@

    $script:FailScript = Join-Path $TestDrive 'fail-script.ps1'
    Set-Content -Path $script:FailScript -Value @'
param(
    [hashtable]$Parameters = @{},
    [switch]$DryRun
)
throw "Script intentionally failed"
'@

    $script:ParamScript = Join-Path $TestDrive 'param-script.ps1'
    Set-Content -Path $script:ParamScript -Value @'
param(
    [hashtable]$Parameters = @{},
    [switch]$DryRun
)
if ($DryRun) {
    Write-Output "WOULD RUN with key=$($Parameters['key'])"
    return
}
Write-Output "Ran with key=$($Parameters['key'])"
'@
}

# ---------------------------------------------------------------------------
# Resolve-ScriptPath
# ---------------------------------------------------------------------------

Describe 'Resolve-ScriptPath' {

    It 'resolves an existing script path' {
        $result = Resolve-ScriptPath -RelativePath 'test-script.ps1' -RootDir $TestDrive
        $result | Should -Be (Join-Path $TestDrive 'test-script.ps1')
    }

    It 'throws when the script file does not exist' {
        { Resolve-ScriptPath -RelativePath 'nonexistent.ps1' -RootDir $TestDrive } |
            Should -Throw '*Script not found*'
    }
}

# ---------------------------------------------------------------------------
# ConvertTo-ParameterHashtable
# ---------------------------------------------------------------------------

Describe 'ConvertTo-ParameterHashtable' {

    It 'returns empty hashtable for null input' {
        $result = ConvertTo-ParameterHashtable $null
        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }

    It 'returns the same hashtable if input is already a hashtable' {
        $ht = @{ key = 'value' }
        $result = ConvertTo-ParameterHashtable $ht
        $result['key'] | Should -Be 'value'
    }

    It 'converts PSCustomObject to hashtable' {
        $obj = [PSCustomObject]@{ foo = 'bar'; num = 42 }
        $result = ConvertTo-ParameterHashtable $obj
        $result | Should -BeOfType [hashtable]
        $result['foo'] | Should -Be 'bar'
        $result['num'] | Should -Be 42
    }
}

# ---------------------------------------------------------------------------
# Invoke-ScriptStep — DryRun mode
# ---------------------------------------------------------------------------

Describe 'Invoke-ScriptStep - DryRun mode' {

    It 'returns Success=$true' {
        $ctx    = script:New-Ctx -Mode 'DryRun'
        $item   = script:New-ScriptItem -ScriptPath 'test-script.ps1'
        $result = Invoke-ScriptStep -CatalogItem $item -RunContext $ctx
        $result.Success | Should -BeTrue
    }

    It 'does not call the actual script in DryRun' {
        $ctx    = script:New-Ctx -Mode 'DryRun'
        $item   = script:New-ScriptItem -ScriptPath 'test-script.ps1'
        $result = Invoke-ScriptStep -CatalogItem $item -RunContext $ctx
        $result.Notes | Should -Contain 'dryRun'
    }

    It 'returns the resolved script path' {
        $ctx    = script:New-Ctx -Mode 'DryRun'
        $item   = script:New-ScriptItem -ScriptPath 'test-script.ps1'
        $result = Invoke-ScriptStep -CatalogItem $item -RunContext $ctx
        $result.ScriptPath | Should -BeLike '*test-script.ps1'
    }

    It 'returns ExplorerRequired=$true when restartExplorer=true' {
        $ctx    = script:New-Ctx -Mode 'DryRun'
        $item   = script:New-ScriptItem -ScriptPath 'test-script.ps1' -RestartExplorer $true
        $result = Invoke-ScriptStep -CatalogItem $item -RunContext $ctx
        $result.ExplorerRequired | Should -BeTrue
    }

    It 'returns ExplorerRequired=$false when restartExplorer=false' {
        $ctx    = script:New-Ctx -Mode 'DryRun'
        $item   = script:New-ScriptItem -ScriptPath 'test-script.ps1' -RestartExplorer $false
        $result = Invoke-ScriptStep -CatalogItem $item -RunContext $ctx
        $result.ExplorerRequired | Should -BeFalse
    }
}

# ---------------------------------------------------------------------------
# Invoke-ScriptStep — Mock mode
# ---------------------------------------------------------------------------

Describe 'Invoke-ScriptStep - Mock mode' {

    BeforeAll {
        Mock Start-Sleep {}
    }

    It 'returns Success=$true' {
        $ctx    = script:New-Ctx -Mode 'Mock'
        $item   = script:New-ScriptItem -ScriptPath 'test-script.ps1'
        $result = Invoke-ScriptStep -CatalogItem $item -RunContext $ctx
        $result.Success | Should -BeTrue
    }

    It 'returns notes containing "mock"' {
        $ctx    = script:New-Ctx -Mode 'Mock'
        $item   = script:New-ScriptItem -ScriptPath 'test-script.ps1'
        $result = Invoke-ScriptStep -CatalogItem $item -RunContext $ctx
        $result.Notes | Should -Contain 'mock'
    }

    It 'calls Start-Sleep to simulate work' {
        $ctx  = script:New-Ctx -Mode 'Mock'
        $item = script:New-ScriptItem -ScriptPath 'test-script.ps1'
        Invoke-ScriptStep -CatalogItem $item -RunContext $ctx | Out-Null
        Should -Invoke Start-Sleep -Times 1
    }
}

# ---------------------------------------------------------------------------
# Invoke-ScriptStep — Real mode (success)
# ---------------------------------------------------------------------------

Describe 'Invoke-ScriptStep - Real mode success' {

    It 'returns Success=$true for a script that completes normally' {
        $ctx    = script:New-Ctx -Mode 'Real'
        $item   = script:New-ScriptItem -ScriptPath 'test-script.ps1'
        $result = Invoke-ScriptStep -CatalogItem $item -RunContext $ctx
        $result.Success | Should -BeTrue
    }

    It 'returns notes containing "real"' {
        $ctx    = script:New-Ctx -Mode 'Real'
        $item   = script:New-ScriptItem -ScriptPath 'test-script.ps1'
        $result = Invoke-ScriptStep -CatalogItem $item -RunContext $ctx
        $result.Notes | Should -Contain 'real'
    }
}

# ---------------------------------------------------------------------------
# Invoke-ScriptStep — Real mode (failure)
# ---------------------------------------------------------------------------

Describe 'Invoke-ScriptStep - Real mode failure' {

    It 'returns Success=$false when script throws' {
        $ctx    = script:New-Ctx -Mode 'Real'
        $item   = script:New-ScriptItem -ScriptPath 'fail-script.ps1'
        $result = Invoke-ScriptStep -CatalogItem $item -RunContext $ctx
        $result.Success | Should -BeFalse
    }

    It 'returns error message when script throws' {
        $ctx    = script:New-Ctx -Mode 'Real'
        $item   = script:New-ScriptItem -ScriptPath 'fail-script.ps1'
        $result = Invoke-ScriptStep -CatalogItem $item -RunContext $ctx
        $result.Error.message | Should -Match 'intentionally failed'
    }
}

# ---------------------------------------------------------------------------
# Invoke-ScriptStep — Script not found
# ---------------------------------------------------------------------------

Describe 'Invoke-ScriptStep - script not found' {

    It 'throws when the script file does not exist' {
        $ctx  = script:New-Ctx -Mode 'DryRun'
        $item = script:New-ScriptItem -ScriptPath 'nonexistent.ps1'
        { Invoke-ScriptStep -CatalogItem $item -RunContext $ctx } | Should -Throw '*Script not found*'
    }
}

# ---------------------------------------------------------------------------
# Invoke-ScriptStep — Invalid mode
# ---------------------------------------------------------------------------

Describe 'Invoke-ScriptStep - invalid mode' {

    It 'throws for unsupported RunContext.Mode values' {
        $ctx  = script:New-Ctx -Mode 'REAL'
        $item = script:New-ScriptItem -ScriptPath 'test-script.ps1'
        { Invoke-ScriptStep -CatalogItem $item -RunContext $ctx } |
            Should -Throw "*Unsupported RunContext.Mode*"
    }
}

# ---------------------------------------------------------------------------
# Invoke-ScriptStep — Parameters passing
# ---------------------------------------------------------------------------

Describe 'Invoke-ScriptStep - parameters' {

    It 'passes parameters to the script' {
        $ctx    = script:New-Ctx -Mode 'Real'
        $item   = script:New-ScriptItem -ScriptPath 'param-script.ps1' -Parameters @{ key = 'hello' }
        $result = Invoke-ScriptStep -CatalogItem $item -RunContext $ctx
        $result.Success | Should -BeTrue
    }
}
