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
if ($fail -eq 0) { Write-Host 'PICKER OK' -ForegroundColor Green } else { Write-Host "$fail PICKER CHECK(S) FAILED" -ForegroundColor Red }
exit $fail
