<#
=======================================================================
 WEB INSTALLER - HEALTH REPORT AND REPAIR

 One line, on a machine with nothing on it:

   irm https://raw.githubusercontent.com/SamuelNDCE/lazarus-toolkit/main/install.ps1 | iex

 With arguments, which `| iex` cannot pass:

   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/SamuelNDCE/lazarus-toolkit/main/install.ps1))) -WhatIfOnly

 WHAT IT DOES

 Downloads this repository as a zip, unpacks it to a temporary folder,
 and runs Tools\Install.ps1 from it. That installer is the thing
 that does the real work; this file only gets it onto the machine. Then
 it deletes the temporary folder.

 THEN IT RUNS THE TOOL, AND OFFERS TO REMOVE IT. This is the web install
 only: the USB stick and Tools\Install.bat still just install. Someone
 who pasted the one-liner wants the report, not a second step to go and
 find. When the report window closes they are asked whether to keep the
 tool or take it off the machine again, and either way they are told how
 to get back to it. -NoRun turns all of that off and only installs.

 It installs the health report and repair tool ONLY. The ~40 third-party
 utilities the full toolkit lists are not downloaded and are not needed.

 NO ADMINISTRATOR. The install goes into %LOCALAPPDATA%. The tool
 elevates itself when it runs, which is a different thing.

 If you would rather see the code before running it, clone the repo and
 run Tools\Install.bat instead. That is the same install with no
 download step, and it is the honest recommendation: piping a URL into a
 shell is convenient and it is also trusting a web server with your
 machine.
