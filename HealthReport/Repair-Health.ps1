<#
=======================================================================
 DEEPER HEALTH CHECK AND REPAIR

 A menu of Windows' own health tools. Nothing extra is installed and
 nothing is downloaded: every one of these ships with Windows.

 Reached ONLY from the Health Report, by answering yes at the end of it.
 There is deliberately no separate launcher entry and no standalone
 .bat: you run the report first, see the state of the machine, and then
 decide what to repair. That order is the point.

 THREE THINGS THAT ARE NOT NEGOTIABLE IN HERE
 --------------------------------------------
 1. NO PIPELINE ON ANY SCAN. sfc, dism and chkdsk draw their progress
    by rewriting one line with a carriage return, and they check
    whether stdout is a real console. Any pipeline at all, including
    Tee-Object, Out-String or Out-Host, means stdout is no longer a
    console, so the percentage either scrolls as hundreds of lines or
    vanishes. This was "fixed" twice by changing WHICH pipeline was
    used before anyone noticed the cause was piping at all.
    The verdict therefore comes from the exit code plus CBS.log.

 2. NOTHING THAT CHANGES THE MACHINE RUNS WITHOUT SAYING SO FIRST.
    Anything that repairs rather than reads is off by default, is
    labelled CHANGES, and offers a restore point before it starts.

 3. THE RUN NEVER STOPS TO ASK. Questions are asked before it starts or
    after it finishes, never in between. A prompt twenty minutes in,
    with nobody watching, halts every task after it and is
    indistinguishable from a crash.
=======================================================================
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# DELIBERATELY NOT setting [Console]::OutputEncoding to Unicode here.
# The build script does, because it CAPTURES sfc and dism output, which
# is UTF-16 and comes out as "s p a c e d  l e t t e r s" otherwise.
# This script never captures anything: every scan runs bare and writes
# straight to the console, so the setting buys nothing, and it makes
# everything ELSE in this script render as spaced letters the moment the
# output is redirected to a file or a pipe. Caught by doing exactly that.

$Log     = [System.Collections.ArrayList]@()
$Started = Get-Date

# Admin is required for SMART counters, chkdsk and every repair.
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Sec($t)  { Write-Host ''; Write-Host "  $t" -ForegroundColor Cyan; Write-Host "  $('-' * $t.Length)" -ForegroundColor DarkCyan; [void]$Log.Add(''); [void]$Log.Add($t); [void]$Log.Add('-' * $t.Length) }
function Good($m) { Write-Host "    ok   $m" -ForegroundColor Green;    [void]$Log.Add("  ok   $m") }
function Warn($m) { Write-Host "    !!   $m" -ForegroundColor Yellow;   [void]$Log.Add("  !!   $m") }
function Fail($m) { Write-Host "    XX   $m" -ForegroundColor Red;      [void]$Log.Add("  XX   $m") }
function Info($m) { Write-Host "         $m" -ForegroundColor DarkGray; [void]$Log.Add("       $m") }
function Work($m) { Write-Host ''; Write-Host "    >>   $m" -ForegroundColor White; [void]$Log.Add("  >>   $m") }

function Mins($t0) {
    $s = ((Get-Date) - $t0).TotalSeconds
    if ($s -lt 60) { "$([math]::Round($s)) sec" } else { "$([math]::Round($s / 60, 1)) min" }
}

# ---------------------------------------------------------------------
#  SPINNER, TICK, CONSOLE CHECK, DEFERRED QUESTIONS: all in Common.ps1
#
#  A long silent pause is indistinguishable from a crash. sfc, dism and
#  chkdsk solve that themselves by drawing their own live percentage,
#  which is exactly why they are never piped in here. Everything else is
#  a PowerShell call that prints nothing until it returns, and some are
#  slow: Checkpoint-Computer sits for a minute with no output at all.
#
#  These were written here first. Health-Report then sat silent on its
#  own slow queries because it had no spinner, so they moved to
#  Common.ps1 and both scripts dot-source it. Two copies of "show the
#  user something is happening" would drift exactly as two copies of
#  "is it installed" already did.
# ---------------------------------------------------------------------
. (Join-Path $PSScriptRoot 'Common.ps1')
$Script:SpinLog = $Log

# ---------------------------------------------------------------------
#  GETTING THE SCANS' FINDINGS INTO THE REPORT
#
#  SFC, DISM and chkdsk run bare so their progress stays visible. The
#  cost of that is real: their output never passes through PowerShell,
#  so it cannot be captured, and the saved report would otherwise say
#  "SFC took 12 minutes" and not one word about what SFC actually FOUND.
#
#  Windows writes all of it down anyway. So read the findings back out
#  afterwards, from the place each tool records them:
#
#    SFC     Windows\Logs\CBS\CBS.log, the [SR] lines
#    DISM    Windows\Logs\DISM\dism.log
#    chkdsk  the Application event log, provider Chkdsk or Wininit
#
#  All three confirmed present on a real machine before being relied on.
# ---------------------------------------------------------------------
function LogOnly($m) { [void]$Log.Add($m) }

function Add-Detail($Title, [string[]]$Lines) {
    if (-not $Lines -or -not $Lines.Count) { return }
    LogOnly ''
    LogOnly "  $Title"
    foreach ($l in $Lines) { LogOnly ('    ' + $l.TrimEnd()) }
}

# CBS.log is read ONCE per SFC pass, behind the spinner and a timeout.
#
# It used to be read twice, bare: once by Get-SfcVerdict and again by
# Get-SfcDetail, with no indicator and no time limit on either. By then
# sfc.exe has exited and its live percentage is gone, so the console
# sits completely silent for the whole read. The box above tells the
# user that percentage IS the loading indicator, so silence starting the
# moment it disappears is precisely what gets read as a freeze and
# closed. Reported from the field 2026-08-14.
#
# The scriptblock uses nothing but built-ins on purpose. Spin runs it in
# a fresh runspace that does not inherit this script's functions, which
# is the reason the read was left bare originally. Only the READ goes in
# there; the filtering stays out here, where the functions exist.
function Get-CbsSrLines {
    $cbs = Join-Path $env:WINDIR 'Logs\CBS\CBS.log'
    if (-not (Test-Path $cbs)) { return $null }
    $lines = Spin 'reading what SFC recorded in CBS.log' {
        param($p)
        try { Get-Content $p -Tail 8000 -ErrorAction Stop | Where-Object { $_ -match '\[SR\]' } }
        catch { }
    } $cbs 120
    # Spin returns $null on stall or failure and has already said so.
    #
    # The leading comma is load bearing. `return @()` emits ZERO objects,
    # so the caller's variable comes back as $null and is indistinguishable
    # from "no CBS.log at all" -- which made the report claim the file was
    # missing on a machine where it was plainly there. The unary comma
    # wraps the array so one object is emitted and the emptiness survives.
    if ($null -eq $lines) { return , @() }
    return , @($lines)
}

function Get-SfcDetail($SrLines) {
    if ($null -eq $SrLines) { return @('CBS.log is not present, so no SFC detail is available.') }
    if (-not $SrLines.Count) { return @('No [SR] entries could be read from the recent part of CBS.log.') }
    $keep = $SrLines | Where-Object {
        $_ -match 'Cannot repair|Repairing corrupted|successfully repaired|is corrupt|Verify complete|No errors detected|Verifying \d+ components'
    } | Select-Object -Last 30
    if (-not $keep) { $keep = $SrLines | Select-Object -Last 10 }
    $keep | ForEach-Object { ($_ -replace '^.*\[SR\]\s*', '') }
}

# Same treatment as CBS.log above, and for the same reason: this runs
# straight after a DISM that can take half an hour, at the exact moment
# its progress bar disappears.
function Get-DismDetail {
    $d = Join-Path $env:WINDIR 'Logs\DISM\dism.log'
    if (-not (Test-Path $d)) { return @('dism.log is not present, so no DISM detail is available.') }
    $tail = Spin 'reading what DISM recorded in dism.log' {
        param($p)
        try { Get-Content $p -Tail 400 -ErrorAction Stop } catch { }
    } $d 120
    if ($null -eq $tail) { return @('Could not read dism.log in time, so no DISM detail is available.') }
    $keep = @($tail) | Where-Object {
        $_ -match 'Error|Warning|corrupt|repair|The restore operation|successfully|Failed'
    } | Select-Object -Last 25
    if (-not $keep) { return @('DISM logged nothing notable in its last 400 lines.') }
    $keep | ForEach-Object { ($_ -replace '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d, ', '') }
}

function Get-ChkdskDetail($Since) {
    # Behind a timeout: reading the Application log can take minutes on a
    # machine with years of events, and this runs straight after a chkdsk
    # the user has already waited a long time for.
    $ev = AsArray (Spin 'reading the chkdsk result from the event log' {
        param($since)
        Get-WinEvent -FilterHashtable @{
            LogName      = 'Application'
            ProviderName = @('Chkdsk', 'Microsoft-Windows-Wininit')
            StartTime    = $since
        } -ErrorAction SilentlyContinue
    } $Since 60)
    if (-not $ev.Count) { return @('Windows logged no chkdsk result for this run.') }
    # The message IS the full chkdsk report, so keep it whole.
    $out = @()
    foreach ($e in ($ev | Select-Object -First 2)) {
        $out += "$($e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))  ($($e.ProviderName))"
        $out += ($e.Message -split "`r?`n" | Where-Object { $_.Trim() })
    }
    $out
}

# SFC tells you almost nothing through its exit code, so the real
# verdict is read out of the log it writes as it goes. Anything it does
# not say clearly is reported as unknown rather than guessed at.
function Get-SfcVerdict($SrLines) {
    if ($null -eq $SrLines -or -not $SrLines.Count) { return 'unknown' }
    $txt = ($SrLines | Select-Object -Last 80) -join "`n"
    if ($txt -match 'Cannot repair member file')                      { return 'stuck' }
    if ($txt -match 'Repairing corrupted file|successfully repaired')  { return 'repaired' }
    if ($txt -match 'Verify complete|No errors detected')              { return 'clean' }
    return 'unknown'
}

$verdicts = [System.Collections.ArrayList]@()
function Verdict($m) { [void]$verdicts.Add($m) }

