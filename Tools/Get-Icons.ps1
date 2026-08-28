<#
=======================================================================
 GET-ICONS  -  pull each tool's icon out of the tool itself
=======================================================================

 WHY THIS EXISTS

 The launcher used to carry 37 hand-made PNGs and a hand-maintained map
 of display name to filename. That meant adding a tool was three steps
 (copy it in, add its entry, draw it an icon) and forgetting the third
 left a tool looking broken next to ones that did not.

 Nothing here is drawn. Every icon is the icon the program already has,
 read out of its own binary, so a tool dropped on the stick looks right
 without anyone doing anything.

 The output is a CACHE. It is gitignored, it is rebuilt from whatever is
 actually present, and deleting it costs a few seconds.

 NAMING

 One rule, shared with the launcher: lowercase the display name and drop
 everything that is not a letter or a digit. "7-Zip" becomes 7zip and
 "Notepad++" becomes notepad, because punctuation is removed rather than
 spelled out. The launcher derives the same slug when it looks for the
 file, so there is no map to keep in step.

 That narrowing is why Tests\test-icons.ps1 asserts no two display names
 collapse to the same slug: the slug IS the filename, so a collision
 would have two tools silently sharing one picture with nothing to say so.

 BATCH FILES

 A .bat has no icon of its own; Windows hands back the generic script
 icon, which is worse than useless because it is the SAME for every
 tool launched that way. So for a .bat the largest .exe under the same
 tool folder is used instead, which is nearly always the program the
 batch file exists to start.
#>
param(
    # Where the stick root is. Defaults to the parent of this script, so
    # running it in place does the right thing with no arguments.
    [string]$Root,
    # Re-extract even if a PNG is already there.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path $PSScriptRoot -Parent }

# Deliberately does NOT load Common.ps1. It uses nothing from it, and the
# dependency was real breakage rather than dead weight: dot-sourcing a
# file that is not beside this one throws under $ErrorActionPreference
# 'Stop', so the script died before extracting anything and reported it
# as a missing icon rather than a missing dependency.
Add-Type -AssemblyName System.Drawing

$IconDir = Join-Path $Root 'Icons'
if (-not (Test-Path $IconDir)) { New-Item -ItemType Directory -Path $IconDir -Force | Out-Null }

function Get-Slug($name) {
    # MUST match slug() in Lazarus.hta. If these two ever disagree the
    # launcher looks for a file this script never writes, and every icon
    # silently falls back to a glyph with nothing reporting a fault.
    ($name.ToLower() -replace '[^a-z0-9]', '')
}

# Helpers that ship ALONGSIDE the real program and must never be mistaken
# for it. Kept identical to the list in biggestExe() in Lazarus.hta.
#
# Firefox is why this matters: its folder contains crashreporter.exe, and
# without this the browser was illustrated with the icon of the thing that
# appears when it falls over.
$HelperExe = '^(unins|setup|vcredist|install|update|crash|report|helper|launcher)'

function Resolve-IconSource($full, $rel) {
    # An ISO is a disc image, not a program. Windows hands back the same
    # generic disc-image icon for every one of them, so extracting turns
    # five distinct entries into five copies of one picture. The launcher
    # already draws a disc glyph for these, which is both honest and
    # consistent, so leave it to do that.
    if ($full -match '\.iso$') { return $null }

    # A .bat or .cmd carries the generic script icon, identical for every
    # tool. Use the biggest exe in the tool folder instead.
    if ($full -notmatch '\.(bat|cmd)$') { return $full }

    # THE SEARCH MUST STAY INSIDE ONE TOOL'S FOLDER.
    #
    # A script sitting directly in a top-level folder has no tool folder
    # of its own, so a recursive search from there sweeps everything
    # under it and returns the largest exe on the stick. Both halves of
    # that were caught by running this for real rather than by reading it:
    #
    #   Tools\Health-Report.bat   gave the health report OCCT's icon.
    #   a batch of top-level *.bat  ALL gave themselves one unrelated
    #   entries                     installer's icon, so several different
    #                               entries showed one identical wrong picture.
    #
    # So depth decides it. "Tools\Firefox\run.bat" has a tool folder and
    # is fine. A bare "Folder\Thing.bat" does not, and the honest answer
    # for it is no icon at all.
    $segments = @($rel -split '\\' | Where-Object { $_ })
    if ($segments.Count -lt 3) { return $null }

    $dir = Split-Path $full -Parent
    $exe = Get-ChildItem -Path $dir -Filter *.exe -Recurse -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -notmatch $HelperExe } |
           Sort-Object Length -Descending | Select-Object -First 1
    if ($exe) { return $exe.FullName }
    return $null
}

# Read the launcher's own table rather than keeping a second list here.
# A tool the launcher does not know about does not need an icon, and a
# second list would drift the moment either side changed.
$hta = Get-Content (Join-Path $Root 'Lazarus.hta') -Raw
$entries = [regex]::Matches($hta, '\["([^"]+)","((?:Tools|Setup|ISO)\\\\[^"]+)"')

Write-Host ''
Write-Host "  Extracting icons into $IconDir" -ForegroundColor Cyan
Write-Host ''

$made = 0; $kept = 0; $skipped = 0; $failed = 0

foreach ($m in $entries) {
    $name = $m.Groups[1].Value -replace '&amp;', '&'
    $rel  = $m.Groups[2].Value -replace '\\\\', '\'
    $slug = Get-Slug $name
    $out  = Join-Path $IconDir "$slug.png"

    if ((Test-Path $out) -and -not $Force) { $kept++; continue }

    $full = Join-Path $Root $rel
    if (-not (Test-Path $full)) {
        # Normal on a clone and on any stick missing a tool. Not a fault.
        $skipped++
        continue
    }

    $src = Resolve-IconSource $full $rel
    if (-not $src) { $skipped++; continue }

    try {
        $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($src)
        if ($null -eq $ico) { $failed++; continue }
        $bmp = $ico.ToBitmap()
        try {
            $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
            Write-Host ("    {0,-28} <- {1}" -f $name, (Split-Path $src -Leaf)) -ForegroundColor DarkGray
            $made++
        } finally { $bmp.Dispose(); $ico.Dispose() }
    } catch {
        Write-Host ("    {0,-28} could not be read: {1}" -f $name, $_.Exception.Message) -ForegroundColor Yellow
        $failed++
    }
}

Write-Host ''
Write-Host "    $made extracted, $kept already present, $skipped not on this stick, $failed failed" -ForegroundColor White
Write-Host ''
# A tool that is present but whose icon could not be read is the only
# real fault here. Missing tools are expected and say so separately.
if ($failed -gt 0) { exit 1 }
exit 0
