#requires -Version 5.1
# Executor.Tests.ps1 - Unit tests for modules/Executor.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\modules\Common.ps1')
    . (Join-Path $PSScriptRoot '..\modules\Tweaks.ps1')
    . (Join-Path $PSScriptRoot '..\modules\ScriptRunner.ps1')
    . (Join-Path $PSScriptRoot '..\modules\PlanState.ps1')
    . (Join-Path $PSScriptRoot '..\modules\Executor.ps1')

    Mock Write-Log {}
    Mock Write-Host {}
    Mock Get-OsVersion { 'Windows 11 Pro' }
    Mock Start-Sleep {}  # avoid actual delays in mock-mode tests

    # ---------------------------------------------------------------------------
    # Test catalog item factories
    # ---------------------------------------------------------------------------
    function script:App-Item {
        param(
            [string]$Id    = 'core.chrome',
            [string]$WinId = 'Google.Chrome',
            [string]$Source = 'winget',
            [string]$Scope  = 'machine',
            $Override       = $null
        )
        [PSCustomObject]@{
            id    = $Id
            type  = 'app'
            winget = [PSCustomObject]@{
                id       = $WinId
                source   = $Source
                scope    = $Scope
                override = $Override
            }
        }
    }

    function script:Script-Item {
        param([string]$Id = 'tweak.ext')
        [PSCustomObject]@{
            id   = $Id
            type = 'script'
            script = [PSCustomObject]@{
                path            = 'scripts/tweak-show-extensions.ps1'
                parameters      = [PSCustomObject]@{}
                restartExplorer = $false
            }
        }
    }

    function script:New-AppStep {
        param([string]$Id = 'core.chrome')
        [ordered]@{ id = $Id; type = 'app'; parameters = @{ override = $null } }
    }

    function script:New-ScriptStep {
        param([string]$Id = 'tweak.ext')
        [ordered]@{ id = $Id; type = 'script'; parameters = @{} }
    }

    function script:Make-TestPaths {
        return @{
            Artifacts = $TestDrive
            Logs      = $TestDrive
            Plan      = (Join-Path $TestDrive 'plan.json')
            State     = (Join-Path $TestDrive 'state.json')
        }
    }

    function script:Make-Ctx {
        param(
            [string]$Mode        = 'DryRun',
            [string]$TweakTarget = 'Test',
            [string]$FailStepId  = $null
        )
        @{
            Mode        = $Mode
            TweakTarget = $TweakTarget
            FailStepId  = $FailStepId
            Paths       = (script:Make-TestPaths)
        }
    }
}

# ---------------------------------------------------------------------------
# Build-WingetCommand
# ---------------------------------------------------------------------------

Describe 'Build-WingetCommand' {

    It 'produces the base mandatory flags' {
        $item = script:App-Item
        $cmd  = Build-WingetCommand -CatalogItem $item
        $cmd  | Should -Match '--id Google\.Chrome'
        $cmd  | Should -Match '--exact'
        $cmd  | Should -Match '--accept-package-agreements'
        $cmd  | Should -Match '--accept-source-agreements'
    }

    It 'includes --source when source is provided' {
        $item = script:App-Item -Source 'winget'
        $cmd  = Build-WingetCommand -CatalogItem $item
        $cmd  | Should -Match '--source winget'
    }

    It 'includes --scope when scope is provided' {
        $item = script:App-Item -Scope 'machine'
        $cmd  = Build-WingetCommand -CatalogItem $item
        $cmd  | Should -Match '--scope machine'
    }

    It 'includes --override when override is non-null' {
        $item = script:App-Item -Override '/SILENT'
        $cmd  = Build-WingetCommand -CatalogItem $item
        $cmd  | Should -Match '--override'
        $cmd  | Should -Match '/SILENT'
    }

    It 'omits --override when override is null' {
        $item = script:App-Item -Override $null
        $cmd  = Build-WingetCommand -CatalogItem $item
        $cmd  | Should -Not -Match '--override'
    }

    It 'uses the correct winget ID in the command' {
        $item = script:App-Item -WinId 'Microsoft.VisualStudioCode'
        $cmd  = Build-WingetCommand -CatalogItem $item
        $cmd  | Should -Match 'Microsoft\.VisualStudioCode'
    }

    It 'starts with winget install' {
        $item = script:App-Item
        $cmd  = Build-WingetCommand -CatalogItem $item
        $cmd  | Should -BeLike 'winget install *'
    }
}

