<#
=======================================================================
 COLLECT-TOOL-LOGS

     .\Collect-ToolLogs.ps1              # gather everything it can find
     .\Collect-ToolLogs.ps1 -WhatIfOnly  # list what it WOULD take
     .\Collect-ToolLogs.ps1 -MaxFileMB 5 # skip anything bigger

 WHY THIS EXISTS

 The repair tools here write their own log. Every OTHER tool on the stick
 writes somewhere else entirely, on the machine being fixed rather than
 on the stick: Malwarebytes under ProgramData, ADWCleaner at the root of
 C:, DDU next to itself, SFC into CBS.log, DISM into dism.log. Finish a
 job on somebody's PC and the evidence of what you did is scattered
 across five directories, on a machine you are about to hand back.

 This copies them into one dated folder next to the health report, with
 an index saying what was found and, just as importantly, WHAT WAS NOT.

 It only ever COPIES. Nothing is moved, nothing is deleted, and the
 source machine is left exactly as it was.
=======================================================================
#>
param(
    [string]$OutRoot,
    [switch]$WhatIfOnly,
    # 20, not 10. The first dry run offered to copy 149 MB, so a cap was
    # clearly needed; 10 MB then excluded CBS.log by 0.7 MB, which is the
    # single most valuable file here because it is what SFC actually
    # wrote. A cap that drops the best evidence is the wrong cap.
    #
    # Genuinely huge files are still skipped, and always with the size
    # and the reason, so a gap in the collection is never silent.
    [int]$MaxFileMB = 20,
    [int]$MaxFilesPerSource = 5
)

. (Join-Path $PSScriptRoot 'Common.ps1')
Set-ConsoleLook 'Collect tool logs'

# Its OWN output helpers, defined here rather than borrowed.
#
# Good, Warn and Info live in Health-Report.ps1 and Repair-Health.ps1,
# not in Common.ps1, and both versions also append to that script's
# report buffer. Calling them from here found nothing and printed
# nothing. That is the third time in this project a function has been
# called from a file that does not define it, so this one carries its
# own and depends on Common.ps1 only for things Common.ps1 actually
# exports.
function Say-Good($m) { Write-Host "    ok   $m" -ForegroundColor Green }
function Say-Warn($m) { Write-Host "    !!   $m" -ForegroundColor Yellow }
function Say-Info($m) { Write-Host "         $m" -ForegroundColor DarkGray }

# Every known location, with what produced it. A source that is absent is
# reported as absent rather than skipped in silence: "ADWCleaner left no
# log" and "I did not look for ADWCleaner" are very different statements
# to somebody reading this afterwards.
$sources = @(
    @{ Tool = 'SFC (CBS.log)';        Path = "$env:WINDIR\Logs\CBS\CBS.log";                            Note = 'what SFC actually found and repaired' }
    @{ Tool = 'DISM';                 Path = "$env:WINDIR\Logs\DISM\dism.log";                          Note = 'component store servicing' }
    @{ Tool = 'CBS folder';           Path = "$env:WINDIR\Logs\CBS";                    Filter = '*.log'; Note = 'older CBS logs' }
    @{ Tool = 'Windows Update';       Path = "$env:WINDIR\Logs\WindowsUpdate";          Filter = '*';     Note = 'update client traces' }
    @{ Tool = 'Malwarebytes';         Path = "$env:ProgramData\Malwarebytes\MBAMService\logs";     Filter = '*'; Note = 'service and protection logs' }
    @{ Tool = 'Malwarebytes scans';   Path = "$env:ProgramData\Malwarebytes\MBAMService\ScanResults"; Filter = '*'; Note = 'what each scan found' }
    @{ Tool = 'ADWCleaner';           Path = 'C:\AdwCleaner\Logs';                      Filter = '*';     Note = 'adware and hijack removals' }
    @{ Tool = 'DDU';                  Path = "$env:SystemDrive\DDU\Logs";               Filter = '*';     Note = 'display driver removal' }
    @{ Tool = 'OCCT';                 Path = "$env:USERPROFILE\Documents\OCCT";         Filter = '*';     Note = 'stress test results' }
    @{ Tool = 'Win11Debloat';         Path = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Win11Debloat\Logs'); Filter = '*'; Note = 'what was removed' }
    @{ Tool = 'BCUninstaller';        Path = "$env:LOCALAPPDATA\BCUninstaller";         Filter = '*.log'; Note = 'bulk uninstall record' }
    @{ Tool = 'Setup / SetupDiag';    Path = "$env:WINDIR\Logs\SetupDiag";              Filter = '*';     Note = 'failed feature updates' }
)

Clear-Host
Write-Host ''
Show-Box -Colour Cyan -Lines @(
    'COLLECT TOOL LOGS',
    'Copies only. Nothing on this machine is moved or deleted.'
)
Write-Host ''

$stamp = Get-Date -f 'yyyy-MM-dd_HHmm'
$dest  = if ($OutRoot) { Join-Path $OutRoot "toollogs-$env:COMPUTERNAME-$stamp" }
         else { $p = Get-ReportPath "toollogs-$env:COMPUTERNAME-$stamp"; $p }

if (-not $dest) {
    Write-Host '    Could not find anywhere writable to collect into.' -ForegroundColor Red
    exit 1
}

$found   = @()
$missing = @()
$skipped = @()
$copied  = 0
$bytes   = 0
# Sources overlap on purpose: "SFC (CBS.log)" names the one file that
# matters, and "CBS folder" sweeps the rest. Without this, CBS.log was
# collected by both and 21.5 MB of a 48 MB collection was the same file
# twice. Keyed on the full source path, so the first source to claim a
# file wins and the later one simply finds nothing new.
$seen = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)

