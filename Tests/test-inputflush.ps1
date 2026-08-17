param([string]$Root)
<#
 THE STOLEN KEYPRESS

 WHAT HAPPENED

 A repair ran for 4.4 minutes, finished cleanly, printed its verdict,
 saved its log, and the window vanished before any of it could be read.
 The log proved the script reached its very last line, because the log
 is written there. So nothing crashed. The final prompt was ANSWERED.

 WHY

 Console input is a QUEUE, and nothing in this project ever emptied it.
 chkdsk, sfc and dism run bare for minutes at a time and do not consume
 stdin, so anything typed while watching them sits in the buffer. The
 next Read-Host takes it instantly, prints nothing, and moves on.

 Health-Report runs Repair-Health with `& $deep` in the SAME console, so
 a keystroke made during the report is still queued during the repair
 and still queued at "Press Enter to close" several minutes later.

 The launcher makes it fatal rather than merely untidy: the Windows
 Terminal path is `start "" wt.exe ... -File Health-Report.ps1` followed
 immediately by `exit /b 0`, so the ONLY thing holding that window open
 is the Read-Host inside PowerShell. Answer it early and the window is
 gone with everything in it.

 THE SAME BUG, QUIETER

 A stolen Enter at a `(y/n)` gate returns an empty string, which does
 not match '^y', so it silently answers NO. That is how "run the repair
 now?" and "create a restore point first?" can both be declined by a
 keystroke aimed at something else, with nothing on screen to say so.

 WHAT THIS ASSERTS

 That the flush helper exists, that it cannot throw on a host with no
 real console, and that every prompt whose answer matters is preceded
 by a flush. The last part is the regression guard: the helper existing
 is worth nothing if a new prompt is added without it.
#>
if (-not $Root) { $Root = Join-Path (Split-Path $PSScriptRoot -Parent) 'Tools' }
. (Join-Path $Root 'Common.ps1')

$fail = 0
function Check($name, $ok, $detail = '') {
    if ($ok) { Write-Host ("  PASS  {0}" -f $name) -ForegroundColor Green }
    else     { Write-Host ("  FAIL  {0}  {1}" -f $name, $detail) -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host 'THE INPUT BUFFER IS EMPTIED BEFORE ANYTHING IS ASKED' -ForegroundColor Cyan

# --- the helper exists and is safe -----------------------------------
$cmd = Get-Command Clear-InputBuffer -ErrorAction SilentlyContinue
Check 'Clear-InputBuffer is defined' ($null -ne $cmd)

# It runs under redirected input here, which is exactly the host whose
# RawUI.FlushInputBuffer throws. If it cannot survive that it will throw
# inside a real run too, on a host nobody tested.
if ($cmd) {
    $threw = $false
    try { Clear-InputBuffer } catch { $threw = $true }
    Check 'it does not throw on a host with no real console' (-not $threw)
}

# --- every prompt that matters is preceded by a flush -----------------
#
# Matched by looking BACKWARDS from the prompt over the preceding few
# code lines, rather than by requiring an exact adjacent line. A comment
# or a Write-Host between the flush and the prompt is fine; the buffer
# stays empty either way.
function FlushedBefore($lines, $idx, $window = 4) {
    # Same line counts, but only when the flush really does come first.
    # `Clear-InputBuffer; Read-Host ...` is correct and idiomatic for a
    # one-line guarded prompt; the reverse order would pass a naive
    # substring test while emptying the queue AFTER reading from it.
    $self = $lines[$idx]
    if ($self -match 'Clear-InputBuffer' -and
        $self.IndexOf('Clear-InputBuffer') -lt $self.IndexOf('Read-Host')) { return $true }

    $start = [Math]::Max(0, $idx - $window)
    for ($n = $start; $n -lt $idx; $n++) {
        if ($lines[$n] -match 'Clear-InputBuffer') { return $true }
    }
    return $false
}

$targets = @(
    @{ File = 'Repair-Health.ps1'; Pattern = 'Press Enter to close';
       Why  = 'the prompt that lost a 4.4 minute repair' }
    @{ File = 'Health-Report.ps1'; Pattern = 'Press Enter to close';
       Why  = 'same prompt, same console, same queue' }
    @{ File = 'Health-Report.ps1'; Pattern = 'Run the repair and recovery now';
       Why  = 'a stolen Enter here silently skips every repair' }
    @{ File = 'Repair-Health.ps1'; Pattern = 'Create a restore point first';
       Why  = 'a stolen Enter here silently declines the restore point' }
    @{ File = 'Repair-Health.ps1'; Pattern = 'ENTER to start, B to go back';
       Why  = 'a stolen Enter here starts repairs nobody confirmed' }
)

foreach ($t in $targets) {
    $path = Join-Path $Root $t.File
    if (-not (Test-Path $path)) { Check "$($t.File) exists" $false; continue }
    $lines = Get-Content $path
    # Read-Host AND the wording. The prompt text also appears in comments
    # explaining an old -Unattended bug, and a test that demanded a flush
    # before a comment would be unsatisfiable.
    $hits  = @(0..($lines.Count - 1) | Where-Object {
        $lines[$_] -match [regex]::Escape($t.Pattern) -and $lines[$_] -match 'Read-Host'
    })
    if (-not $hits.Count) {
        Check "$($t.File): '$($t.Pattern)' found" $false 'the prompt moved or was reworded'
        continue
    }
    foreach ($h in $hits) {
        Check "$($t.File):$($h + 1) flushed before '$($t.Pattern)'" (FlushedBefore $lines $h) $t.Why
    }
}

# --- the deferred questions too --------------------------------------
#
# Invoke-Deferred asks everything that was held back until the end, so
# it runs at exactly the point the buffer is most likely to hold
# something typed during a long scan.
$common = Get-Content (Join-Path $Root 'Common.ps1')
$defIdx = @(0..($common.Count - 1) | Where-Object { $common[$_] -match 'function Invoke-Deferred' })
Check 'Invoke-Deferred found' ($defIdx.Count -eq 1)
if ($defIdx.Count -eq 1) {
    $body = ($common[$defIdx[0]..([Math]::Min($common.Count - 1, $defIdx[0] + 40))]) -join "`n"
    Check 'Invoke-Deferred flushes before it asks' ($body -match 'Clear-InputBuffer')
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'INPUT FLUSH OK' -ForegroundColor Green }
else { Write-Host "$fail INPUT FLUSH CHECK(S) FAILED" -ForegroundColor Red }
exit $fail