# ---------------------------------------------------------------------------
# Invoke-AppStep  — DryRun mode
# ---------------------------------------------------------------------------

Describe 'Invoke-AppStep - DryRun mode' {

    BeforeAll {
        Mock Invoke-WingetInstall {}
    }

    It 'returns Success=$true' {
        $ctx    = script:Make-Ctx -Mode 'DryRun'
        $step   = script:New-AppStep
        $item   = script:App-Item
        $result = Invoke-AppStep -Step $step -CatalogItem $item -RunContext $ctx -Paths $ctx.Paths
        $result.Success | Should -BeTrue
    }

    It 'does NOT call Invoke-WingetInstall' {
        $ctx  = script:Make-Ctx -Mode 'DryRun'
        $step = script:New-AppStep
        $item = script:App-Item
        Invoke-AppStep -Step $step -CatalogItem $item -RunContext $ctx -Paths $ctx.Paths | Out-Null
        Should -Invoke Invoke-WingetInstall -Times 0
    }

    It 'returns notes containing "dryRun"' {
        $ctx    = script:Make-Ctx -Mode 'DryRun'
        $step   = script:New-AppStep
        $item   = script:App-Item
        $result = Invoke-AppStep -Step $step -CatalogItem $item -RunContext $ctx -Paths $ctx.Paths
        $result.Notes | Should -Contain 'dryRun'
    }

    It 'returns the built command in the Command field' {
        $ctx    = script:Make-Ctx -Mode 'DryRun'
        $step   = script:New-AppStep
        $item   = script:App-Item
        $result = Invoke-AppStep -Step $step -CatalogItem $item -RunContext $ctx -Paths $ctx.Paths
        $result.Command | Should -BeLike 'winget install *'
    }

    It 'returns null Error' {
        $ctx    = script:Make-Ctx -Mode 'DryRun'
        $step   = script:New-AppStep
        $item   = script:App-Item
        $result = Invoke-AppStep -Step $step -CatalogItem $item -RunContext $ctx -Paths $ctx.Paths
        $result.Error | Should -BeNullOrEmpty
    }
}

# ---------------------------------------------------------------------------
# Invoke-AppStep  — Mock mode (success)
# ---------------------------------------------------------------------------

Describe 'Invoke-AppStep - Mock mode success' {

    BeforeAll {
        Mock Invoke-WingetInstall {}
    }

    It 'returns Success=$true when FailStepId does not match' {
        $ctx    = script:Make-Ctx -Mode 'Mock' -FailStepId 'other.id'
        $step   = script:New-AppStep 'core.chrome'
        $item   = script:App-Item
        $result = Invoke-AppStep -Step $step -CatalogItem $item -RunContext $ctx -Paths $ctx.Paths
        $result.Success | Should -BeTrue
    }

    It 'does NOT call Invoke-WingetInstall' {
        $ctx  = script:Make-Ctx -Mode 'Mock'
        $step = script:New-AppStep
        $item = script:App-Item
        Invoke-AppStep -Step $step -CatalogItem $item -RunContext $ctx -Paths $ctx.Paths | Out-Null
        Should -Invoke Invoke-WingetInstall -Times 0
    }

    It 'returns notes containing "mock"' {
        $ctx    = script:Make-Ctx -Mode 'Mock'
        $step   = script:New-AppStep
        $item   = script:App-Item
        $result = Invoke-AppStep -Step $step -CatalogItem $item -RunContext $ctx -Paths $ctx.Paths
        $result.Notes | Should -Contain 'mock'
    }

    It 'calls Start-Sleep to simulate work' {
        $ctx  = script:Make-Ctx -Mode 'Mock'
        $step = script:New-AppStep
        $item = script:App-Item
        Invoke-AppStep -Step $step -CatalogItem $item -RunContext $ctx -Paths $ctx.Paths | Out-Null
        Should -Invoke Start-Sleep -Times 1
    }
}

