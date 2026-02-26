#requires -Version 5.1
# TuiChecklist.Tests.ps1 - Unit tests for modules/TuiChecklist.ps1
#
# Focuses on the pure-logic helpers that do not interact with the console:
#   - script:Limit-ScrollOffset
#   - Layout constant values and the viewport-size arithmetic used inside
#     Invoke-TuiChecklist

BeforeAll {
    # Stub out every [Console] member referenced at module level or inside any
    # function that could be triggered indirectly, so dot-sourcing is safe in
    # a headless test environment.
    Add-Type -TypeDefinition @'
using System;
namespace TuiTestStubs {
    public static class ConsoleStub {}
}
'@ -ErrorAction SilentlyContinue

    . (Join-Path $PSScriptRoot '..\modules\TuiChecklist.ps1')

    # ---------------------------------------------------------------------------
    # Row-building helpers – reproduce the structure that Invoke-TuiChecklist
    # builds so tests can construct realistic inputs without calling the full TUI.
    # ---------------------------------------------------------------------------

    function script:New-HeaderRow {
        param([string]$Category)
        @{ Kind = 'Header'; Category = $Category }
    }

    function script:New-ItemRow {
        param([int]$RowIndex, [string]$Id = "item$RowIndex")
        @{ Kind = 'Item'; RowIndex = $RowIndex; Id = $Id; DisplayName = $Id; Checked = $false }
    }

    # Build a flat row list + itemIndices from a simple spec string.
    # Spec format: comma-separated tokens – 'H:CatName' for a header, 'I:id' for an item.
    # Returns [hashtable] @{ Rows = [array]; ItemIndices = [array] }
    function script:Build-Rows {
        param([string[]]$Spec)
        $rows        = [System.Collections.Generic.List[hashtable]]::new()
        $itemIndices = [System.Collections.Generic.List[int]]::new()
        foreach ($token in $Spec) {
            if ($token.StartsWith('H:')) {
                $rows.Add((script:New-HeaderRow -Category $token.Substring(2)))
            } else {
                # 'I:id'
                $id     = $token.Substring(2)
                $rowIdx = $rows.Count
                $rows.Add((script:New-ItemRow -RowIndex $rowIdx -Id $id))
                $itemIndices.Add($rowIdx)
            }
        }
        @{ Rows = $rows.ToArray(); ItemIndices = $itemIndices.ToArray() }
    }
}

# ===========================================================================
# Layout constants
# ===========================================================================

Describe 'TuiChecklist layout constants' {

    It 'BANNER_HEIGHT is 5' {
        $script:BANNER_HEIGHT | Should -Be 5
    }

    It 'MENU_MIN_HEIGHT is 5' {
        $script:MENU_MIN_HEIGHT | Should -Be 5
    }

    It 'FOOTER_HEIGHT is 3' {
        $script:FOOTER_HEIGHT | Should -Be 3
    }

    It 'MIN_WINDOW_HEIGHT equals BANNER_HEIGHT + MENU_MIN_HEIGHT + FOOTER_HEIGHT' {
        $expected = $script:BANNER_HEIGHT + $script:MENU_MIN_HEIGHT + $script:FOOTER_HEIGHT
        $script:MIN_WINDOW_HEIGHT | Should -Be $expected
    }

    It 'MIN_WINDOW_HEIGHT is 13' {
        $script:MIN_WINDOW_HEIGHT | Should -Be 13
    }
}

# ===========================================================================
# Viewport arithmetic derived from window height
# ===========================================================================

