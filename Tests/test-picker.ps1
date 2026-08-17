param([string]$Root)
<#
 Drives the shared picker with scripted keystrokes.

 WHY THIS EXISTS

 Show-Picker moved out of Repair-Health.ps1 into Common.ps1 so the health
 report could ask "which sections?" with the same interface as "which
 repairs?". That refactor made one piece of fiddly, heavily-patched code
 serve two callers, which is the right shape and also doubles what a
 regression breaks.

 The picker cannot run under redirected input, so nothing in the check
 suite exercised its navigation at all: the frame either drew or it did
 not, and everything underneath (index wrapping, skipping the spacer row,
 START with nothing ticked, Esc, the Cancel row) was only ever proven by
 hand. Its -TestKeys mode exists precisely so that logic can be driven
 without a console, and until now nothing used it.

 Virtual key codes: 38 up, 40 down, 13 enter, 27 esc, 32 space.
#>
if (-not $Root) { $Root = Join-Path (Split-Path $PSScriptRoot -Parent) 'Tools' }
. (Join-Path $Root 'Common.ps1')

$fail = 0
function Check($name, $ok, $detail = '') {
    if ($ok) { Write-Host ("  PASS  {0}" -f $name) -ForegroundColor Green }
    else     { Write-Host ("  FAIL  {0}  {1}" -f $name, $detail) -ForegroundColor Red; $script:fail++ }
}

# Three items, so the row list is: 0,1,2 items | 3 gap | 4 START | 5 Cancel
function NewItems {
    @(
        [pscustomobject]@{ Key='1'; On=$true;  Name='First';  Desc='the first one';  Changes=$false; Time='no time'; Low=0; High=0 }
        [pscustomobject]@{ Key='2'; On=$true;  Name='Second'; Desc='the second one'; Changes=$false; Time='no time'; Low=0; High=0 }
        [pscustomobject]@{ Key='3'; On=$false; Name='Third';  Desc='the third one';  Changes=$true;  Time='no time'; Low=0; High=0 }
    )
}

Write-Host ''
Write-Host 'PICKER NAVIGATION' -ForegroundColor Cyan

# --- Esc cancels, and changes nothing --------------------------------
$items = NewItems
$r = Show-Picker -Items $items -TestKeys @(27)
Check 'Esc returns cancel' ($r -eq $false)
Check 'Esc left every item as it was' (($items[0].On -eq $true) -and ($items[2].On -eq $false))

# --- Enter on an item toggles it -------------------------------------
$items = NewItems
# toggle row 0 off, then down x3 to land on START (the gap at row 3 is
# skipped automatically), then Enter to accept.
$r = Show-Picker -Items $items -TestKeys @(13, 40, 40, 40, 13)
Check 'START returns true' ($r -eq $true)
Check 'Enter toggled the highlighted item off' ($items[0].On -eq $false)
Check 'it did not touch the others' (($items[1].On -eq $true) -and ($items[2].On -eq $false))

# --- Space toggles too -----------------------------------------------
$items = NewItems
$r = Show-Picker -Items $items -TestKeys @(32, 40, 40, 40, 13)
Check 'Space toggles as well as Enter' (($items[0].On -eq $false) -and ($r -eq $true))

# --- THE SPACER ROW IS SKIPPED ---------------------------------------
# Three downs from row 0 must land on START, not on the blank row
# between the list and it. If the gap were not skipped, this run would
# press Enter on nothing and never return true.
$items = NewItems
$r = Show-Picker -Items $items -TestKeys @(40, 40, 40, 13)
Check 'three downs land on START, skipping the spacer' ($r -eq $true)

# --- The Cancel row --------------------------------------------------
$items = NewItems
$r = Show-Picker -Items $items -TestKeys @(40, 40, 40, 40, 13)
Check 'the Cancel row returns cancel' ($r -eq $false)