# ---------------------------------------------------------------------------
# Invoke-AppStep  — Mock mode with FailStepId
# ---------------------------------------------------------------------------

Describe 'Invoke-AppStep - Mock mode simulated failure' {

    It 'returns Success=$false when FailStepId matches step ID' {
        $ctx    = script:Make-Ctx -Mode 'Mock' -FailStepId 'dev.vscode'
        $step   = script:New-AppStep 'dev.vscode'
        $item   = script:App-Item -Id 'dev.vscode' -WinId 'Microsoft.VisualStudioCode'
        $result = Invoke-AppStep -Step $step -CatalogItem $item -RunContext $ctx -Paths $ctx.Paths
        $result.Success | Should -BeFalse
    }

    It 'returns an error message for the simulated failure' {
        $ctx    = script:Make-Ctx -Mode 'Mock' -FailStepId 'dev.vscode'
        $step   = script:New-AppStep 'dev.vscode'
        $item   = script:App-Item -Id 'dev.vscode' -WinId 'Microsoft.VisualStudioCode'
        $result = Invoke-AppStep -Step $step -CatalogItem $item -RunContext $ctx -Paths $ctx.Paths
        $result.Error.message | Should -Match 'Simulated'
    }

    It 'includes "simulatedFailure" in notes' {
        $ctx    = script:Make-Ctx -Mode 'Mock' -FailStepId 'dev.vscode'
        $step   = script:New-AppStep 'dev.vscode'
        $item   = script:App-Item -Id 'dev.vscode'
        $result = Invoke-AppStep -Step $step -CatalogItem $item -RunContext $ctx -Paths $ctx.Paths
        $result.Notes | Should -Contain 'simulatedFailure'
    }

    It 'does NOT fail a different step ID' {
        $ctx    = script:Make-Ctx -Mode 'Mock' -FailStepId 'dev.vscode'
        $step   = script:New-AppStep 'core.chrome'
        $item   = script:App-Item -Id 'core.chrome'
        $result = Invoke-AppStep -Step $step -CatalogItem $item -RunContext $ctx -Paths $ctx.Paths
        $result.Success | Should -BeTrue
    }
}

# ---------------------------------------------------------------------------
# Invoke-ScriptStepDispatch  — DryRun mode
# ---------------------------------------------------------------------------

Describe 'Invoke-ScriptStepDispatch - DryRun mode' {

    BeforeAll {
        Mock Invoke-ScriptStep {
            return @{ Success = $true; ScriptPath = 'scripts/test.ps1'; ExplorerRequired = $false; Notes = @('dryRun') }
        }
    }

    It 'returns Success=$true' {
        $ctx    = script:Make-Ctx -Mode 'DryRun'
        $step   = script:New-ScriptStep
        $item   = script:Script-Item
        $result = Invoke-ScriptStepDispatch -Step $step -CatalogItem $item -RunContext $ctx
        $result.Success | Should -BeTrue
    }

    It 'includes mode name in notes' {
        $ctx    = script:Make-Ctx -Mode 'DryRun'
        $step   = script:New-ScriptStep
        $item   = script:Script-Item
        $result = Invoke-ScriptStepDispatch -Step $step -CatalogItem $item -RunContext $ctx
        $result.Notes | Should -Contain 'dryRun'
    }
}

# ---------------------------------------------------------------------------
# Invoke-ScriptStepDispatch  — Mock mode simulated failure
# ---------------------------------------------------------------------------