foreach ($s in $sources) {
    if (-not (Test-Path $s.Path)) { $missing += $s; continue }

    $item = Get-Item $s.Path -ErrorAction SilentlyContinue
    if (-not $item) { $missing += $s; continue }

    # Newest first, capped. A Windows Update folder with 47 files is not
    # worth copying whole, and the newest are the ones about this job.
    $files = if ($item.PSIsContainer) {
        @(Get-ChildItem $s.Path -File -Filter ($s.Filter) -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First $MaxFilesPerSource)
    } else { @($item) }

    if (-not $files.Count) { $missing += $s; continue }

    $sub = Join-Path $dest ($s.Tool -replace '[^\w\-]', '_')
    if (-not $WhatIfOnly) { New-Item -ItemType Directory -Path $sub -Force -ErrorAction SilentlyContinue | Out-Null }

    $tookHere = 0
    foreach ($f in $files) {
        if (-not $seen.Add($f.FullName)) { continue }   # already taken by an earlier source
        if ($f.Length -gt ($MaxFileMB * 1MB)) {
            $skipped += "$($s.Tool): $($f.Name) is $([math]::Round($f.Length/1MB,1)) MB, over the ${MaxFileMB} MB cap"
            continue
        }
        if (-not $WhatIfOnly) {
            try { Copy-Item $f.FullName (Join-Path $sub $f.Name) -Force -ErrorAction Stop }
            catch { $skipped += "$($s.Tool): $($f.Name) could not be read ($($_.Exception.Message))"; continue }
        }
        $tookHere++; $copied++; $bytes += $f.Length
    }
    if ($tookHere) {
        $found += [pscustomobject]@{ Tool = $s.Tool; Count = $tookHere; Note = $s.Note }
        Say-Good ("{0,-22} {1} file(s)" -f $s.Tool, $tookHere)
    } else { $missing += $s }
}

Write-Host ''
foreach ($m in $missing) { Say-Info ("{0,-22} nothing here" -f $m.Tool) }
if ($skipped.Count) {
    Write-Host ''
    foreach ($k in $skipped) { Say-Warn $k }
}

# An index, so the folder explains itself in six months.
if (-not $WhatIfOnly -and $copied) {
    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine("# Tool logs: $env:COMPUTERNAME")
    [void]$md.AppendLine()
    [void]$md.AppendLine("**Collected:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')  ")
    [void]$md.AppendLine("**Files:** $copied  |  **Size:** $([math]::Round($bytes/1MB,2)) MB  ")
    [void]$md.AppendLine()
    [void]$md.AppendLine('Copied from the machine, which was not modified.')
    [void]$md.AppendLine()
    [void]$md.AppendLine('## Collected')
    [void]$md.AppendLine()
    [void]$md.AppendLine('| Tool | Files | What it records |')
    [void]$md.AppendLine('|---|---|---|')
    foreach ($f in $found) { [void]$md.AppendLine("| $($f.Tool) | $($f.Count) | $($f.Note) |") }
    if ($missing.Count) {
        [void]$md.AppendLine()
        [void]$md.AppendLine('## Nothing found')
        [void]$md.AppendLine()
        [void]$md.AppendLine('Looked for these and found nothing. Absence is a finding: it usually means the tool was never run on this machine.')
        [void]$md.AppendLine()
        foreach ($m in $missing) { [void]$md.AppendLine("- **$($m.Tool)** - $($m.Note)") }
    }
    if ($skipped.Count) {
        [void]$md.AppendLine()
        [void]$md.AppendLine('## Skipped')
        [void]$md.AppendLine()
        foreach ($k in $skipped) { [void]$md.AppendLine("- $k") }
    }
    Set-Content -Path (Join-Path $dest 'index.md') -Value $md.ToString() -Encoding UTF8
}

Write-Host ''
if ($WhatIfOnly) {
    Write-Host "    WOULD collect $copied file(s), $([math]::Round($bytes/1MB,2)) MB" -ForegroundColor Yellow
    Write-Host '    Nothing was copied. Re-run without -WhatIfOnly.' -ForegroundColor DarkGray
} elseif ($copied) {
    Say-Good "collected $copied file(s), $([math]::Round($bytes/1MB,2)) MB"
    Write-Host "    Saved: $dest" -ForegroundColor DarkGray
    Write-Host '           index.md lists what was found and what was not.' -ForegroundColor DarkGray
} else {
    Say-Warn 'nothing to collect: none of the known tools have written a log on this machine'
}
exit 0
