#requires -Version 5.1
# TuiChecklist.ps1 - Keyboard-only interactive checklist TUI

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Layout constants
# ---------------------------------------------------------------------------

$script:BANNER_HEIGHT    = 5   # rows 0-4
$script:MENU_MIN_HEIGHT  = 5   # minimum rows for the scrollable menu zone
$script:FOOTER_HEIGHT    = 3   # rows below menu
$script:MIN_WINDOW_HEIGHT = $script:BANNER_HEIGHT + $script:MENU_MIN_HEIGHT + $script:FOOTER_HEIGHT  # 13

# ---------------------------------------------------------------------------
# Internal rendering helpers
# ---------------------------------------------------------------------------

function script:Show-Banner {
    param(
        [string] $Title,
        [int]    $MaxWidth
    )
    # 5 lines: blank / title / blank / rule / blank
    [Console]::CursorVisible = $false
    $origFg = [Console]::ForegroundColor

    [Console]::SetCursorPosition(0, 0)
    Write-Host ''.PadRight($MaxWidth) -NoNewline                           # row 0 blank

    [Console]::SetCursorPosition(0, 1)
    [Console]::ForegroundColor = [ConsoleColor]::White
    Write-Host "  $Title".PadRight($MaxWidth) -NoNewline                   # row 1 title

    [Console]::SetCursorPosition(0, 2)
    [Console]::ForegroundColor = $origFg
    Write-Host ''.PadRight($MaxWidth) -NoNewline                           # row 2 blank

    [Console]::SetCursorPosition(0, 3)
    [Console]::ForegroundColor = [ConsoleColor]::DarkGray
    Write-Host ("  " + ([string][char]0x2500) * [Math]::Max(0, $MaxWidth - 4)).PadRight($MaxWidth) -NoNewline  # row 3 rule

    [Console]::SetCursorPosition(0, 4)
    [Console]::ForegroundColor = $origFg
    Write-Host ''.PadRight($MaxWidth) -NoNewline                           # row 4 blank

    [Console]::ForegroundColor = $origFg
}

function script:Show-Footer {
    param(
        [int] $FooterTop,
        [int] $MaxWidth
    )
    # 3 lines: rule / instructions / blank
    $origFg = [Console]::ForegroundColor

    [Console]::SetCursorPosition(0, $FooterTop)
    [Console]::ForegroundColor = [ConsoleColor]::DarkGray
    Write-Host ("  " + ([string][char]0x2500) * [Math]::Max(0, $MaxWidth - 4)).PadRight($MaxWidth) -NoNewline  # row 0 rule

    [Console]::ForegroundColor = $origFg
    [Console]::SetCursorPosition(0, $FooterTop + 1)
    Write-Host '  UP/DOWN: move   SPACE: toggle   ENTER: confirm   ESC: cancel'.PadRight($MaxWidth) -NoNewline  # row 1 instructions

    [Console]::SetCursorPosition(0, $FooterTop + 2)
    [Console]::ForegroundColor = $origFg
    Write-Host ''.PadRight($MaxWidth) -NoNewline                           # row 2 blank


}

function script:Limit-ScrollOffset {
    param(
        [int]   $FocusIdx,
        [array] $ItemIndices,
        [array] $Rows,
        [int]   $ScrollOffset,
        [int]   $ViewportSize
    )
    $rowIdx = $ItemIndices[$FocusIdx]
    # If a section header sits immediately above the focused item, include it in the viewport
    $effectiveTop = $rowIdx
    if ($rowIdx -gt 0 -and $Rows[$rowIdx - 1].Kind -eq 'Header') {
        $effectiveTop = $rowIdx - 1
    }
    if ($effectiveTop -lt $ScrollOffset) {
        return $effectiveTop
    }
    if ($rowIdx -ge ($ScrollOffset + $ViewportSize)) {
        return $rowIdx - $ViewportSize + 1
    }
    return $ScrollOffset
}

