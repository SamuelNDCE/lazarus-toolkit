param([string]$Root)
<#
 ICONS COME OUT OF THE TOOLS, NOT OUT OF THE REPO

 The launcher used to ship 37 hand-made PNGs and a hand-kept map of
 display name to filename. Adding a tool meant drawing it an icon, and
 forgetting left it looking broken next to the ones that had one.

 Now Tools\Get-Icons.ps1 reads each icon out of the tool's own binary and
 the launcher finds it by slug. THREE places derive that slug: the
 extractor, the launcher, and Docs\validate.js. They cannot be allowed to
 disagree, because a disagreement produces no error at all: every icon
 quietly becomes a fallback glyph and the UI looks the same as a stick
 with no tools on it.

 So this builds a throwaway stick with a real binary on it, runs the real
 extractor, and asserts a real PNG comes out under the name the launcher
 will actually ask for.
#>
if (-not $Root) { $Root = Join-Path (Split-Path $PSScriptRoot -Parent) 'Tools' }
$RepoRoot = Split-Path $Root -Parent

$fail = 0
function Check($name, $ok, $detail = '') {
    if ($ok) { Write-Host ("  PASS  {0}" -f $name) -ForegroundColor Green }
    else     { Write-Host ("  FAIL  {0}  {1}" -f $name, $detail) -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host 'ICONS ARE EXTRACTED, NOT SHIPPED' -ForegroundColor Cyan

# --- the three slug rules must agree ---------------------------------
#
# Compared as SOURCE TEXT rather than by running each one, because two of
# the three live in languages not loaded here. A character-level match is
# a stronger guarantee than three implementations that happen to agree on
# whatever examples someone thought to try.
$ps  = Get-Content (Join-Path $Root 'Get-Icons.ps1') -Raw
$hta = Get-Content (Join-Path $RepoRoot 'Lazarus.hta') -Raw
$js  = Get-Content (Join-Path $RepoRoot 'Docs\validate.js') -Raw

Check 'the extractor lowercases and strips non-alphanumerics' ($ps -match "ToLower\(\)\s*-replace\s*'\[\^a-z0-9\]'")
Check 'the launcher uses the same rule'  ($hta -match 'toLowerCase\(\)[\s\S]{0,60}\[\^a-z0-9\]')
Check 'the validator uses the same rule' ($js  -match 'toLowerCase\(\)[\s\S]{0,60}\[\^a-z0-9\]')

# --- and produce the same answers ------------------------------------
function Get-SlugLocal($n) { ($n.ToLower() -replace '[^a-z0-9]', '') }
Check '"7-Zip" slugs to 7zip'                  ((Get-SlugLocal '7-Zip') -eq '7zip')
Check '"Notepad++" slugs to notepad'           ((Get-SlugLocal 'Notepad++') -eq 'notepad')
Check '"Health Report and Repair" slugs right' ((Get-SlugLocal 'Health Report and Repair') -eq 'healthreportandrepair')

# --- no two tools may slug to the same name --------------------------
#
# The slug is the filename, so a collision means two tools silently share
# one icon and the second one to be extracted wins. Nothing would report
# it: both tools show an icon, one of them is just the wrong picture.
# "Notepad++" collapsing to "notepad" is exactly the kind of narrowing
# that makes this possible, so it is asserted against the real table
# rather than against examples.
$htaNames = [regex]::Matches($hta, '\["([^"]+)","(?:Tools|Setup|ISO)\\\\') |
            ForEach-Object { $_.Groups[1].Value -replace '&amp;', '&' }
$bySlug = $htaNames | Group-Object { Get-SlugLocal $_ } | Where-Object Count -gt 1
Check "no two tools share a slug ($($htaNames.Count) names checked)" ($bySlug.Count -eq 0) `
      "collide: $(($bySlug | ForEach-Object { $_.Group -join ' + ' }) -join '; ')"

# --- the extractor actually produces a PNG ---------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("lz-icons-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    # A throwaway stick: one tool folder with a real signed binary in it,
    # and a launcher table that points at it.
    $toolDir = Join-Path $tmp 'Tools\Fake Tool'
    New-Item -ItemType Directory -Path $toolDir -Force | Out-Null
    Copy-Item (Join-Path $env:WINDIR 'System32\notepad.exe') (Join-Path $toolDir 'notepad.exe')

    # A second folder whose entry point is a .bat, to prove the generic
    # script icon is refused in favour of the exe beside it.
    $batDir = Join-Path $tmp 'Tools\Batch Tool'
    New-Item -ItemType Directory -Path $batDir -Force | Out-Null
    Copy-Item (Join-Path $env:WINDIR 'System32\notepad.exe') (Join-Path $batDir 'notepad.exe')
    Set-Content (Join-Path $batDir 'run.bat') '@echo off' -Encoding ASCII

    @'
var DATA = [
["Group", [
 ["Fake Tool","Tools\\Fake Tool\\notepad.exe","purpose","desc","",""],
 ["Batch Tool","Tools\\Batch Tool\\run.bat","purpose","desc","",""]
]]
];
'@ | Set-Content (Join-Path $tmp 'Lazarus.hta') -Encoding UTF8

    Copy-Item (Join-Path $Root 'Common.ps1') $tmp -ErrorAction SilentlyContinue
    $gi = Join-Path $tmp 'Get-Icons.ps1'
    Copy-Item (Join-Path $Root 'Get-Icons.ps1') $gi

    & $gi -Root $tmp *>$null
    $exeIcon = Join-Path $tmp 'Icons\faketool.png'
    $batIcon = Join-Path $tmp 'Icons\batchtool.png'

    Check 'an icon is extracted from an exe' (Test-Path $exeIcon)
    Check 'a .bat falls back to the exe beside it' (Test-Path $batIcon)

    if (Test-Path $exeIcon) {
        # Assert it is a real PNG, not a zero-byte file that merely
        # satisfies Test-Path. The 8-byte PNG signature is the check.
        $bytes = [IO.File]::ReadAllBytes($exeIcon)
        $sig   = @(137, 80, 78, 71, 13, 10, 26, 10)
        $isPng = $bytes.Length -gt 8
        if ($isPng) { for ($n = 0; $n -lt 8; $n++) { if ($bytes[$n] -ne $sig[$n]) { $isPng = $false } } }
        Check 'and it is a real PNG, not an empty file' $isPng "$($bytes.Length) bytes"

        $img = $null
        try { $img = [System.Drawing.Image]::FromFile($exeIcon) } catch { }
        Check 'with real pixel dimensions' ($null -ne $img -and $img.Width -ge 16 -and $img.Height -ge 16) `
              $(if ($img) { "$($img.Width)x$($img.Height)" } else { 'unreadable' })
        if ($img) { $img.Dispose() }
    }

    # --- a .bat in the Tools ROOT must not adopt the whole stick -----
    #
    # Found by running the extractor against the real stick: the health
    # report is Tools\Health-Report.bat, so "the folder it lives in" is
    # Tools itself, the recursive search swept all 48 tools, and the
    # flagship was illustrated with OCCT's icon. Our own scripts have no
    # binary, so the correct answer is no icon at all.
    Set-Content (Join-Path $tmp 'Tools\Loose.bat') '@echo off' -Encoding ASCII
    @'
var DATA = [
["Group", [
 ["Loose Script","Tools\\Loose.bat","purpose","desc","",""]
]]
];
'@ | Set-Content (Join-Path $tmp 'Lazarus.hta') -Encoding UTF8
    & $gi -Root $tmp *>$null
    Check 'a .bat in the Tools root adopts no other tool''s icon' (
        -not (Test-Path (Join-Path $tmp 'Icons\loosescript.png')))

    # --- a helper exe must not beat the real one ---------------------
    #
    # Also found for real: Firefox ships crashreporter.exe beside
    # firefox.exe, and the browser was being illustrated with the icon of
    # the thing that appears when it falls over.
    #
    # Asserted by comparing the PRODUCED PNG against both candidates
    # rather than by grepping the exclusion list, so it fails if the
    # exclusion stops working for any reason at all.
    $helperDir = Join-Path $tmp 'Tools\Helper Tool'
    New-Item -ItemType Directory -Path $helperDir -Force | Out-Null
    Set-Content (Join-Path $helperDir 'go.bat') '@echo off' -Encoding ASCII
    Copy-Item (Join-Path $env:WINDIR 'System32\notepad.exe') (Join-Path $helperDir 'realapp.exe')
    # Deliberately LARGER than the real one, so picking by size alone
    # would choose the helper and this test would catch it.
    #
    # taskmgr.exe, not mspaint.exe: Paint is a Store app on Windows 11 and
    # is no longer in System32. Using it made Copy-Item fail, the two
    # assertions below never ran, and the suite still printed ICONS OK.
    # A missing prerequisite must therefore FAIL rather than skip.
    $bigExe = Join-Path $env:WINDIR 'System32\taskmgr.exe'
    Check 'the larger stand-in binary exists on this machine' (Test-Path $bigExe) $bigExe
    if (Test-Path $bigExe) { Copy-Item $bigExe (Join-Path $helperDir 'crashreporter.exe') }
    @'
var DATA = [
["Group", [
 ["Helper Tool","Tools\\Helper Tool\\go.bat","purpose","desc","",""]
]]
];
'@ | Set-Content (Join-Path $tmp 'Lazarus.hta') -Encoding UTF8
    & $gi -Root $tmp *>$null

    # Returns $null rather than throwing, so a missing file becomes a
    # visible FAIL below instead of an exception that unwinds past every
    # remaining Check and still lets the suite print OK.
    function Get-IconBytes($exe) {
        if (-not (Test-Path $exe)) { return $null }
        try {
            $i = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
            $b = $i.ToBitmap()
            $ms = New-Object IO.MemoryStream
            $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $out = $ms.ToArray()
            $ms.Dispose(); $b.Dispose(); $i.Dispose()
            return [Convert]::ToBase64String($out)
        } catch { return $null }
    }
    $produced = Join-Path $tmp 'Icons\helpertool.png'
    if (Test-Path $produced) {
        $got  = [Convert]::ToBase64String([IO.File]::ReadAllBytes($produced))
        $real = Get-IconBytes (Join-Path $helperDir 'realapp.exe')
        $bad  = Get-IconBytes (Join-Path $helperDir 'crashreporter.exe')
        Check 'both reference icons could be read' ($null -ne $real -and $null -ne $bad)
        Check 'the real binary supplies the icon' ($null -ne $real -and $got -eq $real)
        Check 'and the larger helper binary does not' ($null -ne $bad -and $got -ne $bad)
    } else {
        Check 'an icon was produced for the helper-tool case' $false
    }

    # --- caching ------------------------------------------------------
    #
    # Re-running must not redo the work. On a 48-tool stick over USB that
    # is the difference between instant and several seconds every refresh.
    #
    # The original two-entry table is restored first, or this would be
    # asserting that a file nothing asked for stayed unchanged, which is
    # true of every file on the disk and proves nothing.
    @'
var DATA = [
["Group", [
 ["Fake Tool","Tools\\Fake Tool\\notepad.exe","purpose","desc","",""],
 ["Batch Tool","Tools\\Batch Tool\\run.bat","purpose","desc","",""]
]]
];
'@ | Set-Content (Join-Path $tmp 'Lazarus.hta') -Encoding UTF8
    $before = (Get-Item $exeIcon -ErrorAction SilentlyContinue).LastWriteTime
    Start-Sleep -Milliseconds 20
    & $gi -Root $tmp *>$null
    $after = (Get-Item $exeIcon -ErrorAction SilentlyContinue).LastWriteTime
    Check 'a second run leaves existing icons alone' (
        $null -ne $before -and $before -eq $after)

    # --- nothing is shipped ------------------------------------------
    Check 'no PNG is tracked in git under Icons' (
        -not (& git -C $RepoRoot ls-files 'Icons/*.png'))
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'ICONS OK' -ForegroundColor Green }
else { Write-Host "$fail ICON CHECK(S) FAILED" -ForegroundColor Red }
exit $fail