# =====================================================================
#  THE MENU
# =====================================================================
# Changes = $true means it modifies the machine. Those are off by
# default and trigger the restore-point offer.
$Tasks = @(
    [pscustomobject]@{ Key='1'; On=$true;  Changes=$true;  Time='about 10 to 40 minutes'; Low=10; High=40
        Name='Repair system files: SFC, then DISM, then SFC'
        Desc='The standard repair, and it runs all three passes every time. SFC checks Windows'' own files against the component store. DISM then repairs that store, because a clean SFC does not prove the machine is healthy: if the store is itself damaged, SFC compares Windows against a bad reference, finds no difference, and reports clean on a machine that plainly is not. SFC then runs again with a repaired source.' }

    # Reads as a sub-option of the line above, because that is exactly what
    # it is: it changes how that repair behaves and does nothing on its
    # own. The old wording ("FORCE the full pass") described it as a
    # separate, larger repair, which hid the relationship between the two.
    #
    # The default is also inverted from how this shipped. DISM used to run
    # only when SFC reported damage; now it always runs and you opt OUT.
    # A clean SFC is the case where DISM is most worth running, because a
    # damaged store is precisely what makes SFC report clean wrongly.
    # Changes=$false: ticking this makes the run do LESS, so tagging it
    # "CHANGES THIS PC" alongside the genuine repairs was wrong.
    # Time is phrased to read correctly after the word "takes", which the
    # detail pane prefixes. "saves 10 to 40 min" rendered as "takes saves
    # 10 to 40 min".
    # ON by default. DISM adds 10 to 40 minutes and most of the time SFC
    # coming back clean means there is nothing for it to do, so paying
    # that on every machine is not worth it. Untick it when a machine
    # misbehaves but SFC insists it is fine, which is the case a clean
    # SFC cannot rule out: SFC compares Windows against the component
    # store, so a damaged store makes it report clean wrongly, and DISM
    # is the only one of the two that checks the store itself.
    [pscustomobject]@{ Key='D'; On=$true;  Changes=$false; Time='nothing extra, it removes a step'; Low=0; High=0
        Name='    ^ skip DISM unless SFC finds damage (faster, default)'
        Desc='A sub-option of the repair above it, not a repair of its own, and it does nothing unless that one is on. ON by default, because DISM adds 10 to 40 minutes and a clean SFC usually means there is nothing for it to do. UNTICK it when a machine clearly misbehaves but SFC insists it is fine: SFC compares Windows against the component store, so if that store is itself damaged SFC finds no difference and reports clean, and DISM is the only one of the two that can see it.' }

    [pscustomobject]@{ Key='2'; On=$true;  Changes=$false; Time='about 2 to 10 minutes';  Low=2;  High=10
        Name='Check the disk for errors (online, no reboot)'
        Desc='chkdsk /scan. Finds filesystem corruption while Windows is running. Reports only, it does not fix, so nothing can go wrong.' }

    [pscustomobject]@{ Key='3'; On=$true;  Changes=$false; Time='a few seconds';          Low=0;  High=1
        Name='Read the drive''s own SMART health data'
        Desc='Power-on hours, reallocated sectors, SSD write life, read and write error counts, straight from the drive firmware.' }

    [pscustomobject]@{ Key='4'; On=$true;  Changes=$false; Time='a few seconds';          Low=0;  High=1
        Name='Sweep the event log for real faults'
        Desc='Last 14 days of unexpected shutdowns, blue screens, disk errors and hardware faults. This is usually where the answer to "it keeps crashing" actually is.' }

    [pscustomobject]@{ Key='5'; On=$true;  Changes=$false; Time='a few seconds';          Low=0;  High=1
        Name='Reliability history: what has been failing, and when'
        Desc='Windows keeps its own record of app crashes, hangs and failed updates. Good for spotting the day a machine went wrong.' }

    [pscustomobject]@{ Key='6'; On=$true;  Changes=$false; Time='a few seconds';          Low=0;  High=1
        Name='Find devices with missing or broken drivers'
        Desc='Lists only genuine driver faults, not devices someone has simply switched off.' }

    [pscustomobject]@{ Key='U'; On=$false; Changes=$true;  Time='about 2 to 20 minutes'; Low=2; High=20
        Name='Install driver updates from Windows Update'
        Desc='Asks Windows Update for driver updates and installs the ones it offers, using Windows'' own update service. Nothing is downloaded from anywhere else and no manufacturer software is installed. Windows Update is deliberately conservative, so it will not always have the newest driver a vendor has published, but it is the only source that is both automatic and safe. The report above tells you which devices are actually broken or on a generic driver.' }

    [pscustomobject]@{ Key='S'; On=$false; Changes=$false; Time='about 1 to 5 minutes'; Low=1; High=5
        Name='Check whether this PC CAN install drivers (a dry run)'
        Desc='A dry run, for when you want to know a machine can install drivers before you promise anyone it will. It does everything the real driver install does, including downloading the actual driver packages and confirming each one arrived, and then stops without installing any of them. Nothing is added to this PC and the downloaded files are deleted at the end, so it is safe on a machine you have not been given permission to change. If it passes, the real install will get at least as far. If it fails, it names which stage failed: no internet, a licence, or a broken Windows Update. NEEDS ADMINISTRATOR, because Windows Update will not download for a standard user.' }

    [pscustomobject]@{ Key='F'; On=$false; Changes=$true;  Time='about 1 to 5 minutes on top of the check'; Low=1; High=5
        Name='Also REPAIR what the disk check finds'
        Desc='Needs the disk check above, and switches it on for you. Per chkdsk''s own documentation the online scan QUEUES what it finds and /spotfix repairs that queue, so this is the second half of one operation rather than a second scan. chkdsk is never run twice. If damage is too deep to mend with Windows running, you are asked at the END of the run whether to schedule a full offline repair. Back up anything irreplaceable first.' }

    [pscustomobject]@{ Key='T'; On=$false; Changes=$true;  Time='about 1 to 5 minutes'; Low=1; High=5
        Name='Clear out temp files'
        Desc='Empties the Windows and user temp folders, the Windows Update download cache, prefetch and the recycle bin. A full disk causes an enormous number of "it is broken" symptoms, and this is the safe part of freeing space.' }

    [pscustomobject]@{ Key='7'; On=$false; Changes=$true;  Time='about 10 to 30 minutes'; Low=10; High=30
        Name='Reclaim disk space from old Windows updates'
        Desc='DISM component store cleanup. Can free several GB on an old machine. Slow, and it holds the Windows servicing lock while it runs, so nothing can install meanwhile.' }

    [pscustomobject]@{ Key='8'; On=$false; Changes=$true;  Time='about 2 to 5 minutes';   Low=2;  High=5
        Name='Repair Windows Update'
        Desc='For a machine stuck on "checking for updates" or failing with the same error forever. Stops the update services, sets aside the download cache so Windows rebuilds it, restarts them. Standard Microsoft-documented fix.' }

    [pscustomobject]@{ Key='9'; On=$false; Changes=$true;  Time='seconds, then a reboot'; Low=0;  High=1
        Name='Reset the network stack'
        Desc='For "connected but no internet" that survives a reboot and a router restart. Resets Winsock and TCP/IP to defaults. NEEDS A REBOOT to take effect, and it clears any custom proxy or static settings.' }

    [pscustomobject]@{ Key='0'; On=$false; Changes=$true;  Time='seconds here, then 15 to 60 minutes at the next restart'; Low=0; High=1
        Name='Test the RAM'
        Desc='Windows Memory Diagnostic. It cannot test memory while Windows is using it, so this schedules the test for the next restart. Worth it for random crashes with no other explanation.' }
)

# Look the task up by its menu key rather than by array index, so
# reordering the menu cannot silently run the wrong section.
function On($k) { [bool](($Tasks | Where-Object { $_.Key -eq $k }).On) }

# =====================================================================
#  THE PICKER: arrow keys, Enter to toggle
# =====================================================================
#  Twelve options is well past the point where "type the number" works.
#  Up and Down move a highlight, Enter switches the highlighted one on
#  or off, and START and Cancel are rows at the bottom you move to and
#  press Enter on.
#
#  It falls back to the numbered menu when it cannot work:
#    - input is redirected (a piped test, a scheduled run)
#    - the host has no RawUI ReadKey (PowerShell ISE throws on NoEcho)
#    - the window is too short to draw the list without scrolling
# =====================================================================
function Wrap($text, $width = 64) {
    $out = @(); $line = ''
    foreach ($w in ($text -split '\s+')) {
        if (($line + ' ' + $w).Trim().Length -gt $width) { $out += $line.Trim(); $line = $w }
        else { $line = ($line + ' ' + $w) }
    }
    if ($line.Trim()) { $out += $line.Trim() }
    $out
}

function Test-CanPick {
    if ([Console]::IsInputRedirected) { return $false }
    try {
        $h = $Host.UI.RawUI
        if ($null -eq $h -or $null -eq $h.WindowSize) { return $false }
        # Was 30, chosen when the list was short enough to always fit.
        # The picker now scrolls its own viewport, so it only needs room
        # for a usable window plus the detail pane. Below this the
        # numbered menu is genuinely the better experience.
        if ($h.WindowSize.Height -lt 24) { return $false }
        return $true
    } catch { return $false }
}

