param([string]$Root)
<#
 THE DOCUMENTED TOOL LIST MUST MATCH THE LAUNCHER

 WHY THIS EXISTS

 Docs\README.txt is the file somebody reads when they pick the stick up,
 and it had drifted badly from what the stick actually carries. It
 advertised 37 tools and 9 boot ISOs. The real numbers were 31 and 5.

 It listed seven tools that are not on the stick at all: System
 Informer, KVRT, CPU-Z, Snappy Driver Installer, GSmartControl,
 VeraCrypt, and three ISOs (Boot-Repair-Disk, TrueNAS SCALE, Proxmox
 VE). It omitted four that ARE on it, including Malwarebytes and the
 health report, which is the flagship. Its malware triage procedure was
 built around KVRT, a tool nobody could run, so following the
 instructions to the letter was impossible.

 Nothing was broken and nothing errored. A stale document simply reads
 as an authoritative one, which is worse than a missing one, because a
 missing document does not tell you to run something that is not there.

 The list is now GENERATED from the launcher's own table. This asserts
 it stayed that way, so the next tool added or removed either updates
 the document or fails the build.
#>
if (-not $Root) { $Root = Join-Path (Split-Path $PSScriptRoot -Parent) 'Tools' }
$RepoRoot = Split-Path $Root -Parent

$fail = 0
function Check($name, $ok, $detail = '') {
    if ($ok) { Write-Host ("  PASS  {0}" -f $name) -ForegroundColor Green }
    else     { Write-Host ("  FAIL  {0}  {1}" -f $name, $detail) -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host 'THE DOCS MATCH THE LAUNCHER' -ForegroundColor Cyan

$htaPath = Join-Path $RepoRoot 'Lazarus.hta'
$docPath = Join-Path $RepoRoot 'Docs\README.txt'
if (-not (Test-Path $htaPath)) { Check 'Lazarus.hta exists' $false; exit 1 }
if (-not (Test-Path $docPath)) { Check 'Docs\README.txt exists' $false; exit 1 }

$hta = Get-Content $htaPath -Raw
$doc = Get-Content $docPath -Raw

# Every launcher entry, keyed on its PATH rather than its name. The path
# says unambiguously whether something is a tool, a boot ISO or one of
# the Setup scripts. The name does not, and guessing from the name is
# what made the first version of this test wrong in two places at once.
$all = [regex]::Matches($hta, '\["([^"]+)","((?:Tools|Setup|ISO)\\\\[^"]+)"') | ForEach-Object {
    [pscustomobject]@{ Name = $_.Groups[1].Value -replace '&amp;', '&'; Path = $_.Groups[2].Value }
}
Check "the launcher table parsed ($($all.Count) entries)" ($all.Count -ge 30)

# Setup\ scripts are summarised in the doc rather than listed one by one,
# so they are excluded from BOTH sides rather than special-cased on one.
$launcherTools = @($all | Where-Object { $_.Path -like 'Tools\*' } | ForEach-Object Name | Sort-Object -Unique)
$launcherIsos  = @($all | Where-Object { $_.Path -like 'ISO\*' })

# The generated section runs from its banner to the next banner.
$section = ''
if ($doc -match '(?s)WHAT IS ON IT.*?\r?\n=+\r?\n(.*?)\r?\n=+\r?\nADDING YOUR OWN TOOLS') {
    $section = $Matches[1]
}
Check 'the WHAT IS ON IT section was found' ($section.Length -gt 500)

# Names in the doc. Generated entries pad the name to a fixed column, so
# the name is exactly the first 28 characters after the two-space indent
# and the purpose begins immediately after. Prose wraps and does not
# align, so keying on the column excludes it without needing a blocklist
# of phrases, which is what the first attempt tried and failed at.
# The leading \S matters. Wrapped detail lines are indented six spaces,
# so without it they fill the 28-character window too and every fragment
# of every description was read as a tool name.
# And the trailing-padding requirement matters just as much. Prose
# indented two spaces also fills a 28-character window, so without it
# the header paragraph read as four more tool names. A real entry is a
# name PADDED OUT to the column, so its window always ends in spaces.
$docNames = [regex]::Matches($section, '(?m)^  (\S.{27})(\S.*)$') |
            Where-Object { $_.Groups[1].Value -match '\s{2,}$' } |
            ForEach-Object { $_.Groups[1].Value.Trim() } |
            Where-Object { $_ } | Sort-Object -Unique

# The doc lists the boot ISOs in the same section, so they count as
# documented names even though they are not Tools\ entries.
$documentable = @($launcherTools) + @($launcherIsos | ForEach-Object Name)
$missing = @($launcherTools | Where-Object { $_ -notin $docNames })
$extra   = @($docNames | Where-Object { $_ -notin $documentable })

Check "every launcher tool is documented ($($launcherTools.Count) tools)" ($missing.Count -eq 0) `
      "undocumented: $($missing -join ', ')"
Check 'the docs name no tool the launcher does not have' ($extra.Count -eq 0) `
      "not in the launcher: $($extra -join ', ')"

# The headline counts, which is what was most visibly wrong.
$toolCount = $launcherTools.Count
$isoCount  = $launcherIsos.Count
if ($doc -match 'WHAT IS ON IT\s+-\s+(\d+) tools \+ (\d+) boot ISOs') {
    Check "the headline tool count is right (says $($Matches[1]), is $toolCount)" ([int]$Matches[1] -eq $toolCount)
    Check "the headline ISO count is right (says $($Matches[2]), is $isoCount)"   ([int]$Matches[2] -eq $isoCount)
} else {
    Check 'the headline counts were found' $false 'the "N tools + N boot ISOs" line has moved'
}

# --- the SCREENSHOT must match the launcher too -----------------------
#
# The README picture is the first thing anyone sees, and after five tools
# were removed it still showed all five, plus a footer reading 48 tools.
# Every text check above passed the whole time, because none of them can
# read a PNG.
#
# So the count the screenshot shows is written beside it as a comment and
# asserted here. It cannot verify the pixels, but it makes the picture
# go stale LOUDLY: change the catalogue and this fails until somebody
# retakes the shot.
$readme = Get-Content (Join-Path $RepoRoot 'README.md') -Raw
if ($readme -match 'SCREENSHOT SHOWS (\d+) TOOLS') {
    $shotCount = [int]$Matches[1]
    Check "the screenshot is current (shows $shotCount, launcher has $($all.Count))" `
          ($shotCount -eq $all.Count) `
          'retake Docs\images\launcher.png, then update the number in the comment beside it'
} else {
    Check 'the screenshot count marker is present' $false `
          'the "SCREENSHOT SHOWS N TOOLS" comment in README.md has gone'
}

# Tools removed on 2026-08-17 must not creep back into the prose.
$gone = @('KVRT','System Informer','CPU-Z','Snappy Driver','GSmartControl','VeraCrypt','NirLauncher','OCCT','RustDesk','KeePassXC','Picocrypt','Dism++')
$crept = @($gone | Where-Object { $doc -match [regex]::Escape($_) })
Check 'no removed tool is still described as present' ($crept.Count -eq 0) "found: $($crept -join ', ')"

Write-Host ''
if ($fail -eq 0) { Write-Host 'DOCS OK' -ForegroundColor Green }
else { Write-Host "$fail DOC CHECK(S) FAILED" -ForegroundColor Red }
exit $fail