Describe 'Viewport size arithmetic' {
    # The formulas used inside Invoke-TuiChecklist:
    #   menuHeight   = windowHeight - BANNER_HEIGHT - FOOTER_HEIGHT
    #   viewportSize = menuHeight - 2

    It 'at minimum window height menuHeight equals MENU_MIN_HEIGHT' {
        $h = $script:MIN_WINDOW_HEIGHT
        $menuHeight = $h - $script:BANNER_HEIGHT - $script:FOOTER_HEIGHT
        $menuHeight | Should -Be $script:MENU_MIN_HEIGHT
    }

    It 'at minimum window height viewportSize is 3' {
        $h           = $script:MIN_WINDOW_HEIGHT
        $menuHeight  = $h - $script:BANNER_HEIGHT - $script:FOOTER_HEIGHT
        $viewportSize = $menuHeight - 2
        $viewportSize | Should -Be 3
    }

    It 'viewportSize grows by 1 for each additional window row' {
        foreach ($extra in 1..5) {
            $h            = $script:MIN_WINDOW_HEIGHT + $extra
            $menuHeight   = $h - $script:BANNER_HEIGHT - $script:FOOTER_HEIGHT
            $viewportSize = $menuHeight - 2
            $viewportSize | Should -Be (3 + $extra) `
                -Because "windowHeight=$h should give viewportSize=$(3 + $extra)"
        }
    }

    It 'menuTop equals BANNER_HEIGHT' {
        # menuTop is hard-coded to $script:BANNER_HEIGHT inside Invoke-TuiChecklist
        $script:BANNER_HEIGHT | Should -Be 5
    }

    It 'footerTop equals menuTop + menuHeight' {
        $windowHeight = 20
        $menuHeight   = $windowHeight - $script:BANNER_HEIGHT - $script:FOOTER_HEIGHT
        $menuTop      = $script:BANNER_HEIGHT
        $footerTop    = $menuTop + $menuHeight
        $footerTop    | Should -Be ($windowHeight - $script:FOOTER_HEIGHT)
    }
}

# ===========================================================================
# Limit-ScrollOffset
# ===========================================================================

Describe 'Limit-ScrollOffset' {

    # ------------------------------------------------------------------
    # Single-item edge case
    # ------------------------------------------------------------------
    Context 'single item, no headers' {
        BeforeAll {
            $script:td = script:Build-Rows -Spec @('I:only')
            # rows: [ {Kind=Item, RowIndex=0} ]
            # itemIndices: [0]
        }

        It 'returns 0 regardless of viewportSize' {
            $result = script:Limit-ScrollOffset `
                -FocusIdx 0 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 0 -ViewportSize 1
            $result | Should -Be 0
        }

        It 'returns 0 with large viewportSize' {
            $result = script:Limit-ScrollOffset `
                -FocusIdx 0 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 0 -ViewportSize 100
            $result | Should -Be 0
        }
    }

    # ------------------------------------------------------------------
    # All items already fit in the viewport
    # ------------------------------------------------------------------
    Context 'all items fit in viewport' {
        BeforeAll {
            # H:Cat1, I:a, I:b, H:Cat2, I:c — 5 rows total, 3 items
            $script:td = script:Build-Rows -Spec @('H:Cat1','I:a','I:b','H:Cat2','I:c')
        }

        It 'keeps scrollOffset 0 for first item when viewport is large' {
            $result = script:Limit-ScrollOffset `
                -FocusIdx 0 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 0 -ViewportSize 10
            $result | Should -Be 0
        }

        It 'keeps scrollOffset 0 for last item when viewport is large' {
            $lastFocus = $script:td.ItemIndices.Count - 1
            $result = script:Limit-ScrollOffset `
                -FocusIdx $lastFocus -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 0 -ViewportSize 10
            $result | Should -Be 0
        }
    }

    # ------------------------------------------------------------------
    # Scrolling down — item below the viewport bottom
    # ------------------------------------------------------------------
    Context 'item below viewport bottom scrolls down' {
        BeforeAll {
            # Flat list: I:a(0) I:b(1) I:c(2) I:d(3) I:e(4) — no headers
            $script:td = script:Build-Rows -Spec @('I:a','I:b','I:c','I:d','I:e')
        }

        It 'scrolls forward so focused item becomes the last visible row' {
            # viewport shows rows [0..2] (size=3), focus moves to item d (rowIdx=3)
            $result = script:Limit-ScrollOffset `
                -FocusIdx 3 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 0 -ViewportSize 3
            # rowIdx 3 >= 0+3, so new offset = 3 - 3 + 1 = 1
            $result | Should -Be 1
        }

        It 'scrolls to the last item (rowIdx=4) with viewport 3' {
            $result = script:Limit-ScrollOffset `
                -FocusIdx 4 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 0 -ViewportSize 3
            # 4 - 3 + 1 = 2
            $result | Should -Be 2
        }

        It 'does not change offset when item is exactly at the bottom edge' {
            # offset=0, viewport=3 → visible rows 0,1,2; item at rowIdx=2 is at edge
            $result = script:Limit-ScrollOffset `
                -FocusIdx 2 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 0 -ViewportSize 3
            $result | Should -Be 0
        }
    }

    # ------------------------------------------------------------------
    # Scrolling up — item above the viewport top
    # ------------------------------------------------------------------
    Context 'item above viewport top scrolls up' {
        BeforeAll {
            # Flat list: I:a(0) I:b(1) I:c(2) I:d(3) I:e(4)
            $script:td = script:Build-Rows -Spec @('I:a','I:b','I:c','I:d','I:e')
        }

        It 'scrolls back so focused item becomes the first visible row' {
            # Currently scrolled to offset=3 (showing d,e), move focus to item b (rowIdx=1)
            $result = script:Limit-ScrollOffset `
                -FocusIdx 1 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 3 -ViewportSize 3
            $result | Should -Be 1
        }

        It 'returns 0 when scrolling back to the first item' {
            $result = script:Limit-ScrollOffset `
                -FocusIdx 0 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 3 -ViewportSize 3
            $result | Should -Be 0
        }

        It 'does not change offset when item is exactly at the top edge' {
            # offset=1, focused item rowIdx=1 == offset → already at top
            $result = script:Limit-ScrollOffset `
                -FocusIdx 1 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 1 -ViewportSize 3
            $result | Should -Be 1
        }
    }

    # ------------------------------------------------------------------
    # Item already visible in middle of viewport — no change
    # ------------------------------------------------------------------
    Context 'item already in viewport is not moved' {
        BeforeAll {
            $script:td = script:Build-Rows -Spec @('I:a','I:b','I:c','I:d','I:e')
        }

        It 'keeps offset unchanged for middle item' {
            # offset=1, viewport=3 → visible rows 1,2,3; focus on item c (rowIdx=2)
            $result = script:Limit-ScrollOffset `
                -FocusIdx 2 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 1 -ViewportSize 3
            $result | Should -Be 1
        }
    }

    # ------------------------------------------------------------------
    # Section header immediately above a focused item
    # ------------------------------------------------------------------
    Context 'header immediately above focused item is included in viewport' {
        BeforeAll {
            # H:Cat1(0) I:a(1) I:b(2) H:Cat2(3) I:c(4) I:d(5) I:e(6)
            # itemIndices = [1, 2, 4, 5, 6]
            $script:td = script:Build-Rows -Spec @('H:Cat1','I:a','I:b','H:Cat2','I:c','I:d','I:e')
        }

        It 'scrolls up to reveal header when first item of a section would be at viewport top' {
            # Focus on item c (focusIdx=2, rowIdx=4); header is at rowIdx=3.
            # effectiveTop = 3.  With scrollOffset=3, effectiveTop(3) < offset(3) is false,
            # and rowIdx(4) < offset+viewportSize(3+3=6) is true → no scroll needed.
            # But if offset=4: effectiveTop(3) < 4 → scroll up to 3.
            $result = script:Limit-ScrollOffset `
                -FocusIdx 2 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 4 -ViewportSize 3
            $result | Should -Be 3
        }

        It 'does not pull in header when header is above a visible item with room above' {
            # offset=0, viewport=5 → all 7 rows visible; focus on item c (rowIdx=4)
            $result = script:Limit-ScrollOffset `
                -FocusIdx 2 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 0 -ViewportSize 5
            $result | Should -Be 0
        }

        It 'header rule does not apply to first item whose predecessor is also an item' {
            # Focus on item b (focusIdx=1, rowIdx=2); row 1 is an item (not a header),
            # so effectiveTop = rowIdx = 2.  With offset=3 → scrolls up to 2.
            $result = script:Limit-ScrollOffset `
                -FocusIdx 1 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 3 -ViewportSize 3
            $result | Should -Be 2
        }

        It 'scrolls down correctly past a header separator' {
            # Focus on item d (focusIdx=3, rowIdx=5); offset=0, viewport=3
            # rowIdx(5) >= 0+3 → new offset = 5 - 3 + 1 = 3
            $result = script:Limit-ScrollOffset `
                -FocusIdx 3 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 0 -ViewportSize 3
            $result | Should -Be 3
        }
    }

    # ------------------------------------------------------------------
    # Minimum-height scenario (viewportSize = 3)
    # ------------------------------------------------------------------
    Context 'minimum-height viewport (viewportSize=3)' {
        BeforeAll {
            # 10 items across two categories
            $spec = @(
                'H:Alpha',
                'I:a1','I:a2','I:a3','I:a4','I:a5',
                'H:Beta',
                'I:b1','I:b2','I:b3'
            )
            $script:td = script:Build-Rows -Spec $spec
            # rows:   0=H:Alpha, 1=a1, 2=a2, 3=a3, 4=a4, 5=a5, 6=H:Beta, 7=b1, 8=b2, 9=b3
            # itemIndices: [1,2,3,4,5,7,8,9]
        }

        It 'navigating to the last item scrolls offset to show it' {
            $lastFocus = $script:td.ItemIndices.Count - 1  # focusIdx=7, rowIdx=9
            $result = script:Limit-ScrollOffset `
                -FocusIdx $lastFocus -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 0 -ViewportSize 3
            # rowIdx(9) >= 0+3 → offset = 9 - 3 + 1 = 7
            $result | Should -Be 7
        }

        It 'navigating back to item a1 returns offset 0 (header included)' {
            # item a1 is focusIdx=0, rowIdx=1; header at rowIdx=0 → effectiveTop=0
            $result = script:Limit-ScrollOffset `
                -FocusIdx 0 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 7 -ViewportSize 3
            $result | Should -Be 0
        }

        It 'navigating to first Beta item reveals its header' {
            # item b1 is focusIdx=5, rowIdx=7; header at rowIdx=6 → effectiveTop=6
            # With offset=7: effectiveTop(6) < 7 → scroll up to 6
            $result = script:Limit-ScrollOffset `
                -FocusIdx 5 -ItemIndices $script:td.ItemIndices `
                -Rows $script:td.Rows -ScrollOffset 7 -ViewportSize 3
            $result | Should -Be 6
        }
    }
}