# --- Up from the top wraps to the bottom ------------------------------
# Row 0, one Up, wraps to row 5 which is Cancel. Enter there cancels.
$items = NewItems
$r = Show-Picker -Items $items -TestKeys @(38, 13)
Check 'Up from the first row wraps round to Cancel' ($r -eq $false)

Write-Host ''
Write-Host 'START WITH NOTHING TICKED' -ForegroundColor Cyan

# --- The repair menu must refuse an empty START ------------------------
# Pressing START having selected no repairs is always a mistake, so it
# must do nothing rather than run an empty pass.
$items = NewItems
foreach ($i in $items) { $i.On = $false }
# Land on START and press Enter twice. Without -AllowEmpty both presses
# must be ignored, so the picker is still looping when the scripted keys
# run out, and running out returns false.
$r = Show-Picker -Items $items -TestKeys @(40, 40, 40, 13, 13)
Check 'without -AllowEmpty, START with nothing ticked does not proceed' ($r -eq $false)

# --- The report menu must ALLOW it ------------------------------------
# "Include no sections and save no file" is a legitimate answer to
# "what do you want to log", unlike an empty repair run.
$items = NewItems
foreach ($i in $items) { $i.On = $false }
$r = Show-Picker -Items $items -AllowEmpty -TestKeys @(40, 40, 40, 13)
Check 'with -AllowEmpty, START with nothing ticked proceeds' ($r -eq $true)

Write-Host ''
Write-Host 'ROW LAYOUT' -ForegroundColor Cyan

# --- No phantom rows --------------------------------------------------
# A switch statement whose cases ended in `continue` once made every
# START, Cancel and spacer row draw a second, empty "[ ]" line
# underneath itself, so two rows looked selected at once. LastRender is
# the row list as text, which is the only way to see that without eyes
# on a console.
$items = NewItems
$null = Show-Picker -Items $items -TestKeys @(27)
$rendered = @($Script:LastRender)
# '\[.\]', not '\[[ x]\]'. Common.ps1 picks the tick glyph at runtime by
# testing what the console can actually render, and on a console that
# can do it the result is U+2713, not the ASCII 'x' fallback. A test that
# hardcodes the fallback passes only on the consoles that cannot draw a
# tick, which is the opposite of the machines this runs on.
$boxes = @($rendered | Where-Object { $_ -match '\[.\]' })
Check 'exactly one checkbox row per item, no phantoms' ($boxes.Count -eq 3) "got $($boxes.Count)"
Check 'START is drawn once'  (@($rendered | Where-Object { $_ -match '\bSTART\b' }).Count -eq 1)
Check 'Cancel is drawn once' (@($rendered | Where-Object { $_ -match 'Cancel' }).Count -eq 1)

# --- Custom labels reach the screen ----------------------------------
$items = NewItems
$null = Show-Picker -Items $items -StartLabel 'CONTINUE' -CancelLabel 'Quit without running' -TestKeys @(27)
$rendered = @($Script:LastRender)
Check 'a custom START label is used'  (@($rendered | Where-Object { $_ -match 'CONTINUE' }).Count -eq 1)
Check 'a custom Cancel label is used' (@($rendered | Where-Object { $_ -match 'Quit without running' }).Count -eq 1)

Write-Host ''
Write-Host 'TICK ALL AND SKIP ALL' -ForegroundColor Cyan

# With -ShowAllNone the rows are:
#   0,1,2 items | 3 gap | 4 allon | 5 alloff | 6 gap2 | 7 START | 8 Cancel
#
# The spacer skip runs AFTER each keypress, so a press that lands on row
# 3 immediately advances to row 4. THREE downs therefore reach "tick
# all", not four. Counting rows rather than tracing the keypresses is
# how the first version of this test was wrong by one on every case.
$items = NewItems
$r = Show-Picker -Items $items -ShowAllNone -TestKeys @(40, 40, 40, 13, 27)
Check 'Tick all switches every item on' (@($items | Where-Object { -not $_.On }).Count -eq 0)
Check 'and it does not itself proceed'  ($r -eq $false)