function Show-Picker {
    # Returns $true to run what is ticked, $false to cancel.
    #
    # -TestKeys feeds a scripted list of virtual key codes and skips all
    # drawing. It exists because the picker cannot run under redirected
    # input, so without it the navigation logic, which is where the real
    # bugs live (index wrapping, skipping the spacer row, START with
    # nothing ticked), would never be exercised by any test at all.
    param([int[]]$TestKeys)
    $silent = [bool]$TestKeys
    $kp = 0

    $rows = @()
    foreach ($t in $Tasks) { $rows += [pscustomobject]@{ Kind = 'task'; Task = $t } }
    $rows += [pscustomobject]@{ Kind = 'gap';    Task = $null }
    $rows += [pscustomobject]@{ Kind = 'start';  Task = $null }
    $rows += [pscustomobject]@{ Kind = 'cancel'; Task = $null }

    $i = 0
    $width = if ($silent) { 78 } else { [Math]::Min(78, $Host.UI.RawUI.WindowSize.Width - 2) }

    # THE HEADER IS NOW PART OF EVERY FRAME.
    #
    # This used to print once, remember the cursor row underneath it as
    # $top, and reposition there on each keypress to repaint in place.
    # That is the standard trick and it kept breaking: any scroll moves
    # every absolute row, $top silently points at the wrong line, and the
    # redraw lands below the previous frame instead of on top of it, so
    # each keypress leaves another full copy of the list on screen.
    #
    # It was patched three times: a viewport so the frame was smaller, a
    # spare row so a frame that exactly filled the window would not scroll
    # itself, and re-deriving $top from the cursor to absorb a scroll of
    # any size. Duplicates survived all three, because I was testing in the
    # classic host while the failures were in Windows Terminal, where the
    # scrollback buffer is 9001 rows rather than 30 and every absolute-row
    # assumption behaves differently.
    #
    # Two changes actually fixed it. The anchor is now the top of the
    # VISIBLE window, re-read every frame, so nothing has to be remembered.
    # And the frame is written in ONE call rather than one Write-Host per
    # line, so it repaints as a single unit instead of visibly rebuilding
    # itself down the screen. See the paint block at the end of the loop.
    #
    # Every line is PADDED to the full width. That is what makes drawing
    # over the previous frame safe without clearing first: a short line
    # would otherwise leave the tail of whatever was there before.
    $HeaderLines = 9
    $drawHeader = {
        Paint (''.PadRight($width))
        Paint ('   =========================================='.PadRight($width)) 'Cyan'
        Paint ('    REPAIR AND RECOVERY'.PadRight($width)) 'Cyan'
        Paint ("    $env:COMPUTERNAME".PadRight($width)) 'DarkGray'
        Paint ('   =========================================='.PadRight($width)) 'Cyan'
        Paint (''.PadRight($width))
        Paint ('    Up and Down to move.  ENTER switches an option on or off.'.PadRight($width)) 'DarkGray'
        Paint ('    Move to START and press ENTER to begin.  Esc quits.'.PadRight($width)) 'DarkGray'
        Paint (''.PadRight($width))
    }

    # Clear ONCE, here, so the first frame starts on a clean screen and
    # there is nothing left below it. Never again inside the loop: that
    # clear is what made the list flash and appear to jump on every
    # keypress, because for one frame the screen was genuinely empty.
    if (-not $silent) { Clear-Host }

    while ($true) {
      # Draw into a buffer, then either paint it or hand it back. Doing
      # it this way is what makes the row layout testable at all: the
      # fall-through bug that drew a phantom "[ ]" under every START and
      # Cancel row was invisible to every test until the rows could be
      # inspected as text.
      $Script:LastRender = New-Object System.Collections.ArrayList
      $paint = -not $silent

      # The frame is BUILT here and PAINTED once at the bottom. Nothing
      # in this loop writes to the console directly any more.
      $frame = New-Object System.Collections.ArrayList

      # Paint: a line that is only ever drawn (header, markers, detail).
      function Paint($text, $colour = 'Gray') {
          if ($paint) { [void]$frame.Add([pscustomobject]@{ T = $text; C = $colour }) }
      }
      # Emit: an option row. Also recorded in LastRender, which is how the
      # silent test mode inspects the row layout without a console.
      function Emit($text, $colour = 'Gray') {
          [void]$Script:LastRender.Add($text)
          if ($paint) { [void]$frame.Add([pscustomobject]@{ T = $text; C = $colour }) }
      }

      # Header first into the frame buffer. Nothing reaches the console
      # until the single paint at the bottom of this loop.
      if ($paint) { & $drawHeader }
      if ($true) {

        # if/elseif, NOT switch.
        #
        # This loop used a switch whose gap, start and cancel cases each
        # ended in `continue`. In PowerShell a switch IS a loop, so
        # `continue` there exits the switch and carries straight on into
        # the task-drawing code below it. Every START, Cancel and spacer
        # row therefore drew a second, empty "[ ]" line underneath itself,
        # highlighted, which is why two rows looked selected at once.
        #
        # This project already had that written down as a rule from the
        # activity collector, and it got made again here. A switch is the
        # wrong shape for "draw one row and move on" full stop.
        # VIEWPORT.
        #
        # The redraw is anchored to $top, an absolute buffer row captured
        # once. That only works while the frame fits on screen. The moment
        # the drawing runs past the bottom, the console scrolls, every
        # absolute row shifts up, $top points at the wrong line, and the
        # next keypress paints a whole fresh copy below the last one.
        # The result was a screen full of stacked duplicate lists.
        #
        # It appeared the moment the list grew: three options were added
        # (force DISM, driver install, self-test) and 12 rows became 15,
        # which pushed the frame past the window. The anchor was always
        # this fragile, the new rows just spent the slack.
        #
        # Two rules make it impossible rather than unlikely:
        #   1. Show a WINDOW of rows, never all of them, sized from the
        #      real window height.
        #   2. Draw EXACTLY the same number of lines every frame, padding
        #      with blanks, so the frame height is constant and nothing
        #      can ever scroll. Constant height is what keeps $top valid.
        # It now survives any number of tasks and any window size.
        $vFirst = 0
        $vCount = $rows.Count
        if ($paint) {
            $detailLines = 10                      # blank, rule, 6 detail, rule, summary
            $chrome      = 2                       # the "more above/below" markers
            # Sized against the header height, which is now a known
            # constant because the header is redrawn with the frame,
            # rather than against a remembered cursor row. Two spare rows:
            # the last line of the frame writes a newline of its own, so a
            # frame that exactly fills the window still scrolls it by one.
            $avail = $Host.UI.RawUI.WindowSize.Height - $HeaderLines - $detailLines - $chrome - 2
            $vCount = [Math]::Max(5, [Math]::Min($rows.Count, $avail))
            # Keep the highlighted row inside the window, with the
            # selection roughly centred rather than pinned to an edge.
            if ($vCount -lt $rows.Count) {
                $vFirst = $i - [int]($vCount / 2)
                if ($vFirst -lt 0) { $vFirst = 0 }
                if ($vFirst + $vCount -gt $rows.Count) { $vFirst = $rows.Count - $vCount }
            }
        }
        $vEnd = $vFirst + $vCount - 1

        if ($vFirst -gt 0) { Paint ("      ^ $vFirst more above".PadRight($width)) 'DarkCyan' }
        else               { Paint (' ' * $width) }

        for ($r = $vFirst; $r -le $vEnd -and $r -lt $rows.Count; $r++) {
            $sel  = ($r -eq $i)
            # An arrow rather than a block of colour across the whole row.
            # Three characters so it is unmissable at a glance without
            # painting over everything else on the line.
            $cur  = if ($sel) { '  >>> ' } else { '      ' }
            $kind = $rows[$r].Kind

            if ($kind -eq 'gap') {
                Emit (' ' * $width)
            }
            elseif ($kind -eq 'start') {
                $txt = "$cur" + 'START'
                if ($sel) { Emit $txt.PadRight($width) 'Green' }
                else      { Emit $txt.PadRight($width) 'DarkGreen' }
            }
            elseif ($kind -eq 'cancel') {
                $txt = "$cur" + 'Cancel, change nothing'
                if ($sel) { Emit $txt.PadRight($width) 'White' }
                else      { Emit $txt.PadRight($width) 'DarkGray' }
            }
            else {
                $t    = $rows[$r].Task
                $box  = if ($t.On) { "[$Script:Tick]" } else { '[ ]' }
                $tag  = if ($t.Changes) { '  CHANGES' } else { '' }
                $txt  = "$cur$box $($t.Name)$tag"
                if ($txt.Length -gt $width) { $txt = $txt.Substring(0, $width) }
                # The row you are on is bright white. On or off is still
                # carried by the tick and by green versus grey, so the
                # highlight only ever answers "where am I", never "is
                # this on", and the two can no longer be confused.
                if     ($sel)       { Emit $txt.PadRight($width) 'White' }
                elseif ($t.On)      { Emit $txt.PadRight($width) 'Green' }
                elseif ($t.Changes) { Emit $txt.PadRight($width) 'DarkYellow' }
                else                { Emit $txt.PadRight($width) 'DarkGray' }
            }
        }

        if ($paint) {
            # Pad to a fixed number of row lines. Without this the frame
            # shrinks near the ends of the list, leaving the tail of the
            # previous, longer frame on screen underneath.
            $drawn = [Math]::Min($vEnd, $rows.Count - 1) - $vFirst + 1
            for ($pad = $drawn; $pad -lt $vCount; $pad++) { Paint (' ' * $width) }

            $below = $rows.Count - 1 - $vEnd
            if ($below -gt 0) { Paint ("      v $below more below".PadRight($width)) 'DarkCyan' }
            else              { Paint (' ' * $width) }
        }

        # Detail pane for whatever is highlighted. The option rows above
        # go through Emit so a test can inspect the layout; these panes
        # are painted straight to the console, so they are guarded to
        # keep the silent test mode genuinely silent.
        if ($paint) {
        Paint (' ' * $width)
        Paint (('    ' + ('-' * ($width - 6))).PadRight($width)) 'DarkGray'
        $detail = @()
        if ($rows[$i].Kind -eq 'task') {
            $t = $rows[$i].Task
            $detail += "takes $($t.Time)" + $(if ($t.Changes) { '   CHANGES THIS PC' } else { '   read only' })
            $detail += ''
            $detail += (Wrap $t.Desc ($width - 8))
        } elseif ($rows[$i].Kind -eq 'start') {
            $detail += 'Begin. Anything marked CHANGES offers a restore point first.'
        } elseif ($rows[$i].Kind -eq 'cancel') {
            $detail += 'Close without touching this computer.'
        }
        for ($d = 0; $d -lt 6; $d++) {
            $line = if ($d -lt $detail.Count) { '      ' + $detail[$d] } else { '' }
            if ($line.Length -gt $width) { $line = $line.Substring(0, $width) }
            Paint $line.PadRight($width) $(if ($d -eq 0) { 'White' } else { 'DarkGray' })
        }
        Paint (('    ' + ('-' * ($width - 6))).PadRight($width)) 'DarkGray'

        $sel2 = @($Tasks | Where-Object On)
        $lo = ($sel2 | Measure-Object Low  -Sum).Sum
        $hi = ($sel2 | Measure-Object High -Sum).Sum
        $est = if (-not $sel2.Count) { 'nothing selected' }
               elseif ($hi -le 1)    { 'under a minute' }
               elseif ($lo -eq 0)    { "up to about $hi minutes" }
               else                  { "roughly $lo to $hi minutes" }
        $ch = @($sel2 | Where-Object Changes).Count
        $sum = "    $($sel2.Count) selected, $est." + $(if ($ch) { "  $ch change this computer." } else { '' })
        Paint $sum.PadRight($width) $(if ($ch) { 'Yellow' } else { 'White' })

        }   # end of the detail and summary panes

      # ---- ONE PAINT ----------------------------------------------------
      # The whole frame goes out in a single write.
      #
      # Per-line Write-Host is flushed and rendered per line, so on every
      # keypress the menu visibly rebuilt itself from the top down: the
      # detail pane blanked, the coloured rows appeared low on the screen,
      # then everything settled back into place. That IS the glitch, and no
      # amount of cursor arithmetic fixes it, because the painting itself
      # is what you are watching.
      #
      # With ANSI enabled the entire frame, colours included, is one string
      # and one write, so the terminal repaints it as a single unit and the
      # frame simply changes. The cursor is hidden across the write as
      # well, because a caret racing down the screen reads as a glitch on
      # its own.
      #
      # NO trailing newline after the final line. Writing one while on the
      # bottom row scrolls the viewport, which is the "it moves all the way
      # down to the bottom" half of the symptom.
      if ($paint) {
        try {
            $wp = $Host.UI.RawUI.WindowPosition
            $Host.UI.RawUI.CursorPosition =
                New-Object System.Management.Automation.Host.Coordinates 0, $wp.Y
        } catch { }

        if ($Script:VtEnabled) {
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append("$([char]27)[?25l")          # hide the cursor
            for ($n = 0; $n -lt $frame.Count; $n++) {
                [void]$sb.Append((Get-AnsiLine $frame[$n].T $frame[$n].C))
                if ($n -lt $frame.Count - 1) { [void]$sb.Append("`n") }
            }
            [void]$sb.Append("$([char]27)[?25h")          # and put it back
            [Console]::Write($sb.ToString())
        } else {
            # No ANSI available. Per-line drawing, which flickers, but a
            # menu that flickers beats a menu that will not draw at all.
            foreach ($ln in $frame) { Write-Host $ln.T -ForegroundColor $ln.C }
        }
      }
      }

      $sel2 = @($Tasks | Where-Object On)
      if ($silent) {
          if ($kp -ge $TestKeys.Count) { return $false }
          $code = $TestKeys[$kp]; $kp++
      } else {
          $code = ($Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')).VirtualKeyCode
      }
      $k = [pscustomobject]@{ VirtualKeyCode = $code }
        switch ($k.VirtualKeyCode) {
            38 { $i--; if ($i -lt 0) { $i = $rows.Count - 1 } }             # up
            40 { $i++; if ($i -ge $rows.Count) { $i = 0 } }                 # down
            27 { return $false }                                            # esc
            13 {                                                            # enter
                switch ($rows[$i].Kind) {
                    'task'   { $rows[$i].Task.On = -not $rows[$i].Task.On }
                    'start'  { if ($sel2.Count) { return $true } }
                    'cancel' { return $false }
                }
            }
            32 { if ($rows[$i].Kind -eq 'task') { $rows[$i].Task.On = -not $rows[$i].Task.On } }  # space
        }
        # Skip the blank spacer row rather than letting the highlight
        # land on nothing.
        if ($rows[$i].Kind -eq 'gap') {
            if ($k.VirtualKeyCode -eq 38) { $i-- } else { $i++ }
            if ($i -lt 0) { $i = $rows.Count - 1 }
            if ($i -ge $rows.Count) { $i = 0 }
        }
    }
}

# What the user just did, echoed under the numbered menu so a toggle is
# visibly acknowledged and not just a character changing somewhere.
$Script:LastAction = ''

function Show-Menu {
    Clear-Host
    Write-Host ''
    Write-Host '   ==========================================' -ForegroundColor Cyan
    Write-Host '    DEEPER HEALTH CHECK' -ForegroundColor Cyan
    Write-Host "    $env:COMPUTERNAME" -ForegroundColor DarkGray
    Write-Host '   ==========================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '    Type an option key to switch it on or off, then ENTER to run.' -ForegroundColor DarkGray
    Write-Host '    Keys are 1 to 9, 0, F and T. Several at once is fine: "12F".' -ForegroundColor DarkGray
    Write-Host '    A = all,  N = none,  Q = quit without doing anything.' -ForegroundColor DarkGray
    Write-Host ''
    if ($Script:LastAction) {
        Write-Host ("    $($Script:LastAction)") -ForegroundColor Cyan
        Write-Host ''
    }
    foreach ($t in $Tasks) {
        # Three signals for the same fact, because one is easy to miss:
        # the tick in the box, the word ON or off, and the colour.
        if ($t.On) {
            Write-Host ("    [{0}] ON   {1}. {2}" -f $Script:Tick, $t.Key, $t.Name) -ForegroundColor Green
        } else {
            Write-Host ("    [ ] off  {0}. {1}" -f $t.Key, $t.Name) -ForegroundColor DarkGray
        }
        $tag = if ($t.Changes) { '   CHANGES THIS PC' } else { '' }
        Write-Host ("             takes {0}{1}" -f $t.Time, $tag) -ForegroundColor $(if ($t.Changes) { 'Yellow' } else { 'DarkGray' })
    }
    Write-Host ''
    Write-Host '    CHANGES THIS PC means it repairs, not just reads. Those are off' -ForegroundColor DarkGray
    Write-Host '    until you switch them on, and you get a restore point first.' -ForegroundColor DarkGray
    Write-Host ''

    $sel = @($Tasks | Where-Object On)
    if (-not $sel.Count) {
        Write-Host '    Nothing selected.' -ForegroundColor Yellow
    } else {
        $lo = ($sel | Measure-Object Low  -Sum).Sum
        $hi = ($sel | Measure-Object High -Sum).Sum
        $est = if ($hi -le 1) { 'under a minute' }
               elseif ($lo -eq 0) { "up to about $hi minutes" }
               else { "roughly $lo to $hi minutes" }
        Write-Host ("    {0} selected, {1}." -f $sel.Count, $est) -ForegroundColor White
        $ch = @($sel | Where-Object Changes).Count
        if ($ch) { Write-Host ("    {0} of them change this computer." -f $ch) -ForegroundColor Yellow }
        if (($sel | Where-Object { $_.Key -eq '1' })) {
            Write-Host '    A badly damaged machine can take longer than that. Do not close the window.' -ForegroundColor DarkGray
        }
    }
    Write-Host ''
}

# --- menu loop --------------------------------------------------------
# Wrapped in an outer loop so the confirmation screen can send you BACK
# here. Without that, pressing Enter by mistake left closing the window
# as the only way out of a 40 minute repair you did not mean to pick.
$confirmed = $false
$CanPick   = Test-CanPick
while (-not $confirmed) {

# The arrow-key picker where the console can support it, the numbered
# menu where it cannot. Both end the same way: $Tasks carries the choice.
if ($CanPick) {
    if (-not (Show-Picker)) {
        Write-Host ''
        Write-Host '    Nothing was run.' -ForegroundColor DarkGray
        Write-Host ''
        exit
    }
} else {
while ($true) {
    Show-Menu
    $c = Read-Host '    Option key to toggle, or ENTER to run'
    if ($c -eq '')                 { break }
    if ($c -match '^\s*[Qq]\s*$')  { Write-Host ''; Write-Host '    Nothing was run.' -ForegroundColor DarkGray; Write-Host ''; exit }
    # A, N and Q are exact commands, not prefixes. Two options are keyed
    # by letter (F and T), so "starts with A" would have swallowed input
    # meant for them.
    if ($c -match '^\s*[Aa]\s*$') { foreach ($t in $Tasks) { $t.On = $true };  $Script:LastAction = 'Switched everything ON.';  continue }
    if ($c -match '^\s*[Nn]\s*$') { foreach ($t in $Tasks) { $t.On = $false }; $Script:LastAction = 'Switched everything off.'; continue }

    # Several at once, so "1 2 F" or "12F" both work. Keys are digits
    # plus F and T, so strip to alphanumerics rather than digits only.
    $keys = ($c -replace '[^0-9A-Za-z]', '').ToUpper().ToCharArray()
    if (-not $keys) {
        $Script:LastAction = "'$c' is not one of the options. Use the numbers, or F or T."
        continue
    }
    $changed = @()
    foreach ($ch in $keys) {
        $hit = $Tasks | Where-Object { $_.Key -eq [string]$ch }
        if ($hit) {
            $hit.On = -not $hit.On
            $changed += ("{0} {1}" -f $(if ($hit.On) { 'ON  ->' } else { 'off ->' }), $hit.Name)
        }
    }
    # Name what just changed. Watching a single character flip somewhere
    # in a ten row list is exactly the kind of feedback people miss.
    $Script:LastAction = if ($changed.Count -eq 1) { "Switched $($changed[0])" }
                         elseif ($changed.Count)   { "Switched $($changed.Count) items: " + ($changed -join ' | ') }
                         else                      { "'$c' matched none of the options." }
}
}   # end of the numbered-menu fallback branch

# Repairing the disk needs the scan that queues the work for it, and
# chkdsk must not be run twice. Rather than let someone pick a repair
# that can do nothing, switch the check on and say so.
$fixDisk  = $Tasks | Where-Object { $_.Key -eq 'F' }
$scanDisk = $Tasks | Where-Object { $_.Key -eq '2' }
if ($fixDisk.On -and -not $scanDisk.On) {
    $scanDisk.On = $true
    Write-Host ''
    Write-Host '    Disk repair needs the disk check, so that has been switched on too.' -ForegroundColor Yellow
    Write-Host '    They run as one pass. chkdsk is not run twice.' -ForegroundColor DarkGray
    Start-Sleep -Seconds 2
}

# Same shape as the disk pair above. Forcing the full pass is a modifier
# ON the system file repair, not a repair of its own, so selecting it
# alone would silently do nothing at all.
$dismOptOut = $Tasks | Where-Object { $_.Key -eq 'D' }
$sysFiles   = $Tasks | Where-Object { $_.Key -eq '1' }
if ($dismOptOut.On -and -not $sysFiles.On) {
    $dismOptOut.On = $false
    Write-Host ''
    Write-Host '    "Skip DISM" only changes how the system file repair behaves, and that' -ForegroundColor Yellow
    Write-Host '    repair is switched off, so it has been unticked. Nothing was lost.' -ForegroundColor DarkGray
    Start-Sleep -Seconds 2
}

$run = @($Tasks | Where-Object On)
if (-not $run.Count) { Write-Host ''; Write-Host '    Nothing selected. Pick at least one.' -ForegroundColor Yellow; Start-Sleep -Seconds 2; continue }

# --- a way back, before anything changes ------------------------------
$changing = @($run | Where-Object Changes)
Clear-Host
Write-Host ''
Write-Host '   ==========================================' -ForegroundColor Cyan
Write-Host '    ABOUT TO RUN' -ForegroundColor Cyan
Write-Host '   ==========================================' -ForegroundColor Cyan
Write-Host ''
foreach ($t in $run) {
    Write-Host ("    - {0}" -f $t.Name) -ForegroundColor $(if ($t.Changes) { 'Yellow' } else { 'Gray' })
    Write-Host ("        takes {0}" -f $t.Time) -ForegroundColor DarkGray
}
Write-Host ''
$lo = ($run | Measure-Object Low  -Sum).Sum
$hi = ($run | Measure-Object High -Sum).Sum
if ($hi -le 1)      { Write-Host '    All together: under a minute.' -ForegroundColor White }
elseif ($lo -eq 0)  { Write-Host "    All together: up to about $hi minutes." -ForegroundColor White }
else                { Write-Host "    All together: roughly $lo to $hi minutes." -ForegroundColor White }
Write-Host ''

# Last chance to change your mind, and it comes BEFORE the restore point
# so an accidental Enter at the menu does not commit you to anything.
$go = Read-Host '    ENTER to start, B to go back and change the list, Q to quit'
if ($go -match '^[Qq]') { Write-Host ''; Write-Host '    Nothing was run.' -ForegroundColor DarkGray; Write-Host ''; exit }
if ($go -match '^[Bb]') { continue }
$confirmed = $true

if ($changing.Count) {
    Write-Host ''
    Write-Host "    $($changing.Count) of these change the computer." -ForegroundColor Yellow
    Write-Host '    A restore point gives you a way back if anything goes wrong.' -ForegroundColor DarkGray
    Write-Host ''
    if ((Read-Host '    Create a restore point first? (y/n)') -match '^y') {
        Work 'creating a restore point'
        try {
            # System protection is OFF by default on Windows 11, so a
            # machine handed to you usually has nothing to roll back to.
            Enable-ComputerRestore -Drive 'C:\' -EA SilentlyContinue
            # Windows silently refuses a second restore point within 24
            # hours. Lift that for this run only, then put it back.
            $rpKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
            $old   = (Get-ItemProperty $rpKey -Name 'SystemRestorePointCreationFrequency' -EA SilentlyContinue).SystemRestorePointCreationFrequency
            New-ItemProperty -Path $rpKey -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force -EA SilentlyContinue | Out-Null
            # Checkpoint-Computer prints nothing and can sit for a full
            # minute, which is the single most alarming silent pause in
            # this tool because it happens right before the repairs.
            Spin 'creating the restore point' {
                param($desc)
                Checkpoint-Computer -Description $desc -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
            } "Before deeper health check $(Get-Date -f 'yyyy-MM-dd HH:mm')" 180 | Out-Null
            if ($null -ne $old) { New-ItemProperty -Path $rpKey -Name 'SystemRestorePointCreationFrequency' -Value $old -PropertyType DWord -Force -EA SilentlyContinue | Out-Null }
            else { Remove-ItemProperty -Path $rpKey -Name 'SystemRestorePointCreationFrequency' -EA SilentlyContinue }
            Good 'restore point created'
        } catch {
            Warn "could not create a restore point: $($_.Exception.Message)"
            if ((Read-Host '    Carry on without one? (y/n)') -notmatch '^y') { exit }
        }
    }
}
}   # end of the outer menu/confirm loop

Clear-Host

# A repair log gets read later, by someone who was not there, possibly
# about a machine they have never seen. Say WHICH machine, WHEN, and
# what was actually asked for, including what was deliberately skipped.
# "Did you run SFC?" has to be answerable from the file alone.
# Behind timeouts. A try/catch does NOT save you from these: a wedged WMI
# or a domain lookup that never returns does not throw, it just never
# comes back, and this runs before the first line of the log is written.
# That is how the Health Report froze on a desktop, and the deeper check
# made the identical call.
$cs = Spin 'identifying the machine' {
    param($x)
    Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
} $null 20
$os = Spin 'reading the Windows edition' {
    param($x)
    Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
} $null 20
$bi = Spin 'reading the BIOS' {
    param($x)
    Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
} $null 20

LogOnly 'DEEPER HEALTH CHECK'
LogOnly ('=' * 60)
LogOnly ("Machine   : $env:COMPUTERNAME")
if ($cs) { LogOnly ("Model     : $($cs.Manufacturer) $($cs.Model)") }
if ($bi) { LogOnly ("Serial    : $($bi.SerialNumber)") }
if ($os) { LogOnly ("Windows   : $($os.Caption) build $($os.BuildNumber)") }
LogOnly ("Started   : $(Get-Date -f 'yyyy-MM-dd HH:mm:ss')")
LogOnly ("Run by    : $env:USERNAME" + $(if ($IsAdmin) { ' (administrator)' } else { ' (NOT administrator, some checks are limited)' }))
LogOnly ''
LogOnly 'Selected:'
foreach ($t in $Tasks) {
    LogOnly ("  [{0}] {1}. {2}" -f $(if ($t.On) { 'x' } else { ' ' }), $t.Key, $t.Name)
}
LogOnly ('=' * 60)

# =====================================================================
#  DISM WATCHDOG
# =====================================================================
#  DISM can wedge completely and give no sign of it. On 2026-08-15 it sat
#  at 62.6% for over an hour on a live machine. Measured at the time: zero
#  CPU, and dism.log's last entry was 35 minutes old and only showed
#  initialisation, so it had never started the actual work. The percentage
#  on screen stays exactly where it was, so the display looks identical to
#  a slow-but-working repair.
#
#  Nothing else here can catch it. Spin's timeout cannot be used, because
#  DISM has to run bare in the foreground or it loses its own progress
#  bar, so the script is blocked for the whole run.
#
#  So: a watcher on a second runspace, checking how long it has been since
#  DISM last wrote to its log. Ten minutes of silence is suspicious, and
#  twenty-five is almost certainly dead. It reports through [Console]
#  rather than Write-Host because a runspace made this way has no host UI
#  of its own, and Console is process-wide so the text reaches the screen.
#
#  Log silence, not CPU, is the signal. DISM legitimately sits at low CPU
#  while waiting on Windows Update, but a healthy run keeps writing.
# =====================================================================
function Start-StallWatch {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Tool,
        [int]$WarnMinutes = 10,
        [int]$DeadMinutes = 25
    )
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript({
        param($log, $tool, $warnM, $deadM)
        $lastWarn = 0
        $lastSize = -1
        while ($true) {
            Start-Sleep -Seconds 30
            try {
                if (-not (Test-Path $log)) { continue }
                $item = Get-Item $log -ErrorAction SilentlyContinue
                if (-not $item) { continue }

                # Size as well as timestamp. Some tools hold the log open
                # and the modified time does not always move on a flush,
                # so growth is the second opinion.
                $grew = ($item.Length -ne $lastSize)
                $lastSize = $item.Length
                $age = [int]((Get-Date) - $item.LastWriteTime).TotalMinutes
                if ($grew -or $age -lt $warnM) { $lastWarn = 0; continue }

                # Warn once when it goes quiet, then again only when the
                # picture changes, rather than nagging every 30 seconds.
                if ($age -ge $deadM -and $lastWarn -lt $deadM) {
                    $lastWarn = $age
                    [Console]::WriteLine('')
                    [Console]::WriteLine("    XX  $tool has written nothing for $age minutes. It is almost certainly stuck.")
                    [Console]::WriteLine('        This is a Windows fault, not a fault in this tool. Press Ctrl+C,')
                    [Console]::WriteLine('        reboot, and run this again. Nothing has been half-applied.')
                } elseif ($age -ge $warnM -and $lastWarn -eq 0) {
                    $lastWarn = $age
                    [Console]::WriteLine('')
                    [Console]::WriteLine("    !!  $tool has written nothing to its log for $age minutes.")
                    [Console]::WriteLine('        It may still be working. If its percentage has not moved either,')
                    [Console]::WriteLine("        give it until $deadM minutes and then treat it as stuck.")
                }
            } catch { }
        }
    })
    [void]$ps.AddArgument($LogPath)
    [void]$ps.AddArgument($Tool)
    [void]$ps.AddArgument($WarnMinutes)
    [void]$ps.AddArgument($DeadMinutes)
    $handle = $ps.BeginInvoke()
    return [pscustomobject]@{ PS = $ps; Handle = $handle }
}

