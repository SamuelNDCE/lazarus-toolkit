<#
=======================================================================
 TEST-STICKREADY

     .\Tests\Test-StickReady.ps1 -Drive D:

 The check to run before pulling the stick out and walking away with it.
 Everything here is read-only.

 It answers one question: if this is plugged into a stranger's broken
 machine tomorrow, does it work? A stick that fails silently in front of
 a client is worse than no stick, because you have already promised.
=======================================================================
#>
param([string]$Drive = 'D:')

$root = $Drive.TrimEnd('\') + '\'
$fail = 0
function Check($name, $ok, $detail = '') {
    if ($ok) { Write-Host ("  PASS  {0}" -f $name) -ForegroundColor Green }
    else     { Write-Host ("  FAIL  {0}  {1}" -f $name, $detail) -ForegroundColor Red; $script:fail++ }
}
function Section($t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan }

Section "DRIVE $Drive"
if (-not (Test-Path $root)) { Write-Host "  $Drive is not present." -ForegroundColor Red; exit 1 }
$vol = Get-Volume -DriveLetter $Drive.TrimEnd(':') -ErrorAction SilentlyContinue
if ($vol) {
    Check "volume present ($($vol.FileSystemLabel), $($vol.FileSystem))" $true
    Check 'filesystem reports healthy' ($vol.HealthStatus -eq 'Healthy') "HealthStatus = $($vol.HealthStatus)"
    $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
    Check "free space ($freeGB GB)" ($vol.SizeRemaining -gt 200MB) 'under 200 MB, reports may not save'
}

Section 'EVERY SCRIPT PARSES'
$psFiles = @(Get-ChildItem $root -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue)
$broken = @()
foreach ($f in $psFiles) {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count) { $broken += "$($f.Name):$($errs[0].Extent.StartLineNumber)" }
}
Check "all $($psFiles.Count) PowerShell script(s) parse" ($broken.Count -eq 0) ($broken -join ', ')

Section 'EVERY LAUNCHER POINTS SOMEWHERE REAL'
# Vendored third-party trees are excluded. They are not ours to fix, and
# they legitimately ship launchers for architectures they do not include:
# WindTerm's bundled clink.bat calls clink_x86.exe on 32-bit Windows and
# clink_x64.exe otherwise, and only ships the 64-bit binary. Flagging
# that was a false alarm, and a readiness check that cries wolf is one
# nobody reads on the day it matters.
$batFiles = @(Get-ChildItem $root -Recurse -File -Filter '*.bat' -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -notmatch '\\vendors?\\' })
$dangling = @()
foreach ($b in $batFiles) {
    foreach ($line in (Get-Content $b.FullName -ErrorAction SilentlyContinue)) {
        # %~dp0-relative targets are the ones that break when a file moves.
        if ($line -match '%~dp0\\?([^"''\s]+\.(ps1|bat|exe|hta))') {
            $target = Join-Path $b.DirectoryName $matches[1]
            if (-not (Test-Path $target)) { $dangling += "$($b.Name) -> $($matches[1])" }
        }
    }
}
Check "all $($batFiles.Count) of our batch launcher target(s) exist" ($dangling.Count -eq 0) ($dangling -join ', ')

Section 'NOTHING LEFT BEHIND'
# Deliberately narrow. Setup\Logs is where the club build tooling is
# SUPPOSED to write, and a filename merely containing "test" caught
# test-tables.js, which is a real part of the launcher's own tooling.
# Junk means scratch and backup files, not "every file with an
# unfortunate name".
$junk = @(Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue |
          Where-Object {
              $_.FullName -notmatch '\\Setup\\Logs\\' -and
              ($_.Name -match '\.(tmp|bak|old|orig)$' -or
               $_.Name -match '^~' -or
               $_.Name -match '\.bak-')
          })
Check 'no temp or backup files' ($junk.Count -eq 0) (($junk | Select-Object -First 5 | ForEach-Object { $_.Name }) -join ', ')

# Anything carrying another machine's name. Counted out loud rather than
# silently tolerated: these are the operator's own records and belong on
# their own stick, but they hold other people's hostnames and serials.
#
# Matched by NAME AND BY CONTENT. An earlier version looked only for
# `report-` and `repairlog-` prefixes plus one known folder, and missed
# `wifi-<HOST>-*.txt`, `activity-<HOST>-*.txt`, a debloat log and two
# registry backups, all of which named client machines. Any tool on the
# stick can write a log, so the pattern cannot be a list of the ones
# thought of in advance.
$hostPat = '[A-Z][A-Z0-9]{5,}|DESKTOP-[A-Z0-9]{7}|LAPTOP-[A-Z0-9]{7}'
$textExt = '.txt', '.log', '.md', '.csv', '.json', '.xml'

# The prefix ALONE is not enough. Matching `^activity-` caught five of
# Firefox's own `activity-stream.*.json` profile files and reported them
# as client records. Every real one is <prefix>-<HOSTNAME>-<date>, so
# require the date too: it is the part Firefox has no reason to have.
$byName = @(Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Extension -in $textExt -and
                ($_.Name -match '^(report|repairlog|wifi|activity)-.+-\d{4}-\d{2}-\d{2}' -or
                 $_.FullName -match '\\Setup\\Logs\\')
            })
# Content is the backstop, restricted to text files so a binary cannot
# produce a spurious hit the way Firefox's desktop-launcher.exe did.
$byContent = @(Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Extension -in $textExt -and $_.Length -lt 5MB } |
               Where-Object {
                   try { (Get-Content $_.FullName -Raw -ErrorAction Stop) -cmatch "\b(DESKTOP|LAPTOP)-[A-Z0-9]{7}\b" }
                   catch { $false }
               })
$reports = @($byName + $byContent | Sort-Object FullName -Unique)
$machines = @($reports | ForEach-Object {
                  if ($_.Name -match '^(?:report|repairlog|wifi|activity)-(.+?)-\d{4}-\d{2}-\d{2}') { $matches[1] }
                  elseif ($_.Name -match '^([A-Za-z0-9\-]+)_\d{4}-\d{2}-\d{2}') { $matches[1] }
                  else { '(by content)' }
              } | Sort-Object -Unique)
Write-Host ("  note  {0} saved report(s) from {1} machine(s): {2}" -f $reports.Count, $machines.Count, ($machines -join ', ')) -ForegroundColor DarkGray
Write-Host '        These contain machine names, models and serial numbers. Fine on your' -ForegroundColor DarkGray
Write-Host '        own stick, not fine anywhere public.' -ForegroundColor DarkGray

Section 'IT CAN STILL BE WRITTEN TO'
$probe = Join-Path $root ('.readycheck-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.tmp')
$wrote = $false
try {
    'ready' | Out-File -FilePath $probe -Encoding utf8 -ErrorAction Stop
    $wrote = (Get-Content $probe -ErrorAction Stop) -eq 'ready'
    Remove-Item $probe -Force -ErrorAction SilentlyContinue
} catch { }
Check 'a file can be created, read back and removed' $wrote 'the stick may be write-protected or failing'

Write-Host ''
if ($fail -eq 0) { Write-Host 'STICK IS READY. Safe to eject.' -ForegroundColor Green }
else { Write-Host "$fail PROBLEM(S). Do not rely on this stick until they are fixed." -ForegroundColor Red }
exit $fail
