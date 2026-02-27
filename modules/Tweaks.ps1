#requires -Version 5.1
# Tweaks.ps1 - Explorer restart helpers

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Explorer restart
# ---------------------------------------------------------------------------

function Restart-Explorer {
    [CmdletBinding()]
    param()

    Write-Log 'Restarting Explorer...' -Level INFO

    # Stop all explorer instances
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 1000

    # Shell restarts Explorer automatically; if not, start it
    $running = Get-Process -Name explorer -ErrorAction SilentlyContinue
    if (-not $running) {
        Start-Process explorer.exe
        Start-Sleep -Milliseconds 1500
    }

    Write-Log 'Explorer restarted.' -Level INFO
}

# ---------------------------------------------------------------------------
# Post-execution Explorer prompt
# ---------------------------------------------------------------------------

function Invoke-ExplorerRestartPrompt {
    <#
    .SYNOPSIS
        Prompts user to restart Explorer after all tweaks are done.
        Skipped in DryRun and when TweakTarget=Test.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$RunContext
    )

    if ($RunContext.Mode -eq 'DryRun' -or $RunContext.TweakTarget -eq 'Test') {
        return
    }

    if ($RunContext.Silent) {
        Write-Log 'Silent mode — restarting Explorer automatically.' -Level INFO
        Restart-Explorer
        return
    }

    Write-Host ''
    Write-Host '  Some tweaks requested an Explorer restart.' -ForegroundColor Yellow
    Write-Host '  Restart Explorer now? (Y/N): ' -NoNewline

    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    Write-Host $key.Character

    if ($key.Character -eq 'Y' -or $key.Character -eq 'y') {
        Restart-Explorer
    } else {
        Write-Log 'Explorer restart deferred by user.' -Level INFO
    }
}
