#requires -Version 5.1
# PlanState.Tests.ps1 - Unit tests for modules/PlanState.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\modules\Common.ps1')
    . (Join-Path $PSScriptRoot '..\modules\PlanState.ps1')

    Mock Write-Log {}
    Mock Get-OsVersion { 'Windows 11 Pro' }

    # ---------------------------------------------------------------------------
    # Helpers — build test catalog items
    # ---------------------------------------------------------------------------
    function script:Make-Item {
        param([string]$Id, [string]$Category, [string]$DisplayName, [int]$Priority, [string]$Type = 'app')
        $item = [PSCustomObject]@{
            id               = $Id
            type             = $Type
            category         = $Category
            displayName      = $DisplayName
            effectivePriority = $Priority
            requiresReboot   = $false
        }
        if ($Type -eq 'app') {
            $item | Add-Member -NotePropertyName 'winget' -NotePropertyValue (
                [PSCustomObject]@{ id = 'Some.App'; source = 'winget'; scope = 'machine'; override = $null }
            )
        } elseif ($Type -eq 'script') {
            $item | Add-Member -NotePropertyName 'script' -NotePropertyValue (
                [PSCustomObject]@{ path = 'scripts/test.ps1'; parameters = [PSCustomObject]@{}; restartExplorer = $false }
            )
        }
        return $item
    }

    $script:AllItems = @(
        (script:Make-Item 'tweak.ext'    'Tweaks'       'Show extensions'    50  'script'),
        (script:Make-Item 'core.chrome'  'Core'         'Google Chrome'     200  'app'),
        (script:Make-Item 'dev.vscode'   'Dev'          'VS Code'           300  'app'),
        (script:Make-Item 'prod.npp'     'Productivity' 'Notepad++'         510  'app')
    )
}

# ---------------------------------------------------------------------------
# Get-PlanHash
# ---------------------------------------------------------------------------

Describe 'Get-PlanHash' {

    It 'returns a non-empty string' {
        $steps  = @([PSCustomObject]@{id='a'}, [PSCustomObject]@{id='b'})
        $result = Get-PlanHash -Steps $steps
        $result | Should -Not -BeNullOrEmpty
    }

    It 'returns a 12-character lowercase hex string' {
        $steps  = @([PSCustomObject]@{id='x.y'})
        $result = Get-PlanHash -Steps $steps
        $result | Should -Match '^[0-9a-f]{12}$'
    }

    It 'is deterministic for the same input' {
        $steps = @([PSCustomObject]@{id='a'}, [PSCustomObject]@{id='b'})
        $h1    = Get-PlanHash -Steps $steps
        $h2    = Get-PlanHash -Steps $steps
        $h1 | Should -Be $h2
    }

    It 'produces different hashes for different step lists' {
        $s1 = @([PSCustomObject]@{id='a'}, [PSCustomObject]@{id='b'})
        $s2 = @([PSCustomObject]@{id='c'}, [PSCustomObject]@{id='d'})
        (Get-PlanHash -Steps $s1) | Should -Not -Be (Get-PlanHash -Steps $s2)
    }

    It 'produces different hashes when order differs' {
        $s1 = @([PSCustomObject]@{id='a'}, [PSCustomObject]@{id='b'})
        $s2 = @([PSCustomObject]@{id='b'}, [PSCustomObject]@{id='a'})
        (Get-PlanHash -Steps $s1) | Should -Not -Be (Get-PlanHash -Steps $s2)
    }
}

# ---------------------------------------------------------------------------
# New-Plan
# ---------------------------------------------------------------------------

