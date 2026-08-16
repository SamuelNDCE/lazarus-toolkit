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
    [int]$MaxFilesPerSource = 5,
    # Override the manifest below. Only a test passes this: the real
    # sources are absolute system paths, so without a seam the only way
    # to exercise the copying, the cap and the dedup is to have
    # Malwarebytes and a damaged component store on the machine running
    # the tests. Same reasoning as Get-ReportPath's -PrimaryDir.
    #
    # NOT named $Sources. PowerShell variables are case insensitive, so a
    # parameter by that name and the $sources below are the same variable
    # and the manifest would silently overwrite whatever was passed in.
    [array]$SourceList
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
# Recurse = $true for the places that keep their logs one or two folders
# down. Panther and WER are both like this: the top level is empty and
# everything of interest is in a subfolder, so a non-recursive read
# reported "nothing here" on a machine that had a failed feature update
# and four application crashes sitting one directory below.
$sources = if ($SourceList) { $SourceList } else { @(
    # --- what our own repairs left behind ----------------------------
    @{ Tool = 'SFC (CBS.log)';        Path = "$env:WINDIR\Logs\CBS\CBS.log";                            Note = 'what SFC actually found and repaired' }
    @{ Tool = 'DISM';                 Path = "$env:WINDIR\Logs\DISM\dism.log";                          Note = 'component store servicing' }
    @{ Tool = 'DISM folder';          Path = "$env:WINDIR\Logs\DISM";                   Filter = '*.log'; Note = 'older DISM logs' }
    @{ Tool = 'CBS folder';           Path = "$env:WINDIR\Logs\CBS";                    Filter = '*.log'; Note = 'older CBS logs' }

    # --- Windows servicing and update --------------------------------
    @{ Tool = 'Windows Update';       Path = "$env:WINDIR\Logs\WindowsUpdate";          Filter = '*';     Note = 'update client traces' }
    @{ Tool = 'Update medic';         Path = "$env:WINDIR\Logs\waasmedic";              Filter = '*';     Note = 'what repaired a broken Windows Update, and why' }
    @{ Tool = 'Update session (SIH)'; Path = "$env:WINDIR\Logs\SIH";                    Filter = '*';     Note = 'server-initiated healing sessions' }
    @{ Tool = 'Feature update';       Path = "$env:WINDIR\Logs\MoSetup";                Filter = '*';     Note = 'whether this PC was allowed to upgrade' }
    @{ Tool = 'Setup / SetupDiag';    Path = "$env:WINDIR\Logs\SetupDiag";              Filter = '*';     Note = 'failed feature updates' }
    # setupact.log and setuperr.log are the record of an upgrade that
    # rolled back, which is one of the commonest reasons a secondhand
    # machine arrives stuck on an old build.
    @{ Tool = 'Setup (Panther)';      Path = "$env:WINDIR\Panther";                     Filter = '*.log'; Recurse = $true; Note = 'Windows setup and upgrade, including rollbacks' }

    # --- drivers and hardware ----------------------------------------
    # The single most useful file when a driver install has gone wrong,
    # and the natural companion to a DDU run. Often large, in which case
    # it is skipped with its size stated rather than dropped in silence.
    @{ Tool = 'Driver installs';      Path = "$env:WINDIR\INF\setupapi.dev.log";                        Note = 'every driver install and removal, in order' }
    @{ Tool = 'DDU';                  Path = "$env:SystemDrive\DDU\Logs";               Filter = '*';     Note = 'display driver removal' }
    @{ Tool = 'RAPR / DriverStore';   Path = "$env:SystemDrive\DriverStoreExplorer";    Filter = '*';     Note = 'driver package removals' }
    # A crash dump is the difference between "it blue screens sometimes"
    # and knowing which driver did it.
    @{ Tool = 'Blue screen dumps';    Path = "$env:WINDIR\Minidump";                    Filter = '*.dmp'; Note = 'which driver caused each blue screen' }

    # --- crashes and reliability -------------------------------------
    @{ Tool = 'App crash reports';    Path = "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"; Filter = '*.wer'; Recurse = $true; Note = 'what crashed, and with which fault module' }

    # --- antivirus and cleanup tools ---------------------------------
    # Needs administrator to read, which is why the tool elevates.
    @{ Tool = 'Defender';             Path = "$env:ProgramData\Microsoft\Windows Defender\Support"; Filter = '*.log'; Note = 'scan history and detections' }
    @{ Tool = 'Malwarebytes';         Path = "$env:ProgramData\Malwarebytes\MBAMService\logs";     Filter = '*'; Note = 'service and protection logs' }
    @{ Tool = 'Malwarebytes scans';   Path = "$env:ProgramData\Malwarebytes\MBAMService\ScanResults"; Filter = '*'; Note = 'what each scan found' }
    # ADWCleaner moved. Older builds write to the root of C:, current
    # ones to ProgramData, and which one a machine has depends on the
    # version somebody ran on it. Both are looked for.
    @{ Tool = 'ADWCleaner';           Path = "$env:SystemDrive\AdwCleaner\Logs";        Filter = '*';     Note = 'adware and hijack removals' }
    @{ Tool = 'ADWCleaner (new)';     Path = "$env:ProgramData\AdwCleaner";             Filter = '*';     Recurse = $true; Note = 'adware and hijack removals, newer versions' }
    @{ Tool = 'KVRT';                 Path = "$env:SystemDrive\KVRT_Data\Reports";      Filter = '*';     Note = 'Kaspersky removal tool findings' }

    # --- everything else on the stick --------------------------------
    @{ Tool = 'OCCT';                 Path = "$env:USERPROFILE\Documents\OCCT";         Filter = '*';     Recurse = $true; Note = 'stress test results' }
    @{ Tool = 'Win11Debloat';         Path = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Win11Debloat\Logs'); Filter = '*'; Note = 'what was removed' }
    # Two locations for the same reason as ADWCleaner: it has used both.
    @{ Tool = 'BCUninstaller';        Path = "$env:LOCALAPPDATA\BCUninstaller";         Filter = '*.log'; Note = 'bulk uninstall record' }
    @{ Tool = 'BCUninstaller (user)'; Path = "$env:APPDATA\BCUninstaller";              Filter = '*.log'; Note = 'bulk uninstall record' }
    @{ Tool = 'BleachBit';            Path = "$env:APPDATA\BleachBit";                  Filter = '*.log'; Note = 'what was cleaned' }
) }

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

# "Nothing here" and "I was not allowed to look" are completely different
# statements, and reporting the second as the first is a lie in the one
# direction that matters. Defender's Support folder, WER\ReportArchive
# and parts of Panther are all readable only by an administrator: run
# unelevated and they enumerate as empty with no error at all, so the
# index said "Defender left no log, which usually means it was never run"
# about a machine that had been scanning daily for two years.
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$denied = @()

foreach ($s in $sources) {
    if (-not (Test-Path $s.Path)) { $missing += $s; continue }

    $item = Get-Item $s.Path -ErrorAction SilentlyContinue
    if (-not $item) { $missing += $s; continue }

    # Newest first, capped. A Windows Update folder with 47 files is not
    # worth copying whole, and the newest are the ones about this job.
    #
    # -Recurse only where the manifest asks for it. Turning it on
    # everywhere would walk %WINDIR%\INF and %ProgramData% whole, which
    # takes minutes and returns thousands of files to then throw away.
    #
    # No `continue` inside this assignment: `if` here is an EXPRESSION
    # whose value becomes $files, and a `continue` buried in an
    # expression jumps out of the foreach with $files still holding the
    # PREVIOUS source's file list. Straightforward to write by accident
    # and very hard to see afterwards. The decision is made below, on
    # plain variables.
    $walkErr = $null
    $files = if ($item.PSIsContainer) {
        $walk = @{ Path = $s.Path; File = $true; ErrorAction = 'SilentlyContinue' }
        if ($s.Filter)  { $walk['Filter']  = $s.Filter }
        if ($s.Recurse) { $walk['Recurse'] = $true }
        # The access error is captured rather than discarded, so an empty
        # result can be told apart from a refused one.
        @(Get-ChildItem @walk -ErrorVariable walkErr |
          Sort-Object LastWriteTime -Descending | Select-Object -First $MaxFilesPerSource)
    } else { @($item) }

    if (-not $files.Count) {
        # Refused, or genuinely empty? Two signals, because neither is
        # reliable alone: an explicit UnauthorizedAccessException when
        # Windows raises one, and the fact that these particular folders
        # are administrator-only and we are not an administrator, for
        # when it enumerates as empty and raises nothing at all.
        $refused = @($walkErr | Where-Object { $_.Exception -is [System.UnauthorizedAccessException] }).Count -gt 0
        if (-not $refused -and -not $isAdmin -and $item.PSIsContainer) {
            $refused = ($s.Path -match 'Windows Defender|\\WER\\|\\Panther')
        }
        if ($refused) { $denied += $s } else { $missing += $s }
        continue
    }

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
            # A recursive source flattens several folders into one, and
            # those folders routinely hold files of the SAME name:
            # WER\ReportArchive has a Report.wer in every subfolder, and
            # Panther keeps a setupact.log per attempt. Copying on name
            # alone means each one overwrites the last and a collection
            # of nine crash reports arrives as one, with the index
            # cheerfully claiming nine were taken.
            $leaf = $f.Name
            $to   = Join-Path $sub $leaf
            if (Test-Path $to) {
                $base = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
                $ext  = [System.IO.Path]::GetExtension($leaf)
                $n = 2
                while (Test-Path $to) { $to = Join-Path $sub ("$base($n)$ext"); $n++ }
            }
            try { Copy-Item $f.FullName $to -Force -ErrorAction Stop }
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
if ($denied.Count) {
    Write-Host ''
    foreach ($d in $denied) { Say-Warn ("{0,-22} needs administrator, not read" -f $d.Tool) }
    if (-not $isAdmin) {
        Say-Info 'Run this from Health-Report.bat, which elevates, to include these.'
    }
}
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
    if ($denied.Count) {
        [void]$md.AppendLine()
        [void]$md.AppendLine('## Not readable')
        [void]$md.AppendLine()
        [void]$md.AppendLine('These exist but were not read. That is a permissions limit, NOT a finding about the machine: do not read it as "this tool was never run here".')
        [void]$md.AppendLine()
        foreach ($d in $denied) { [void]$md.AppendLine("- **$($d.Tool)** - $($d.Note)") }
        if (-not $isAdmin) {
            [void]$md.AppendLine()
            [void]$md.AppendLine('Collected without administrator rights. Re-run from `Health-Report.bat` to include them.')
        }
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
