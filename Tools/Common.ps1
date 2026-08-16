# =====================================================================
#  SHARED BY Health-Report.ps1 AND Repair-Health.ps1
#
#  Dot-sourced by both. Do not run it on its own, it only defines things.
#
#  It exists because the spinner was written for the repair tool and the
#  report never got one, so Health-Report sat silent for 12 seconds on
#  the Windows activation query and read as frozen. Two copies of "show
#  the user something is happening" would drift the same way two copies
#  of "is it installed" already did.
# =====================================================================

# Animation needs a real console. Redirected to a file or a pipe, \r
# writes one enormous unreadable line instead, so it degrades to a
# single plain line.
$Script:CanAnimate = -not [Console]::IsOutputRedirected

# ---------------------------------------------------------------------
#  QUICK EDIT
#
#  The freeze that none of the protection above could catch.
#
#  Windows consoles ship with QuickEdit mode ON. A single click in the
#  window starts a text selection, and while a selection is active the
#  console host BLOCKS every write the owning process makes. The script
#  is not slow, not crashed and not waiting for input: it is stopped
#  dead inside Write-Host until someone presses Enter or Escape.
#
#  Nothing else in this file can save you from it. Spin's timeout needs
#  to print "gave up after Ns" and that print blocks too, so the
#  watchdog is gagged by the same thing it is supposed to report. The
#  spinner freezes mid-frame, which looks exactly like the hang the
#  spinner was added to disprove.
#
#  Seen 2026-08-15: Health-Report sat at zero CPU with
#  the window title reading "Select Administrator: Health and Handover
#  Report". That "Select " prefix is the console host announcing the
#  selection, and it is the tell. Confirmed by the fix that works from
#  the keyboard: click the window, press Enter, it carries on as if
#  nothing happened.
#
#  This matters more here than in most tools, because these run on
#  other people's machines while the owner watches over your shoulder,
#  and a person watching a slow repair WILL click the window. Then they
#  are told the repair tool crashed their PC.
#
#  Per Microsoft's SetConsoleMode documentation: "To disable this mode,
#  use ENABLE_EXTENDED_FLAGS without this flag." Clearing the QuickEdit
#  bit alone is silently ignored, so the extended-flags bit is load
#  bearing rather than decoration.
#
#  Selecting text is still possible on purpose through the window menu
#  (Alt+Space, Edit, Mark). Losing click-to-select costs nothing here:
#  both tools write the whole run to a .txt file next to themselves,
#  which is what you actually send to anyone.
# ---------------------------------------------------------------------
function Disable-ConsoleQuickEdit {
    # Returns $true if QuickEdit is off when this returns, $false if it
    # could not be turned off, $null if there is no console to fix.
    if ([Console]::IsInputRedirected) { return $null }

    try {
        if (-not ('HealthKit.ConMode' -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace HealthKit {
    public static class ConMode {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    }
}
'@
        }

        $STD_INPUT      = -10
        $QUICK_EDIT     = 0x0040
        $EXTENDED_FLAGS = 0x0080

        $h = [HealthKit.ConMode]::GetStdHandle($STD_INPUT)
        if ($h -eq [IntPtr]::Zero -or $h -eq [IntPtr](-1)) { return $null }

        $mode = 0
        if (-not [HealthKit.ConMode]::GetConsoleMode($h, [ref]$mode)) { return $null }
        if (-not ($mode -band $QUICK_EDIT)) { return $true }   # already off

        $new = ($mode -band (-bnot $QUICK_EDIT)) -bor $EXTENDED_FLAGS
        if (-not [HealthKit.ConMode]::SetConsoleMode($h, $new)) { return $false }

        # Trust the console, not the return code. A successful call that
        # did not change anything is the exact failure this guards.
        $check = 0
        if ([HealthKit.ConMode]::GetConsoleMode($h, [ref]$check)) {
            return (-not ($check -band $QUICK_EDIT))
        }
        return $true
    } catch {
        return $false
    }
}

# Run it before anything is printed, so the window cannot be frozen by a
# click during the run. If it could not be done, say so plainly and tell
# the user the keystroke that unsticks it, rather than leaving them to
# discover a dead window with no explanation.
$Script:QuickEditOff = Disable-ConsoleQuickEdit
if ($Script:QuickEditOff -eq $false) {
    Write-Host '    !!   Could not disable click-to-select on this console.' -ForegroundColor Yellow
    Write-Host '         If the display stops moving, click the window and press' -ForegroundColor DarkGray
    Write-Host '         Enter. It is a selection freeze, not a crash.' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------
#  HOW IT LOOKS
#
#  Launched as a .ps1, these run in the Windows PowerShell host, which
#  still defaults to the 1990s navy blue background. It reads as an
#  unfinished script somebody knocked together, which is a problem when
#  the person watching is a client deciding whether to trust the machine
#  you just worked on. The content was never the issue; the frame was.
#
#  Black background, light grey text, and a title that says what is
#  running. The cyan headings and green/yellow/red verdicts already used
#  throughout were chosen against a dark background and are unchanged.
#
#  Every step is guarded. A host with no RawUI (ISE, a remoting session,
#  anything redirected) throws on these, and looking slightly wrong is
#  never worth refusing to run.
# ---------------------------------------------------------------------
function Set-ConsoleLook([string]$Title) {
    if (-not $Script:CanAnimate) { return }
    try {
        $host.UI.RawUI.BackgroundColor = 'Black'
        $host.UI.RawUI.ForegroundColor = 'Gray'
        if ($Title) { $host.UI.RawUI.WindowTitle = $Title }

        # Widen a narrow window if we can. Several lines here are laid out
        # at 78 columns and wrap into mush in an 80 column window once the
        # scrollbar takes a column. Buffer must never be narrower than the
        # window, so the buffer goes first.
        $w = $host.UI.RawUI.WindowSize
        $b = $host.UI.RawUI.BufferSize
        $max = $host.UI.RawUI.MaxPhysicalWindowSize
        $want = 100
        if ($w.Width -lt $want) {
            $target = [Math]::Min($want, $max.Width)
            if ($target -gt $w.Width) {
                $b.Width = [Math]::Max($target, $b.Width)
                $host.UI.RawUI.BufferSize = $b
                $w.Width = $target
                $host.UI.RawUI.WindowSize = $w
            }
        }
        # Height too. The repair picker draws a fixed frame of options
        # plus a detail pane, and the taller the window the more of the
        # list is visible at once without scrolling its viewport. 40 rows
        # shows the whole list as it stands today.
        $wantH = 40
        if ($w.Height -lt $wantH) {
            $targetH = [Math]::Min($wantH, $max.Height)
            if ($targetH -gt $w.Height) {
                $b = $host.UI.RawUI.BufferSize
                if ($b.Height -lt $targetH) { $b.Height = $targetH; $host.UI.RawUI.BufferSize = $b }
                $w.Height = $targetH
                $host.UI.RawUI.WindowSize = $w
            }
        }

        # SCROLLBACK. The buffer is what you scroll through; the window is
        # only how much of it you can see at once. If the buffer height is
        # left equal to the window height there is no scrollback at all,
        # and the top of a 600 line report is simply gone by the time it
        # finishes. Ask for a deep buffer explicitly rather than hoping the
        # host defaulted to one.
        #
        # Set AFTER the window sizing above, because a buffer may never be
        # smaller than the window and the order of those two assignments is
        # what throws "cannot be less than the window size".
        $wantScroll = 9999
        $b = $host.UI.RawUI.BufferSize
        if ($b.Height -lt $wantScroll) {
            try { $b.Height = $wantScroll; $host.UI.RawUI.BufferSize = $b } catch { }
        }
        # Repaint, or the new background only applies to text written from
        # here on and the window stays half blue.
        Clear-Host
    } catch { }
}

Set-ConsoleLook 'Health Report and Repair'

# ---------------------------------------------------------------------
#  VIRTUAL TERMINAL
#
#  Turns on ANSI escape handling so a full screen of coloured text can be
#  written in ONE call instead of one Write-Host per line.
#
#  That distinction is the whole reason this exists. Write-Host per line
#  is flushed and rendered per line, so a redrawing menu is visibly
#  painted from the top down: the detail pane blanks, the coloured rows
#  appear at the bottom, then everything settles. It reads as the menu
#  glitching every time you press an arrow key. One write is one repaint,
#  and the frame simply changes.
#
#  Windows Terminal handles ANSI natively. The classic console host
#  supports it from Windows 10 1511 but does NOT enable it by default
#  under Windows PowerShell 5.1, hence setting it here rather than
#  assuming. Anything that cannot do it falls back to per-line drawing,
#  which looks worse but works.
# ---------------------------------------------------------------------
function Enable-ConsoleVirtualTerminal {
    if ([Console]::IsOutputRedirected) { return $false }
    try {
        if (-not ('HealthKit.ConMode' -as [type])) { return $false }
        $STD_OUTPUT = -11
        $ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
        $h = [HealthKit.ConMode]::GetStdHandle($STD_OUTPUT)
        if ($h -eq [IntPtr]::Zero -or $h -eq [IntPtr](-1)) { return $false }
        $mode = 0
        if (-not [HealthKit.ConMode]::GetConsoleMode($h, [ref]$mode)) { return $false }
        if ($mode -band $ENABLE_VIRTUAL_TERMINAL_PROCESSING) { return $true }
        if (-not [HealthKit.ConMode]::SetConsoleMode($h, ($mode -bor $ENABLE_VIRTUAL_TERMINAL_PROCESSING))) { return $false }
        # Read it back. A SetConsoleMode that returns success without
        # changing anything is the same trap the QuickEdit guard hit.
        $check = 0
        if ([HealthKit.ConMode]::GetConsoleMode($h, [ref]$check)) {
            return [bool]($check -band $ENABLE_VIRTUAL_TERMINAL_PROCESSING)
        }
        return $true
    } catch { return $false }
}

$Script:VtEnabled = Enable-ConsoleVirtualTerminal

# Console colour name to ANSI foreground code, so a frame built as text
# can carry per-line colour and still go out as a single write.
$Script:Ansi = @{
    'Black'='30';'DarkRed'='31';'DarkGreen'='32';'DarkYellow'='33';'DarkBlue'='34'
    'DarkMagenta'='35';'DarkCyan'='36';'Gray'='37';'DarkGray'='90';'Red'='91'
    'Green'='92';'Yellow'='93';'Blue'='94';'Magenta'='95';'Cyan'='96';'White'='97'
}
function Get-AnsiLine($text, $colour) {
    $c = $Script:Ansi[$colour]
    if (-not $c) { $c = '37' }
    return "$([char]27)[${c}m$text$([char]27)[0m"
}

# ---------------------------------------------------------------------
#  DEFERRED QUESTIONS
#
#  Shared by every tool here, because the same fault keeps coming back:
#  a Read-Host in the middle of a script prints its prompt underneath a
#  wall of output, waits, and is indistinguishable from a freeze. Three
#  separate tools have now been reported as "frozen" for exactly that
#  reason, and in every case they were simply waiting for a keystroke.
#
#  Rule: a script may ask a question BEFORE it starts working, or AFTER
#  it has finished. Never in between. Anything discovered mid-run is
#  queued here with the action it would take, and the queue is played
#  back at the end by Invoke-Deferred.
# ---------------------------------------------------------------------
$Script:Deferred = New-Object System.Collections.ArrayList

function Defer($Question, [scriptblock]$Action, $Detail = $null) {
    [void]$Script:Deferred.Add([pscustomobject]@{ Q = $Question; Do = $Action; Detail = $Detail })
    Write-Host '         noted, you will be asked at the end so this can finish first' -ForegroundColor DarkGray
    if ($null -ne $Script:SpinLog) { [void]$Script:SpinLog.Add("  (deferred) $Question") }
}

function Invoke-Deferred {
    if (-not $Script:Deferred.Count) { return }
    # Unattended there is nobody to answer, and the safe reading of an
    # unanswered question is always no. Say what went unasked rather than
    # silently dropping it, or the report claims a clean run when things
    # were skipped.
    if ($Script:Unattended) {
        Write-Host ''
        Write-Host "  $($Script:Deferred.Count) thing(s) needed an answer and were SKIPPED (unattended)" -ForegroundColor Yellow
        foreach ($d in $Script:Deferred) {
            Write-Host "         not asked: $($d.Q)" -ForegroundColor DarkGray
            if ($null -ne $Script:SpinLog) { [void]$Script:SpinLog.Add("  NOT ASKED (unattended): $($d.Q)") }
        }
        return
    }
    Write-Host ''
    Write-Host "  $($Script:Deferred.Count) thing(s) need your answer" -ForegroundColor Cyan
    Write-Host "  $('-' * 32)" -ForegroundColor DarkCyan
    Write-Host '         Nothing below has happened yet.' -ForegroundColor DarkGray
    foreach ($d in $Script:Deferred) {
        Write-Host ''
        if ($d.Detail) { Write-Host "         $($d.Detail)" -ForegroundColor DarkGray }
        if ($null -ne $Script:SpinLog) { [void]$Script:SpinLog.Add("  ASKED: $($d.Q)") }
        if ((Read-Host "    $($d.Q) (y/n)") -match '^y') {
            if ($null -ne $Script:SpinLog) { [void]$Script:SpinLog.Add('  answered yes') }
            try { & $d.Do } catch { Write-Host "    !!   that failed: $($_.Exception.Message)" -ForegroundColor Yellow }
        } else {
            if ($null -ne $Script:SpinLog) { [void]$Script:SpinLog.Add('  answered no') }
            Write-Host '         Skipped.' -ForegroundColor DarkGray
        }
    }
}

# A tick is only safe if this console can encode it. A fresh Windows
# console is often on codepage 850 or 437 where U+2713 does not exist
# and prints as "?" or a box. Round-trip each candidate through the live
# encoding and take the best that survives. Checked: 65001 gives the
# check mark, 437 gives U+221A, 850 and 1252 fall back to ASCII.
# ---------------------------------------------------------------------
#  STORAGE ENUMS
#
#  Get-PhysicalDisk returns HealthStatus and MediaType as friendly
#  STRINGS on some machines and as raw UInt16 ENUM NUMBERS on others.
#  The difference showed up when the call was moved onto a runspace:
#  the type adapter that prints "Healthy" is not always loaded in there,
#  so the raw 0 comes through instead.
#
#  A comparison of `-ne 'Healthy'` against the number 0 is true, so a
#  perfectly healthy 1 TB SSD was reported as "FAILING, replace it" on
#  a client's laptop. Per Microsoft's MSFT_PhysicalDisk documentation,
#  0 IS Healthy. Both forms are normalised here, once, for both tools.
# ---------------------------------------------------------------------
function Get-DiskHealthText($v) {
    if ($null -eq $v) { return 'unknown' }
    switch ("$v") {
        '0' { 'Healthy' }; '1' { 'Warning' }; '2' { 'Unhealthy' }; '5' { 'Unknown' }
        default { "$v" }
    }
}
function Test-DiskHealthy($v) {
    $t = Get-DiskHealthText $v
    # Unknown is not a failure. Plenty of USB sticks and RAID
    # controllers never report a health state at all, and calling that
    # "failing" is how a check gets ignored.
    return ($t -eq 'Healthy' -or $t -eq 'Unknown' -or $t -eq 'unknown')
}
function Get-MediaTypeText($v) {
    if ($null -eq $v) { return 'unknown' }
    switch ("$v") {
        '0' { 'Unspecified' }; '3' { 'HDD' }; '4' { 'SSD' }; '5' { 'SCM' }
        default { "$v" }
    }
}

# WHERE THE REPORT GOES.
#
# Next to the tool first, because on a USB stick that means every machine
# you touch collects in one folder, which is the whole point of carrying
# it. That is also "where it is installed" when somebody has copied this
# onto a PC.
#
# But that location is not always writable. Run from Program Files, from
# a read-only stick, or from a network share, and Set-Content throws. The
# old code caught that and printed "could not save", and the entire
# report was then LOST: minutes of checks on somebody's machine, gone,
# with the console about to close.
#
# So it falls back, in order of how findable the file is afterwards, and
# always says exactly where the file went. A report saved somewhere
# unexpected is recoverable; a report not saved at all is not.
function Get-ReportPath {
    # -PrimaryDir rather than reading $PSScriptRoot inside: a function
    # that reaches for an automatic variable cannot be tested, because
    # $PSScriptRoot is whatever the CALLER's file is. The first test of
    # this reported a failure that was purely an artefact of that.
    param(
        [string]$Leaf,
        [string]$PrimaryDir = $PSScriptRoot
    )
    $candidates = @(
        $PrimaryDir                                                      # beside the tool
        (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Lazarus Reports')
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Lazarus Reports')
        $env:TEMP                                                        # last resort
    )
    foreach ($dir in $candidates) {
        if (-not $dir) { continue }
        try {
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
            # Prove it is writable rather than assuming. A folder can
            # exist and still refuse a write.
            $probe = Join-Path $dir ('.w' + [guid]::NewGuid().ToString('N').Substring(0, 6))
            [System.IO.File]::WriteAllText($probe, 'x')
            [System.IO.File]::Delete($probe)
            return (Join-Path $dir $Leaf)
        } catch { continue }
    }
    return $null
}

# ---------------------------------------------------------------------
#  MARKDOWN REPORT
#
#  The .txt stays the record of the run and is what the tools read back.
#  This is the readable copy: the same content with structure a person
#  or a language model can follow, rather than fixed-width padding.
#
#  Markdown rather than HTML, chosen deliberately. It opens in anything,
#  it diffs, it pastes into an email or a ticket, and it can be handed
#  straight to an AI to summarise, which is the main reason. HTML looked
#  smarter and was worse at all four.
#
#  Structure is recovered from the text report rather than collected
#  separately, so the two can never disagree about what was found.
# ---------------------------------------------------------------------
function Write-MarkdownReport {
    param(
        [string[]]$Lines,
        [string]$Path,
        [string]$Verdict = '',
        [int]$WarnCount = 0,
        [int]$BadCount  = 0
    )

    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine("# Health Report and Repair: $env:COMPUTERNAME")
    [void]$md.AppendLine()
    [void]$md.AppendLine("**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')  ")
    [void]$md.AppendLine("**Verdict:** $Verdict  ")
    [void]$md.AppendLine("**Faults:** $BadCount  |  **To note:** $WarnCount  ")
    [void]$md.AppendLine()
    [void]$md.AppendLine('Every check that produced this was read-only.')
    [void]$md.AppendLine()

    # Tracks whether a Markdown table is open, so anything that is not a
    # row closes it first. A stray paragraph inside a table swallows the
    # rows above it when rendered.
    $inTable = $false

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $raw = $Lines[$i]
        if ($null -eq $raw) { continue }
        $t = $raw.TrimEnd()

        # A heading is a line whose successor is nothing but dashes.
        if ($i + 1 -lt $Lines.Count -and $Lines[$i+1] -match '^-{3,}$' -and $t.Trim()) {
            if ($inTable) { [void]$md.AppendLine(); $inTable = $false }
            [void]$md.AppendLine()
            [void]$md.AppendLine("## $($t.Trim())")
            [void]$md.AppendLine()
            $i++
            continue
        }
        if ($t -match '^-{3,}$') { continue }
        if (-not $t.Trim()) { continue }
        # Banner and title lines. They are the document's own heading here,
        # so repeating them as body text is noise.
        if ($t -match '^(HEALTH AND HANDOVER REPORT|HEALTH REPORT AND REPAIR|Generated )') { continue }

        # Progress and timing lines are run noise, not findings. They stay
        # in the .txt, which is the full record.
        if ($t -match '^\s*(done|\.\.)\s+') { continue }

        if ($t -match '^\s*XX\s+(.*)$') {
            if ($inTable) { [void]$md.AppendLine(); $inTable = $false }
            [void]$md.AppendLine("- **FAULT:** $($matches[1].Trim())")
            continue
        }
        if ($t -match '^\s*!!\s+(.*)$') {
            if ($inTable) { [void]$md.AppendLine(); $inTable = $false }
            [void]$md.AppendLine("- **CHECK:** $($matches[1].Trim())")
            continue
        }
        if ($t -match '^\s*ok\s+(.*)$') {
            if ($inTable) { [void]$md.AppendLine(); $inTable = $false }
            [void]$md.AppendLine("- **OK:** $($matches[1].Trim())")
            continue
        }

        # "  Key                    value" becomes a table row. The text
        # report pads keys to a fixed width, so a run of 2+ spaces is a
        # reliable separator. Pipes are escaped or they break the table.
        if ($t -match '^\s{2,}(\S.*?)\s{2,}(\S.*)$') {
            $k = $matches[1].Trim() -replace '\|', '\|'
            $v = $matches[2].Trim() -replace '\|', '\|'
            if (-not $inTable) {
                [void]$md.AppendLine('| | |')
                [void]$md.AppendLine('|---|---|')
                $inTable = $true
            }
            [void]$md.AppendLine("| $k | $v |")
        } else {
            if ($inTable) { [void]$md.AppendLine(); $inTable = $false }
            [void]$md.AppendLine($t.Trim())
        }
    }

    # RUN DETAIL, at the end, instead of in a second file.
    #
    # These are the "done reading the BIOS (0s)" and "STALLED" lines.
    # They are noise while you are reading findings, which is why they are
    # stripped from the body above, but they are the only record of how
    # long each check took and which ones gave up.
    #
    # That was the entire justification for writing a separate .txt, and
    # it does not justify a second file. It justifies a section at the
    # bottom that nobody has to read.
    $detail = @()
    foreach ($raw in $Lines) {
        if ($null -eq $raw) { continue }
        $t = $raw.TrimEnd()
        if ($t -match '^\s*(done|\.\.)\s+' -or $t -cmatch 'STALL|timed out|gave up after') {
            $detail += $t.Trim()
        }
    }
    if ($detail.Count) {
        [void]$md.AppendLine()
        [void]$md.AppendLine('---')
        [void]$md.AppendLine()
        [void]$md.AppendLine('## Run detail')
        [void]$md.AppendLine()
        [void]$md.AppendLine('How long each check took, and any that gave up. Only worth reading when something looks wrong.')
        [void]$md.AppendLine()
        [void]$md.AppendLine('```')
        foreach ($d in $detail) { [void]$md.AppendLine($d) }
        [void]$md.AppendLine('```')
    }

    Set-Content -Path $Path -Value $md.ToString() -Encoding UTF8
}

# ---------------------------------------------------------------------
#  BOXES
#
#  Every box in these tools used to be three hand-typed strings, and the
#  padding was counted by eye. They drifted: the driver install box had a
#  62 character border over a 64 character line, so the right edge
#  stepped out and it looked broken.
#
#  Hand-counting is the bug. Give it the lines, it sizes itself.
# ---------------------------------------------------------------------
function Show-Box {
    param(
        [string[]]$Lines,
        [string]$Colour = 'Yellow',
        [string]$Indent = '    '
    )
    # The arithmetic, because getting it wrong by one is the entire
    # reason this function exists:
    #   border row  = '+' + inner dashes + '+'        = inner + 2
    #   content row = '|' + 2 spaces + text + '|'     = inner + 2
    # so the text must be padded to inner - 2, leaving two spaces on the
    # left and at least two on the right. Written as inner - 3 first,
    # which made every content row one short and the right edge ragged:
    # the same defect, in the function meant to end it.
    $widest = 0
    foreach ($l in $Lines) { if ($l.Length -gt $widest) { $widest = $l.Length } }
    $inner  = $widest + 4
    $rule   = $Indent + '+' + ('-' * $inner) + '+'
    Write-Host $rule -ForegroundColor $Colour
    foreach ($l in $Lines) {
        Write-Host ($Indent + '|  ' + $l.PadRight($inner - 2) + '|') -ForegroundColor $Colour
    }
    Write-Host $rule -ForegroundColor $Colour
}

# ---------------------------------------------------------------------
#  PROGRESS TICKER
#
#  For work that BLOCKS the main thread and cannot be moved onto a
#  runspace, because it owns COM objects that do not cross that boundary.
#  Windows Update's Download() and Install() are both like this: they
#  take minutes, print nothing, and leave the screen frozen on the last
#  line. Nine drivers downloaded with no sign of life on screen.
#
#  So the ANIMATION goes on the second thread instead of the work. It
#  reports through [Console] because a runspace made this way has no host
#  UI of its own, the same reason the DISM watchdog does.
#
#  -WatchDownloadCache turns the elapsed counter into real progress by
#  reading how much has actually landed in SoftwareDistribution, which is
#  the only honest measure available while Download() is blocking.
# ---------------------------------------------------------------------
function Start-ProgressTicker {
    param([string]$Label, [switch]$WatchDownloadCache)

    # Redirected to a file or a pipe, \r does not return to the start of
    # a line, so an animation writes hundreds of near-identical lines
    # instead of one that updates. Spin has always degraded this way; the
    # ticker did not, and it filled the check suite's output with spinner
    # frames. One plain line, then silence.
    #
    # [Console]::Write also bypasses PowerShell's streams entirely, so a
    # caller cannot suppress this from the outside. It has to decide for
    # itself.
    if (-not $Script:CanAnimate) {
        Write-Host "    ..   $Label" -ForegroundColor DarkGray
        return $null
    }

    $ps = [PowerShell]::Create()
    [void]$ps.AddScript({
        param($label, $watchCache)
        $frames = '|', '/', '-', '\'
        $i = 0
        $t0 = Get-Date
        $dir = Join-Path $env:WINDIR 'SoftwareDistribution\Download'
        while ($true) {
            $secs = [int]((Get-Date) - $t0).TotalSeconds
            $extra = ''
            if ($watchCache) {
                try {
                    $mb = (Get-ChildItem $dir -Recurse -File -Force -ErrorAction SilentlyContinue |
                           Measure-Object Length -Sum).Sum / 1MB
                    if ($mb -gt 0) { $extra = ('   {0:N1} MB fetched' -f $mb) }
                } catch { }
            }
            [Console]::Write(("`r    {0}    {1}  {2}s{3}          " -f $frames[$i % 4], $label, $secs, $extra))
            Start-Sleep -Milliseconds 250
            $i++
        }
    })
    [void]$ps.AddArgument($Label)
    [void]$ps.AddArgument([bool]$WatchDownloadCache)
    $h = $ps.BeginInvoke()
    return [pscustomobject]@{ PS = $ps; Handle = $h }
}

function Stop-ProgressTicker($t) {
    if (-not $t) { return }
    try { $t.PS.Stop() }    catch { }
    try { $t.PS.Dispose() } catch { }
    # Wipe the spinner line so the result prints on a clean row rather
    # than on top of a half-drawn frame.
    try { [Console]::Write("`r" + (' ' * 78) + "`r") } catch { }
}

# ---------------------------------------------------------------------
#  RETRY
#
#  For work that fails for a reason that will not still be true in ten
#  seconds: a Windows Update search on a laptop whose WiFi has just come
#  back, a service that is mid-restart. Left alone these produce a hard
#  "no driver updates offered", which is indistinguishable from a machine
#  that genuinely has none.
#
#  Deliberately narrow. It retries only when the work THREW, never when
#  it returned an empty result, because "nothing found" is a legitimate
#  answer and retrying it three times just wastes a minute confirming it.
#
#  Every attempt is announced. A tool that silently retries looks like a
#  tool that is hanging, which is the thing this whole file exists to
#  avoid.
# ---------------------------------------------------------------------
function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)][scriptblock]$Work,
        [string]$Label = 'the operation',
        [int]$Attempts = 3,
        [int]$DelaySeconds = 10
    )
    for ($n = 1; $n -le $Attempts; $n++) {
        try {
            return & $Work
        } catch {
            if ($n -eq $Attempts) {
                Write-Host "    !!   $Label failed $Attempts times, giving up: $($_.Exception.Message)" -ForegroundColor Yellow
                if ($null -ne $Script:SpinLog) { [void]$Script:SpinLog.Add("  !!   $Label failed after $Attempts attempts") }
                throw
            }
            Write-Host "    !!   $Label failed (attempt $n of $Attempts): $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "         Retrying in ${DelaySeconds}s. This is usually a network blip." -ForegroundColor DarkGray
            if ($null -ne $Script:SpinLog) { [void]$Script:SpinLog.Add("  retry $n of $Attempts for $Label") }
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Test-Glyph([char]$c) {
    try {
        $e = [Console]::OutputEncoding
        return ($e.GetString($e.GetBytes([string]$c)) -eq [string]$c)
    } catch { return $false }
}
$Script:Tick = 'x'
foreach ($cand in @([char]0x2713, [char]0x221A)) {
    if (Test-Glyph $cand) { $Script:Tick = [string]$cand; break }
}

# ---------------------------------------------------------------------
#  SPIN
#
#  Runs $Work on a second runspace in this same process, same token, and
#  animates in the foreground until it finishes. The elapsed counter
#  matters as much as the spinner: it turns "is this stuck?" into a
#  number you can watch climb.
#
#  -TimeoutSeconds stops one slow call hanging the whole tool. Measured
#  on a fast desktop, SoftwareLicensingProduct takes 12 seconds; on an
#  old refurbished laptop, which is what these tools are FOR, it can be
#  far longer, and on a sick machine it may never return at all. A check
#  that cannot answer must give up and say so rather than sit there.
#
#  If a caller defines $Script:SpinLog as a collection, the completed
#  line is appended to it.
# ---------------------------------------------------------------------
# ---------------------------------------------------------------------
#  ASARRAY
#
#  Spin returns $null when a check times out or fails. Every caller that
#  treats the result as a list wrote @(Spin ...) to force an array, and
#  that is where it goes wrong: in PowerShell @($null) is an array of ONE
#  element whose value is $null, not an empty array. So .Count is 1, the
#  "did we find anything" test passes, and the code walks into its
#  found-something branch holding nothing.
#
#  Not hypothetical. From a real repair log, 2026-08-15:
#
#      STALLED  listing the active network adapters: no response in 25s
#        adapter:   []
#          DHCP        :
#
#  The check had timed out and returned nothing. The tool then reported a
#  network adapter with no name and no settings, and wrote that into the
#  record of what the machine looked like BEFORE a network reset, which
#  is the one thing that log exists to preserve.
#
#  A timeout must read as "unknown", never as "found one, and it is
#  blank". Use this anywhere a Spin result is counted or iterated.
# ---------------------------------------------------------------------
function AsArray($v) {
    if ($null -eq $v) { return ,@() }
    return ,@($v)
}

function Spin {
    param(
        [string]$Label,
        [scriptblock]$Work,
        $Argument = $null,
        [int]$TimeoutSeconds = 0
    )

    # NO ANIMATION POSSIBLE (output redirected, or not a real console).
    #
    # This branch used to run the work synchronously and return, which
    # quietly threw away the timeout: the ONE thing this function exists
    # to guarantee. Every caller believed it was protected and was not.
    # Found 2026-08-13 by testing that a 3-second timeout actually fires;
    # it waited the full 60 seconds instead.
    #
    # A redirected console is where a hang is hardest to notice, so it is
    # the last place to drop the protection. No spinner here, but the
    # timeout is still enforced.
    if (-not $Script:CanAnimate) {
        Write-Host "    ..   $Label" -ForegroundColor DarkGray
        if ($null -ne $Script:SpinLog) { [void]$Script:SpinLog.Add("  ..   $Label") }
        if ($TimeoutSeconds -le 0) { return (& $Work $Argument) }

        $psq = [PowerShell]::Create()
        [void]$psq.AddScript($Work)
        [void]$psq.AddArgument($Argument)
        $hq = $psq.BeginInvoke()
        if ($hq.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            try { return $psq.EndInvoke($hq) }
            catch { return $null }
            finally { try { $psq.Dispose() } catch { } }
        }
        Write-Host "    !!   '$Label' gave up after ${TimeoutSeconds}s and was skipped" -ForegroundColor Yellow
        if ($null -ne $Script:SpinLog) { [void]$Script:SpinLog.Add("  !!   '$Label' timed out after ${TimeoutSeconds}s") }
        try { $psq.Stop() }    catch { }
        try { $psq.Dispose() } catch { }
        return $null
    }

    $ps = [PowerShell]::Create()
    [void]$ps.AddScript($Work)
    [void]$ps.AddArgument($Argument)
    $handle = $ps.BeginInvoke()

    $frames = '|', '/', '-', '\'
    $i = 0
    $t0 = Get-Date
    $timedOut = $false
    $result = $null

    # "Slow" is announced before "stalled", so a long wait stops looking
    # like a freeze while it is still a long wait. The threshold is half
    # the allowance, or 10 seconds when there is no limit.
    $slowAt = if ($TimeoutSeconds -gt 0) { [int]($TimeoutSeconds / 2) } else { 10 }
    $warned = $false

    try {
        while (-not $handle.IsCompleted) {
            $secs = [int]((Get-Date) - $t0).TotalSeconds
            if ($TimeoutSeconds -gt 0 -and $secs -ge $TimeoutSeconds) { $timedOut = $true; break }

            if (-not $warned -and $secs -ge $slowAt) {
                $warned = $true
                $limit = if ($TimeoutSeconds -gt 0) { "will give up at ${TimeoutSeconds}s" } else { 'no time limit on this one' }
                Write-Host ("`r{0}`r" -f (' ' * 78)) -NoNewline
                # "Still running, not frozen. The counter below is live."
                # used to print here. There is a spinner and a climbing
                # second count directly underneath it saying exactly that,
                # visibly, so the sentence was telling the reader something
                # the screen was already telling them.
                Write-Host ("    !!    '{0}' is taking longer than expected ({1})" -f $Label, $limit) -ForegroundColor Yellow
            }

            $cap = if ($TimeoutSeconds -gt 0) { " of $TimeoutSeconds" } else { '' }
            $col = if ($warned) { 'Yellow' } else { 'Cyan' }
            Write-Host ("`r    {0}    {1}  {2}s{3}   " -f $frames[$i % 4], $Label, $secs, $cap) -NoNewline -ForegroundColor $col
            Start-Sleep -Milliseconds 120
            $i++
        }
        if ($timedOut) { $ps.Stop() }
        else { $result = $ps.EndInvoke($handle) }
    } catch {
        Write-Host ''
        Write-Host "    !!   $Label failed: $($_.Exception.Message)" -ForegroundColor Yellow
        if ($null -ne $Script:SpinLog) { [void]$Script:SpinLog.Add("  !!   $Label failed: $($_.Exception.Message)") }
        return $null
    } finally {
        $ps.Dispose()
    }

    $took = [int]((Get-Date) - $t0).TotalSeconds
    if ($timedOut) {
        # Say plainly that a stall was DETECTED and that the tool is
        # carrying on. Silence here is what made every earlier version
        # look like it had crashed.
        Write-Host ("`r{0}`r" -f (' ' * 78)) -NoNewline
        Write-Host ''
        # Was hand-sized: a 60 character border over 58 character lines,
        # so the right edge never lined up. It also truncated the label at
        # 54 characters. Show-Box sizes itself to the longest line.
        Show-Box -Colour Red -Lines @(
            'STALL DETECTED'
            $Label
            "did not respond in ${took}s. Skipped, the run continues."
        )
        # ${Label}: not $Label: -- a colon straight after a variable name
        # is parsed as a scope or drive qualifier, so the braces are load
        # bearing rather than decoration.
        if ($null -ne $Script:SpinLog) { [void]$Script:SpinLog.Add("  STALLED  ${Label}: no response in $took" + 's, skipped') }
        return $null
    }
    # Overwrite the spinner line rather than leaving it above the result.
    Write-Host ("`r    done  {0}  ({1}s){2}" -f $Label, $took, (' ' * 10)) -ForegroundColor DarkGray
    if ($null -ne $Script:SpinLog) { [void]$Script:SpinLog.Add("  done  $Label  ($took" + 's)') }
    return $result
}

# =====================================================================
#  MACHINE AND BIOS WITHOUT WMI
#
#  Make, model, motherboard, BIOS vendor, BIOS version, BIOS date, CPU
#  and Windows edition are ALL in the registry, and reading them is
#  instant. Windows populates HKLM\HARDWARE\DESCRIPTION\System\BIOS from
#  SMBIOS at every boot, before anything WMI-related is running.
#
#  This exists because the first fix for a wedged WMI was to skip the
#  Machine section, and that traded a twenty second hang for losing the
#  single most useful thing in the report. "I never read the BIOS" is a
#  fair complaint about a repair tool.
#
#  So the Machine section is registry FIRST, always, on every machine
#  whether WMI is healthy or not, and WMI is only asked for the few
#  things the registry genuinely does not hold. On a healthy PC this
#  also removes four twenty-second timeouts from the critical path of
#  the very first section, which is where a slow start is most visible.
# =====================================================================
function Get-BiosFactsNoWmi {
    $f = @{}
    try {
        $b = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -ErrorAction SilentlyContinue
        if ($b) {
            # "To be filled by O.E.M." is what a custom-built desktop puts
            # in half of these. It is noise, not an answer, so it is
            # dropped here rather than printed as if it meant something.
            foreach ($k in 'SystemManufacturer','SystemProductName','SystemFamily','SystemSKU',
                           'BaseBoardManufacturer','BaseBoardProduct','BaseBoardVersion',
                           'BIOSVendor','BIOSVersion','BIOSReleaseDate') {
                $v = "$($b.$k)".Trim()
                if ($v -and $v -notmatch '^(To be filled by O\.?E\.?M\.?|System manufacturer|System Product Name|Default string|None|N/A)$') {
                    $f[$k] = $v
                }
            }
        }
        $cpu = (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction SilentlyContinue).ProcessorNameString
        if ($cpu) { $f['Cpu'] = "$cpu".Trim() }
        $w = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        if ($w) {
            # ProductName still says "Windows 10 Pro" on Windows 11, which
            # Microsoft never corrected. The build number is the honest
            # answer: 22000 and above is 11.
            $build = [int]$w.CurrentBuild
            $name  = "$($w.ProductName)".Trim()
            if ($build -ge 22000 -and $name -match 'Windows 10') { $name = $name -replace 'Windows 10', 'Windows 11' }
            $f['Windows'] = ("{0} {1} (build {2}.{3})" -f $name, $w.DisplayVersion, $w.CurrentBuild, $w.UBR).Trim()
        }
    } catch { }
    return $f
}

# The SERIAL NUMBER, which is the one thing above that is not sitting in
# a named registry value. It is in the raw SMBIOS table, which Windows
# caches under the mssmbios service, so it can be read with no WMI at
# all. Needs administrator.
#
# Structure, per the DMTF SMBIOS specification: the cached blob starts
# with an 8 byte Windows header, then a sequence of structures. Each has
# type, length, handle, a formatted area, then its strings NUL
# separated and terminated by a double NUL. Type 1 is System
# Information, and its SerialNumber is the string INDEX at offset 0x07.
#
# Every step is bounds checked and the whole thing is wrapped, because
# this is byte parsing of vendor-supplied data and some vendors ship
# malformed tables. A missing serial is a small loss; an exception here
# would take the first section of the report with it.
function Get-SerialNoWmi {
    try {
        $raw = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\services\mssmbios\Data' `
                -Name SMBiosData -ErrorAction SilentlyContinue).SMBiosData
        if (-not $raw -or $raw.Length -lt 16) { return $null }

        $i = 8                                    # skip the Windows header
        while ($i + 4 -lt $raw.Length) {
            $type = $raw[$i]
            $len  = $raw[$i + 1]
            if ($len -lt 4) { break }             # malformed, do not loop forever
            $strStart = $i + $len
            if ($strStart -ge $raw.Length) { break }

            if ($type -eq 1) {
                $idx = if ($i + 7 -lt $raw.Length) { $raw[$i + 7] } else { 0 }
                if ($idx -lt 1) { return $null }
                # Walk the NUL separated strings to the requested index.
                $p = $strStart
                for ($n = 1; $n -le $idx; $n++) {
                    $end = $p
                    while ($end -lt $raw.Length -and $raw[$end] -ne 0) { $end++ }
                    if ($n -eq $idx) {
                        $s = [System.Text.Encoding]::ASCII.GetString($raw, $p, $end - $p).Trim()
                        if (-not $s -or $s -match '^(To be filled by O\.?E\.?M\.?|Default string|None|N/A|0+)$') { return $null }
                        return $s
                    }
                    $p = $end + 1
                    if ($p -ge $raw.Length) { return $null }
                }
                return $null
            }

            # Skip past this structure's string area: scan for the double
            # NUL that terminates it.
            $p = $strStart
            while ($p + 1 -lt $raw.Length -and -not ($raw[$p] -eq 0 -and $raw[$p + 1] -eq 0)) { $p++ }
            $i = $p + 2
        }
        return $null
    } catch { return $null }
}

# =====================================================================
#  THE CHOOSER: arrow keys, Enter to toggle
# =====================================================================
#  This lived in Repair-Health.ps1 and answered one question: which
#  repairs to run. The health report now asks a question of exactly the
#  same shape before it starts: which sections to include, and whether
#  to save a file at all. Two pickers would have been two sets of the
#  frame-painting bugs below, and the second copy would have had to
#  re-learn every one of them.
#
#  So it takes a LIST rather than reaching for a global. Each item needs
#  Name, On and Desc. Repairs additionally carry Changes, Time, Low and
#  High, and -ShowTime turns those into the estimate line; the report
#  sections have none of them and simply do not pass it.
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
        # The picker scrolls its own viewport, so it only needs room for a
        # usable window plus the detail pane. Below this the numbered menu
        # is genuinely the better experience.
        if ($h.WindowSize.Height -lt 24) { return $false }
        return $true
    } catch { return $false }
}