$items = NewItems
$r = Show-Picker -Items $items -ShowAllNone -TestKeys @(40, 40, 40, 40, 13, 27)
Check 'Skip all switches every item off' (@($items | Where-Object { $_.On }).Count -eq 0)

# One keypress to skip everything, then straight to START. This is the
# whole point of the row: a look-only run without unticking each line.
$items = NewItems
$r = Show-Picker -Items $items -ShowAllNone -AllowEmpty -TestKeys @(40, 40, 40, 40, 13, 40, 13)
Check 'Skip all then START runs with nothing ticked' (($r -eq $true) -and (@($items | Where-Object { $_.On }).Count -eq 0))

# THE SECOND SPACER. There are two blank rows once the bulk rows exist,
# and the skip logic was a single `if` written when there was one. That
# would park the highlight on a blank row with Enter doing nothing,
# which reads as the menu having frozen. Five downs must reach START.
$items = NewItems
$r = Show-Picker -Items $items -ShowAllNone -TestKeys @(40, 40, 40, 40, 40, 13)
Check 'five downs reach START, skipping BOTH spacer rows' ($r -eq $true)

# The rows say what they do, and the recommendation is on screen.
$items = NewItems
$null = Show-Picker -Items $items -ShowAllNone -TestKeys @(27)
$rendered = @($Script:LastRender)
Check 'a recommended tick-all row is drawn' (@($rendered | Where-Object { $_ -match 'ON.*recommended' }).Count -eq 1)
Check 'a SKIP ALL row is drawn'             (@($rendered | Where-Object { $_ -match 'SKIP ALL' }).Count -eq 1)

# Without the switch, neither row exists, so the repair menu is unchanged.
$items = NewItems
$null = Show-Picker -Items $items -TestKeys @(27)
$rendered = @($Script:LastRender)
Check 'without -ShowAllNone there is no SKIP ALL row' (@($rendered | Where-Object { $_ -match 'SKIP ALL' }).Count -eq 0)

# -SkipProceeds: the skip row unticks everything AND goes, in one press.
# For the report that means "skip step 1, go to the repairs", which is
# one decision rather than untick-everything-then-confirm-separately.
$items = NewItems
$r = Show-Picker -Items $items -ShowAllNone -SkipProceeds -AllowEmpty -TestKeys @(40, 40, 40, 40, 13)
Check '-SkipProceeds returns straight away' ($r -eq $true)
Check 'and it unticked everything first'    (@($items | Where-Object { $_.On }).Count -eq 0)

# Without it the skip row only unticks, so the repair menu keeps its
# behaviour: there is no way to start an empty repair run by accident.
$items = NewItems
$r = Show-Picker -Items $items -ShowAllNone -TestKeys @(40, 40, 40, 40, 13, 27)
Check 'without -SkipProceeds the skip row does not proceed' ($r -eq $false)

Write-Host ''
Write-Host 'THE REDRAW MUST NOT STACK' -ForegroundColor Cyan

# THE ACTUAL BUG, after three wrong diagnoses.
#
# Every earlier fix here sized the frame so it would fit the window, on
# the theory that an over-tall frame scrolled the console and moved the
# anchor. The frame did fit, and the menu still stacked, because the
# anchor was wrong for a reason that had nothing to do with height:
#
#   $Host.UI.RawUI.WindowPosition.Y is the top of the VISIBLE WINDOW
#   within the buffer. Set-ConsoleLook asks for a 9001 row scrollback,
#   so the buffer is 9001 rows against a window of 30. Content is
#   appended at the bottom of the buffer and the viewport follows it,
#   so WindowPosition tracks where you are LOOKING, not where the frame
#   was drawn. Measured: BufferSize 120x9001, WindowSize 120x30.
#
# The fix is to use no absolute row at all: step back up over the frame
# just drawn with ESC[{n}F, which is relative and cannot be wrong about
# where it started.
$common = Get-Content (Join-Path $Root 'Common.ps1') -Raw

