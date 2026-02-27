#requires -Version 5.1
# Common.ps1 - Shared utilities: paths, logging, JSON I/O, environment checks

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

function Get-ArtifactPaths {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Returns a collection of path values — plural noun is semantically correct.')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$RootDir
    )

    $artifacts = Join-Path $RootDir 'setup-artifacts'
    $logs      = Join-Path $artifacts 'logs'

    return @{
        Root      = $RootDir
        Artifacts = $artifacts
        Logs      = $logs
        Plan      = Join-Path $artifacts 'plan.json'
        State     = Join-Path $artifacts 'state.json'
        Catalog   = Join-Path $RootDir  'catalog.json'
    }
}

function Initialize-ArtifactDirectories {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Initialises multiple directories — plural noun is semantically correct.')]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Paths
    )

    foreach ($dir in @($Paths.Artifacts, $Paths.Logs)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

$script:LogFile = $null

function Initialize-Log {
    param(
        [Parameter(Mandatory)]
        [string]$LogDir
    )

    $timestamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:LogFile = Join-Path $LogDir "setup_$timestamp.log"
    Write-SetupLog "=== PC Setup Log started at $(Get-Date -Format 'u') ==="
}

function Write-SetupLog {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Logging requires coloured console output via Write-Host.')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Message,

        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Level = 'INFO'
    )

    process {
        $ts   = Get-Date -Format 'HH:mm:ss'
        $line = "[$ts][$Level] $Message"

        # Console
        switch ($Level) {
            'WARN'  { Write-Host $line -ForegroundColor Yellow }
            'ERROR' { Write-Host $line -ForegroundColor Red    }
            'DEBUG' { Write-Host $line -ForegroundColor DarkGray }
            default { Write-Host $line }
        }

        # File
        if ($script:LogFile) {
            try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
            catch { $null = $_ <# Intentionally ignored — logging must not interrupt the calling operation #> }
        }
    }
}

# ---------------------------------------------------------------------------
# Atomic JSON write
# ---------------------------------------------------------------------------

function Write-JsonAtomic {
    <#
    .SYNOPSIS
        Writes an object as JSON to $Path using an atomic temp-then-rename strategy.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        $InputObject,

        [int]$Depth = 10
    )

    $dir  = Split-Path $Path -Parent
    $tmp  = Join-Path $dir ([System.IO.Path]::GetRandomFileName())

    try {
        $json = ConvertTo-Json -InputObject $InputObject -Depth $Depth
        # Write and flush
        [System.IO.File]::WriteAllText($tmp, $json, [System.Text.Encoding]::UTF8)
        # Atomic rename
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } catch {
        # Clean up temp on error
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        throw
    }
}

function Read-JsonFile {
    <#
    .SYNOPSIS
        Reads a JSON file and returns a PSCustomObject.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }

    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    return ConvertFrom-Json $raw
}

# ---------------------------------------------------------------------------
# Environment checks
# ---------------------------------------------------------------------------

function Test-Windows11 {
    [OutputType([bool])]
    param()

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        # Windows 11 reports build >= 22000
        $build = [int]($os.BuildNumber)
        return $build -ge 22000
    } catch {
        return $false
    }
}

function Get-OsVersion {
    [OutputType([string])]
    param()

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        return $os.Caption
    } catch {
        return 'Unknown'
    }
}

function Test-WingetAvailable {
    [OutputType([bool])]
    param()

    return ($null -ne (Get-Command winget -ErrorAction SilentlyContinue))
}

function Assert-Prerequisites {
    <#
    .SYNOPSIS
        Validates Windows 11 + winget are present. Throws if not.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Checks multiple prerequisites — plural noun is semantically correct.')]
    param(
        [Parameter(Mandatory)]
        [hashtable]$RunContext
    )

    if (-not (Test-Windows11)) {
        Write-SetupLog 'WARNING: OS is not Windows 11 (build < 22000). Continuing anyway.' -Level WARN
    }

    if ($RunContext.Mode -ne 'DryRun' -and -not (Test-WingetAvailable)) {
        throw 'winget is not available. Install the App Installer package from the Microsoft Store and try again.'
    }

    if (-not (Test-WingetAvailable)) {
        Write-SetupLog 'winget not found — running in DryRun/Mock without real installs.' -Level WARN
    }
}

# ---------------------------------------------------------------------------
# Archive artifacts
# ---------------------------------------------------------------------------

function Invoke-ArchiveArtifacts {
    <#
    .SYNOPSIS
        Archives existing plan/state/logs into a timestamped subfolder.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Archives multiple artifacts — plural noun is semantically correct.')]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Paths
    )

    $ts      = Get-Date -Format 'yyyyMMdd_HHmmss'
    $archive = Join-Path $Paths.Artifacts "archive_$ts"
    New-Item -ItemType Directory -Path $archive -Force | Out-Null

    foreach ($file in @($Paths.Plan, $Paths.State)) {
        if (Test-Path $file) {
            Move-Item -LiteralPath $file -Destination $archive -Force
            Write-SetupLog "Archived: $file -> $archive"
        }
    }

    # Archive log files
    $logFiles = Get-ChildItem -Path $Paths.Logs -Filter '*.log' -ErrorAction SilentlyContinue
    foreach ($lf in $logFiles) {
        Move-Item -LiteralPath $lf.FullName -Destination $archive -Force
    }

    Write-SetupLog "Previous artifacts archived to: $archive"
}
