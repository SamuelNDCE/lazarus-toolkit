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
    [void]$md.AppendLine("# Health and Handover Report: $env:COMPUTERNAME")
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

    [void]$md.AppendLine()
    [void]$md.AppendLine('---')
    [void]$md.AppendLine()
    [void]$md.AppendLine('The matching `.txt` next to this file is the full record of the run, including the progress and timing lines left out here.')

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
