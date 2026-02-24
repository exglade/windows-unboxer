#requires -Version 5.1
# Common.Tests.ps1 - Unit tests for modules/Common.ps1

BeforeAll {
    # Suppress console noise from Write-Log during tests
    $script:ModulePath = Join-Path $PSScriptRoot '..\modules\Common.ps1'
    . $script:ModulePath

    # Silence logger for the whole file (Write-Log is defined in Common.ps1)
    Mock Write-Log {}
}

# ---------------------------------------------------------------------------
# Get-ArtifactPaths
# ---------------------------------------------------------------------------

Describe 'Get-ArtifactPaths' {

    It 'returns all required keys' {
        $p = Get-ArtifactPaths -RootDir 'C:\Foo'
        $p.Keys | Should -Contain 'Root'
        $p.Keys | Should -Contain 'Artifacts'
        $p.Keys | Should -Contain 'Logs'
        $p.Keys | Should -Contain 'Plan'
        $p.Keys | Should -Contain 'State'
        $p.Keys | Should -Contain 'Catalog'
    }

    It 'Root equals the supplied RootDir' {
        $p = Get-ArtifactPaths -RootDir 'C:\MyPC'
        $p.Root | Should -Be 'C:\MyPC'
    }

    It 'Artifacts is RootDir\setup-artifacts' {
        $p = Get-ArtifactPaths -RootDir 'C:\Foo'
        $p.Artifacts | Should -Be 'C:\Foo\setup-artifacts'
    }

    It 'Logs is Artifacts\logs' {
        $p = Get-ArtifactPaths -RootDir 'C:\Foo'
        $p.Logs | Should -Be 'C:\Foo\setup-artifacts\logs'
    }

    It 'Plan is Artifacts\plan.json' {
        $p = Get-ArtifactPaths -RootDir 'C:\Foo'
        $p.Plan | Should -Be 'C:\Foo\setup-artifacts\plan.json'
    }

    It 'State is Artifacts\state.json' {
        $p = Get-ArtifactPaths -RootDir 'C:\Foo'
        $p.State | Should -Be 'C:\Foo\setup-artifacts\state.json'
    }

    It 'Catalog is RootDir\catalog.json' {
        $p = Get-ArtifactPaths -RootDir 'C:\Foo'
        $p.Catalog | Should -Be 'C:\Foo\catalog.json'
    }
}

# ---------------------------------------------------------------------------
# Initialize-ArtifactDirectories
# ---------------------------------------------------------------------------

Describe 'Initialize-ArtifactDirectories' {

    It 'creates Artifacts and Logs directories when they do not exist' {
        $root  = Join-Path $TestDrive 'newdirs'
        $paths = Get-ArtifactPaths -RootDir $root
        Initialize-ArtifactDirectories -Paths $paths
        Test-Path $paths.Artifacts | Should -BeTrue
        Test-Path $paths.Logs      | Should -BeTrue
    }

    It 'does not throw when directories already exist' {
        $root  = Join-Path $TestDrive 'existdirs'
        $paths = Get-ArtifactPaths -RootDir $root
        New-Item -ItemType Directory -Path $paths.Artifacts -Force | Out-Null
        New-Item -ItemType Directory -Path $paths.Logs      -Force | Out-Null
        { Initialize-ArtifactDirectories -Paths $paths } | Should -Not -Throw
    }
}

# ---------------------------------------------------------------------------
# Write-JsonAtomic + Read-JsonFile
# ---------------------------------------------------------------------------

Describe 'Write-JsonAtomic' {

    It 'writes valid JSON that can be read back' {
        $path = Join-Path $TestDrive 'wj_basic.json'
        $obj  = @{ name = 'test'; value = 99 }
        Write-JsonAtomic -Path $path -InputObject $obj
        $result = Read-JsonFile -Path $path
        $result.name  | Should -Be 'test'
        $result.value | Should -Be 99
    }

    It 'produces a file at the target path' {
        $path = Join-Path $TestDrive 'wj_exists.json'
        Write-JsonAtomic -Path $path -InputObject @{ x = 1 }
        Test-Path $path | Should -BeTrue
    }

    It 'overwrites an existing file with new content' {
        $path = Join-Path $TestDrive 'wj_overwrite.json'
        Write-JsonAtomic -Path $path -InputObject @{ v = 1 }
        Write-JsonAtomic -Path $path -InputObject @{ v = 2 }
        $result = Read-JsonFile -Path $path
        $result.v | Should -Be 2
    }

    It 'leaves no leftover temp files on success' {
        $dir  = Join-Path $TestDrive 'wj_tempclean'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $path = Join-Path $dir 'out.json'
        Write-JsonAtomic -Path $path -InputObject @{ a = 1 }
        $extra = @(Get-ChildItem $dir | Where-Object { $_.Name -ne 'out.json' })
        $extra.Count | Should -Be 0
    }

    It 'preserves nested objects through round-trip' {
        $path = Join-Path $TestDrive 'wj_nested.json'
        $obj  = @{ outer = @{ inner = 'hello'; nums = @(1, 2, 3) } }
        Write-JsonAtomic -Path $path -InputObject $obj
        $result = Read-JsonFile -Path $path
        $result.outer.inner | Should -Be 'hello'
    }

    It 'preserves arrays through round-trip' {
        $path = Join-Path $TestDrive 'wj_array.json'
        $obj  = @{ items = @('alpha', 'beta', 'gamma') }
        Write-JsonAtomic -Path $path -InputObject $obj
        $result = Read-JsonFile -Path $path
        $result.items.Count | Should -Be 3
        $result.items[1]    | Should -Be 'beta'
    }

    It 'handles deeply nested depth without truncation' {
        $path  = Join-Path $TestDrive 'wj_depth.json'
        $inner = @{ steps = @(@{ id = 'a'; status = 'Pending'; nested = @{ sub = 'ok' } }) }
        Write-JsonAtomic -Path $path -InputObject $inner -Depth 10
        $result = Read-JsonFile -Path $path
        $result.steps[0].nested.sub | Should -Be 'ok'
    }
}

Describe 'Read-JsonFile' {

    It 'throws when the file does not exist' {
        { Read-JsonFile -Path (Join-Path $TestDrive 'nosuchfile.json') } |
            Should -Throw
    }

    It 'returns a PSCustomObject' {
        $path = Join-Path $TestDrive 'rj_type.json'
        Write-JsonAtomic -Path $path -InputObject @{ k = 'v' }
        $result = Read-JsonFile -Path $path
        $result | Should -BeOfType [System.Management.Automation.PSCustomObject]
    }
}