Describe 'New-Plan' {

    It 'returns a hashtable with planVersion 1.0' {
        $plan = New-Plan -AllItems $script:AllItems -SelectedIds @('core.chrome')
        $plan.planVersion | Should -Be '1.0'
    }

    It 'includes only selected IDs in steps' {
        $plan = New-Plan -AllItems $script:AllItems -SelectedIds @('core.chrome', 'dev.vscode')
        $ids  = $plan.steps | ForEach-Object { $_.id }
        $ids | Should -Contain 'core.chrome'
        $ids | Should -Contain 'dev.vscode'
        $ids | Should -Not -Contain 'tweak.ext'
        $ids | Should -Not -Contain 'prod.npp'
    }

    It 'produces the correct step count' {
        $plan = New-Plan -AllItems $script:AllItems -SelectedIds @('core.chrome', 'dev.vscode', 'tweak.ext')
        $plan.steps.Count | Should -Be 3
    }

    It 'sorts steps by effectivePriority ascending' {
        $plan       = New-Plan -AllItems $script:AllItems -SelectedIds @('dev.vscode', 'core.chrome', 'tweak.ext')
        $ids        = $plan.steps | ForEach-Object { $_.id }
        $ids[0]     | Should -Be 'tweak.ext'   # priority 50
        $ids[1]     | Should -Be 'core.chrome' # priority 200
        $ids[2]     | Should -Be 'dev.vscode'  # priority 300
    }

    It 'sets type=app on app steps' {
        $plan = New-Plan -AllItems $script:AllItems -SelectedIds @('core.chrome')
        $plan.steps[0].type | Should -Be 'app'
    }

    It 'sets type=script on script steps' {
        $plan = New-Plan -AllItems $script:AllItems -SelectedIds @('tweak.ext')
        $plan.steps[0].type | Should -Be 'script'
    }

    It 'includes environment.computerName' {
        $plan = New-Plan -AllItems $script:AllItems -SelectedIds @('core.chrome')
        $plan.environment.computerName | Should -Not -BeNullOrEmpty
    }

    It 'sets generatedAt to a non-empty datetime string' {
        $plan = New-Plan -AllItems $script:AllItems -SelectedIds @('core.chrome')
        $plan.generatedAt | Should -Not -BeNullOrEmpty
    }

    It 'returns an empty steps array when no IDs are selected' {
        $plan = New-Plan -AllItems $script:AllItems -SelectedIds ([string[]]@())
        $plan.steps.Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# New-State
# ---------------------------------------------------------------------------

Describe 'New-State' {

    BeforeAll {
        $script:Plan = New-Plan -AllItems $script:AllItems `
            -SelectedIds @('tweak.ext', 'core.chrome', 'dev.vscode')
        $script:State = New-State -Plan $script:Plan
    }

    It 'returns a hashtable with stateVersion 1.0' {
        $script:State.stateVersion | Should -Be '1.0'
    }

    It 'has the same number of steps as the plan' {
        $script:State.steps.Count | Should -Be $script:Plan.steps.Count
    }

    It 'all steps start with status Pending' {
        $nonPending = $script:State.steps | Where-Object { $_.status -ne 'Pending' }
        $nonPending | Should -BeNullOrEmpty
    }

    It 'all steps have null startedAt initially' {
        $withStart = $script:State.steps | Where-Object { $null -ne $_.startedAt }
        $withStart | Should -BeNullOrEmpty
    }

    It 'all steps have null endedAt initially' {
        $withEnd = $script:State.steps | Where-Object { $null -ne $_.endedAt }
        $withEnd | Should -BeNullOrEmpty
    }

    It 'all steps have null error initially' {
        $withErr = $script:State.steps | Where-Object { $null -ne $_.error }
        $withErr | Should -BeNullOrEmpty
    }

    It 'includes a planHash' {
        $script:State.planHash | Should -Not -BeNullOrEmpty
    }

    It 'planHash is consistent with the plan steps' {
        $expected = Get-PlanHash -Steps $script:Plan.steps
        $script:State.planHash | Should -Be $expected
    }

    It 'step IDs match the plan step IDs in order' {
        for ($i = 0; $i -lt $script:Plan.steps.Count; $i++) {
            $script:State.steps[$i].id | Should -Be $script:Plan.steps[$i].id
        }
    }

    It 'includes a non-empty startedAt timestamp' {
        $script:State.startedAt | Should -Not -BeNullOrEmpty
    }
}

# ---------------------------------------------------------------------------
# Update-StateStep
# ---------------------------------------------------------------------------

Describe 'Update-StateStep' {

    BeforeAll {
        # Build a fresh mutable state for each context
        $basePlan  = New-Plan -AllItems $script:AllItems -SelectedIds @('core.chrome', 'dev.vscode')
        $script:MutState = New-State -Plan $basePlan
    }

    It 'updates status to InProgress' {
        Update-StateStep -State $script:MutState -Id 'core.chrome' -Status 'InProgress'
        $step = $script:MutState.steps | Where-Object { $_.id -eq 'core.chrome' }
        $step.status | Should -Be 'InProgress'
    }

    It 'sets startedAt when provided' {
        $ts = (Get-Date -Format 'o')
        Update-StateStep -State $script:MutState -Id 'core.chrome' -StartedAt $ts
        $step = $script:MutState.steps | Where-Object { $_.id -eq 'core.chrome' }
        $step.startedAt | Should -Be $ts
    }

    It 'sets endedAt when provided' {
        $ts = (Get-Date -Format 'o')
        Update-StateStep -State $script:MutState -Id 'dev.vscode' -EndedAt $ts
        $step = $script:MutState.steps | Where-Object { $_.id -eq 'dev.vscode' }
        $step.endedAt | Should -Be $ts
    }

    It 'sets error info when provided' {
        $err = @{ message = 'Something failed'; exitCode = 1 }
        Update-StateStep -State $script:MutState -Id 'dev.vscode' -ErrorInfo $err
        $step = $script:MutState.steps | Where-Object { $_.id -eq 'dev.vscode' }
        $step.error.message | Should -Be 'Something failed'
    }

    It 'sets notes when provided' {
        Update-StateStep -State $script:MutState -Id 'core.chrome' -Notes @('mock', 'dryRun')
        $step = $script:MutState.steps | Where-Object { $_.id -eq 'core.chrome' }
        $step.notes | Should -Contain 'mock'
        $step.notes | Should -Contain 'dryRun'
    }

    It 'sets command when provided' {
        Update-StateStep -State $script:MutState -Id 'core.chrome' -Command 'winget install ...'
        $step = $script:MutState.steps | Where-Object { $_.id -eq 'core.chrome' }
        $step.command | Should -Be 'winget install ...'
    }

    It 'sets targetPath when provided' {
        Update-StateStep -State $script:MutState -Id 'core.chrome' -TargetPath 'HKCU:\Foo\Bar'
        $step = $script:MutState.steps | Where-Object { $_.id -eq 'core.chrome' }
        $step.targetPath | Should -Be 'HKCU:\Foo\Bar'
    }

    It 'throws when step ID is not found in state' {
        { Update-StateStep -State $script:MutState -Id 'nonexistent.id' -Status 'Succeeded' } |
            Should -Throw
    }

    It 'only modifies the targeted step — other steps remain unchanged' {
        $origStatus = ($script:MutState.steps | Where-Object { $_.id -eq 'dev.vscode' }).status
        Update-StateStep -State $script:MutState -Id 'core.chrome' -Status 'Succeeded'
        $vsStep = $script:MutState.steps | Where-Object { $_.id -eq 'dev.vscode' }
        $vsStep.status | Should -Be $origStatus
    }
}

# ---------------------------------------------------------------------------
# Get-StateStepById
# ---------------------------------------------------------------------------

Describe 'Get-StateStepById' {

    BeforeAll {
        $plan           = New-Plan -AllItems $script:AllItems -SelectedIds @('core.chrome', 'dev.vscode')
        $script:GsbState = New-State -Plan $plan
    }

    It 'returns the correct step' {
        $step = Get-StateStepById -State $script:GsbState -Id 'dev.vscode'
        $step | Should -Not -BeNullOrEmpty
        $step.id | Should -Be 'dev.vscode'
    }

    It 'returns null for a non-existent ID' {
        $step = Get-StateStepById -State $script:GsbState -Id 'not.there'
        $step | Should -BeNullOrEmpty
    }
}