# Named wrappers, so a call site reads as what it is watching.
function Start-DismWatchdog {
    param([int]$WarnMinutes = 10, [int]$DeadMinutes = 25)
    Start-StallWatch -LogPath (Join-Path $env:WINDIR 'Logs\DISM\dism.log') -Tool 'DISM' `
                     -WarnMinutes $WarnMinutes -DeadMinutes $DeadMinutes
}

# SFC reports through CBS.log. It hangs less often than DISM but it does
# happen, usually on a machine whose component store is already damaged,
# which is exactly the machine this gets run on.
function Start-SfcWatchdog {
    param([int]$WarnMinutes = 15, [int]$DeadMinutes = 30)
    Start-StallWatch -LogPath (Join-Path $env:WINDIR 'Logs\CBS\CBS.log') -Tool 'SFC' `
                     -WarnMinutes $WarnMinutes -DeadMinutes $DeadMinutes
}

function Stop-StallWatch($w) {
    if (-not $w) { return }
    try { $w.PS.Stop() }    catch { }
    try { $w.PS.Dispose() } catch { }
}

# =====================================================================
#  1. SFC, DISM, SFC
# =====================================================================
if (On '1') {
    Sec 'Repairing system files'
    Write-Host ''
    # Was a thirteen line box. Most of it explained why there is no
    # spinner over the top of SFC's own percentage, which is a note to
    # whoever maintains this, not to the person watching a repair. Kept:
    # the percentage stalls on one number and that is normal, and do not
    # close the window. Those two are the ones that stop somebody killing
    # a repair halfway through.
    Show-Box @(
        'SFC and DISM show their own percentage below.'
        'It can sit on one number for several minutes. That is normal.'
        'DO NOT CLOSE THIS WINDOW.'
    )
    Write-Host ''
    LogOnly '  SFC and DISM run bare so they draw their own live percentage.'

    Work 'SFC pass 1'
    Write-Host ("           started at {0}" -f (Get-Date -f 'HH:mm:ss')) -ForegroundColor DarkGray
    Write-Host ''
    $t0 = Get-Date
    # BARE. No pipeline, no redirect, no spinner. See the header: any of
    # those and the live percentage is gone.
    $sfcW = Start-SfcWatchdog
    & sfc.exe /scannow
    Stop-StallWatch $sfcW
    Write-Host ''
    # The timing line goes out FIRST, before the log read, so the console
    # never goes quiet in the gap between sfc.exe exiting (which takes
    # its percentage away with it) and the spinner starting.
    Info "SFC pass 1 finished at $(Get-Date -f 'HH:mm:ss'), took $(Mins $t0)"
    # Its output went to the console and nowhere else, so recover the
    # findings from CBS.log into the report. One read, feeding both the
    # verdict and the detail.
    $sr1  = Get-CbsSrLines
    $sfc1 = Get-SfcVerdict $sr1
    Add-Detail 'SFC pass 1, from CBS.log:' (Get-SfcDetail $sr1)

    # Ticking 'D' opts OUT of always running DISM.
    $skipUnlessDamaged = On 'D'
    switch ($sfc1) {
        'clean'    {
            if ($skipUnlessDamaged) { Good 'SFC pass 1: no integrity violations. Skipping DISM, as you asked.' }
            else                    { Good 'SFC pass 1: no integrity violations. DISM still runs, to check the store itself.' }
            Verdict 'system files: intact'
        }
        'repaired' { Good 'SFC pass 1: found damage and repaired it'; Verdict 'system files: repaired' }
        'stuck'    { Warn 'SFC found damage it could NOT repair. That is what DISM is for.' }
        default    { Warn 'SFC gave no clear verdict in CBS.log. Running DISM anyway to be safe.' }
    }

    # DISM RUNS BY DEFAULT. $skipUnlessDamaged is the opt-out.
    #
    # This used to be the other way round: DISM only ran when SFC reported
    # damage. That is backwards, because a clean SFC is exactly the result
    # you cannot trust on its own. SFC compares Windows against the
    # component store, so if the store is damaged it compares against a bad
    # reference, finds no difference, and reports clean on a machine that
    # plainly is not. DISM is the only one of the two that checks the store
    # itself, so skipping it whenever SFC is happy skips it precisely when
    # it would have told you something new.
    if ($sfc1 -ne 'clean' -or -not $skipUnlessDamaged) {
        if ($skipUnlessDamaged -eq $false -and $sfc1 -eq 'clean') {
            Info 'SFC found nothing, but you unticked "skip DISM", so it runs anyway.'
            Info 'That is the right call when a machine misbehaves and SFC says it is fine.'
        }
        Work 'DISM RestoreHealth: rebuilding the store SFC copies from'
        Write-Host ("           started at {0}" -f (Get-Date -f 'HH:mm:ss')) -ForegroundColor DarkGray
        Write-Host '           It is normal for the percentage to STOP for a long time at' -ForegroundColor DarkGray
        Write-Host '           various points. It is repairing files when it does that.' -ForegroundColor DarkGray
        Write-Host '           Do not close this window.' -ForegroundColor DarkGray
        Write-Host '           It needs the internet: Windows Update is its default source.' -ForegroundColor DarkGray
        Write-Host '           If the number has not moved at all in 20 minutes it is genuinely' -ForegroundColor DarkGray
        Write-Host '           stuck: press Ctrl+C, reboot, and run this again.' -ForegroundColor DarkGray
        Write-Host ''
        $t0 = Get-Date
        $wd = Start-DismWatchdog
        # BARE.
        & dism.exe /Online /Cleanup-Image /RestoreHealth
        $dismRc = $LASTEXITCODE
        Stop-StallWatch $wd
        Write-Host ''
        Info "DISM finished at $(Get-Date -f 'HH:mm:ss'), took $(Mins $t0)"
        Add-Detail 'DISM RestoreHealth, from dism.log:' (Get-DismDetail)
        if ($dismRc -eq 0) { Good 'DISM completed' }
        else {
            Fail "DISM exited with code $dismRc"
            Info 'The usual cause is no internet. DISM pulls replacement files from Windows Update.'
            Info 'Connect and run this again, or point DISM at a Windows ISO with /Source.'
        }

        Work 'SFC pass 2, now with a repaired source to copy from'
        $t0 = Get-Date
        # BARE.
        $sfcW = Start-SfcWatchdog
        & sfc.exe /scannow
        Stop-StallWatch $sfcW
        Write-Host ''
        Info "SFC pass 2 finished at $(Get-Date -f 'HH:mm:ss'), took $(Mins $t0)"
        $sr2  = Get-CbsSrLines
        $sfc2 = Get-SfcVerdict $sr2
        Add-Detail 'SFC pass 2, from CBS.log:' (Get-SfcDetail $sr2)
        switch ($sfc2) {
            'clean'    { Good 'SFC pass 2: clean. The machine is repaired.'; Verdict 'system files: repaired' }
            'repaired' { Good 'SFC pass 2: repaired the remaining files'; Verdict 'system files: repaired' }
            'stuck'    {
                Fail 'SFC still cannot repair some files after DISM.'
                Info "The detail is in $env:WINDIR\Logs\CBS\CBS.log, search for [SR]."
                Info 'Next step is an in-place repair install: run setup.exe from a Windows ISO'
                Info 'and choose "Keep personal files and apps". It keeps everything.'
                Verdict 'system files: STILL DAMAGED, needs an in-place repair install'
            }
            default    { Warn 'No clear verdict from CBS.log after pass 2.'; Verdict 'system files: verdict unclear' }
        }
    }
}