function Show-Picker {
    # Returns $true to proceed with what is ticked, $false to cancel.
    #
    # -TestKeys feeds a scripted list of virtual key codes and skips all
    # drawing. It exists because the picker cannot run under redirected
    # input, so without it the navigation logic, which is where the real
    # bugs live (index wrapping, skipping the spacer row, START with
    # nothing ticked), would never be exercised by any test at all.
    param(
        [array]$Items,
        [string]$Title       = 'CHOOSE',
        [string]$StartLabel  = 'START',
        [string]$CancelLabel = 'Cancel, change nothing',
        [string]$Hint        = '',
        [switch]$ShowTime,
        # Allow proceeding with nothing ticked. The repair menu must not:
        # "START" with no repairs selected is always a mistake. The report
        # menu must: everything unticked plus "save a file" unticked is a
        # legitimate choice meaning "show me the machine, save nothing".
        [switch]$AllowEmpty,
        [int[]]$TestKeys
    )
    $silent = [bool]$TestKeys
    $kp = 0

    $rows = @()
    foreach ($t in $Items) { $rows += [pscustomobject]@{ Kind = 'task'; Task = $t } }
    $rows += [pscustomobject]@{ Kind = 'gap';    Task = $null }
    $rows += [pscustomobject]@{ Kind = 'start';  Task = $null }
    $rows += [pscustomobject]@{ Kind = 'cancel'; Task = $null }

    $i = 0
    $width = if ($silent) { 78 } else { [Math]::Min(78, $Host.UI.RawUI.WindowSize.Width - 2) }

    # THE HEADER IS PART OF EVERY FRAME.
    #
    # It used to print once, remember the cursor row underneath it, and
    # reposition there on each keypress to repaint in place. That is the
    # standard trick and it kept breaking: any scroll moves every absolute
    # row, the remembered row silently points at the wrong line, and the
    # redraw lands below the previous frame instead of on top of it, so
    # each keypress leaves another full copy of the list on screen.
    #
    # Two changes fixed it. The anchor is the top of the VISIBLE window,
    # re-read every frame, so nothing has to be remembered. And the frame
    # is written in ONE call rather than one Write-Host per line, so it
    # repaints as a single unit instead of visibly rebuilding itself down
    # the screen.
    #
    # Every line is PADDED to the full width. That is what makes drawing
    # over the previous frame safe without clearing first: a short line
    # would otherwise leave the tail of whatever was there before.
    $HeaderLines = 9
    $hintText = if ($Hint) { $Hint } else { '    Move to ' + $StartLabel + ' and press ENTER to begin.  Esc quits.' }
    $drawHeader = {
        Paint (''.PadRight($width))
        Paint ('   =========================================='.PadRight($width)) 'Cyan'
        Paint ("    $Title".PadRight($width)) 'Cyan'
        Paint ("    $env:COMPUTERNAME".PadRight($width)) 'DarkGray'
        Paint ('   =========================================='.PadRight($width)) 'Cyan'
        Paint (''.PadRight($width))
        Paint ('    Up and Down to move.  ENTER switches an option on or off.'.PadRight($width)) 'DarkGray'
        Paint ($hintText.PadRight($width)) 'DarkGray'
        Paint (''.PadRight($width))
    }

    # Clear ONCE, here, so the first frame starts on a clean screen and
    # there is nothing left below it. Never again inside the loop: that
    # clear is what made the list flash and appear to jump on every
    # keypress, because for one frame the screen was genuinely empty.
    if (-not $silent) { Clear-Host }

    while ($true) {
      $Script:LastRender = New-Object System.Collections.ArrayList
      $paint = -not $silent
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

      if ($paint) { & $drawHeader }

        # VIEWPORT.
        #
        # Two rules make a stacked-duplicates redraw impossible rather
        # than unlikely:
        #   1. Show a WINDOW of rows, never all of them, sized from the
        #      real window height.
        #   2. Draw EXACTLY the same number of lines every frame, padding
        #      with blanks, so the frame height is constant and nothing
        #      can ever scroll.
        $vFirst = 0
        $vCount = $rows.Count
        if ($paint) {
            $detailLines = 10                      # blank, rule, 6 detail, rule, summary
            $chrome      = 2                       # the "more above/below" markers
            $avail = $Host.UI.RawUI.WindowSize.Height - $HeaderLines - $detailLines - $chrome - 2
            $vCount = [Math]::Max(5, [Math]::Min($rows.Count, $avail))
            if ($vCount -lt $rows.Count) {
                $vFirst = $i - [int]($vCount / 2)
                if ($vFirst -lt 0) { $vFirst = 0 }
                if ($vFirst + $vCount -gt $rows.Count) { $vFirst = $rows.Count - $vCount }
            }
        }
        $vEnd = $vFirst + $vCount - 1

        if ($vFirst -gt 0) { Paint ("      ^ $vFirst more above".PadRight($width)) 'DarkCyan' }
        else               { Paint (' ' * $width) }

        # if/elseif, NOT switch. In PowerShell a switch IS a loop, so a
        # `continue` in a case exits the switch and carries straight on
        # into the code below it. That made every START, Cancel and
        # spacer row draw a second, empty "[ ]" line underneath itself.
        for ($r = $vFirst; $r -le $vEnd -and $r -lt $rows.Count; $r++) {
            $sel  = ($r -eq $i)
            $cur  = if ($sel) { '  >>> ' } else { '      ' }
            $kind = $rows[$r].Kind

            if ($kind -eq 'gap') {
                Emit (' ' * $width)
            }
            elseif ($kind -eq 'start') {
                $txt = "$cur" + $StartLabel
                if ($sel) { Emit $txt.PadRight($width) 'Green' }
                else      { Emit $txt.PadRight($width) 'DarkGreen' }
            }
            elseif ($kind -eq 'cancel') {
                $txt = "$cur" + $CancelLabel
                if ($sel) { Emit $txt.PadRight($width) 'White' }
                else      { Emit $txt.PadRight($width) 'DarkGray' }
            }
            else {
                $t    = $rows[$r].Task
                $box  = if ($t.On) { "[$Script:Tick]" } else { '[ ]' }
                $tag  = if ($t.Changes) { '  CHANGES' } else { '' }
                $txt  = "$cur$box $($t.Name)$tag"
                if ($txt.Length -gt $width) { $txt = $txt.Substring(0, $width) }
                # The row you are on is bright white. On or off is carried
                # by the tick and by green versus grey, so the highlight
                # only ever answers "where am I", never "is this on".
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

        if ($paint) {
            Paint (' ' * $width)
            Paint (('    ' + ('-' * ($width - 6))).PadRight($width)) 'DarkGray'
            $detail = @()
            if ($rows[$i].Kind -eq 'task') {
                $t = $rows[$i].Task
                if ($ShowTime) {
                    $detail += "takes $($t.Time)" + $(if ($t.Changes) { '   CHANGES THIS PC' } else { '   read only' })
                    $detail += ''
                }
                $detail += (Wrap $t.Desc ($width - 8))
            } elseif ($rows[$i].Kind -eq 'start') {
                $detail += $(if ($ShowTime) { 'Begin. Anything marked CHANGES offers a restore point first.' }
                             else           { 'Begin with the options ticked above.' })
            } elseif ($rows[$i].Kind -eq 'cancel') {
                $detail += 'Close without touching this computer.'
            }
            for ($d = 0; $d -lt 6; $d++) {
                $line = if ($d -lt $detail.Count) { '      ' + $detail[$d] } else { '' }
                if ($line.Length -gt $width) { $line = $line.Substring(0, $width) }
                Paint $line.PadRight($width) $(if ($d -eq 0) { 'White' } else { 'DarkGray' })
            }
            Paint (('    ' + ('-' * ($width - 6))).PadRight($width)) 'DarkGray'

            $selNow = @($Items | Where-Object On)
            if ($ShowTime) {
                $lo = ($selNow | Measure-Object Low  -Sum).Sum
                $hi = ($selNow | Measure-Object High -Sum).Sum
                $est = if (-not $selNow.Count) { 'nothing selected' }
                       elseif ($hi -le 1)      { 'under a minute' }
                       elseif ($lo -eq 0)      { "up to about $hi minutes" }
                       else                    { "roughly $lo to $hi minutes" }
                $ch = @($selNow | Where-Object Changes).Count
                $sum = "    $($selNow.Count) selected, $est." + $(if ($ch) { "  $ch change this computer." } else { '' })
                Paint $sum.PadRight($width) $(if ($ch) { 'Yellow' } else { 'White' })
            } else {
                $sum = "    $($selNow.Count) of $($Items.Count) included."
                Paint $sum.PadRight($width) 'White'
            }
        }

      # ---- ONE PAINT --------------------------------------------------
      # The whole frame goes out in a single write. Per-line Write-Host is
      # flushed and rendered per line, so on every keypress the menu
      # visibly rebuilt itself from the top down. That IS the glitch, and
      # no amount of cursor arithmetic fixes it, because the painting
      # itself is what you are watching.
      #
      # NO trailing newline after the final line. Writing one while on the
      # bottom row scrolls the viewport.
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

      $anyOn = @($Items | Where-Object On).Count
      if ($silent) {
          if ($kp -ge $TestKeys.Count) { return $false }
          $code = $TestKeys[$kp]; $kp++
      } else {
          $code = ($Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')).VirtualKeyCode
      }
        switch ($code) {
            38 { $i--; if ($i -lt 0) { $i = $rows.Count - 1 } }             # up
            40 { $i++; if ($i -ge $rows.Count) { $i = 0 } }                 # down
            27 { return $false }                                            # esc
            13 {                                                            # enter
                switch ($rows[$i].Kind) {
                    'task'   { $rows[$i].Task.On = -not $rows[$i].Task.On }
                    'start'  { if ($anyOn -or $AllowEmpty) { return $true } }
                    'cancel' { return $false }
                }
            }
            32 { if ($rows[$i].Kind -eq 'task') { $rows[$i].Task.On = -not $rows[$i].Task.On } }  # space
        }
        # Skip the blank spacer row rather than letting the highlight land
        # on nothing.
        if ($rows[$i].Kind -eq 'gap') {
            if ($code -eq 38) { $i-- } else { $i++ }
            if ($i -lt 0) { $i = $rows.Count - 1 }
            if ($i -ge $rows.Count) { $i = 0 }
        }
    }
}
