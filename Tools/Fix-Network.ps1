<#
=======================================================================
 FIX-NETWORK  -  the Wi-Fi adapter that DISAPPEARS, not the one that
                 merely fails to connect

     Run it from the stick, on the affected laptop. Needs administrator.

 WHAT THIS IS FOR, AND WHAT IT IS NOT FOR

 The symptom this was built for, reported 2026-08-23 on an ASUS
 Vivobook X1504VA: the whole Wi-Fi section vanishes out of Windows
 Settings, and comes back on its own after ten minutes to an hour.

 That is NOT the same fault as "cannot see the network" or "will not
 connect". If the Wi-Fi page is still there and the network list is
 still drawn, the adapter is present and this is the wrong tool. When
 the PAGE ITSELF goes, the WLAN device has left the device tree, and
 Windows removes the page because there is no longer a radio to draw a
 page for. A device leaving the tree on its own is a power or PCIe link
 problem, not a networking problem, which is why nothing in the usual
 "reset your network" advice touches it.

 So the fixes below are aimed at the device staying PRESENT:
 link state power management, adapter power-down, wireless radio power
 saving, fast startup, and the driver's own power-saving keywords.

 EVERYTHING IS RECORDED BEFORE IT IS CHANGED

 The old Fix-WiFi reset the network stack and printed "any static IP,
 custom DNS or proxy settings have been cleared" without ever recording
 what they had been, so a machine with a static address could not be put
 back. Every value this script changes is written into the log first,
 with the exact command to put it back.

 WHAT IS DELIBERATELY NOT AUTOMATIC

 Three things are queued as questions at the END of the run, never in
 the middle: disabling the Wi-Fi Direct virtual adapter (it costs
 Miracast and Mobile Hotspot), the network stack reset (heavier, and
 needs its before-state recorded), and the reboot. A script may ask
 before it starts or after it finishes, never in between.
=======================================================================
#>
param(
    # Report and record, change nothing. Used by the build test, and
    # worth having on a machine you have not seen before.
    [switch]$DryRun,
    # No questions at the end. The safe reading of an unanswered
    # question is always no, and Invoke-Deferred says what it skipped.
    [switch]$Unattended
)

$ErrorActionPreference = 'Continue'

# --- console appearance ----------------------------------------------
# Set on entry rather than by the caller: this can be started from the
# Lazarus UI, the .bat, a desktop shortcut or an open console, and each
# arrives with different colours.
try {
    $H = $Host.UI.RawUI
    $H.BackgroundColor = 'Black'
    $H.ForegroundColor = 'Gray'
    if ($H.WindowSize.Width -lt 100) {
        $max = $H.MaxPhysicalWindowSize
        $b = $H.BufferSize; $b.Width = [Math]::Min(100, $max.Width); $H.BufferSize = $b
        $w = $H.WindowSize; $w.Width = [Math]::Min(100, $max.Width); $H.WindowSize = $w
    }
    Clear-Host
} catch { }

$Log = New-Object System.Collections.ArrayList

# ---------------------------------------------------------------------
#  COMMON.PS1
#
#  Loaded for Spin (spinner + hard timeout), Defer/Invoke-Deferred and
#  Show-Box. It is dot-sourced rather than copied because two copies of
#  "show the user something is happening" drift, which this toolkit has
#  already had happen once.
#
#  It degrades instead of refusing to start. If this file has been
#  copied somewhere without Common.ps1 beside it, a shim keeps the tool
#  usable: no animation, but the work still runs and still prints. The
#  shim keeps the TIMEOUT, because a shim that silently dropped it would
#  recreate the exact bug Spin was rewritten to fix.
# ---------------------------------------------------------------------
$commonPath = Join-Path $PSScriptRoot 'Common.ps1'
$Script:HaveCommon = $false
if (Test-Path $commonPath) {
    try { . $commonPath; $Script:HaveCommon = $true } catch { }
}