# =====================================================================
#  2. CHKDSK, and the repair in the SAME pass
# =====================================================================
if (On '2') {
    Sec 'Checking the disk'
    Work 'chkdsk C: /scan  (online, nothing is changed, no reboot)'
    Write-Host ("           started at {0}. chkdsk prints its own percentage" -f (Get-Date -f 'HH:mm:ss')) -ForegroundColor DarkGray
    Write-Host '           per stage below. It scans while Windows runs.' -ForegroundColor DarkGray
    Write-Host ''
    $t0 = Get-Date
    # BARE.
    & chkdsk.exe C: /scan
    $rc = $LASTEXITCODE
    Write-Host ''
    Info "chkdsk finished at $(Get-Date -f 'HH:mm:ss'), took $(Mins $t0)"
    # chkdsk writes its full report into the Application event log, which
    # is the only way to get it into this file: capturing its stdout
    # would have cost the live progress.
    Info 'reading the chkdsk report Windows wrote to the event log'
    Add-Detail 'chkdsk report, from the Application event log:' (Get-ChkdskDetail $t0.AddMinutes(-1))

    # chkdsk: 0 no problems, 2 problems found, 3 could not check.
    $diskDirty = ($rc -eq 2)
    switch ($rc) {
        0 { Good 'no filesystem problems on C:'; Verdict 'disk C: clean' }
        2 { Warn 'chkdsk found problems on C:.' }
        3 { Fail 'chkdsk could not check the disk'; Verdict 'disk C: could not be checked' }
        default { Warn "chkdsk exited with $rc"; Verdict "disk C: chkdsk returned $rc" }
    }

    # ---------------------------------------------------------------
    #  REPAIR, in the SAME pass. chkdsk is not run a second time.
    #
    #  Per chkdsk's own help: /scan runs the online scan, and defects it
    #  finds "are queued for offline repair (i.e. chkdsk /spotfix)". So
    #  /spotfix repairs what the scan just queued. They are two halves of
    #  one operation, not two scans, and running /scan again before it
    #  would be pointless work on a disk that is already suspect.
    # ---------------------------------------------------------------
    if (-not $diskDirty) {
        if (On 'F') { Info 'Nothing to repair: the scan found no problems, so /spotfix is skipped.' }
    }
    elseif (-not (On 'F')) {
        Info 'Repair was not selected. Tick "also repair what the check finds" to fix these.'
        Verdict 'disk C: HAS ERRORS, not repaired because repair was not selected'
    }
    else {
        Work 'repairing what the scan queued  (chkdsk /spotfix)'
        Info 'This repairs online in minutes. The old boot-time scan took hours.'
        Write-Host ''
        $t1 = Get-Date
        # BARE, like every other scan.
        & chkdsk.exe C: /spotfix
        $frc = $LASTEXITCODE
        Write-Host ''
        Info "repair finished at $(Get-Date -f 'HH:mm:ss'), took $(Mins $t1)"
        Add-Detail 'chkdsk /spotfix report, from the Application event log:' (Get-ChkdskDetail $t1.AddMinutes(-1))

        if ($frc -eq 0) { Good 'disk repaired'; Verdict 'disk C: repaired online' }
        else {
            # spotfix mends what it can reach with the volume mounted.
            # Anything deeper needs the volume offline, which means the
            # boot-time scan, which means a decision. That decision is
            # DEFERRED so a long run is not left sitting on a prompt.
            Warn "repair returned $frc, so some damage needs the volume taken offline."
            Verdict "disk C: damage remains that needs an offline repair (exit $frc)"
            Defer 'Schedule a full offline chkdsk for the next restart?' {
                # echo y: chkdsk asks whether to schedule and has no
                # switch meaning yes, so without this it waits forever.
                cmd.exe /c 'echo y| chkdsk C: /f' | Out-Null
                Write-Host '    ok   full chkdsk scheduled: it runs at the next restart, before Windows loads.' -ForegroundColor Green
                Write-Host '         On a large or damaged disk that can take hours. Do not interrupt it.' -ForegroundColor DarkGray
            } 'Some filesystem damage can only be repaired with Windows not running. Back up anything irreplaceable first.'
        }
    }
}

# =====================================================================
#  F. handled inside section 2, above
# =====================================================================