Check 'the redraw does not anchor to WindowPosition' `
      (-not ($common -match 'CursorPosition\s*=[\s\S]{0,120}WindowPosition')) `
      'an absolute row is meaningless when the buffer is 9001 and the window is 30'

# Clear-Host must drive BOTH redraw paths, not just the fallback: one
# call to open the picker, one for the ANSI repaint, one for the
# no-ANSI repaint.
$clears = ([regex]::Matches($common, '(?m)^\s*Clear-Host\s*$')).Count
Check 'the redraw clears the screen every frame, on both paths' ($clears -ge 3) `
      "found $clears Clear-Host calls, expected at least 3"

# Nothing may POSITION the cursor. Every version of that calculation
# has failed on a real terminal. Colour and cursor hide/show are fine.
Check 'the redraw no longer homes or steps the cursor' `
      (-not (($common -match '27\)\[H') -or ($common -match '27\)\[0J') -or ($common -match 'LastFrameLines'))) `
      'a redraw that computes where the last frame went can be wrong, and was, five times'

Check 'nothing is remembered between frames' `
      (-not ($common -match 'LastFrameLines')) `
      'state that persists between frames is state that can drift'

Check 'the no-ANSI path clears instead of appending' `
      ($common -match '(?s)No ANSI.*?Clear-Host') `
      'appending without clearing is what stacked the frames'

Write-Host ''
Write-Host 'NO LINE MAY WRAP' -ForegroundColor Cyan

# THE THIRD ROUTE TO THE SAME BUG.
#
# The height arithmetic counts LINES. A line only costs one row if it
# fits the width; an over-width one wraps and costs two or three, which
# nothing measuring the frame can see. Frame outgrows window, console
# scrolls, anchor goes stale, menus stack.
#
# It happened because -Hint was typed [string] rather than [string[]],
# so PowerShell silently joined a four-line array into one 300-character
# line: counted as one row, drawn as four.
$items = NewItems
$null = Show-Picker -Items $items -ShowAllNone `
        -Title 'A title that is quite long but still sensible for a tool like this' `
        -Hint @('    line one of the hint', '    line two of the hint') `
        -StartLabel 'CONTINUE  ->  run the report  (recommended)' `
        -SkipLabel  'SKIP THE REPORT  ->  go straight to the repairs' `
        -CancelLabel 'Quit. Do not report, do not repair.' -TestKeys @(27)
$rendered = @($Script:LastRender)
$tooWide = @($rendered | Where-Object { $_.Length -gt 78 })
Check 'no rendered row is wider than the frame' ($tooWide.Count -eq 0) `
      $(if ($tooWide.Count) { "$($tooWide.Count) over-wide, longest $(($tooWide | Measure-Object Length -Maximum).Maximum)" })

# An absurdly long label must be CUT, not allowed to wrap.
$items = NewItems
$null = Show-Picker -Items $items -ShowAllNone -SkipLabel ('X' * 400) -TestKeys @(27)
$rendered = @($Script:LastRender)
Check 'a 400-character label is truncated, not wrapped' `
      (@($rendered | Where-Object { $_.Length -gt 78 }).Count -eq 0)

# And a multi-line hint must survive as MULTIPLE lines rather than being
# joined into one. Proven through the header height the picker derives.
$common = Get-Content (Join-Path $Root 'Common.ps1') -Raw
Check 'Hint is [string[]], so an array is not joined into one line' `
      ($common -match '\[string\[\]\]\$Hint') `
      '[string]$Hint silently joins an array with spaces'
Check 'Paint and Emit cut every line to the width' `
      ($common -match 'function Fit\(\$text\)') `
      'PadRight only lengthens; something must also truncate'