if (-not $Script:HaveCommon) {
    Write-Host '  Common.ps1 was not found beside this script.' -ForegroundColor Yellow
    Write-Host '  Running in reduced mode: no spinner, timeouts still enforced.' -ForegroundColor DarkGray
    $Script:Deferred = New-Object System.Collections.ArrayList
    $Script:CanAnimate = $false
    function Spin {
        param([string]$Label, [scriptblock]$Work, $Argument = $null, [int]$TimeoutSeconds = 0)
        Write-Host "    ..   $Label" -ForegroundColor DarkGray
        if ($TimeoutSeconds -le 0) { return (& $Work $Argument) }
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript($Work); [void]$ps.AddArgument($Argument)
        $h = $ps.BeginInvoke()
        if ($h.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            try { return $ps.EndInvoke($h) } catch { return $null } finally { try { $ps.Dispose() } catch { } }
        }
        Write-Host "    !!   '$Label' gave up after ${TimeoutSeconds}s and was skipped" -ForegroundColor Yellow
        try { $ps.Stop() } catch { }; try { $ps.Dispose() } catch { }
        return $null
    }
    function Defer($Question, [scriptblock]$Action, $Detail = $null) {
        [void]$Script:Deferred.Add([pscustomobject]@{ Q = $Question; Do = $Action; Detail = $Detail })
        Write-Host '         noted, you will be asked at the end so this can finish first' -ForegroundColor DarkGray
    }
    function Invoke-Deferred {
        if (-not $Script:Deferred.Count) { return }
        if ($Script:Unattended) {
            Write-Host ''
            Write-Host "  $($Script:Deferred.Count) thing(s) needed an answer and were SKIPPED (unattended)" -ForegroundColor Yellow
            foreach ($d in $Script:Deferred) { Write-Host "         not asked: $($d.Q)" -ForegroundColor DarkGray }
            return
        }
        Write-Host ''
        Write-Host "  $($Script:Deferred.Count) thing(s) need your answer" -ForegroundColor Cyan
        Write-Host '         Nothing below has happened yet.' -ForegroundColor DarkGray
        foreach ($d in $Script:Deferred) {
            Write-Host ''
            if ($d.Detail) { Write-Host "         $($d.Detail)" -ForegroundColor DarkGray }
            if ((Read-Host "    $($d.Q) (y/n)") -match '^y') {
                try { & $d.Do } catch { Write-Host "    !!   that failed: $($_.Exception.Message)" -ForegroundColor Yellow }
            } else { Write-Host '         Skipped.' -ForegroundColor DarkGray }
        }
    }
    function Show-Box {
        param([string]$Colour = 'Cyan', [string[]]$Lines)
        $w = (($Lines | Measure-Object -Property Length -Maximum).Maximum) + 4
        Write-Host ''
        Write-Host ('  +' + ('-' * $w) + '+') -ForegroundColor $Colour
        foreach ($l in $Lines) { Write-Host ('  |  ' + $l.PadRight($w - 4) + '  |') -ForegroundColor $Colour }
        Write-Host ('  +' + ('-' * $w) + '+') -ForegroundColor $Colour
    }
}

$Script:SpinLog     = $Log
$Script:Unattended  = [bool]$Unattended

# ---------------------------------------------------------------------
#  OUTPUT HELPERS
#
#  Everything printed is also appended to $Log, so the saved file and
#  the screen can never disagree about what was found.
# ---------------------------------------------------------------------
function Head($t) {
    Write-Host ''
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host "  $('-' * $t.Length)" -ForegroundColor DarkCyan
    [void]$Log.Add(''); [void]$Log.Add("  $t"); [void]$Log.Add("  $('-' * $t.Length)")
}
function OK($m)   { Write-Host "    ok   $m" -ForegroundColor Green;      [void]$Log.Add("  ok   $m") }
function Warn($m) { Write-Host "    !!   $m" -ForegroundColor Yellow;     [void]$Log.Add("  !!   $m") }
function Bad($m)  { Write-Host "    XX   $m" -ForegroundColor Red;        [void]$Log.Add("  XX   $m") }
function Info($m) { Write-Host "         $m" -ForegroundColor DarkGray;   [void]$Log.Add("       $m") }
function Did($m)  { Write-Host "    ->   $m" -ForegroundColor Cyan;       [void]$Log.Add("  ->   $m") }
function LogOnly($m) { [void]$Log.Add($m) }

# Undo lines are collected as they are earned, then written into the log
# in one block. A change recorded with no way back is the gap that lost
# a machine's static addressing once already.
$Undo = New-Object System.Collections.ArrayList
function AddUndo($what, $cmd) {
    [void]$Undo.Add([pscustomobject]@{ What = $what; Cmd = $cmd })
}

# Deferred questions have to honour -DryRun too, and the first version
# of this did not: the questions were still queued, so answering yes to
# "reset the network stack" during a DRY RUN would have reset it for
# real. A dry run that can change something is not a dry run. Caught by
# running one, not by reading it.
function AskLater($Question, [scriptblock]$Action, $Detail = $null) {
    if ($DryRun) {
        Write-Host "    --   WOULD OFFER: $Question" -ForegroundColor DarkYellow
        [void]$Log.Add("  --   WOULD OFFER: $Question")
        return
    }
    Defer $Question $Action $Detail
}

# A single place that decides whether a change actually happens, so
# -DryRun cannot be honoured by some fixes and forgotten by others.
function Apply($Description, [scriptblock]$Action, $UndoCmd = $null) {
    if ($DryRun) {
        Write-Host "    --   WOULD: $Description" -ForegroundColor DarkYellow
        [void]$Log.Add("  --   WOULD: $Description")
        return $true
    }
    try {
        & $Action
        Did $Description
        if ($UndoCmd) { AddUndo $Description $UndoCmd }
        return $true
    } catch {
        Warn "could not: $Description  ($($_.Exception.Message))"
        return $false
    }
}