=======================================================================
#>
param(
    [string]$Destination,
    [string]$Ref = 'main',
    [switch]$WhatIfOnly,
    [switch]$NoShortcuts,
    [switch]$NoPath,
    [switch]$Force,
    # Only install. Do not run the tool afterwards and do not ask about
    # removing it. For a scripted install, or someone who wants the old
    # behaviour.
    [switch]$NoRun,
    # Leave the unpacked copy behind and print where it is. For working
    # out why an install went wrong.
    [switch]$KeepFiles
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------
#  NEVER CALL exit IN THIS FILE.
#
#  The headline way to run this is `irm ... | iex`, and iex executes the
#  script INSIDE the caller's own session rather than in a child process.
#  So `exit` does not end the script, it ends their PowerShell, and the
#  window shuts. That happened on the SUCCESS path too, because the last
#  line of this file was `exit $code`: a completed install closed the
#  terminal before anyone could read what it had just told them.
#
#  Reported as "it runs a bunch of stuff, then it closes", which reads
#  as a crash and is the opposite of one.
#
#  Verified rather than reasoned about. Under iex:
#      exit    stops the script, KILLS the session
#      break   stops the script, KILLS the session
#      return  stops the script, session survives
#  So every early exit below is `return`, and the exit code travels in
#  $LASTEXITCODE the way a caller expects.
#
#  $PSCommandPath is empty under iex and set when the file is run
#  directly, which is how the one real `exit` at the bottom is guarded.
# ---------------------------------------------------------------------
$RanFromFile = -not [string]::IsNullOrWhiteSpace($PSCommandPath)

$Owner = 'SamuelNDCE'
$Repo  = 'lazarus-toolkit'

function Say-Step($m) { Write-Host "    >>   $m" -ForegroundColor Cyan }
function Say-Good($m) { Write-Host "    ok   $m" -ForegroundColor Green }
function Say-Warn($m) { Write-Host "    !!   $m" -ForegroundColor Yellow }
function Say-Fail($m) { Write-Host "    XX   $m" -ForegroundColor Red }
function Say-Info($m) { Write-Host "         $m" -ForegroundColor DarkGray }

# ---------------------------------------------------------------------
#  WATCHED WORK
#
#  A local copy of what Common.ps1's Spin does, because Common.ps1 is
#  inside the thing being downloaded and does not exist yet.
#
#  Every rule this project has about blocking work applies hardest here:
#  a download on a client's flaky wifi is the single most likely thing in
#  the whole toolkit to hang, and it happens on a bare console with
#  nothing else on screen. So the work goes on a runspace, an animation
#  and a climbing second count go on this thread, and the timeout is
#  enforced whether or not anything can be animated.
#
#  The no-animation branch is the one that matters. Common.ps1's Spin
#  once ran the work synchronously there with no timeout at all, so every
#  caller believed it was protected and none of them were. Redirected
#  output is exactly where a hang is hardest to spot, so it is the last
#  place to drop the protection.
# ---------------------------------------------------------------------

# ---------------------------------------------------------------------
#  PROGRESS BARS
#
#  Somebody who pasted a one-liner into a terminal and then sees a still
#  screen for ten seconds assumes it has died, and closes it. So nothing
#  in this file is allowed to be quiet for long.
#
#  Two kinds, both ASCII only (this is fetched over the web and run in
#  whatever code page the person's console happens to use):
#
#    Show-Stage    the whole job as a filling bar, "step 2 of 5"
#    Get-Bounce    for a wait of unknown length, a block sliding to and
#                  fro. It cannot say how long is left, because nothing
#                  knows, but it is unmistakably moving.
# ---------------------------------------------------------------------
$StageTotal = 5

function Show-Stage([int]$n, [string]$label) {
    $w = 30
    $filled = [int][math]::Floor($w * $n / $StageTotal)
    $bar = ('#' * $filled) + ('-' * ($w - $filled))
    Write-Host ''
    Write-Host ("    [{0}]  step {1} of {2}: {3}" -f $bar, $n, $StageTotal, $label) -ForegroundColor Cyan
}

function Get-Bounce([int]$i, [int]$width = 14, [int]$block = 4) {
    $span = $width - $block
    $pos = $i % (2 * $span)
    if ($pos -gt $span) { $pos = 2 * $span - $pos }
    return (' ' * $pos) + ('#' * $block) + (' ' * ($span - $pos))
}

function Invoke-Watched {
    # -Detail is run on THIS thread every frame and its text is shown at
    # the end of the line, so the download can show its size climbing.
    param([string]$Label, [scriptblock]$Work, $Argument = $null, [int]$TimeoutSeconds = 120, [scriptblock]$Detail = $null)

    $canAnimate = $true
    try { if ([Console]::IsOutputRedirected) { $canAnimate = $false } } catch { $canAnimate = $false }

    $ps = [PowerShell]::Create()
    [void]$ps.AddScript($Work)
    [void]$ps.AddArgument($Argument)
    $handle = $ps.BeginInvoke()

    if (-not $canAnimate) {
        Write-Host "    ..   $Label" -ForegroundColor DarkGray
        if ($handle.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            try { return $ps.EndInvoke($handle) } catch { return $null } finally { $ps.Dispose() }
        }
        Say-Fail "'$Label' gave up after ${TimeoutSeconds}s"
        try { $ps.Stop() } catch { }
        try { $ps.Dispose() } catch { }
        return $null
    }

    $frames = '|', '/', '-', '\'
    $i = 0
    $t0 = Get-Date
    $timedOut = $false
    $result = $null
    # Warn at half the allowance, so a slow download stops looking like a
    # freeze while it is still only slow.
    $slowAt = [int]($TimeoutSeconds / 2)
    $warned = $false

    try {
        while (-not $handle.IsCompleted) {
            $secs = [int]((Get-Date) - $t0).TotalSeconds
            if ($secs -ge $TimeoutSeconds) { $timedOut = $true; break }
            if (-not $warned -and $secs -ge $slowAt) {
                $warned = $true
                Write-Host ("`r{0}`r" -f (' ' * 78)) -NoNewline
                Write-Host ("    !!    '{0}' is taking longer than expected (will give up at ${TimeoutSeconds}s)" -f $Label) -ForegroundColor Yellow
            }
            $col = if ($warned) { 'Yellow' } else { 'Cyan' }
            $extra = ''
            if ($Detail) { try { $extra = '  ' + [string](& $Detail) } catch { $extra = '' } }
            # Kept under 78 columns so the carriage-return redraw never
            # wraps on an 80-column console, where a wrapped line turns
            # into a scrolling mess instead of a bar.
            Write-Host ("`r    [{0}] {1} {2}  {3}s{4}   " -f (Get-Bounce $i), $frames[$i % 4], $Label, $secs, $extra) -NoNewline -ForegroundColor $col
            Start-Sleep -Milliseconds 120
            $i++
        }
        if ($timedOut) { $ps.Stop() } else { $result = $ps.EndInvoke($handle) }
    } catch {
        Write-Host ''
        Say-Fail "$Label failed: $($_.Exception.Message)"
        return $null
    } finally { $ps.Dispose() }

    Write-Host ("`r{0}`r" -f (' ' * 78)) -NoNewline
    if ($timedOut) {
        Say-Fail "$Label did not finish in ${TimeoutSeconds}s"
        return $null
    }
    Say-Good ("{0}  ({1}s)" -f $Label, [int]((Get-Date) - $t0).TotalSeconds)
    return $result
}

# ---------------------------------------------------------------------
Write-Host ''
Write-Host '    +--------------------------------------------------------+' -ForegroundColor Cyan
Write-Host '    |  HEALTH REPORT AND REPAIR - web installer              |' -ForegroundColor Cyan
Write-Host '    +--------------------------------------------------------+' -ForegroundColor Cyan
Write-Host ''

# Windows PowerShell 5.1 still defaults to TLS 1.0 on plenty of machines,
# and GitHub refuses that outright. The failure it produces is
# "The request was aborted: Could not create SSL/TLS secure channel",
# which reads like a firewall or a proxy and is neither.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$zipUrl = "https://github.com/$Owner/$Repo/archive/refs/heads/$Ref.zip"
$work   = Join-Path $env:TEMP ("hrr-install-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$zip    = Join-Path $work 'toolkit.zip'

Say-Info "Source:  $zipUrl"
Say-Info "Staging: $work"

# Decided up front, so the step counter can be honest about how many steps
# there are. Whether the tool will be run afterwards depends only on
# things known now, except the "did anything actually get installed"
# check, which is made after the install and can still skip it.
$interactive = $true
try { if ([Console]::IsInputRedirected) { $interactive = $false } } catch { $interactive = $false }
$wantRun = (-not $NoRun) -and (-not $WhatIfOnly) -and $interactive
$StageTotal = if ($wantRun) { 5 } else { 3 }

try { New-Item -ItemType Directory -Path $work -Force -ErrorAction Stop | Out-Null }
catch {
    Say-Fail "could not create a staging folder: $($_.Exception.Message)"
    $global:LASTEXITCODE = 1; return
}

# --- Download ---------------------------------------------------------
# WebClient rather than Invoke-WebRequest: on Windows PowerShell 5.1
# Invoke-WebRequest builds the whole response in memory through the IE
# engine and is markedly slower, and it also fails outright when
# Internet Explorer has never been configured on the machine, which is
# true of most fresh Windows 11 installs.
Show-Stage 1 'downloading'
$ok = Invoke-Watched -Label 'downloading the toolkit' -TimeoutSeconds 180 -Argument @($zipUrl, $zip) `
    -Detail { if (Test-Path $zip) { '{0:N0} KB' -f ((Get-Item $zip).Length / 1KB) } } -Work {
    param($a)
    $client = New-Object System.Net.WebClient
    $client.Headers.Add('User-Agent', 'health-report-installer')
    try { $client.DownloadFile($a[0], $a[1]); return $true }
    catch { return $_.Exception.Message }
    finally { $client.Dispose() }
}
if ($ok -ne $true) {
    Say-Fail "download failed: $(if ($ok) { $ok } else { 'no response' })"
    Say-Info 'Check the machine is online, then try again. To install without'
    Say-Info 'a download, clone the repo and run Tools\Install.bat.'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 1; return
}
if (-not (Test-Path $zip)) {
    Say-Fail 'the download reported success but no file arrived'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 1; return
}
Say-Info ("{0:N0} KB downloaded" -f ((Get-Item $zip).Length / 1KB))

# --- Unpack -----------------------------------------------------------
Show-Stage 2 'unpacking'
$ok = Invoke-Watched -Label 'unpacking' -TimeoutSeconds 120 -Argument @($zip, $work) -Work {
    param($a)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($a[0], $a[1])
        return $true
    } catch { return $_.Exception.Message }
}
if ($ok -ne $true) {
    Say-Fail "unpacking failed: $(if ($ok) { $ok } else { 'no response' })"
    Say-Info "The zip is at $zip if you want to open it by hand."
    $global:LASTEXITCODE = 1; return
}

# GitHub names the extracted folder <repo>-<ref>, but a ref with a slash
# in it becomes something else, so it is found rather than assumed.
$root = @(Get-ChildItem $work -Directory -ErrorAction SilentlyContinue |
          Where-Object { Test-Path (Join-Path $_.FullName 'Tools\Install.ps1') } |
          Select-Object -First 1)
if (-not $root.Count) {
    Say-Fail 'the download unpacked, but Tools\Install.ps1 is not in it'
    Say-Info "Look in $work yourself. Nothing was installed."
    $global:LASTEXITCODE = 1; return
}
$installer = Join-Path $root[0].FullName 'Tools\Install.ps1'
Say-Good 'toolkit unpacked'

# --- Hand over --------------------------------------------------------
Show-Stage 3 'installing'
Write-Host ''

# Forwarded explicitly rather than through @PSBoundParameters, which
# would also forward -Ref and -KeepFiles and make Install.ps1 fail on
# parameters it does not have.
$forward = @{}
if ($Destination) { $forward['Destination'] = $Destination }
if ($WhatIfOnly)  { $forward['WhatIfOnly']  = $true }
if ($NoShortcuts) { $forward['NoShortcuts'] = $true }
if ($NoPath)      { $forward['NoPath']      = $true }
if ($Force)       { $forward['Force']       = $true }

# Where Tools\Install.ps1 puts it by default. Duplicated here rather than
# read back, because the installer does not report its destination.
$installDir = if ($Destination) { $Destination } else { Join-Path $env:LOCALAPPDATA (Join-Path 'Programs' 'Health Report and Repair') }

# When was the manifest last written? If the installer answers "already
# installed, overwrite?" with a no, it exits 0 having changed nothing, and
# that must not be mistaken for a fresh install worth running.
$manifestFile = Join-Path $installDir 'installed.json'
$manifestBefore = $null
if (Test-Path $manifestFile) { $manifestBefore = (Get-Item $manifestFile).LastWriteTimeUtc }

& $installer @forward
$code = $LASTEXITCODE
if ($null -eq $code) { $code = 0 }

# --- Tidy up ----------------------------------------------------------
if ($KeepFiles) {
    Say-Info "Unpacked copy kept at $($root[0].FullName)"
} else {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $work) { Say-Info "Could not clear $work. It is only a temp folder; delete it whenever." }
}

# --- Run it, then offer to remove it ----------------------------------
# Skipped, and the install left exactly as it was, for anything that is
# not a person at a keyboard finishing a fresh install: a failed install,
# a what-if, -NoRun, redirected input (a prompt would hang forever), or an
# install the person declined to overwrite.
$freshInstall = $false
if (Test-Path $manifestFile) {
    $manifestAfter = (Get-Item $manifestFile).LastWriteTimeUtc
    $freshInstall = ($null -eq $manifestBefore) -or ($manifestAfter -gt $manifestBefore)
}
$toolScript = Join-Path $installDir 'Health-Report.ps1'

if ($code -eq 0 -and $wantRun -and $freshInstall -and (Test-Path $toolScript)) {
    Show-Stage 4 'running the report'
    Write-Host ''
    Say-Info 'Windows will ask for administrator, say yes. The report opens in its'
    Say-Info 'own window. Come back to this one when you are done with it.'
    Write-Host ''

    # Started here rather than through Health-Report.bat, and NOT with a
    # plain powershell.exe:
    #
    #  - The .bat hands off to Windows Terminal and returns at once, so
    #    waiting on it would come back while the report was still on screen.
    #  - A bare elevated powershell.exe opens the old console host, which
    #    is the navy blue box that is hard to read. The report belongs in
    #    Windows Terminal, the same as it opens from the .bat and the
    #    Start menu shortcut.
    #
    # Windows Terminal's wt.exe returns in a fraction of a second while its
    # window lives on, so there is no process to wait for. The window
    # therefore reports on itself instead: it drops a heartbeat file every
    # two seconds from a background thread, and a done file when the tool
    # ends. This side watches both. A window closed with the X never writes
    # done, but its heartbeat stops, which is noticed. The bouncing bar and
    # the clock are the proof it is alive.
    #
    # The wrapper travels as an inline -EncodedCommand, not a script file:
    # a file in a user-writable temp folder that is then run ELEVATED is
    # one that anything else running as this user could swap in between.
    #
    # No overall timeout, deliberately: the person is reading a report and
    # choosing repairs, which can take an hour. Only the START is timed.
    $useWt = [bool](Get-Command wt.exe -ErrorAction SilentlyContinue)
    $runDir    = Join-Path $env:TEMP ('hrr-run-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $doneFile  = Join-Path $runDir 'done.txt'
    $aliveFile = Join-Path $runDir 'alive.txt'
    $launchTool = $toolScript
    $ran = $true
    $proc = $null
    try {
        New-Item -ItemType Directory -Path $runDir -Force -ErrorAction Stop | Out-Null
$wrapperTemplate = @'
$RunDir = '@@RUNDIR@@'
$Tool = '@@TOOL@@'
$hb = [PowerShell]::Create()
[void]$hb.AddScript({ param($d) while ($true) { try { [IO.File]::WriteAllText((Join-Path $d 'alive.txt'), 'x') } catch { } Start-Sleep -Seconds 2 } }).AddArgument($RunDir)
[void]$hb.BeginInvoke()
& $Tool
try { [IO.File]::WriteAllText((Join-Path $RunDir 'done.txt'), 'done') } catch { }
'@
        $wrapper = $wrapperTemplate.Replace('@@RUNDIR@@', $runDir.Replace("'", "''")).Replace('@@TOOL@@', $launchTool.Replace("'", "''"))
        $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($wrapper))
        $psArgs = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc"
        if ($useWt) {
            $proc = Start-Process -FilePath 'wt.exe' -ArgumentList "--title `"Health Report and Repair`" powershell $psArgs" `
                -WorkingDirectory $installDir -Verb RunAs -PassThru -ErrorAction Stop
        } else {
            $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs `
                -WorkingDirectory $installDir -Verb RunAs -PassThru -ErrorAction Stop
        }
    } catch {
        $ran = $false
        Say-Warn 'the report did not start (administrator was declined, or Windows refused)'
        Say-Info $_.Exception.Message
    }

    $tracked = $false
    if ($ran) {
        try {
            $animate = $true
            try { if ([Console]::IsOutputRedirected) { $animate = $false } } catch { $animate = $false }
            if (-not $animate) { Say-Info 'waiting for the report window to close' }
            $frames = '|', '/', '-', '\'
            $i = 0
            $t0 = Get-Date
            $lastTick = $t0
            while (-not (Test-Path $doneFile)) {
                $now = Get-Date
                # A gap far longer than one frame means this machine was
                # asleep, and the heartbeat looks stale for that reason
                # only, so that pass is not allowed to declare it gone.
                $wasAsleep = (($now - $lastTick).TotalSeconds -gt 5)
                $lastTick = $now

                # The plain powershell.exe path has a real process to ask.
                if (-not $useWt -and $proc) {
                    $exited = $false
                    try { $exited = $proc.HasExited } catch { }
                    if ($exited) { break }
                }

                if (Test-Path $aliveFile) {
                    try {
                        $age = ([DateTime]::UtcNow - (Get-Item $aliveFile -ErrorAction Stop).LastWriteTimeUtc).TotalSeconds
                        if (-not $wasAsleep -and $age -gt 20) { break }
                    } catch { }
                } elseif (($now - $t0).TotalSeconds -gt 45) {
                    throw 'the report window never reported in'
                }

                if ($animate) {
                    $el = $now - $t0
                    Write-Host ("`r    [{0}] {1} report window open  {2:00}:{3:00}  (close it to continue)   " -f (Get-Bounce $i), $frames[$i % 4], [int][math]::Floor($el.TotalMinutes), $el.Seconds) -NoNewline -ForegroundColor Cyan
                }
                Start-Sleep -Milliseconds 150
                $i++
            }
            if ($animate) { Write-Host ("`r{0}`r" -f (' ' * 78)) -NoNewline }
            $tracked = $true
        } catch {
            # Never an error the person has to read: fall back to asking.
        }
    }
    Remove-Item $runDir -Recurse -Force -ErrorAction SilentlyContinue
    if ($ran -and -not $tracked) {
        Write-Host ''
        Say-Info 'This window cannot follow the report from here.'
        Read-Host '         Press Enter here once you have closed the report window' | Out-Null
    }

    Write-Host ''
    if ($ran) { Say-Good 'the report window has closed' }

    Show-Stage 5 'keep it, or remove it'
    Write-Host ''
    $answer = Read-Host '         Remove Health Report and Repair from this PC now? (y/n)'
    Write-Host ''

    $removed = $false
    if ($answer -match '^[Yy]') {
        $uninstaller = Join-Path $installDir 'Uninstall.ps1'
        if (Test-Path $uninstaller) {
            # Uninstall.ps1 moves this session's location to Documents so it
            # can delete its own folder. That would leave the person's
            # terminal somewhere they never went, so it is put back.
            Push-Location
            try { & $uninstaller -Confirm } finally { Pop-Location }
            $removed = -not (Test-Path $toolScript)
        } else {
            Say-Warn "Uninstall.ps1 is not in $installDir, so nothing was removed."
        }
    }

    Write-Host ''
    if ($removed) {
        Say-Good 'removed. Saved reports are kept, not deleted.'
        Say-Info 'To get it back, run this again:'
        Say-Info "irm https://raw.githubusercontent.com/$Owner/$Repo/main/install.ps1 | iex"
    } else {
        Say-Good 'kept.'
        if (-not $NoPath)      { Say-Info 'To run it again, open a terminal and type:  health-report' }
        if (-not $NoShortcuts) { Say-Info 'Or search "Health Report" in the Start menu.' }
        Say-Info 'To remove it later: Settings > Apps > Installed apps > Health Report and Repair.'
    }
    Write-Host ''
}

# Set the code either way, so a caller that checks $LASTEXITCODE still
# gets the truth, then only really exit when this was run as a file.
$global:LASTEXITCODE = $code
if ($RanFromFile) { exit $code }
