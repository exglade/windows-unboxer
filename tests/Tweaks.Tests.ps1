#requires -Version 5.1
# Tweaks.Tests.ps1 - Unit tests for modules/Tweaks.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\modules\Common.ps1')
    . (Join-Path $PSScriptRoot '..\modules\Tweaks.ps1')

    Mock Write-Log {}
}

# ---------------------------------------------------------------------------
# Restart-Explorer
# ---------------------------------------------------------------------------

Describe 'Restart-Explorer' {

    BeforeAll {
        Mock Stop-Process {}
        Mock Start-Sleep {}
        Mock Start-Process {}
        Mock Get-Process {
            param([string]$Name)
            if ($Name -ne 'explorer') { return $null }
            @([PSCustomObject]@{ Name = 'explorer'; Id = 1111 })
        }
    }

    It 'stops running explorer process instances' {
        Restart-Explorer
        Should -Invoke Stop-Process -Times 1
    }

    It 'does not start explorer.exe when it is already running after stop attempt' {
        Restart-Explorer
        Should -Invoke Start-Process -Times 0 -ParameterFilter { $FilePath -eq 'explorer.exe' }
    }
}

Describe 'Restart-Explorer when explorer is not running' {

    BeforeAll {
        Mock Stop-Process {}
        Mock Start-Sleep {}
        Mock Start-Process {}

        $script:getProcessCalls = 0
        Mock Get-Process {
            param([string]$Name)
            if ($Name -ne 'explorer') { return $null }
            $script:getProcessCalls++
            if ($script:getProcessCalls -eq 1) {
                @([PSCustomObject]@{ Name = 'explorer'; Id = 1111 })
            } else {
                $null
            }
        }
    }

    It 'starts explorer.exe when no explorer process is detected after stop' {
        Restart-Explorer
        Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -eq 'explorer.exe' }
    }
}

# ---------------------------------------------------------------------------
# Invoke-ExplorerRestartPrompt
# ---------------------------------------------------------------------------

Describe 'Invoke-ExplorerRestartPrompt - DryRun skips restart' {

    BeforeAll {
        Mock Restart-Explorer {}
    }

    It 'does not restart Explorer in DryRun mode' {
        $ctx = @{ Mode = 'DryRun'; TweakTarget = 'Real'; Silent = $false }
        Invoke-ExplorerRestartPrompt -RunContext $ctx
        Should -Invoke Restart-Explorer -Times 0
    }
}

Describe 'Invoke-ExplorerRestartPrompt - Test target skips restart' {

    BeforeAll {
        Mock Restart-Explorer {}
    }

    It 'does not restart Explorer when TweakTarget is Test' {
        $ctx = @{ Mode = 'Mock'; TweakTarget = 'Test'; Silent = $false }
        Invoke-ExplorerRestartPrompt -RunContext $ctx
        Should -Invoke Restart-Explorer -Times 0
    }
}

Describe 'Invoke-ExplorerRestartPrompt - Silent mode auto-restarts Explorer' {

    BeforeAll {
        Mock Restart-Explorer {}
    }

    It 'automatically restarts Explorer without prompting in Silent mode' {
        $ctx = @{ Mode = 'Real'; TweakTarget = 'Real'; Silent = $true }
        Invoke-ExplorerRestartPrompt -RunContext $ctx
        Should -Invoke Restart-Explorer -Times 1
    }
}