# =====================================================================
#  T. Temp files
# =====================================================================
if (On 'T') {
    Sec 'Clearing out temp files'
    $before = (Get-PSDrive C).Free

    # Named literally, one entry each, because a deletion loop built from
    # concatenated paths is how a previous cleanup script produced a plan
    # claiming more data than the drive held.
    $spots = @(
        @{ N = 'Windows temp';         P = "$env:WINDIR\Temp" }
        @{ N = 'your temp';            P = $env:TEMP }
        @{ N = 'Windows Update cache'; P = "$env:WINDIR\SoftwareDistribution\Download" }
        @{ N = 'prefetch';             P = "$env:WINDIR\Prefetch" }
    )
    foreach ($s in $spots) {
        if (-not (Test-Path $s.P)) { Info "$($s.N): not present"; continue }

        # Count first, so the progress line has a denominator. A bare
        # "working..." tells you nothing; "820 of 3636" tells you whether
        # it is moving.
        $items = @(Get-ChildItem -LiteralPath $s.P -Force -ErrorAction SilentlyContinue)
        Work ("$($s.N): $($items.Count) item(s) to clear")

        $n = 0; $skipped = 0; $done = 0
        $t0 = Get-Date
        foreach ($item in $items) {
            $done++
            # Top level only, with -Recurse doing the descending.
            # Deleting every file individually was measured at 1.1x, not
            # the 10x it looks like, so it buys nothing.
            try { Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop; $n++ }
            catch {
                # A file in use cannot be deleted and that is fine and
                # expected: the browser, the antivirus and Windows itself
                # all hold handles in here. Skipping is correct, and
                # forcing would be wrong. It is counted, not hidden.
                $skipped++
            }
            if ($Script:CanAnimate -and ($done % 25 -eq 0 -or $done -eq $items.Count)) {
                Write-Host ("`r           {0} of {1}   removed {2}, in use {3}   {4}s    " -f `
                    $done, $items.Count, $n, $skipped, [int]((Get-Date) - $t0).TotalSeconds) -NoNewline -ForegroundColor DarkGray
            }
        }
        if ($Script:CanAnimate) { Write-Host "`r$(' ' * 78)`r" -NoNewline }
        $note = if ($skipped) { ", $skipped left alone because they are in use" } else { '' }
        Info "$($s.N): removed $n of $($items.Count)$note  ($(Mins $t0))"
    }

    # -Confirm:$false, NOT -Force.
    #
    # This is what hung the run. Clear-RecycleBin declares
    # ConfirmImpact = High, and Windows defaults $ConfirmPreference to
    # High, so it asks "Are you sure?" before doing anything. -Force does
    # NOT suppress a ShouldProcess confirmation, it only overrides
    # read-only and hidden. Only -Confirm:$false does. The prompt appeared
    # under the temp-file output and the whole tool looked frozen.
    Work 'emptying the recycle bin'
    try { Clear-RecycleBin -Force -Confirm:$false -ErrorAction Stop; Info 'recycle bin emptied' }
    catch { Info 'recycle bin was already empty, or is not accessible' }

    $freed = [math]::Round(((Get-PSDrive C).Free - $before) / 1GB, 2)
    if ($freed -gt 0) { Good "reclaimed $freed GB on C:"; Verdict "temp cleanup freed $freed GB" }
    else { Good 'temp folders cleared, nothing significant to reclaim' }
    Info 'Files in use are skipped rather than forced. That is deliberate.'
}

# =====================================================================
#  3. SMART
# =====================================================================
if (On '3') {
    Sec 'Drive health from the firmware'
    # Get-PhysicalDisk and the reliability counters both go out to the
    # storage stack and print nothing while they do it. On a machine with
    # a struggling disk, which is exactly when you are running this, that
    # wait gets long.
    $disks = Spin 'asking each drive for its SMART data' {
        param($x)
        Get-PhysicalDisk -ErrorAction SilentlyContinue |
            ForEach-Object { [pscustomobject]@{
                Disk = $_
                Rel  = (Get-StorageReliabilityCounter -PhysicalDisk $_ -ErrorAction SilentlyContinue) } }
    } $null 60
    foreach ($entry in (AsArray $disks)) {
        $d = $entry.Disk
        Write-Host ("    {0}" -f $d.FriendlyName) -ForegroundColor White
        [void]$Log.Add("  $($d.FriendlyName)")
        $hTxt = Get-DiskHealthText $d.HealthStatus
        $mTxt = Get-MediaTypeText  $d.MediaType
        Info ("{0} GB, {1}, reported health: {2}" -f [math]::Round($d.Size/1GB,0), $mTxt, $hTxt)
        if (-not (Test-DiskHealthy $d.HealthStatus)) {
            Fail "$($d.FriendlyName): health is '$hTxt'"
            Verdict "$($d.FriendlyName): reports $hTxt, check it with CrystalDiskInfo before trusting it"
        }

        $r = $entry.Rel
        if (-not $r) {
            if (-not $IsAdmin) { Warn 'SMART counters need administrator rights, and this is not running as admin. Start from Health-Report.bat, which elevates.' }
            else { Info 'no reliability counters (normal for USB sticks and some RAID controllers)' }
            continue
        }
        if ($r.PowerOnHours) { Info ("powered on for {0} hours, about {1} years" -f $r.PowerOnHours, [math]::Round($r.PowerOnHours/24/365,1)) }
        if ($r.Temperature)  { Info "temperature $($r.Temperature) C" }
        if ($null -ne $r.Wear) {
            Info "SSD write life used: $($r.Wear) %"
            if     ($r.Wear -gt 90) { Fail "$($d.FriendlyName): $($r.Wear)% of write life used. Replace it."; Verdict "$($d.FriendlyName): worn out" }
            elseif ($r.Wear -gt 70) { Warn "$($d.FriendlyName): $($r.Wear)% of write life used. Plan a replacement." }
        }
        foreach ($p in @(@{N='read errors';   V=$r.ReadErrorsTotal},
                         @{N='write errors';  V=$r.WriteErrorsTotal},
                         @{N='uncorrected read errors'; V=$r.ReadErrorsUncorrected})) {
            if ($p.V -gt 0) { Warn "$($d.FriendlyName): $($p.V) $($p.N)" }
        }
    }
}

# =====================================================================
#  4. Event log
# =====================================================================
if (On '4') {
    Sec 'Faults in the last 14 days'
    $since = (Get-Date).AddDays(-14)

    # Five separate queries over a fortnight of the System log, each of
    # which prints nothing until it returns. On a busy or sick machine
    # this is genuinely slow, so it runs behind one spinner.
    $ev = Spin 'reading 14 days of the Windows event log' {
        param($since)
        [pscustomobject]@{
            # Event 41 is Windows saying it was not shut down cleanly:
            # the fingerprint of a crash, a freeze or a power cut.
            K41  = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=41; StartTime=$since} -ErrorAction SilentlyContinue)
            Bug  = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; StartTime=$since} -ErrorAction SilentlyContinue)
            # Disk 7/11/51 mean the hardware itself is struggling.
            Disk = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='disk'; StartTime=$since} -ErrorAction SilentlyContinue |
                     Where-Object { $_.Id -in 7, 11, 51 })
            Whea = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$since} -ErrorAction SilentlyContinue)
            Svc  = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=7000, 7001, 7026; StartTime=$since} -ErrorAction SilentlyContinue)
        }
    } $since 90

    $k41 = @($ev.K41)
    if ($k41.Count) {
        Warn "$($k41.Count) unexpected shutdown(s) or crash(es). Most recent: $($k41[0].TimeCreated.ToString('yyyy-MM-dd HH:mm'))"
        Verdict "$($k41.Count) unexpected shutdowns in 14 days"
    } else { Good 'no unexpected shutdowns' }

    $bug = @($ev.Bug)
    if ($bug.Count) { Fail "$($bug.Count) blue screen(s) recorded"; Verdict "$($bug.Count) blue screens in 14 days" }
    else { Good 'no blue screens recorded' }

    $disk = @($ev.Disk)
    if (-not $disk.Count) { Good 'no disk hardware errors' }
    else {
        # NAME THE DRIVE. The event says "\Device\Harddisk1", which means
        # nothing to a person and is actively misleading: on one machine
        # Harddisk1 was a USB stick, not the system SSD, so the blanket
        # "dying drive" verdict would have sent someone to replace the
        # wrong disk. Resolve the number to a real model first.
        $diskMap = @{}
        $physDrives = AsArray (Spin 'matching the event to a real drive' {
            param($x)
            Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
        } $null 60)
        foreach ($dd in $physDrives) {
            if ($dd.DeviceID -match 'PHYSICALDRIVE(\d+)') {
                $diskMap[$matches[1]] = @{ Model = $dd.Model; Bus = $dd.InterfaceType }
            }
        }
        $hit = @{}
        foreach ($e in $disk) {
            $n = if ($e.Message -match '\\Device\\Harddisk(\d+)') { $matches[1] } else { '?' }
            if (-not $hit.ContainsKey($n)) { $hit[$n] = 0 }
            $hit[$n]++
        }
        foreach ($n in $hit.Keys) {
            $d2   = $diskMap[$n]
            $name = if ($d2) { "$($d2.Model)" } else { "Harddisk$n (not currently attached)" }
            $bus  = if ($d2) { $d2.Bus } else { $null }
            Fail ("{0} disk error(s) on {1}" -f $hit[$n], $name)
            if ($bus -eq 'USB') {
                # A USB stick throwing paging errors is usually the cable,
                # the port or the stick being yanked, not a failing system
                # drive. Saying "dying drive" here would be wrong.
                Info 'That is a USB device. On removable media this is usually a loose'
                Info 'connection, a knocked cable or the stick being pulled out mid-write,'
                Info 'rather than a failing internal disk. Reseat it and re-check.'
                Verdict "disk errors on the USB device '$name', probably connection not failure"
            } else {
                Info 'On an internal drive treat this as a failing disk until proven otherwise.'
                Info 'Back it up before anything else, then check SMART.'
                Verdict "disk hardware errors on $name, treat as failing"
            }
        }
    }

    $whea = @($ev.Whea)
    if ($whea.Count) { Warn "$($whea.Count) hardware error(s) reported by the CPU or chipset (WHEA)"; Verdict 'WHEA hardware errors logged' }
    else { Good 'no CPU or chipset hardware errors' }

    $svc = @($ev.Svc)
    if ($svc.Count -gt 5) { Warn "$($svc.Count) service or driver start failures. Often a leftover from software that was removed badly." }

    # A count is a headline, not evidence. Whoever reads this later needs
    # the dates and the actual message to act on any of it, so the real
    # entries go into the file even though only the counts go on screen.
    function Fmt($events, $limit = 8) {
        @($events | Select-Object -First $limit | ForEach-Object {
            $msg = ($_.Message -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 2) -join ' '
            "{0}  id {1}  {2}" -f $_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $_.Id, $msg.Trim()
        })
    }
    Add-Detail 'Unexpected shutdowns:'          (Fmt $k41)
    Add-Detail 'Blue screens:'                  (Fmt $bug)
    Add-Detail 'Disk hardware errors:'          (Fmt $disk)
    Add-Detail 'CPU or chipset errors (WHEA):'  (Fmt $whea)
    Add-Detail 'Service and driver failures:'   (Fmt $svc 12)
}

# =====================================================================
#  5. Reliability history
# =====================================================================
if (On '5') {
    Sec 'What has been failing'
    $rr = AsArray (Spin 'reading the reliability history' {
        param($x)
        Get-CimInstance Win32_ReliabilityRecords -ErrorAction SilentlyContinue
    } $null 60)
    if (-not $rr.Count) { Info 'Windows has no reliability history on this machine yet.' }
    else {
        $top = $rr | Where-Object { $_.SourceName } | Group-Object SourceName |
               Sort-Object Count -Descending | Select-Object -First 8
        Info "$($rr.Count) recorded events. The most frequent sources:"
        foreach ($g in $top) { Info ("  {0,-40} {1}" -f $g.Name, $g.Count) }
        Info 'Full picture: run  perfmon /rel  for the graph version of this.'
    }
}

# =====================================================================
#  6. Driver faults
# =====================================================================
if (On '6') {
    Sec 'Devices with driver problems'
    # Enumerating every PnP device is a WMI walk of the whole device
    # tree. Seconds on a healthy machine, much longer on a sick one.
    $bad = AsArray (Spin 'checking every device for a driver fault' {
        param($x)
        # NOT 22: that is a device somebody deliberately disabled, and
        # reporting that as a fault is how a check gets ignored. 28 is
        # the one an unrecognised USB device produces.
        Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.ConfigManagerErrorCode -in @(1, 10, 28, 31, 43) }
    } $null 90)
    if (-not $bad.Count) { Good 'every device has a working driver' }
    else {
        foreach ($d in $bad) {
            $why = switch ($d.ConfigManagerErrorCode) {
                1  { 'not configured correctly' }
                10 { 'cannot start' }
                28 { 'NO DRIVER INSTALLED' }
                31 { 'driver failed to load' }
                43 { 'Windows stopped it after it reported a fault' }
            }
            Fail "$($d.Name): $why (code $($d.ConfigManagerErrorCode))"
        }
        Verdict "$($bad.Count) device(s) with driver problems"
        Info 'Try "Install driver updates from Windows Update" in the menu.'
        Info 'BIOS and firmware still only come from the board maker''s own site.'
    }
}


# =====================================================================
#  U. Driver updates from Windows Update
# =====================================================================
#  This replaces the old standalone Tools\Drivers tool, which was deleted.
#
#  That tool did two things wrong. It winget-installed the manufacturer's
#  own updater (MSI Center, MyASUS and friends), which is exactly the
#  heavy vendor software you do not want left on a machine you are handing
#  back. And it reached for the third-party PSWindowsUpdate module, which
#  has to be downloaded from the PowerShell Gallery, needs the NuGet
#  provider, installs machine-wide, and simply fails on a machine with no
#  internet, which is half of what this stick is for.
#
#  Windows has had its own update API since Vista. It is already present,
#  needs no download, and is what Settings itself calls. Per Microsoft's
#  IUpdateSearcher::Search documentation the Type criterion takes
#  'Driver', so the whole job is one search string.
#
#  It is honest about the limit: Windows Update is deliberately
#  conservative and lags the vendor's own releases. The report says which
#  devices are broken or on a generic driver; this installs what Microsoft
#  will actually vouch for, and nothing else.
# =====================================================================
# Delete the DOWNLOADED PACKAGES once they are installed, which is what
# was asked for, and be precise about which files that means.
#
# Windows keeps driver updates in TWO places and only one of them is
# rubbish afterwards:
#
#   SoftwareDistribution\Download   the downloaded payload. Disposable.
#                                   Windows clears it on its own after
#                                   about ten days and rebuilds it on
#                                   demand. Safe to delete now.
#
#   System32\DriverStore\FileRepository   the staged driver package.
#                                   NOT rubbish. Windows needs it to
#                                   reinstall the device, to roll the
#                                   driver back, and to bring the device
#                                   up after a reset. Deleting from here
#                                   is what DriverStore Explorer does,
#                                   and doing it automatically after an
#                                   install would remove the only way
#                                   back from a bad driver.
#
# So this clears the download cache only. Files still locked by the
# update service are skipped rather than forced, because a half-deleted
# payload is worse than a full one.
function Clear-UpdateDownloadCache {
    $dir = Join-Path $env:WINDIR 'SoftwareDistribution\Download'
    if (-not (Test-Path $dir)) { Info 'no download cache to clear'; return }
    $before = 0
    try { $before = (Get-ChildItem $dir -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum } catch { }
    if (-not $before) { Info 'download cache is already empty'; return }

    Work 'deleting the downloaded driver packages'
    Get-ChildItem $dir -Force -EA SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force -EA SilentlyContinue
    }
    $after = 0
    try { $after = (Get-ChildItem $dir -Recurse -File -Force -EA SilentlyContinue | Measure-Object Length -Sum).Sum } catch { }
    $freed = [math]::Round((($before - $after) / 1MB), 1)
    if ($freed -gt 0) { Good "removed $freed MB of downloaded packages" }
    else { Info 'nothing could be removed, the update service still has the files open' }
    if ($after -gt 0) {
        Info ("{0} MB left behind, still in use. Windows clears it automatically within about ten days." -f [math]::Round($after/1MB,1))
    }
    Info 'The drivers themselves are untouched, so a bad one can still be rolled back.'
}

if (On 'U') {
    Sec 'Driver updates from Windows Update'

    # Name the broken devices FIRST, with severity, so the offered list
    # below can be read as "does this fix my actual problem" rather than
    # as an anonymous pile of updates.
    $broken = AsArray (Spin 'checking which devices are missing a driver' {
        param($x)
        Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.ConfigManagerErrorCode -in @(1, 10, 24, 28, 31, 43) } |
            Select-Object Name, PNPClass, ConfigManagerErrorCode, DeviceID
    } $null 90)

    if ($broken.Count) {
        $sevOf = {
            param($c, $code)
            if ("$c" -match '^Net$|^NetAdapter')                          { 'CRITICAL' }
            elseif ("$c" -match '^(SCSIAdapter|HDC|DiskDrive|Volume|System)$') { 'CRITICAL' }
            elseif ("$c" -match '^(Display|USB|HIDClass|Keyboard|Mouse)$')     { 'HIGH' }
            elseif ("$c" -match '^(Media|AudioEndpoint|Bluetooth|Image|Camera|Printer)$') { 'MEDIUM' }
            elseif ("$code" -eq '28') { 'MEDIUM' }
            else { 'LOW' }
        }
        Warn "$($broken.Count) device(s) currently have no working driver:"
        $anyCritical = $false
        foreach ($b in $broken) {
            $sev = & $sevOf $b.PNPClass $b.ConfigManagerErrorCode
            if ($sev -eq 'CRITICAL') { $anyCritical = $true }
            Info ("  [{0}] {1}" -f $sev, $b.Name)
        }
        if ($anyCritical) {
            Warn 'One of those is CRITICAL. A machine missing its network driver cannot'
            Warn 'download its own fix, so if the search below finds nothing, that is why.'
        }
    } else {
        Good 'no device is currently missing a driver'
        Info 'Anything found below is an update to a driver that already works.'
    }
    Write-Host ''

    $found = AsArray (Spin 'asking Windows Update for driver updates' {
        param($x)
        # Plain data only. COM objects are not handed back across the
        # runspace boundary; the install below makes its own session.
        try {
            $s = New-Object -ComObject Microsoft.Update.Session
            $r = $s.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Driver'")
            $o = @()
            foreach ($u in $r.Updates) {
                # The DATE matters as much as the version number. A version
                # string means nothing on its own: "1.0.0.0" could be from
                # last week or from 2009. The date tells you whether
                # Windows Update is actually offering something newer than
                # what is already installed, which is the question being
                # asked. LastDeploymentChangeTime is when Microsoft last
                # published it, and is the only date the API exposes here.
                $when = $null
                try { $when = [datetime]$u.LastDeploymentChangeTime } catch { }
                $o += [pscustomobject]@{
                    Title = [string]$u.Title
                    Size  = [int64]$u.MaxDownloadSize
                    Date  = $when
                }
            }
            $o
        } catch { $null }
    } $null 300)

    if (-not $found.Count) {
        Good 'Windows Update has no driver updates for this machine'
        Info 'That is not the same as current. Windows Update lags the vendor''s own'
        Info 'releases, so anything the report flagged still needs the vendor''s driver.'
    } else {
        Warn "$($found.Count) driver update(s) offered by Windows Update:"
        foreach ($f in ($found | Sort-Object { if ($_.Date) { $_.Date } else { [datetime]'1900-01-01' } } -Descending)) {
            $mb   = if ($f.Size -gt 0) { "  ($([math]::Round($f.Size/1MB,1)) MB)" } else { '' }
            $date = if ($f.Date) { "  published $($f.Date.ToString('yyyy-MM-dd'))" } else { '  no date given' }
            Info "  $($f.Title)$mb"
            Info "      $date"
        }
        Write-Host ''

        # DEFAULTS TO YES, and that is the fix for a real mistake.
        #
        # This was "(y/n)" tested with -match '^y', so pressing Enter meant
        # NO. Somebody who had already ticked "Install driver updates" in
        # the menu, watched it search, and read the list, then pressed the
        # one key that means "go ahead" everywhere else, and silently got
        # "Skipped. Nothing was downloaded or installed." We hit
        # exactly this on 2026-08-15 and reasonably read it as a crash.
        #
        # Consent was already given by ticking the menu item. This prompt
        # exists only so the LIST can be seen first, which is not knowable
        # until after the search. So Enter confirms, and declining takes a
        # deliberate n.
        $answer = Read-Host '    Install these driver updates now? [Y/n]'
        if ($answer -notmatch '^\s*n') {
            Write-Host ''
            # Self-sizing. The hand-typed version had a 62 character
            # border over a 64 character line and the right edge stepped
            # out mid-box.
            Show-Box @(
                'DOWNLOADING AND INSTALLING DRIVERS. DO NOT CLOSE THIS.'
                'Each driver is named below as it is installed.'
            )
            Write-Host ''
            $t0 = Get-Date
            try {
                $s = New-Object -ComObject Microsoft.Update.Session
                Work 'searching again to get the download handles (warm, so quicker)'
                # Retried: this is the step that fails when WiFi drops for
                # a moment, and a failure here reads as "no drivers
                # offered" on a machine that has nine waiting.
                $r = Invoke-WithRetry -Label 'the Windows Update search' -Work {
                    $s.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Driver'")
                }

                $coll = New-Object -ComObject Microsoft.Update.UpdateColl
                foreach ($u in $r.Updates) {
                    # EULA acceptance is per update and must happen before
                    # download, or the install silently returns "not
                    # applicable" for that item.
                    if (-not $u.EulaAccepted) { try { $u.AcceptEula() } catch { } }
                    [void]$coll.Add($u)
                }

                if (-not $coll.Count) {
                    Info 'nothing left to install, the list changed between the two searches'
                } else {
                    # A SPINNER OVER BOTH BLOCKING CALLS.
                    #
                    # Download() and Install() each take minutes, print
                    # nothing, and own COM objects that cannot be moved
                    # onto a runspace, so the work cannot be handed off
                    # the way Spin does it. The animation goes on the
                    # second thread instead. Nine drivers were watched
                    # download with a completely static screen and
                    # reasonably asked whether it was doing anything.
                    #
                    # The download ticker reads the actual cache size, so
                    # it reports MB landing on disk rather than only a
                    # clock ticking.
                    Work "downloading $($coll.Count) driver(s)"
                    $d = $s.CreateUpdateDownloader()
                    $d.Updates = $coll
                    $tick = Start-ProgressTicker "downloading $($coll.Count) driver(s)" -WatchDownloadCache
                    try   { $dr = $d.Download() }
                    finally { Stop-ProgressTicker $tick }
                    if ($dr.ResultCode -eq 2) { Good 'download complete' }
                    else { Warn "download finished with result code $($dr.ResultCode). Carrying on to install what did arrive." }

                    Work "installing $($coll.Count) driver(s)"
                    $i = $s.CreateUpdateInstaller()
                    $i.Updates = $coll
                    $tick = Start-ProgressTicker "installing $($coll.Count) driver(s), each is named below as it finishes"
                    try   { $ir = $i.Install() }
                    finally { Stop-ProgressTicker $tick }

                    # Per update, not just an overall code. "Some drivers
                    # failed" with no names is useless to whoever reads
                    # this log later.
                    for ($n = 0; $n -lt $coll.Count; $n++) {
                        $rc = $ir.GetUpdateResult($n).ResultCode
                        $t  = $coll.Item($n).Title
                        switch ($rc) {
                            2 { Good "installed: $t" }
                            3 { Warn "installed with errors: $t" }
                            4 { Fail "FAILED: $t" }
                            5 { Warn "cancelled: $t" }
                            default { Warn "result $rc for: $t" }
                        }
                    }
                    Info "driver install took $(Mins $t0)"

                    # Tidy up after ourselves, but only once something
                    # actually installed. Clearing the cache after a
                    # failed install throws away the payload you would
                    # need to retry without downloading it all again.
                    $okCount = 0
                    for ($n = 0; $n -lt $coll.Count; $n++) {
                        if ($ir.GetUpdateResult($n).ResultCode -in @(2, 3)) { $okCount++ }
                    }
                    if ($okCount -gt 0) {
                        Write-Host ''
                        Clear-UpdateDownloadCache
                    } else {
                        Info 'Nothing installed, so the downloaded packages are being kept.'
                        Info 'Retrying will not have to fetch them again.'
                    }

                    if ($ir.RebootRequired) {
                        Warn 'A REBOOT IS REQUIRED before these drivers take effect.'
                        Verdict 'drivers installed, REBOOT REQUIRED'
                    } else {
                        Verdict "$($coll.Count) driver update(s) installed"
                    }
                }
            } catch {
                Fail "Windows Update driver install failed: $($_.Exception.Message)"
                Info 'The usual causes are no internet, or the Windows Update service being'
                Info 'stopped. Option 8 above repairs Windows Update itself.'
            }
        } else {
            Info 'Skipped. Nothing was downloaded or installed.'
            Verdict 'driver updates offered but declined'
        }
    }
}

# =====================================================================
#  S. Self-test the driver installer
# =====================================================================
#  Answers "will this machine be able to install drivers" WITHOUT
#  installing one, so it can be run on a client PC you have not been
#  given permission to change yet.
#
#  It exercises every stage of the real thing and stops one call short:
#    session -> search -> licences -> DOWNLOAD -> confirm each arrived
#  and then never calls Install(). Downloading is not a change to the
#  machine's configuration, it only fills a cache that this then empties.
#
#  The honest limit, stated in the output as well as here: this cannot
#  prove the final Install() call succeeds, because the only way to test
#  installing a driver is to install a driver. What it does prove is that
#  every failure that happens BEFORE that point is not going to happen,
#  and in practice that is where driver installs die: no network, a
#  stopped update service, a proxy, or an unaccepted licence.
# =====================================================================
if (On 'S') {
    Sec 'Self-test: can this machine install drivers'
    Info 'Nothing will be installed. This stops one step short on purpose.'
    if (-not $IsAdmin) {
        Warn 'NOT an administrator, so the download stage will fail for that reason'
        Warn 'alone and tell you nothing. Start from Health-Report.bat instead.'
    }
    Write-Host ''
    $stage = 'starting'
    $t0 = Get-Date
    try {
        $stage = 'creating a Windows Update session'
        Work $stage
        $s = New-Object -ComObject Microsoft.Update.Session
        Good 'the Windows Update API is available'

        $stage = 'searching Windows Update for drivers'
        Work "$stage (this is the slow part, and the one that fails with no internet)"
        $r = $s.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Driver'")
        Good "search completed, $($r.Updates.Count) driver update(s) offered"

        if ($r.Updates.Count -eq 0) {
            Info 'Nothing offered, so the download and licence stages cannot be tested.'
            Info 'Reaching Windows Update at all is still the main thing, and that worked.'
            Verdict 'driver self-test: Windows Update reachable, nothing offered to test with'
        } else {
            $stage = 'accepting the licences'
            Work $stage
            $coll = New-Object -ComObject Microsoft.Update.UpdateColl
            $eula = 0
            foreach ($u in $r.Updates) {
                if (-not $u.EulaAccepted) { try { $u.AcceptEula(); $eula++ } catch { } }
                [void]$coll.Add($u)
            }
            Good "licences in order ($eula accepted now, the rest already were)"

            $stage = 'downloading the packages'
            Work "$stage, which is the real network test"
            $d = $s.CreateUpdateDownloader()
            $d.Updates = $coll
            $dr = $d.Download()
            if ($dr.ResultCode -eq 2) { Good 'download completed' }
            else { Warn "downloader returned result code $($dr.ResultCode)" }

            $stage = 'confirming each package actually arrived'
            Work $stage
            $got = 0; $missing = @()
            foreach ($u in $coll) {
                if ($u.IsDownloaded) { $got++ } else { $missing += $u.Title }
            }
            # $downloadOk gates the verdict below. The first version of
            # this self-test printed "PASSED" while zero of nine packages
            # had downloaded, because the verdict only looked at the
            # reboot flag. A self-test that reports success on a failed
            # run is worse than no self-test: it is a false all-clear.
            $downloadOk = ($got -eq $coll.Count)
            if ($downloadOk) { Good "all $got package(s) are on disk and ready to install" }
            else {
                Fail "only $got of $($coll.Count) package(s) downloaded"
                foreach ($m in ($missing | Select-Object -First 5)) { Info "  did not arrive: $m" }
                if (-not $IsAdmin) {
                    Warn 'THIS IS ALMOST CERTAINLY THE CAUSE: not running as administrator.'
                    Info 'Windows Update will not download on behalf of a standard user. Start'
                    Info 'from Health-Report.bat, which elevates, and run this again.'
                } else {
                    Info 'Running as administrator, so this is a real download failure: no'
                    Info 'internet, a proxy, or a damaged Windows Update. Option 8 repairs it.'
                }
            }

            $stage = 'checking the installer is ready'
            Work $stage
            $i = $s.CreateUpdateInstaller()
            $i.Updates = $coll
            if ($i.IsBusy) { Warn 'the installer is busy: another update is running right now' }
            else { Good 'the installer is free and accepted the package list' }
            $rebootBlocked = $i.RebootRequiredBeforeInstallation
            if ($rebootBlocked) {
                Warn 'THIS MACHINE MUST REBOOT BEFORE ANY DRIVER CAN INSTALL.'
                Warn 'A real install would fail right now. Restart first.'
            } else {
                Good 'no reboot is blocking an install'
            }

            # One verdict, computed from every stage rather than from the
            # last one that happened to run.
            Write-Host ''
            if ($downloadOk -and -not $rebootBlocked) {
                Good "SELF-TEST PASSED in $(Mins $t0). Every stage before the install itself works."
                Info 'Windows Update is reachable, licences accepted, packages download intact.'
                Info 'It cannot prove the install call itself, only every stage before it.'
                Verdict 'driver self-test: passed, this machine can install drivers'
            } elseif (-not $downloadOk) {
                Fail "SELF-TEST FAILED in $(Mins $t0): the packages would not download."
                Info 'A real driver install would fail at the same point. Fix this first.'
                Verdict 'driver self-test: FAILED, packages would not download'
            } else {
                Fail "SELF-TEST BLOCKED in $(Mins $t0): this machine must reboot first."
                Info 'The download worked, so once it has restarted an install should succeed.'
                Verdict 'driver self-test: BLOCKED, reboot required before installing'
            }

            Write-Host ''
            Info 'Clearing the cache this test filled, so it leaves nothing behind.'
            Clear-UpdateDownloadCache
        }
    } catch {
        Fail "self-test failed while $stage"
        Info $_.Exception.Message
        Info 'The usual causes are no internet, a proxy, or the Windows Update service'
        Info 'being stopped or damaged. Option 8 repairs Windows Update itself.'
        Verdict "driver self-test: FAILED while $stage"
    }
}

# =====================================================================
#  7. Component store cleanup
# =====================================================================
if (On '7') {
    Sec 'Reclaiming space from old updates'
    $before = (Get-PSDrive C).Free
    Work 'DISM StartComponentCleanup'
    Info 'Nothing can install while this runs. It holds the servicing lock.'
    $t0 = Get-Date
    $wd = Start-DismWatchdog
    # BARE.
    & dism.exe /Online /Cleanup-Image /StartComponentCleanup
    Stop-StallWatch $wd
    Write-Host ''
    Info "took $(Mins $t0)"
    $freed = [math]::Round(((Get-PSDrive C).Free - $before) / 1GB, 2)
    if ($freed -gt 0) { Good "reclaimed $freed GB on C:"; Verdict "reclaimed $freed GB" }
    else { Info 'nothing to reclaim, the store was already tidy' }
}

# =====================================================================
#  8. Windows Update repair
# =====================================================================
if (On '8') {
    Sec 'Repairing Windows Update'
    Work 'stopping the update services'
    foreach ($s in 'wuauserv', 'bits', 'cryptsvc', 'msiserver') { Stop-Service $s -Force -EA SilentlyContinue }
    Start-Sleep -Seconds 2

    # Renamed, not deleted. Windows rebuilds it, and if this makes
    # things worse the old one is still sitting there to put back.
    $sd = Join-Path $env:WINDIR 'SoftwareDistribution'
    $bak = "$sd.old-$(Get-Date -f 'yyyyMMdd-HHmm')"
    try {
        if (Test-Path $sd) { Rename-Item $sd $bak -EA Stop; Good "download cache set aside as $(Split-Path $bak -Leaf)" }
    } catch { Warn "could not move the download cache: $($_.Exception.Message)"; Info 'A reboot then a re-run usually clears whatever is holding it.' }

    $cr = Join-Path $env:WINDIR 'System32\catroot2'
    try {
        if (Test-Path $cr) { Rename-Item $cr "$cr.old-$(Get-Date -f 'yyyyMMdd-HHmm')" -EA Stop; Good 'catroot2 set aside' }
    } catch { Info 'catroot2 is in use, left alone. Usually harmless.' }

    Work 'starting the services again'
    foreach ($s in 'cryptsvc', 'bits', 'wuauserv', 'msiserver') { Start-Service $s -EA SilentlyContinue }
    $up = Get-Service wuauserv -EA SilentlyContinue
    if ($up.Status -eq 'Running') { Good 'Windows Update service is running again' } else { Fail 'Windows Update service did not restart' }
    Info "The old cache is kept at $bak. Delete it once updates work."
    Verdict 'Windows Update components reset'
    Info 'Now open Settings > Windows Update and check for updates. The first check will be slow, because it is rebuilding what was cleared.'
}

# =====================================================================
#  9. Network stack reset
# =====================================================================
if (On '9') {
    Sec 'Resetting the network stack'

    # RECORD IT BEFORE DESTROYING IT.
    #
    # This reset wipes static IP addresses, manual DNS servers and proxy
    # settings. The first version said so and then deleted them without
    # writing down what they were, which means a machine with a static
    # address could not be put back. A destructive step must capture its
    # own before-state, in the log, where someone can read it later.
    Work 'recording the current network settings before they are cleared'
    LogOnly ''
    LogOnly '  NETWORK SETTINGS AS THEY WERE BEFORE THIS RESET'
    LogOnly '  (write these down if anything here was set by hand)'
    # 25s was not enough and this timed out on a real run, printing an
    # empty adapter into the record of what the network looked like
    # BEFORE the reset, which is the one thing that log exists to keep.
    $upAdapters = AsArray (Spin 'listing the active network adapters' {
        param($x)
        Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
    } $null 60)
    foreach ($n in $upAdapters) {
        LogOnly "    adapter: $($n.Name)  [$($n.InterfaceDescription)]"
        foreach ($ip in (Get-NetIPAddress -InterfaceIndex $n.InterfaceIndex -AddressFamily IPv4 -EA SilentlyContinue)) {
            LogOnly ("      IPv4        : {0}/{1}   assigned by {2}" -f $ip.IPAddress, $ip.PrefixLength, $ip.PrefixOrigin)
        }
        $gw = Get-NetRoute -InterfaceIndex $n.InterfaceIndex -DestinationPrefix '0.0.0.0/0' -EA SilentlyContinue
        if ($gw) { LogOnly "      gateway     : $(($gw | ForEach-Object { $_.NextHop }) -join ', ')" }
        $dns = Get-DnsClientServerAddress -InterfaceIndex $n.InterfaceIndex -AddressFamily IPv4 -EA SilentlyContinue
        if ($dns -and $dns.ServerAddresses.Count) { LogOnly "      DNS         : $($dns.ServerAddresses -join ', ')" }
        $dhcp = (Get-NetIPInterface -InterfaceIndex $n.InterfaceIndex -AddressFamily IPv4 -EA SilentlyContinue).Dhcp
        LogOnly "      DHCP        : $dhcp"
    }
    # The proxy is per-user and survives nothing here either.
    $px = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -EA SilentlyContinue
    if ($px) {
        LogOnly "    proxy enabled : $($px.ProxyEnable)"
        if ($px.ProxyServer)   { LogOnly "    proxy server  : $($px.ProxyServer)" }
        if ($px.AutoConfigURL) { LogOnly "    proxy PAC url : $($px.AutoConfigURL)" }
    }
    LogOnly ''
    Info 'Recorded in the saved log, so anything set by hand can be put back.'

    Work 'netsh winsock reset'
    & netsh.exe winsock reset
    Work 'netsh int ip reset'
    & netsh.exe int ip reset
    Warn 'A REBOOT IS REQUIRED before this takes effect.'
    Info 'Any static IP, custom DNS or proxy settings have been cleared.'
    Info 'What they were is written into the saved log above, under'
    Info '"NETWORK SETTINGS AS THEY WERE BEFORE THIS RESET".'
    Verdict 'network stack reset, REBOOT REQUIRED'
}

# =====================================================================
#  0. Memory test
# =====================================================================
if (On '0') {
    Sec 'Memory test'
    Info 'Windows cannot test memory while it is using it, so the test'
    Info 'runs before Windows loads, at the next restart.'
    Work 'opening Windows Memory Diagnostic'
    Start-Process 'mdsched.exe' -EA SilentlyContinue
    Info 'Choose "Restart now" or "Check next time I start". The test takes'
    Info '15 to 60 minutes and the result appears in the event log afterwards.'
    Verdict 'memory test scheduled'
}

# =====================================================================
#  THE QUESTIONS THAT WAITED
# =====================================================================
# Every task has finished by this point, so answering these can no
# longer stop anything else from running.
Invoke-Deferred

# =====================================================================
#  VERDICT
# =====================================================================
$total = Mins $Started
Write-Host ''
Write-Host '   ==========================================' -ForegroundColor Cyan
Write-Host "    DONE in $total" -ForegroundColor Cyan
Write-Host '   ==========================================' -ForegroundColor Cyan
LogOnly ''
LogOnly ('=' * 60)
LogOnly ("Finished  : $(Get-Date -f 'yyyy-MM-dd HH:mm:ss')   (took $total)")
LogOnly ''
LogOnly 'WHAT THIS FOUND'
Write-Host ''
if ($verdicts.Count) {
    foreach ($v in $verdicts) { Write-Host "    - $v" -ForegroundColor White; LogOnly "  - $v" }
} else {
    Write-Host '    Nothing to report. Everything checked came back clean.' -ForegroundColor Green
    LogOnly '  Nothing to report. Everything checked came back clean.'
}
Write-Host ''

$file = Join-Path $PSScriptRoot ("repairlog-$env:COMPUTERNAME-$(Get-Date -f 'yyyy-MM-dd_HHmm').txt")
try { $Log -join "`r`n" | Set-Content $file -Encoding UTF8; Write-Host "    Saved: $file" -ForegroundColor DarkGray }
catch { Write-Host "    Could not save the log: $($_.Exception.Message)" -ForegroundColor Red }
Write-Host ''
Read-Host '    Press Enter to close'