# ---------------------------------------------------------------------
$machine = $env:COMPUTERNAME
$started = Get-Date

Show-Box -Colour Cyan -Lines @(
    'FIX NETWORK'
    'For a Wi-Fi adapter that DISAPPEARS from Windows'
    "$machine   $($started.ToString('yyyy-MM-dd HH:mm'))"
)
if ($DryRun) {
    Show-Box -Colour Yellow -Lines @('DRY RUN', 'Nothing will be changed. Reporting only.')
}

LogOnly "FIX NETWORK   $machine   $($started.ToString('yyyy-MM-dd HH:mm'))"
LogOnly ("mode: " + $(if ($DryRun) { 'DRY RUN, no changes' } else { 'live, changes will be made' }))

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# A LIVE run without admin cannot do its job and must stop. A DRY RUN
# without admin is still worth having: most of the diagnosis reads fine
# unelevated, and being able to look at a machine without a UAC prompt
# is the difference between checking and not bothering. It continues,
# loudly, and every check that comes back empty says whether it was
# empty or simply not permitted. "Nothing found" and "not allowed to
# look" must never render the same way.
if (-not $admin -and -not $DryRun) {
    Show-Box -Colour Red -Lines @(
        'NOT RUNNING AS ADMINISTRATOR'
        'Power settings, the registry and the driver keywords all'
        'need admin. Close this and use Fix-Network.bat, which asks.'
    )
    LogOnly 'ABORTED: not elevated.'
    Write-Host ''
    if (-not $Unattended) { Read-Host '  Press Enter to close' | Out-Null }
    exit 1
}
if (-not $admin) {
    Show-Box -Colour Yellow -Lines @(
        'NOT ELEVATED, AND THIS IS A DRY RUN'
        'Reporting continues. Some checks need admin and will say so'
        'rather than quietly reporting nothing.'
    )
    LogOnly 'NOTE: dry run without administrator. Some reads unavailable.'
}
$Script:Elevated = $admin

# =====================================================================
#  1. THE ADAPTER
#
#  Printed one fact at a time as each is read. Gathering everything and
#  then printing means a stall shows a heading and nothing under it,
#  which is the shape that gets read as a freeze and closed.
# =====================================================================
Head 'The wireless adapter'

$wifi = Spin -Label 'looking for a wireless adapter' -TimeoutSeconds 25 -Work {
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.MediaType -eq 'Native 802.11' } |
        Select-Object -First 1 Name, InterfaceDescription, InterfaceGuid, DriverVersion,
                               DriverDate, DriverProvider, Status, ifIndex, MacAddress
}

if (-not $wifi) {
    Bad 'No wireless adapter is present in Windows right now.'
    Info 'That is the fault itself, caught in the act. The radio has left the device tree.'
    Info 'This is the single most useful moment to be running this tool.'
    LogOnly '  NOTE: adapter ABSENT at scan time. The fixes below still apply and'
    LogOnly '        take effect for the next time it enumerates.'
} else {
    OK "$($wifi.InterfaceDescription)"
    Info "adapter name   : $($wifi.Name)"
    Info "driver version : $($wifi.DriverVersion)"
    Info "driver date    : $($wifi.DriverDate)"
    Info "driver from    : $($wifi.DriverProvider)"
    Info "status         : $($wifi.Status)"
}

# Windows build matters: the disappearing-adapter reports cluster on
# 25H2 (build 26200), which is what the target machine runs.
$build = Spin -Label 'reading the Windows build' -TimeoutSeconds 15 -Work {
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
    if ($p) { "$($p.CurrentBuild).$($p.UBR)  $($p.DisplayVersion)" } else { $null }
}
if ($build) { Info "windows        : $build" } else { Warn 'could not read the Windows build from the registry' }

# =====================================================================
#  2. BEFORE STATE, RECORDED BEFORE ANYTHING CHANGES
#
#  Written to the log even in a live run, and written FIRST. A
#  destructive step must record its own before-state; this section is
#  that rule applied to the whole tool rather than to one step.
# =====================================================================
Head 'Recording what everything is set to now'

LogOnly ''
LogOnly '  ============ BEFORE STATE ============'

