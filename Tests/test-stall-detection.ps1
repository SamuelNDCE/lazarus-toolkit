# Proves Start-StallWatch's timeout ACTUALLY FIRES, not just that the
# function starts and stops without throwing (that part is
# test-watchdogs.ps1). A watchdog that never warns is indistinguishable
# from a working one until the one time it matters, so this exercises
# real detection: a backdated log file, a real wait, real printed text.
#
# NOT part of Run-Checks.ps1's default run. It needs ~2.5 real minutes
# (two 30s poll cycles per case, so the watchdog's own -1 "unseen yet"
# sentinel on the first poll cannot mask a file that was already stale
# before watching began) and it is genuinely slow, unlike everything
# else in Tests\, which finishes in seconds. Run it by hand, the same
# way Test-StickReady.ps1 is run separately rather than on every check.
#
# Start-StallWatch prints via raw [Console]::WriteLine from a background
# runspace, which is process-wide but bypasses PowerShell's own output
# streams entirely, so 6>&1 / *>&1 style capture inside this same
# process sees nothing. The only thing that reliably sees it is real
# OS-level stdout redirection, so this test launches itself in a child
# process with '>' redirection and reads the file back, rather than
# trying to capture in-process.
param([string]$Root)
if (-not $Root) { $Root = Join-Path (Split-Path $PSScriptRoot -Parent) 'Tools' }

$inner = @'
param($Root, $AgeMinutes, $WarnM, $DeadM, $WaitSeconds)
$file = Join-Path $Root 'Repair-Health.ps1'
$ast  = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
$defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        Where-Object { $_.Name -in 'Start-StallWatch','Stop-StallWatch' }
foreach ($d in $defs) { . ([scriptblock]::Create($d.Extent.Text)) }

$tmp = [System.IO.Path]::GetTempFileName()
'seed' | Out-File $tmp -Encoding ascii
(Get-Item $tmp).LastWriteTime = (Get-Date).AddMinutes(-$AgeMinutes)

$w = Start-StallWatch -LogPath $tmp -Tool 'TESTTOOL' -WarnMinutes $WarnM -DeadMinutes $DeadM
Start-Sleep -Seconds $WaitSeconds
Stop-StallWatch $w
Remove-Item $tmp -ErrorAction SilentlyContinue
'@
$innerPath = Join-Path ([System.IO.Path]::GetTempPath()) ("stallwatch-inner-{0}.ps1" -f ([guid]::NewGuid().ToString('N').Substring(0,8)))
Set-Content -Path $innerPath -Value $inner -Encoding UTF8

function RunCase($label, $ageMinutes, $warnM, $deadM, $expectPattern) {
    $outFile = Join-Path ([System.IO.Path]::GetTempPath()) ("stallwatch-out-{0}.txt" -f ([guid]::NewGuid().ToString('N').Substring(0,8)))
    # 75s: two 30s poll cycles plus margin, not the 30s a single naive
    # wait would use. This is the exact number this test was wrong about
    # on the first attempt, see wiki/logs/usb-toolkit.md 2026-08-16.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -File `"$innerPath`" `"$Root`" $ageMinutes $warnM $deadM 75"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    # Write-Host, not Write-Output. This function's return value is used
    # in a boolean context by the caller: `if (-not (RunCase ...))`. The
    # parentheses capture EVERY item this function writes to its output
    # stream into one array, narration included, and hand that whole
    # array to -not. A non-empty array is truthy regardless of what is
    # in it, so a Write-Output narration line before `return $false`
    # would make -not ALWAYS see a non-empty array and ALWAYS evaluate
    # to $false, meaning $fail could never increment no matter what this
    # function found. Caught by testing that this test can fail at all
    # (see the bottom of this file, before it was fixed here) rather than
    # trusting the first green run. Write-Host bypasses the output
    # stream entirely, so it cannot pollute the return value.
    Write-Host "  $label"
    if ($stdout -match [regex]::Escape($expectPattern)) {
        Write-Host "    PASS (found: '$expectPattern')"
        return $true
    } else {
        Write-Host "    FAIL: expected to find '$expectPattern' in the watchdog's output, did not."
        Write-Host "    --- captured stdout ---"
        ($stdout -split "`n" | Select-Object -First 15) | ForEach-Object { Write-Host "    $_" }
        if ($stderr) { Write-Host "    --- stderr ---"; Write-Host "    $stderr" }
        return $false
    }
}

$fail = 0
Write-Output 'Real stall detection (this takes about 2.5 minutes; it needs real wall-clock time)'
Write-Output ''
if (-not (RunCase 'WARN path: log backdated 2 min, WarnMinutes=1, DeadMinutes=5' 2 1 5 'has written nothing to its log for')) { $fail++ }
Write-Output ''
if (-not (RunCase 'DEAD path: log backdated 4 min, WarnMinutes=1, DeadMinutes=2' 4 1 2 'is almost certainly stuck')) { $fail++ }

Remove-Item $innerPath -ErrorAction SilentlyContinue

Write-Output ''
if ($fail -eq 0) { Write-Output 'PASS: the real stall watchdog actually warns and actually declares dead'; exit 0 }
Write-Output "FAIL: $fail case(s) did not print the expected warning"
exit 1
