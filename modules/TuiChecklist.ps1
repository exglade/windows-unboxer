#requires -Version 5.1
# TuiChecklist.ps1 - Keyboard-only interactive checklist TUI

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Internal rendering helpers
# ---------------------------------------------------------------------------

function script:Render-Checklist {
    param(
        [array]  $Rows,       # flat list: @{Kind='Header'|'Item'; ...}
        [int]    $CursorIdx,  # index into $Rows for current cursor (Items only)
        [int[]]  $ItemIndices # indices in $Rows that are selectable Items
    )

    [Console]::CursorVisible = $false
    $origFg = [Console]::ForegroundColor
    $origBg = [Console]::BackgroundColor

    $topRow   = [Console]::CursorTop
    $maxWidth = [Console]::WindowWidth - 2
    if ($maxWidth -lt 40) { $maxWidth = 40 }

    $lineNum = 0
    foreach ($row in $Rows) {
        [Console]::SetCursorPosition(0, $topRow + $lineNum)

        if ($row.Kind -eq 'Header') {
            # Category header — not selectable
            $label = "  -- $($row.Category) --"
            $pad   = $label.PadRight($maxWidth)
            [Console]::ForegroundColor = [ConsoleColor]::Cyan
            [Console]::BackgroundColor = $origBg
            Write-Host $pad -NoNewline
        } else {
            $isSelected = $row.Checked
            $isCursor   = ($row.RowIndex -eq $CursorIdx)

            $checkMark  = if ($isSelected) { '[x]' } else { '[ ]' }
            $label      = "$checkMark $($row.DisplayName)"
            $pad        = $label.PadRight($maxWidth)

            if ($isCursor) {
                [Console]::ForegroundColor = [ConsoleColor]::Black
                [Console]::BackgroundColor = [ConsoleColor]::Cyan
            } elseif ($isSelected) {
                [Console]::ForegroundColor = [ConsoleColor]::Green
                [Console]::BackgroundColor = $origBg
            } else {
                [Console]::ForegroundColor = $origFg
                [Console]::BackgroundColor = $origBg
            }
            Write-Host $pad -NoNewline
        }

        $lineNum++
    }

    # Reset colors and move below list
    [Console]::ForegroundColor = $origFg
    [Console]::BackgroundColor = $origBg
    [Console]::SetCursorPosition(0, $topRow + $lineNum)
    Write-Host ''

    # Instructions row
    [Console]::SetCursorPosition(0, $topRow + $lineNum + 1)
    [Console]::ForegroundColor = [ConsoleColor]::DarkGray
    Write-Host '  UP/DOWN: move   SPACE: toggle   ENTER: confirm   ESC: cancel    ' -NoNewline
    [Console]::ForegroundColor = $origFg
}

# ---------------------------------------------------------------------------
# Public function
# ---------------------------------------------------------------------------

function Invoke-TuiChecklist {
    <#
    .SYNOPSIS
        Shows an interactive keyboard checklist grouped by category.
        Returns an array of selected item IDs, or $null if ESC was pressed.
    .PARAMETER Items
        Sorted catalog items (PSCustomObjects with id, category, displayName).
    .PARAMETER PreselectedIds
        Array of IDs to pre-check.
    .PARAMETER Title
        Heading shown above the list.
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Items,

        [array]$PreselectedIds = @(),

        [string]$Title = 'Select items to install/configure'
    )

    if ($Items.Count -eq 0) {
        Write-Warning 'No catalog items to display.'
        return @()
    }

    # Build a lookup of checked states
    $checkedMap = @{}
    foreach ($item in $Items) {
        $checkedMap[$item.id] = ($PreselectedIds -contains $item.id)
    }

    # Build flat row list (headers + items interspersed)
    $rows        = [System.Collections.Generic.List[hashtable]]::new()
    $itemIndices = [System.Collections.Generic.List[int]]::new()  # row indices that are Items
    $lastCat     = $null

    foreach ($item in $Items) {
        if ($item.category -ne $lastCat) {
            $rows.Add(@{ Kind = 'Header'; Category = $item.category })
            $lastCat = $item.category
        }
        $rowIdx = $rows.Count
        $rows.Add(@{
            Kind        = 'Item'
            RowIndex    = $rowIdx
            Id          = $item.id
            DisplayName = $item.displayName
            Checked     = $checkedMap[$item.id]
        })
        $itemIndices.Add($rowIdx)
    }

    # Cursor tracks index into $itemIndices (which item is focused)
    $focusIdx = 0  # index into $itemIndices list

    # Clear area and print header
    Clear-Host
    $headerLines = 3
    Write-Host ''
    [Console]::ForegroundColor = [ConsoleColor]::White
    Write-Host "  $Title" -NoNewline
    [Console]::ResetColor()
    Write-Host ''
    Write-Host ''

    $startTop = [Console]::CursorTop

    # Ensure enough console buffer lines exist (scroll if needed)
    $neededLines = $rows.Count + 3
    $bufLines    = [Console]::BufferHeight - $startTop - 1
    if ($neededLines -gt $bufLines) {
        # Print blank lines to scroll
        for ($i = 0; $i -lt ($neededLines - $bufLines); $i++) {
            Write-Host ''
        }
        [Console]::SetCursorPosition(0, $startTop)
    }

    # Initial render
    $cursorRowIdx = $itemIndices[$focusIdx]
    Render-Checklist -Rows $rows -CursorIdx $cursorRowIdx -ItemIndices $itemIndices

    # Input loop
    while ($true) {
        $key = [Console]::ReadKey($true)  # intercept = true (don't echo)

        switch ($key.Key) {

            'UpArrow' {
                if ($focusIdx -gt 0) { $focusIdx-- }
            }

            'DownArrow' {
                if ($focusIdx -lt ($itemIndices.Count - 1)) { $focusIdx++ }
            }

            'Spacebar' {
                $ri = $itemIndices[$focusIdx]
                $row = $rows[$ri]
                $row.Checked = -not $row.Checked
                $checkedMap[$row.Id] = $row.Checked
            }

            'Enter' {
                # Confirm — return selected IDs
                [Console]::CursorVisible = $true
                $selected = $rows |
                    Where-Object { $_.Kind -eq 'Item' -and $_.Checked } |
                    ForEach-Object { $_.Id }
                return @($selected)
            }

            'Escape' {
                [Console]::CursorVisible = $true
                return $null
            }
        }

        $cursorRowIdx = $itemIndices[$focusIdx]
        Render-Checklist -Rows $rows -CursorIdx $cursorRowIdx -ItemIndices $itemIndices
    }
}