Write-Host ''
Write-Host 'THE FRAME MUST FIT THE WINDOW' -ForegroundColor Cyan

# THE BUG THIS EXISTS FOR, twice now.
#
# The redraw anchors to the top of the VISIBLE window and repaints over
# the previous frame. That only works while the frame fits: one row too
# tall and the console scrolls, the anchor points at a row that has
# moved, and every keypress leaves another complete copy of the menu on
# screen. Reported as "it's repeating the health whatever on and on".
#
# The first cause was a hand-counted $HeaderLines that stopped matching
# the header. The second was a Max(5, ...) FLOOR on the option rows,
# which forced five of them on top of fixed chrome that already did not
# fit in a short window.
#
# So the arithmetic is checked directly, at every window height the tool
# can plausibly meet, rather than by looking at a menu and hoping.
function Get-FrameHeight([int]$WindowHeight, [int]$HeaderLines, [int]$RowCount) {
    $markers = 2; $detailFixed = 4
    $budget = $WindowHeight - $HeaderLines - $markers - $detailFixed - 1
    $detailBody = 6
    while ($detailBody -gt 2 -and ($detailBody + 3) -gt $budget) { $detailBody-- }
    $avail  = $budget - $detailBody
    $vCount = [Math]::Min($RowCount, [Math]::Max(1, $avail))
    # header + above-marker + rows + below-marker + blank + rule + detail + rule + summary
    return $HeaderLines + 1 + $vCount + 1 + 1 + 1 + $detailBody + 1 + 1
}

$overflow = @()
foreach ($wh in 26..60) {
    foreach ($hdr in 8..16) {          # the header varies by caller
        foreach ($rc in 6..26) {       # 3 items up to the full report list
            $fh = Get-FrameHeight $wh $hdr $rc
            # -ge, not -gt. A frame that EXACTLY fills the window still
            # scrolls it by one, because its last line ends with a
            # newline like every other. The bar is $wh - 1.
            if ($fh -ge $wh) { $overflow += "window=$wh header=$hdr rows=$rc frame=$fh" }
        }
    }
}
Check 'the frame always leaves a spare row, at any size' ($overflow.Count -eq 0) `
      $(if ($overflow.Count) { "$($overflow.Count) overflow(s), first: $($overflow[0])" })

# And prove the OLD arithmetic fails this, so the check is known to bite.
function Get-OldFrameHeight([int]$WindowHeight, [int]$HeaderLines, [int]$RowCount) {
    $avail = $WindowHeight - $HeaderLines - 10 - 2 - 2
    $vCount = [Math]::Max(5, [Math]::Min($RowCount, $avail))
    return $HeaderLines + 1 + $vCount + 1 + 10
}
$oldBad = @(foreach ($wh in 26..60) { if ((Get-OldFrameHeight $wh 9 20) -ge $wh) { $wh } })
Check 'the old arithmetic really did overflow (so this check bites)' ($oldBad.Count -gt 0) `
      'the old sum fit everywhere, so this test proves nothing'

# The header height must be DERIVED from the header, never hand-counted.
$common = Get-Content (Join-Path $Root 'Common.ps1') -Raw
Check 'HeaderLines is derived from the header, not a literal' `
      ($common -match '\$HeaderLines = \$headerText\.Count') `
      'a hand-counted header height is what broke this the first time'
Check 'the option-row count has no floor above 1' `
      (-not ($common -match '\$vCount = \[Math\]::Max\(5')) `
      'a floor forces rows onto a frame that already does not fit'

Write-Host ''
Write-Host 'THE REPORT SECTIONS ARE WELL FORMED' -ForegroundColor Cyan