function script:Show-Checklist {
    param(
        [array] $Rows,
        [array] $ItemIndices,
        [int]   $FocusIdx,     # index into $ItemIndices
        [int]   $ScrollOffset, # first $Rows index in viewport
        [int]   $MenuTop,      # absolute console row where menu zone starts
        [int]   $MenuHeight,   # total rows in menu zone
        [int]   $MaxWidth
    )

    [Console]::CursorVisible = $false
    $origFg = [Console]::ForegroundColor
    $origBg = [Console]::BackgroundColor

    $viewportSize  = $MenuHeight - 2   # rows 1..(MenuHeight-2) hold actual items
    $cursorRowIdx  = $ItemIndices[$FocusIdx]

    # --- top indicator (row 0 of menu zone) ---
    [Console]::SetCursorPosition(0, $MenuTop)
    if ($ScrollOffset -gt 0) {
        [Console]::ForegroundColor = [ConsoleColor]::DarkGray
        Write-Host "  $([char]0x2191) ... ($ScrollOffset more above)".PadRight($MaxWidth) -NoNewline
    } else {
        [Console]::ForegroundColor = $origFg
        Write-Host ''.PadRight($MaxWidth) -NoNewline
    }

    # --- visible rows ---
    for ($slot = 0; $slot -lt $viewportSize; $slot++) {
        $rowIdx = $ScrollOffset + $slot
        [Console]::SetCursorPosition(0, $MenuTop + 1 + $slot)

        if ($rowIdx -ge $Rows.Count) {
            # past end — blank padding
            [Console]::ForegroundColor = $origFg
            [Console]::BackgroundColor = $origBg
            Write-Host ''.PadRight($MaxWidth) -NoNewline
            continue
        }

        $row = $Rows[$rowIdx]

        if ($row.Kind -eq 'Header') {
            [Console]::ForegroundColor = [ConsoleColor]::Cyan
            [Console]::BackgroundColor = $origBg
            $label = "  -- $($row.Category) --"
            Write-Host $label.PadRight($MaxWidth) -NoNewline
        } else {
            $isCursor  = ($row.RowIndex -eq $cursorRowIdx)
            $checkMark = if ($row.Checked) { '[x]' } else { '[ ]' }
            $label     = "$checkMark $($row.DisplayName)"

            if ($isCursor) {
                [Console]::ForegroundColor = [ConsoleColor]::Black
                [Console]::BackgroundColor = [ConsoleColor]::Cyan
            } elseif ($row.Checked) {
                [Console]::ForegroundColor = [ConsoleColor]::Green
                [Console]::BackgroundColor = $origBg
            } else {
                [Console]::ForegroundColor = $origFg
                [Console]::BackgroundColor = $origBg
            }
            Write-Host $label.PadRight($MaxWidth) -NoNewline
        }
    }

    # --- bottom indicator (last row of menu zone) ---
    [Console]::ForegroundColor = $origFg
    [Console]::BackgroundColor = $origBg
    [Console]::SetCursorPosition(0, $MenuTop + $MenuHeight - 1)
    $remaining = $Rows.Count - ($ScrollOffset + $viewportSize)
    if ($remaining -gt 0) {
        [Console]::ForegroundColor = [ConsoleColor]::DarkGray
        Write-Host "  $([char]0x2193) ... ($remaining more below)".PadRight($MaxWidth) -NoNewline
    } else {
        Write-Host ''.PadRight($MaxWidth) -NoNewline
    }

    [Console]::ForegroundColor = $origFg
    [Console]::BackgroundColor = $origBg
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

    # --- Minimum height guard ---
    $windowHeight = [Console]::WindowHeight
    if ($windowHeight -lt $script:MIN_WINDOW_HEIGHT) {
        throw [System.InvalidOperationException]::new("Terminal window is too small (height = $windowHeight lines). Minimum required height is $($script:MIN_WINDOW_HEIGHT) lines.")
    }

    # --- Compute zone heights ---
    $menuHeight   = $windowHeight - $script:BANNER_HEIGHT - $script:FOOTER_HEIGHT
    $viewportSize = $menuHeight - 2           # slots between the two indicators
    $menuTop      = $script:BANNER_HEIGHT     # = 5
    $footerTop    = $menuTop + $menuHeight

    $maxWidth = [Math]::Max(40, [Console]::WindowWidth - 2)

    # --- Build flat row list (headers + items interspersed) ---
    $checkedMap  = @{}
    foreach ($item in $Items) {
        $checkedMap[$item.id] = ($PreselectedIds -contains $item.id)
    }

    $rows        = [System.Collections.Generic.List[hashtable]]::new()
    $itemIndices = [System.Collections.Generic.List[int]]::new()
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

    # --- Initial state ---
    $focusIdx    = 0
    $scrollOffset = 0

    # --- Static render (banner + footer rendered once) ---
    try {
        Clear-Host
        Show-Banner -Title $Title -MaxWidth $maxWidth
        Show-Footer -FooterTop $footerTop -MaxWidth $maxWidth

        # --- Initial menu render ---
        Show-Checklist -Rows $rows -ItemIndices $itemIndices `
            -FocusIdx $focusIdx -ScrollOffset $scrollOffset `
            -MenuTop $menuTop -MenuHeight $menuHeight -MaxWidth $maxWidth

        # --- Input loop ---
        while ($true) {
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {

                'UpArrow' {
                    if ($focusIdx -gt 0) {
                        $focusIdx--
                        $scrollOffset = Limit-ScrollOffset -FocusIdx $focusIdx `
                            -ItemIndices $itemIndices -Rows $rows -ScrollOffset $scrollOffset -ViewportSize $viewportSize
                    }
                }

                'DownArrow' {
                    if ($focusIdx -lt ($itemIndices.Count - 1)) {
                        $focusIdx++
                        $scrollOffset = Limit-ScrollOffset -FocusIdx $focusIdx `
                            -ItemIndices $itemIndices -Rows $rows -ScrollOffset $scrollOffset -ViewportSize $viewportSize
                    }
                }

                'Spacebar' {
                    $ri  = $itemIndices[$focusIdx]
                    $row = $rows[$ri]
                    $row.Checked          = -not $row.Checked
                    $checkedMap[$row.Id]  = $row.Checked
                }

                'Enter' {
                    $selected = $rows |
                        Where-Object { $_.Kind -eq 'Item' -and $_.Checked } |
                        ForEach-Object { $_.Id }
                    return @($selected)
                }

                'Escape' {
                    return $null
                }
            }

            Show-Checklist -Rows $rows -ItemIndices $itemIndices `
                -FocusIdx $focusIdx -ScrollOffset $scrollOffset `
                -MenuTop $menuTop -MenuHeight $menuHeight -MaxWidth $maxWidth
        }
    } finally {
        # Ensure the cursor is always restored, even if an exception is thrown
        # during rendering or input handling.
        [Console]::CursorVisible = $true
    }
}