Describe 'Invoke-ScriptStepDispatch - Mock mode simulated failure' {

    It 'returns Success=$false when FailStepId matches' {
        $ctx    = script:Make-Ctx -Mode 'Mock' -FailStepId 'tweak.ext'
        $step   = script:New-ScriptStep 'tweak.ext'
        $item   = script:Script-Item 'tweak.ext'
        $result = Invoke-ScriptStepDispatch -Step $step -CatalogItem $item -RunContext $ctx
        $result.Success | Should -BeFalse
    }

    It 'sets error message on simulated failure' {
        $ctx    = script:Make-Ctx -Mode 'Mock' -FailStepId 'tweak.ext'
        $step   = script:New-ScriptStep 'tweak.ext'
        $item   = script:Script-Item 'tweak.ext'
        $result = Invoke-ScriptStepDispatch -Step $step -CatalogItem $item -RunContext $ctx
        $result.Error.message | Should -Match 'Simulated'
    }

    It 'does not fail a non-matching step' {
        Mock Invoke-ScriptStep {
            return @{ Success = $true; ScriptPath = 'scripts/test.ps1'; ExplorerRequired = $false; Notes = @('mock') }
        }
        $ctx    = script:Make-Ctx -Mode 'Mock' -FailStepId 'tweak.ext'
        $step   = script:New-ScriptStep 'tweak.other'
        $item   = script:Script-Item 'tweak.other'
        $result = Invoke-ScriptStepDispatch -Step $step -CatalogItem $item -RunContext $ctx
        $result.Success | Should -BeTrue
    }
}

# ---------------------------------------------------------------------------
# Invoke-Plan  — DryRun end-to-end
# ---------------------------------------------------------------------------

Describe 'Invoke-Plan - DryRun full run' {

    BeforeAll {
        Mock Get-OsVersion  { 'Windows 11 Pro' }
        Mock Set-RegistryValue {}
        Mock Invoke-ExplorerRestartPrompt {}

        $allItems = @(
            (& {
                $i = [PSCustomObject]@{ id='core.chrome'; type='app'; category='Core'; displayName='Chrome'
                    effectivePriority=200; requiresReboot=$false
                    winget=[PSCustomObject]@{id='Google.Chrome';source='winget';scope='machine';override=$null} }
                $i
            }),
            (& {
                $i = [PSCustomObject]@{ id='dev.vscode'; type='app'; category='Dev'; displayName='VS Code'
                    effectivePriority=300; requiresReboot=$false
                    winget=[PSCustomObject]@{id='Microsoft.VisualStudioCode';source='winget';scope='machine';override=$null} }
                $i
            })
        )

        $plan  = New-Plan -AllItems $allItems -SelectedIds @('core.chrome', 'dev.vscode')
        $state = New-State -Plan $plan

        $ctx = @{
            Mode        = 'DryRun'
            TweakTarget = 'Real'
            FailStepId  = $null
            Paths       = (script:Make-TestPaths)
        }

        Write-JsonAtomic -Path $ctx.Paths.State -InputObject $state
        Invoke-Plan -Plan $plan -State $state -CatalogItems $allItems -RunContext $ctx -ResumeOption 'All'
    }

    It 'marks all steps as Succeeded' {
        $notSucceeded = $state.steps | Where-Object { $_.status -ne 'Succeeded' }
        $notSucceeded | Should -BeNullOrEmpty
    }

    It 'all steps have a non-null endedAt' {
        $withoutEnd = $state.steps | Where-Object { $null -eq $_.endedAt }
        $withoutEnd | Should -BeNullOrEmpty
    }

    It 'state.json is written to disk' {
        Test-Path $ctx.Paths.State | Should -BeTrue
    }

    It 'all step notes contain "dryRun"' {
        foreach ($step in $state.steps) {
            $step.notes | Should -Contain 'dryRun'
        }
    }
}

# ---------------------------------------------------------------------------
# Invoke-Plan  — Mock mode stops on first failure
# ---------------------------------------------------------------------------

