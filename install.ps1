<#
=======================================================================
 WEB INSTALLER - HEALTH REPORT AND REPAIR

 One line, on a machine with nothing on it:

   irm https://raw.githubusercontent.com/SamuelNDCE/lazarus-toolkit/main/install.ps1 | iex

 With arguments, which `| iex` cannot pass:

   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/SamuelNDCE/lazarus-toolkit/main/install.ps1))) -WhatIfOnly

 WHAT IT DOES

 Downloads this repository as a zip, unpacks it to a temporary folder,
 and runs Tools\HealthReport\Install.ps1 from it. That installer is the thing
 that does the real work; this file only gets it onto the machine. Then
 it deletes the temporary folder.

 It installs the health report and repair tool ONLY. The ~40 third-party
 utilities the full toolkit lists are not downloaded and are not needed.

 NO ADMINISTRATOR. The install goes into %LOCALAPPDATA%. The tool
 elevates itself when it runs, which is a different thing.

 If you would rather see the code before running it, clone the repo and
 run Tools\HealthReport\Install.bat instead. That is the same install with no
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
    # Leave the unpacked copy behind and print where it is. For working
    # out why an install went wrong.
    [switch]$KeepFiles
)

$ErrorActionPreference = 'Continue'

$Owner = 'SamuelNDCE'
$Repo  = 'lazarus-toolkit'

function Say-Step($m) { Write-Host "    >>   $m" -ForegroundColor Cyan }
function Say-Good($m) { Write-Host "    ok   $m" -ForegroundColor Green }
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
function Invoke-Watched {
    param([string]$Label, [scriptblock]$Work, $Argument = $null, [int]$TimeoutSeconds = 120)

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
            Write-Host ("`r    {0}    {1}  {2}s of {3}   " -f $frames[$i % 4], $Label, $secs, $TimeoutSeconds) -NoNewline -ForegroundColor $col
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
Write-Host ''

try { New-Item -ItemType Directory -Path $work -Force -ErrorAction Stop | Out-Null }
catch { Say-Fail "could not create a staging folder: $($_.Exception.Message)"; exit 1 }

# --- Download ---------------------------------------------------------
# WebClient rather than Invoke-WebRequest: on Windows PowerShell 5.1
# Invoke-WebRequest builds the whole response in memory through the IE
# engine and is markedly slower, and it also fails outright when
# Internet Explorer has never been configured on the machine, which is
# true of most fresh Windows 11 installs.
$ok = Invoke-Watched -Label 'downloading the toolkit' -TimeoutSeconds 180 -Argument @($zipUrl, $zip) -Work {
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
    Say-Info 'a download, clone the repo and run Tools\HealthReport\Install.bat.'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
if (-not (Test-Path $zip)) {
    Say-Fail 'the download reported success but no file arrived'
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Say-Info ("{0:N0} KB downloaded" -f ((Get-Item $zip).Length / 1KB))

# --- Unpack -----------------------------------------------------------
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
    exit 1
}

# GitHub names the extracted folder <repo>-<ref>, but a ref with a slash
# in it becomes something else, so it is found rather than assumed.
$root = @(Get-ChildItem $work -Directory -ErrorAction SilentlyContinue |
          Where-Object { Test-Path (Join-Path $_.FullName 'Tools\HealthReport\Install.ps1') } |
          Select-Object -First 1)
if (-not $root.Count) {
    Say-Fail 'the download unpacked, but Tools\HealthReport\Install.ps1 is not in it'
    Say-Info "Look in $work yourself. Nothing was installed."
    exit 1
}
$installer = Join-Path $root[0].FullName 'Tools\HealthReport\Install.ps1'
Say-Good 'toolkit unpacked'

# --- Hand over --------------------------------------------------------
Write-Host ''
Say-Step 'running the installer'
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

exit $code