# The health report builds its own list and maps names to keys. A key in
# the map with no matching section, or a duplicate key, switches a check
# off permanently and silently.
$hr = Get-Content (Join-Path $Root 'Health-Report.ps1') -Raw
$keys = @(([regex]"Key='([A-Z])'; On=").Matches($hr) | ForEach-Object { $_.Groups[1].Value })
Check "the report defines its sections ($($keys.Count) found)" ($keys.Count -ge 11)
$dupes = @($keys | Group-Object | Where-Object Count -gt 1)
Check 'no duplicate section keys' ($dupes.Count -eq 0) "duplicated: $(($dupes | ForEach-Object Name) -join ',')"

# Every key the Include map can ask for must exist as a section.
#
# The map is matched as a BLOCK, not line by line. Filtering to the one
# line containing 'machine=' found only the five pairs that happen to sit
# on the first line and reported the other seven sections as unreachable:
# a wrapped hashtable literal is still one hashtable.
$mapBlock = ''
if ($hr -match '(?s)\$map\s*=\s*@\{(.*?)\}') { $mapBlock = $Matches[1] }
$mapped = @(([regex]"(\w+)='([A-Z])'").Matches($mapBlock) | ForEach-Object { $_.Groups[2].Value })
Check 'the Include map was found and parsed' ($mapped.Count -ge 11) "found $($mapped.Count) mappings"
$orphans = @($mapped | Where-Object { $_ -notin $keys })
Check 'every key the Include map uses exists as a section' ($orphans.Count -eq 0) "orphaned: $($orphans -join ',')"

# And every section must be reachable through the map, or it can be
# unticked in the picker and still run.
$unreachable = @($keys | Where-Object { $_ -notin $mapped })
Check 'every section is reachable through the Include map' ($unreachable.Count -eq 0) "unreachable: $($unreachable -join ',')"

Write-Host ''
Write-Host 'WHERE THE CURSOR STARTS' -ForegroundColor Cyan

# The health report opens on START, so the common answer is one keypress
# and nobody has to decide anything. The repair menu must keep opening on
# the first repair, because there the ticks ARE the decision.
#
# Both halves are asserted. A test that only proved the new behaviour
# would pass just as happily if -StartSelected had been made the default
# for every caller, which is the actual risk in a shared control.

# --- default: cursor is on the first item ----------------------------
$items = NewItems
$r = Show-Picker -Items $items -TestKeys @(13)
Check 'without -StartSelected, Enter toggles the first item' ($items[0].On -eq $false)
Check 'and does not proceed' ($null -eq $r -or $r -eq $false -or $items[0].On -eq $false)

# --- -StartSelected: cursor is on START ------------------------------
$items = NewItems
$r = Show-Picker -Items $items -TestKeys @(13) -StartSelected
Check '-StartSelected: one Enter proceeds' ($r -eq $true)
Check '-StartSelected: it toggled nothing' (
    ($items[0].On -eq $true) -and ($items[1].On -eq $true) -and ($items[2].On -eq $false))

# --- the index is found, not assumed ---------------------------------
#
# -ShowAllNone inserts three more rows before START. A hardcoded offset
# would land on "turn every option on" here and silently tick the lot,
# which looks like it worked. This is the case that catches that.
$items = NewItems
$r = Show-Picker -Items $items -TestKeys @(13) -StartSelected -ShowAllNone -AllowEmpty
Check '-StartSelected finds START past the bulk rows' ($r -eq $true)
Check 'and still toggled nothing' (
    ($items[0].On -eq $true) -and ($items[1].On -eq $true) -and ($items[2].On -eq $false))

# --- the report actually asks for it ---------------------------------
Check 'Health-Report calls the picker with -StartSelected' ($hr -match '-StartSelected')
$rh = Get-Content (Join-Path $Root 'Repair-Health.ps1') -Raw
Check 'Repair-Health does NOT' ($rh -notmatch '-StartSelected')

Write-Host ''
if ($fail -eq 0) { Write-Host 'PICKER OK' -ForegroundColor Green } else { Write-Host "$fail PICKER CHECK(S) FAILED" -ForegroundColor Red }
exit $fail