Describe 'Invoke-Plan - Mock mode stop-on-failure' {

    BeforeAll {
        Mock Set-RegistryValue {}
        Mock Invoke-ExplorerRestartPrompt {}

        $allItems = @(
            (& {
                [PSCustomObject]@{ id='core.chrome'; type='app'; category='Core'; displayName='Chrome'
                    effectivePriority=200; requiresReboot=$false
                    winget=[PSCustomObject]@{id='Google.Chrome';source='winget';scope='machine';override=$null} }
            }),
            (& {
                [PSCustomObject]@{ id='dev.vscode'; type='app'; category='Dev'; displayName='VS Code'
                    effectivePriority=300; requiresReboot=$false
                    winget=[PSCustomObject]@{id='Microsoft.VisualStudioCode';source='winget';scope='machine';override=$null} }
            }),
            (& {
                [PSCustomObject]@{ id='dev.git'; type='app'; category='Dev'; displayName='Git'
                    effectivePriority=310; requiresReboot=$false
                    winget=[PSCustomObject]@{id='Git.Git';source='winget';scope='machine';override=$null} }
            })
        )

        $plan  = New-Plan -AllItems $allItems -SelectedIds @('core.chrome', 'dev.vscode', 'dev.git')
        $state = New-State -Plan $plan

        $ctx = @{
            Mode        = 'Mock'
            TweakTarget = 'Test'
            FailStepId  = 'dev.vscode'   # second step fails
            Paths       = (script:Make-TestPaths)
        }

        Write-JsonAtomic -Path $ctx.Paths.State -InputObject $state
        Invoke-Plan -Plan $plan -State $state -CatalogItems $allItems -RunContext $ctx -ResumeOption 'All'
    }

    It 'first step (core.chrome) succeeds' {
        $step = $state.steps | Where-Object { $_.id -eq 'core.chrome' }
        $step.status | Should -Be 'Succeeded'
    }

    It 'failing step (dev.vscode) is marked Failed' {
        $step = $state.steps | Where-Object { $_.id -eq 'dev.vscode' }
        $step.status | Should -Be 'Failed'
    }

    It 'step after failure (dev.git) is not executed — still Pending' {
        $step = $state.steps | Where-Object { $_.id -eq 'dev.git' }
        $step.status | Should -Be 'Pending'
    }

    It 'failed step has an error message' {
        $step = $state.steps | Where-Object { $_.id -eq 'dev.vscode' }
        $step.error.message | Should -Not -BeNullOrEmpty
    }
}

# ---------------------------------------------------------------------------
# Invoke-Plan  — ResumeOption = ResumePending skips Succeeded steps
# ---------------------------------------------------------------------------

Describe 'Invoke-Plan - ResumePending skips already-Succeeded steps' {

    BeforeAll {
        Mock Set-RegistryValue {}
        Mock Invoke-ExplorerRestartPrompt {}

        # Artificial: make the first step already Succeeded in the state before the run
        $allItems = @(
            (& {
                [PSCustomObject]@{ id='core.chrome'; type='app'; category='Core'; displayName='Chrome'
                    effectivePriority=200; requiresReboot=$false
                    winget=[PSCustomObject]@{id='Google.Chrome';source='winget';scope='machine';override=$null} }
            }),
            (& {
                [PSCustomObject]@{ id='dev.vscode'; type='app'; category='Dev'; displayName='VS Code'
                    effectivePriority=300; requiresReboot=$false
                    winget=[PSCustomObject]@{id='Microsoft.VisualStudioCode';source='winget';scope='machine';override=$null} }
            })
        )

        $plan  = New-Plan -AllItems $allItems -SelectedIds @('core.chrome', 'dev.vscode')
        $state = New-State -Plan $plan

        # Pre-mark first step as Succeeded
        Update-StateStep -State $state -Id 'core.chrome' -Status 'Succeeded' `
            -StartedAt (Get-Date -Format 'o') -EndedAt (Get-Date -Format 'o')

        $ctx = @{
            Mode        = 'DryRun'
            TweakTarget = 'Real'
            FailStepId  = $null
            Paths       = (script:Make-TestPaths)
        }

        Write-JsonAtomic -Path $ctx.Paths.State -InputObject $state
        Invoke-Plan -Plan $plan -State $state -CatalogItems $allItems -RunContext $ctx -ResumeOption 'ResumePending'
    }

    It 'core.chrome remains Succeeded (not re-run)' {
        $step = $state.steps | Where-Object { $_.id -eq 'core.chrome' }
        $step.status | Should -Be 'Succeeded'
    }

    It 'dev.vscode is now Succeeded (was Pending, got resumed)' {
        $step = $state.steps | Where-Object { $_.id -eq 'dev.vscode' }
        $step.status | Should -Be 'Succeeded'
    }
}