$ipBefore = Spin -Label 'recording addresses, gateway, DNS and proxy' -TimeoutSeconds 30 -Work {
    $out = New-Object System.Collections.ArrayList
    foreach ($a in (Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $cfg = Get-NetIPConfiguration -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue
        if (-not $cfg) { continue }
        $v4  = $cfg.IPv4Address | Select-Object -First 1
        $dns = ($cfg.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | Select-Object -ExpandProperty ServerAddresses) -join ', '
        $ipi = Get-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        [void]$out.Add("    $($a.Name): $($v4.IPAddress)/$($v4.PrefixLength)  gw=$($cfg.IPv4DefaultGateway.NextHop)  dns=$dns  dhcp=$($ipi.Dhcp)")
    }
    $px = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    [void]$out.Add("    proxy: enable=$($px.ProxyEnable) server=$($px.ProxyServer)")
    return $out
}
if ($ipBefore) {
    LogOnly '  addressing and proxy as found:'
    foreach ($l in $ipBefore) { LogOnly $l }
    OK 'addressing, DNS and proxy recorded to the log'
} else {
    Warn 'could not record addressing (recorded as unknown, not as absent)'
    LogOnly '    addressing: COULD NOT BE READ. Do not assume it was default.'
}

# The power plan values this tool is about to change.
$pwrBefore = Spin -Label 'recording power plan values' -TimeoutSeconds 30 -Work {
    $out = New-Object System.Collections.ArrayList
    # PCI Express link state, then Wireless Adapter power saving. Both
    # verified present by GUID on a real machine before being used:
    # SUB_WIRELESS is NOT a valid powercfg alias, so the GUID is used.
    foreach ($pair in @(
        @{ n = 'PCIe Link State Power Management'; sub = '501a4d13-42af-4429-9fd1-a8218c268e20'; set = 'ee12f906-d277-404b-b6da-e5fa1a576df5' },
        @{ n = 'Wireless Adapter Power Saving';    sub = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'; set = '12bbebe6-58d6-4636-95bb-3217ef867c1a' }
    )) {
        $q = powercfg /q SCHEME_CURRENT $pair.sub $pair.set 2>&1
        $ac = ($q | Select-String 'Current AC Power Setting Index' | Select-Object -First 1) -replace '.*:\s*', ''
        $dc = ($q | Select-String 'Current DC Power Setting Index' | Select-Object -First 1) -replace '.*:\s*', ''
        [void]$out.Add("    $($pair.n): AC=$ac DC=$dc")
    }
    $hb = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue
    [void]$out.Add("    Fast Startup (HiberbootEnabled): $($hb.HiberbootEnabled)")
    $svc = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
    [void]$out.Add("    WLAN AutoConfig service: status=$($svc.Status) startup=$($svc.StartType)")
    return $out
}
if ($pwrBefore) {
    LogOnly '  power and service settings as found:'
    foreach ($l in $pwrBefore) { LogOnly $l; Info $l.Trim() }
} else {
    Warn 'could not record the power plan values'
    LogOnly '    power plan: COULD NOT BE READ.'
}

LogOnly '  ========== END BEFORE STATE =========='
LogOnly ''

# =====================================================================
#  3. WHY IT VANISHES: what Windows recorded
#
#  Read only. The point is to find the device actually being removed and
#  re-added, which is what separates this fault from a connection fault.
# =====================================================================
Head 'What Windows recorded'

$pnp = Spin -Label 'looking for the device being removed and re-added' -TimeoutSeconds 45 -Work {
    # Kernel-PnP 410/411/412/430 and the generic 219 cover a device
    # arriving and leaving. Filtered to the last 14 days so an old
    # unrelated event cannot be presented as today's cause.
    $since = (Get-Date).AddDays(-14)
    Get-WinEvent -FilterHashtable @{
        LogName      = 'System'
        ProviderName = 'Microsoft-Windows-Kernel-PnP'
        StartTime    = $since
    } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'Wi-?Fi|Wireless|WLAN|MediaTek|MT79|Network' } |
        Select-Object -First 12 TimeCreated, Id, Message
}
if ($pnp) {
    Warn "$($pnp.Count) PnP event(s) in 14 days mention the wireless device"
    foreach ($e in $pnp) {
        $first = ($e.Message -split "`n")[0].Trim()
        Info ("{0:MM-dd HH:mm}  id {1}  {2}" -f $e.TimeCreated, $e.Id, $first)
    }
} else {
    Info 'No Kernel-PnP events naming the wireless device in the last 14 days.'
    Info 'That is not an all-clear: PnP logging is sparse, and the fault may'
    Info 'predate the window. It only means this log had nothing to add.'
}

$wlanEvents = Spin -Label 'reading the wireless stack log' -TimeoutSeconds 45 -Work {
    Get-WinEvent -LogName 'Microsoft-Windows-WLAN-AutoConfig/Operational' -MaxEvents 15 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, Message
}
if ($wlanEvents) {
    OK "last $($wlanEvents.Count) wireless events read"
    foreach ($e in ($wlanEvents | Select-Object -First 8)) {
        $first = ($e.Message -split "`n")[0].Trim()
        Info ("{0:MM-dd HH:mm}  id {1}  {2}" -f $e.TimeCreated, $e.Id, $first)
    }
} else {
    Info 'The WLAN-AutoConfig operational log returned nothing.'
    Info 'On a machine whose radio is currently absent that is expected.'
}

# Modern Standby is the state the machine is in when this happens, so
# whether it is even in use changes which fixes matter.
$sleep = Spin -Label 'checking which sleep states this machine uses' -TimeoutSeconds 25 -Work {
    (powercfg /a 2>&1) -join "`n"
}
if ($sleep) {
    if ($sleep -match 'Standby \(S0 Low Power Idle\)') {
        Warn 'This machine uses Modern Standby (S0 low power idle).'
        Info 'The radio stays under driver power control while "asleep", which is'
        Info 'exactly where a device that never comes back gets lost.'
    } elseif ($sleep -match 'Standby \(S3\)') {
        Info 'This machine uses classic S3 sleep.'
    } else {
        Info 'Sleep states read, neither S0 low power idle nor S3 named explicitly.'
    }
} else {
    Warn 'could not read the supported sleep states'
}

# =====================================================================
#  4. THE FIXES
# =====================================================================
Head 'Applying the fixes'

# --- 4a. stop Windows powering the adapter down ----------------------
# The supported cmdlet first. The registry is the fallback, because on
# some drivers the Power Management tab (and the cmdlet behind it) is
# simply not exposed, and PnPCapabilities is then the only lever.
if ($wifi) {
    $pmDone = $false
    if (-not $DryRun) {
        try {
            $pm = Get-NetAdapterPowerManagement -Name $wifi.Name -ErrorAction Stop
            LogOnly "    adapter power management before: AllowComputerToTurnOffDevice=$($pm.AllowComputerToTurnOffDevice)"
            if ($pm.AllowComputerToTurnOffDevice -ne 'Disabled') {
                $pm.AllowComputerToTurnOffDevice = 'Disabled'
                $pm | Set-NetAdapterPowerManagement -ErrorAction Stop
                Did 'Windows may no longer power the wireless adapter down'
                AddUndo 'adapter power-down' "Set it back in Device Manager, Network adapters, the Wi-Fi card, Power Management tab"
            } else {
                OK 'Windows was already not allowed to power the adapter down'
            }
            $pmDone = $true
        } catch {
            Info "the power management cmdlet did not apply here: $($_.Exception.Message)"
        }
    } else {
        Write-Host '    --   WOULD: stop Windows powering the wireless adapter down' -ForegroundColor DarkYellow
        [void]$Log.Add('  --   WOULD: stop Windows powering the wireless adapter down')
        $pmDone = $true
    }

    if (-not $pmDone) {
        # PnPCapabilities lives on the adapter's own class key, found by
        # matching NetCfgInstanceId to the adapter's InterfaceGuid. Never
        # by index: the numbering is not stable across machines.
        $classRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
        $key = Spin -Label 'finding the adapter registry key' -TimeoutSeconds 25 -Argument $wifi.InterfaceGuid -Work {
            param($guid)
            $root = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
            foreach ($k in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
                $p = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
                if ($p.NetCfgInstanceId -eq $guid) { return $k.PSPath }
            }
            return $null
        }
        if ($key) {
            $was = (Get-ItemProperty -Path $key -Name PnPCapabilities -ErrorAction SilentlyContinue).PnPCapabilities
            LogOnly "    PnPCapabilities before: $(if ($null -eq $was) { '(not set)' } else { $was })"
            Apply 'set PnPCapabilities=24 so the adapter is never powered down' {
                Set-ItemProperty -Path $key -Name PnPCapabilities -Value 24 -Type DWord -Force
            } "Set-ItemProperty -Path '$key' -Name PnPCapabilities -Value $(if ($null -eq $was) { 0 } else { $was })" | Out-Null
        } else {
            Warn 'could not locate the adapter registry key, power-down setting left alone'
        }
    }
} else {
    Info 'No adapter present to set power management on. Skipped, not failed.'
    Info 'Run this again once the radio is back and this step will apply.'
}

# --- 4b. PCIe link state power management ----------------------------
# The most likely single cause of a PCIe device dropping off the bus and
# reappearing later. Index 0 is Off, confirmed from powercfg's own
# enumeration rather than assumed.
Apply 'turn PCIe Link State Power Management off, on battery and on mains' {
    $sub = '501a4d13-42af-4429-9fd1-a8218c268e20'
    $set = 'ee12f906-d277-404b-b6da-e5fa1a576df5'
    powercfg /setacvalueindex SCHEME_CURRENT $sub $set 0 | Out-Null
    powercfg /setdcvalueindex SCHEME_CURRENT $sub $set 0 | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
} 'powercfg /setdcvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 2' | Out-Null

# --- 4c. wireless radio power saving ---------------------------------
Apply 'set Wireless Adapter Power Saving to Maximum Performance' {
    $sub = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'
    $set = '12bbebe6-58d6-4636-95bb-3217ef867c1a'
    powercfg /setacvalueindex SCHEME_CURRENT $sub $set 0 | Out-Null
    powercfg /setdcvalueindex SCHEME_CURRENT $sub $set 0 | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
} 'powercfg /setdcvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 2' | Out-Null

# --- 4d. fast startup -------------------------------------------------
# Fast Startup resumes the kernel and the device tree from a hibernation
# image instead of enumerating hardware fresh. A radio that failed to
# come back then stays missing across what looks like a full shutdown,
# which is why "I turned it off and on again" does not clear this fault.
$hb = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
if ($hb -eq 0) {
    OK 'Fast Startup is already off'
} else {
    Apply 'turn Fast Startup off so a shutdown really re-enumerates the hardware' {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -Type DWord -Force
    } "Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 1" | Out-Null
}

# --- 4e. the driver's own power-saving keywords ----------------------
# Only keywords that ACTUALLY EXIST on this adapter are touched, and the
# value is taken from the driver's own list of valid values rather than
# guessed. A hardcoded value here would silently do nothing on a
# different card, or throw on a card that spells it differently.
if ($wifi) {
    $props = Spin -Label 'reading the driver power-saving options' -TimeoutSeconds 30 -Argument $wifi.Name -Work {
        param($n)
        Get-NetAdapterAdvancedProperty -Name $n -ErrorAction SilentlyContinue |
            Select-Object RegistryKeyword, DisplayName, DisplayValue, ValidDisplayValues
    }
    if ($props) {
        $targets = @('powersave', 'uapsd', 'u-apsd', 'selectivesuspend', 'magicpacket',
                     'mimopowersave', 'greenethernet', 'eee', 'autopowersave')
        $hit = $props | Where-Object {
            $kw = "$($_.RegistryKeyword)$($_.DisplayName)".ToLower() -replace '[^a-z]', ''
            $m = $false
            foreach ($t in $targets) { if ($kw -like "*$($t -replace '[^a-z]','')*") { $m = $true } }
            $m
        }
        if ($hit) {
            foreach ($p in $hit) {
                $valid = @($p.ValidDisplayValues)
                $want = $null
                foreach ($cand in @('Disabled', 'Off', 'Maximum Performance', 'No Power Saving', 'None')) {
                    if ($valid -contains $cand) { $want = $cand; break }
                }
                if (-not $want) {
                    Info "left alone: $($p.DisplayName) (no 'disabled' style value offered; is '$($p.DisplayValue)')"
                    LogOnly "    valid values were: $($valid -join ' | ')"
                    continue
                }
                if ($p.DisplayValue -eq $want) {
                    OK "$($p.DisplayName) is already '$want'"
                    continue
                }
                $wasVal = $p.DisplayValue
                $kwName = $p.RegistryKeyword
                Apply "set $($p.DisplayName) to '$want' (was '$wasVal')" {
                    Set-NetAdapterAdvancedProperty -Name $wifi.Name -RegistryKeyword $kwName -DisplayValue $want -ErrorAction Stop
                } "Set-NetAdapterAdvancedProperty -Name '$($wifi.Name)' -RegistryKeyword '$kwName' -DisplayValue '$wasVal'" | Out-Null
            }
        } else {
            Info 'This driver exposes no power-saving keywords to change.'
            Info 'Not a fault. MediaTek cards vary in what they expose.'
        }
    } else {
        Warn 'could not read the driver advanced properties'
    }
} else {
    Info 'No adapter present, so its driver options could not be read. Skipped.'
}

# --- 4f. WLAN AutoConfig service -------------------------------------
$svc = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
if (-not $svc) {
    Bad 'The WLAN AutoConfig service is not present on this machine.'
} elseif ($svc.Status -eq 'Running' -and $svc.StartType -eq 'Automatic') {
    OK 'WLAN AutoConfig is running and set to start automatically'
} else {
    Apply "set WLAN AutoConfig to Automatic and start it (was $($svc.StartType)/$($svc.Status))" {
        Set-Service -Name WlanSvc -StartupType Automatic -ErrorAction Stop
        if ((Get-Service WlanSvc).Status -ne 'Running') { Start-Service WlanSvc -ErrorAction Stop }
    } "Set-Service -Name WlanSvc -StartupType $($svc.StartType)" | Out-Null
}

# =====================================================================
#  5. THE DRIVER
#
#  Reported, and offered, never installed silently. The version actually
#  installed is the one fact the 2026-08-13 log failed to capture (it
#  recorded only the date), which is why it is printed prominently.
# =====================================================================
Head 'The driver'

# Known-good target for the MediaTek MT7902 in the ASUS Vivobook
# X1504VA, read off ASUS's own download page for that model on
# 2026-08-23. Kept as data, not prose, so it is easy to update.
$targetVer  = '3.5.2.1349'
$targetDate = '2025/11/07'
$asusUrl    = 'https://www.asus.com/laptops/for-home/vivobook/asus-vivobook-15-x1504/helpdesk_download?model2Name=X1504VA'

if ($wifi) {
    Info "installed : $($wifi.DriverVersion)   dated $($wifi.DriverDate)   from $($wifi.DriverProvider)"
    if ($wifi.InterfaceDescription -match 'MT79|MediaTek|RZ6') {
        Info "ASUS ships : $targetVer  ($targetDate)  for the MT7902 in the X1504VA"
        try {
            $haveV = [version]($wifi.DriverVersion)
            $wantV = [version]$targetVer
            if ($haveV -lt $wantV) {
                Warn "This driver is OLDER than the one ASUS ships. Updating it is the"
                Warn "single highest value action on this machine."
            } elseif ($haveV -eq $wantV) {
                OK 'This is exactly the version ASUS ships. The driver is current.'
            } else {
                OK "Installed driver is newer than ASUS's listed $targetVer. Nothing to do."
            }
        } catch {
            Info 'Could not compare version numbers, so no claim is made about which is newer.'
        }
    } else {
        Info 'This is not the MediaTek card this tool was written around,'
        Info 'so no version comparison is offered. The fixes above still apply.'
    }
} else {
    Warn 'No adapter present, so no driver version could be read.'
}

# ---------------------------------------------------------------------
#  STAGED DRIVERS, MATCHED BY HARDWARE ID
#
#  The first version of this offered the first .exe it found in the
#  Drivers folder. That is dangerous on a stick that travels between
#  machines, and it was immediately proved so: of the three MediaTek
#  packages downloaded for this job, only ONE listed DEV_7902. The other
#  two are for MT7925/7927/7935. Offering "the first installer" would
#  have put a wrong-chip driver in front of the person fixing the
#  laptop, twice out of three times.
#
#  So the adapter's own PCI device ID is read, and only a package whose
#  .inf actually lists that ID is offered. A package that does not match
#  is named and skipped rather than hidden, because "no driver staged"
#  and "the staged one is for a different chip" are different problems.
#
#  It also has to handle INF-only packages. The correct package for this
#  card has no .exe at all: it is an .inf plus .sys plus firmware blobs,
#  installed with pnputil. Searching only for .exe found nothing in the
#  one case that mattered.
# ---------------------------------------------------------------------
$driverDir = Join-Path $PSScriptRoot 'Drivers'

# PNPDeviceID looks like PCI\VEN_14C3&DEV_7902&SUBSYS_...  The DEV part
# is the chip, and it is what an .inf matches on.
$devId = $null
if ($wifi) {
    $pnp = Get-NetAdapter -Name $wifi.Name -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PnPDeviceID -ErrorAction SilentlyContinue
    if ($pnp -and $pnp -match '(DEV_[0-9A-Fa-f]{4})') { $devId = $Matches[1].ToUpper() }
}
if ($devId) { Info "this card's hardware id : $devId" }

if (-not (Test-Path $driverDir)) {
    Info 'No Drivers folder on the stick, so nothing could be offered offline.'
    Info "To make this offline in future, create it and drop driver packages in:"
    Info "  $driverDir"
} else {
    $pkgs = Get-ChildItem $driverDir -Directory -ErrorAction SilentlyContinue
    if (-not $pkgs) {
        Info "The Drivers folder is empty:  $driverDir"
    } else {
        $match = $null
        foreach ($p in $pkgs) {
            $infs = Get-ChildItem $p.FullName -Filter *.inf -Recurse -ErrorAction SilentlyContinue
            $ids = @()
            foreach ($i in $infs) {
                try { $ids += ([regex]::Matches([System.IO.File]::ReadAllText($i.FullName), 'DEV_[0-9A-Fa-f]{4}') | ForEach-Object { $_.Value.ToUpper() }) } catch { }
            }
            $ids = $ids | Sort-Object -Unique
            if ($devId -and ($ids -contains $devId)) {
                OK "$($p.Name)  matches this card"
                if (-not $match) { $match = $p }
            } elseif ($devId) {
                Info "$($p.Name)  is for a different chip, skipped"
            } else {
                Info "$($p.Name)  present, but this card's id is unknown so it was not matched"
            }
        }

        if ($match) {
            $inf = Get-ChildItem $match.FullName -Filter *.inf -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            $exe = Get-ChildItem $match.FullName -Include '*.exe', '*.msi' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            $ver = $null
            if ($inf) {
                $dv = (Select-String -Path $inf.FullName -Pattern '^\s*DriverVer\s*=' -ErrorAction SilentlyContinue | Select-Object -First 1)
                if ($dv) { $ver = ($dv.Line -replace '.*=\s*', '').Trim() }
            }
            if ($ver) { Info "staged version : $ver" }

            if ($exe) {
                $exePath = $exe.FullName
                AskLater "Install the matching driver by running '$($exe.Name)'?" {
                    Start-Process -FilePath $exePath -Wait
                } "It opens its own installer. Reboot afterwards."
            } elseif ($inf) {
                $infPath = $inf.FullName
                AskLater "Install the matching driver from '$($inf.Name)' now?" {
                    Write-Host '         Installing with pnputil, this takes a few seconds...' -ForegroundColor DarkGray
                    $r = & pnputil.exe /add-driver "$infPath" /install 2>&1
                    foreach ($l in $r) { Write-Host "         $l" -ForegroundColor DarkGray }
                    Write-Host '         Reboot to finish.' -ForegroundColor Yellow
                } "This package has no installer, it is an .inf, so pnputil adds it to the driver store and installs it. The Wi-Fi will drop out briefly."
            } else {
                Warn "$($match.Name) matched but contains neither an installer nor an .inf"
            }
        } elseif ($devId) {
            Warn 'No staged driver package matches this card.'
            Info 'Nothing was offered, deliberately. Installing a driver for a'
            Info 'different chip is worse than installing none.'
        }
    }
}

# The download page is always offered, staged driver or not: the staged
# one may be older than what the vendor now ships, and the Bluetooth
# driver is a separate download that ASUS says to update alongside.
AskLater 'Open the ASUS download page for this model in a browser?' {
    Start-Process $asusUrl
} "For the newest WLAN driver, and the MediaTek Bluetooth driver, which is a separate download. ASUS says to update both together."

# =====================================================================
#  6. THE HEAVIER OPTIONS, ASKED AT THE END
# =====================================================================

# Wi-Fi Direct virtual adapter. Deferred rather than automatic because
# it has a cost the user can see: no Miracast, no Mobile Hotspot.
$wfd = Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
       Where-Object { $_.InterfaceDescription -match 'Wi-?Fi Direct' -and $_.Status -ne 'Disabled' }
if ($wfd) {
    $names = ($wfd | Select-Object -ExpandProperty Name) -join ', '
    AskLater 'Disable the Wi-Fi Direct virtual adapter?' {
        foreach ($a in $wfd) { Disable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction SilentlyContinue }
    } "Reported to fix a broken power transition handler on 25H2. COSTS: Miracast screen casting and Mobile Hotspot stop working. Re-enable in Device Manager. Adapters: $names"
}

# Network stack reset. Its before-state is already in the log above,
# which is the precondition the old tool did not meet.
AskLater 'Reset the network stack (winsock and TCP/IP)?' {
    netsh winsock reset | Out-Null
    netsh int ip reset | Out-Null
    Write-Host '         Done. This one needs a reboot to take effect.' -ForegroundColor DarkGray
} 'Clears winsock and TCP/IP to defaults. Your current addresses, DNS and proxy are already written into this run log, above, so they can be put back. Needs a reboot.'

# Reboot last, so it is asked after everything else has been answered.
AskLater 'Restart the computer now?' {
    Write-Host '         Restarting in 15 seconds. Close anything unsaved.' -ForegroundColor Yellow
    shutdown /r /t 15 /c "Lazarus Fix-Network: applying network power settings"
} 'The power and Fast Startup changes only take full effect after a restart.'

# =====================================================================
#  7. VERDICT AND SAVED LOG
# =====================================================================
Head 'Summary'

$took = [int]((Get-Date) - $started).TotalSeconds
if ($DryRun) {
    Info 'Dry run. Nothing was changed.'
} elseif ($Undo.Count) {
    OK "$($Undo.Count) setting(s) changed. Every one has an undo line in the saved log."
} else {
    OK 'Nothing needed changing. Everything this tool checks was already correct.'
}
Info "Finished in ${took}s."

if ($Undo.Count) {
    LogOnly ''
    LogOnly '  ============ HOW TO UNDO ============'
    LogOnly '  Run these in an ADMIN PowerShell to put things back as they were.'
    foreach ($u in $Undo) {
        LogOnly ''
        LogOnly "    # $($u.What)"
        LogOnly "    $($u.Cmd)"
    }
    LogOnly '  ========== END HOW TO UNDO =========='
}

LogOnly ''
LogOnly "Finished $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  after ${took}s"

$leaf = "netlog-$machine-$($started.ToString('yyyy-MM-dd_HHmm')).txt"
$dest = if ($Script:HaveCommon) { Get-ReportPath -Leaf $leaf -PrimaryDir $PSScriptRoot } else { Join-Path $PSScriptRoot $leaf }
if ($dest) {
    try {
        [System.IO.File]::WriteAllLines($dest, $Log)
        OK "Log saved: $dest"
    } catch {
        Warn "Could not save the log: $($_.Exception.Message)"
        Warn 'The run itself was fine. Only the saved copy failed.'
    }
} else {
    Warn 'No writable location was found for the log, so it was not saved.'
}

Invoke-Deferred

Write-Host ''
if (-not $Unattended) {
    # Only exists when Common.ps1 loaded. Calling it blind would throw a
    # CommandNotFound on the very last line of an otherwise clean run,
    # which reads as "the tool crashed at the end".
    if (Get-Command Clear-InputBuffer -ErrorAction SilentlyContinue) { Clear-InputBuffer }
    Read-Host '  Press Enter to close' | Out-Null
}
