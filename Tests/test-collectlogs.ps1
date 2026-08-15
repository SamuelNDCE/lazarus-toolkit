<#
 Behaviour test for Collect-ToolLogs.ps1.

 WHY THIS EXISTS

 Every other check in this suite reads the source: does it parse, do the
 commands resolve, is everything defined before use. Those are real and
 they caught real bugs, but none of them can tell you whether this tool
 actually COPIES the right files, or whether it leaves the machine alone
 while doing it. That was verified by hand twice and by nothing else,
 which is exactly the gap this suite exists to close.

 The promise on the tin is "It only ever COPIES. Nothing is moved,
 nothing is deleted, and the source machine is left exactly as it was."
 A test that does not check that is not testing this tool.

 Runs against a fixture tree via -SourceList, so it needs no Malwarebytes
 install and no damaged component store.
#>
param(
    # Points at the shipped tool. Overridden only to aim this test at a
    # deliberately broken copy, which is how the test itself gets proven:
    # a behaviour test that has never failed has not been shown to work.
    [string]$Tool
)
if (-not $Tool) { $Tool = Join-Path (Split-Path $PSScriptRoot -Parent) 'HealthReport\Collect-ToolLogs.ps1' }
$tool = $Tool
$fail = 0
function Check($what, $ok, $detail) {
    if ($ok) { Write-Host "  PASS  $what" -ForegroundColor Green }
    else {
        Write-Host "  FAIL  $what" -ForegroundColor Red
        if ($detail) { Write-Host "          $detail" -ForegroundColor DarkGray }
        $script:fail++
    }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("collectlogs-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$src  = Join-Path $root 'src'
$out  = Join-Path $root 'out'
New-Item -ItemType Directory -Path $src, $out -Force | Out-Null

try {
    # A single file source.
    $one = Join-Path $src 'single.log'
    Set-Content $one 'alpha' -Encoding ASCII

    # A folder with more files than MaxFilesPerSource, so the cap is
    # exercised. Distinct timestamps: the tool takes the NEWEST, and with
    # identical times "newest 3" is whatever the sort happens to return.
    $many = Join-Path $src 'many'
    New-Item -ItemType Directory -Path $many -Force | Out-Null
    for ($i = 1; $i -le 7; $i++) {
        $f = Join-Path $many "log$i.log"
        Set-Content $f "entry $i" -Encoding ASCII
        (Get-Item $f).LastWriteTime = (Get-Date).AddMinutes(-$i)
    }

    # Over the size cap. Must be SKIPPED and SAID OUT LOUD, not dropped
    # in silence: a gap in a collection nobody mentions reads as "that
    # tool wrote nothing", which is a different and wrong conclusion.
    $big = Join-Path $src 'huge.log'
    $fs = [System.IO.File]::Create($big); $fs.SetLength(3MB); $fs.Close()

    $sources = @(
        @{ Tool = 'Single';   Path = $one;  Note = 'one file' }
        @{ Tool = 'Many';     Path = $many; Filter = '*.log'; Note = 'capped folder' }
        @{ Tool = 'Overlap';  Path = $many; Filter = '*.log'; Note = 'same folder again, must dedupe' }
        @{ Tool = 'TooBig';   Path = $big;  Note = 'over the cap' }
        @{ Tool = 'Absent';   Path = (Join-Path $src 'nope'); Filter = '*'; Note = 'never run on this machine' }
    )

    # Fingerprint the fixture so "copies only" can be proven rather than
    # asserted: name, length and write time of every source file.
    $before = @(Get-ChildItem $src -Recurse -File | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" } | Sort-Object)

    # ---- 1. -WhatIfOnly must not write anything ----
    $whatIfOut = Join-Path $root 'whatif'
    New-Item -ItemType Directory -Path $whatIfOut -Force | Out-Null
    & $tool -OutRoot $whatIfOut -SourceList $sources -MaxFileMB 2 -MaxFilesPerSource 3 -WhatIfOnly *>&1 | Out-Null
    $wrote = @(Get-ChildItem $whatIfOut -Recurse -File -ErrorAction SilentlyContinue)
    Check '-WhatIfOnly copies nothing' ($wrote.Count -eq 0) "$($wrote.Count) file(s) appeared"

    # ---- 2. the real run ----
    $out2 = Join-Path $root 'real'
    New-Item -ItemType Directory -Path $out2 -Force | Out-Null
    $log = & $tool -OutRoot $out2 -SourceList $sources -MaxFileMB 2 -MaxFilesPerSource 3 *>&1
    $text = ($log | Out-String)

    $dest = @(Get-ChildItem $out2 -Directory | Select-Object -First 1)
    Check 'a dated collection folder is created' ($dest.Count -eq 1) "found $($dest.Count)"

    if ($dest.Count -eq 1) {
        $copied = @(Get-ChildItem $dest[0].FullName -Recurse -File | Where-Object { $_.Name -ne 'index.md' })

        # 1 single + 3 from the capped folder. The overlap source must add
        # nothing, and the oversized file must not be there at all.
        Check 'per-source cap honoured, overlap deduped (expect 4 files)' ($copied.Count -eq 4) "copied $($copied.Count): $(($copied.Name | Sort-Object) -join ', ')"
        Check 'the oversized file is not copied' (-not ($copied.Name -contains 'huge.log')) 'huge.log was copied despite the cap'
        Check 'the newest files are the ones kept' (($copied.Name -contains 'log1.log') -and ($copied.Name -contains 'log2.log')) "kept: $(($copied.Name | Sort-Object) -join ', ')"

        $index = Join-Path $dest[0].FullName 'index.md'
        Check 'index.md is written' (Test-Path $index)
        if (Test-Path $index) {
            $idx = Get-Content $index -Raw
            Check 'index names a source that was found' ($idx -match 'Single')
            Check 'index records what was NOT found' (($idx -match 'Nothing found') -and ($idx -match 'Absent')) 'an absent tool is a finding and must be listed'
            Check 'index records what was skipped and why' (($idx -match 'Skipped') -and ($idx -match 'cap')) 'the size-capped file must be named, not silently dropped'
        }
    }

    # ---- 3. the promise on the tin ----
    $after = @(Get-ChildItem $src -Recurse -File | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" } | Sort-Object)
    Check 'the source tree is untouched: nothing moved, deleted or altered' (-not (Compare-Object $before $after)) 'the fixture changed during collection'

    # ---- 4. nothing to collect is a stated outcome, not a crash ----
    $empty = Join-Path $root 'empty'
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $log2 = & $tool -OutRoot $empty -SourceList @(@{ Tool = 'Absent'; Path = (Join-Path $src 'nowhere'); Filter = '*'; Note = 'nothing' }) *>&1
    Check 'says so plainly when there is nothing to collect' ((($log2 | Out-String) -match 'nothing to collect'))
}
finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -eq 0) { Write-Host '  PASS  Collect-ToolLogs copies, caps, dedupes and leaves the machine alone' -ForegroundColor Green }
exit $fail
