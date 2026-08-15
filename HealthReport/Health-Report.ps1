<#
=======================================================================
 HEALTH AND HANDOVER REPORT

 One click, one page, from data Windows already has. No extra software.

 Two jobs:
   REPAIR   - a before/after record of what a machine was like, which
              is also what you show a client.
   HANDOVER - proof a club laptop is fit to give to a child: battery
              not worn out, disk not dying, Windows activated,
              safeguarding actually switched on.

 Written for secondhand ex-corporate laptops, which is what club
 machines usually are, so it checks the things those specifically
 come with: worn batteries, missing activation, BitLocker you do not
 have the key for, and Absolute persistence.
=======================================================================
#>

# -Unattended: survey the machine and write the report with no keypresses.
# Every check here is read-only, so there is nothing to consent to; the
# only interactive parts are the offer to run repairs and the "press Enter
# to close" at the end, and both are skipped. For surveying a stack of
# machines, or running from a scheduled task, without sitting over it.
#
# It deliberately does NOT gain the ability to repair anything unattended.
# Anything that changes a machine still requires somebody to say yes.
param(
    [switch]$Unattended
)

# SilentlyContinue is right for this script: it queries a lot of WMI that
# legitimately fails on some machines, and a client watching a health
# check does not need a screen of red for a battery class that does not
# exist on their desktop.
#
# The cost is that it hides OUR bugs too. Repair-Health uses 'Continue',
# which is exactly why a call to an undefined function showed up there
# immediately; the same mistake in this file would have vanished without
# a trace. So errors are still collected and written into the saved
# report at the end. Quiet on screen, never lost.
$ErrorActionPreference = 'SilentlyContinue'
$Error.Clear()
$Script:Unattended = [bool]$Unattended
$out  = [System.Collections.ArrayList]@()
$warn = [System.Collections.ArrayList]@()
$bad  = [System.Collections.ArrayList]@()

# Spin, the tick, and the console-animation check. Shared with
# Repair-Health rather than copied, because this report had no progress
# indicator at all and sat silent on the slow WMI queries, which reads
# as frozen. A second copy would drift.
. (Join-Path $PSScriptRoot 'Common.ps1')
$Script:SpinLog = $out

# Several checks here read things only an administrator can see: SMART
# counters, BitLocker, battery capacity. Unelevated they return nothing
# and their sections used to print a heading and then stop dead, which
# reads as the report failing to load rather than as a permissions
# limit. Now it is said once, up front, and again per section.
$Script:IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
                  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Sec($t) { Write-Host ''; Write-Host "  $t" -ForegroundColor Cyan; Write-Host "  $('-' * $t.Length)" -ForegroundColor DarkCyan; [void]$out.Add(''); [void]$out.Add($t); [void]$out.Add('-' * $t.Length) }
function Line($k, $v, $colour = 'Gray') {
    # {0,-26} pads a SHORT key to 26 and does nothing at all to a longer
    # one, so any key past 26 characters ran straight into its value:
    # "High precision event timerDISABLED". Device names blow past 26
    # constantly. Guarantee the gap instead of assuming the pad provides
    # it.
    $key = "$k"
    $col = if ($key.Length -ge 26) { $key + '  ' } else { $key.PadRight(26) }
    Write-Host ("    {0}{1}" -f $col, $v) -ForegroundColor $colour
    [void]$out.Add(("  {0}{1}" -f $col, $v))
}
function Warn($m) { Write-Host "    !! $m" -ForegroundColor Yellow; [void]$warn.Add($m); [void]$out.Add("  !! $m") }
function Fail($m) { Write-Host "    XX $m" -ForegroundColor Red;    [void]$bad.Add($m);  [void]$out.Add("  XX $m") }
function Good($m) { Write-Host "    ok $m" -ForegroundColor Green;  [void]$out.Add("  ok $m") }
# Info was CALLED seven times in this file and DEFINED in none of it. It
# only ever existed in Repair-Health.ps1. Because this script sets
# $ErrorActionPreference = 'SilentlyContinue', every one of those calls
# raised CommandNotFoundException and was swallowed whole: no output, no
# error, no line in the saved file, and the script carried on as if it
# had printed. Verified 2026-08-15 by running an undefined call under
# SilentlyContinue and watching the line disappear.
#
# What was silently lost: the BIOS update advice and the exact vendor
# search string, the warning that bundled browsers bypass Chrome policy,
# the instruction to only take firmware from the board maker, and the
# pointer to Windows Update repair. Every one of them is guidance about
# a problem the report had just found, which is the whole job.
function Info($m) { Write-Host "         $m" -ForegroundColor DarkGray; [void]$out.Add("       $m") }

Clear-Host
Write-Host ''
Write-Host '   ==========================================' -ForegroundColor Cyan
Write-Host '    HEALTH REPORT AND REPAIR' -ForegroundColor Cyan
Write-Host '   ==========================================' -ForegroundColor Cyan
[void]$out.Add("HEALTH REPORT AND REPAIR")
[void]$out.Add("Generated $(Get-Date -f 'yyyy-MM-dd HH:mm')")

# ---------------------------------------------------------- machine
Sec 'Machine'
# THIS is where the report froze on one desktop: the
# heading appeared and then nothing, because all three of these ran
# before a single line was printed, and one of them never returned.
#
# Win32_ComputerSystem is the usual offender. It exposes domain
# membership, so on a machine that has ever been joined to a domain, or
# that has a stale DNS or network configuration, it can block on a lookup
# that never completes. A laptop on working WiFi answers instantly, which
# is why this was invisible on every machine tested before.
#
# Each call now has its own timeout and its own line, so a stall is
# bounded, named, and does not take the rest of the report with it.
$cs = Spin 'reading the system make and model' {
    param($x)
    Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
} $null 20
$bios = Spin 'reading the BIOS' {
    param($x)
    Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
} $null 20
$os = Spin 'reading the Windows edition' {
    param($x)
    Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
} $null 20
# The MOTHERBOARD, not the OEM system name.
#
# On a prebuilt laptop Win32_ComputerSystem gives something useful. On a
# custom-built desktop it returns "To Be Filled By O.E.M." and you are no
# closer to knowing what board is in the machine. Win32_BaseBoard is the
# board itself, and board maker + board model + current BIOS version is
# precisely the three things a vendor's BIOS download page asks for.
$mb = Spin 'reading the motherboard' {
    param($x)
    Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
} $null 20
Line 'Name'         $env:COMPUTERNAME
if ($cs) { Line 'Make / model' "$($cs.Manufacturer) $($cs.Model)" }
else     { Warn 'Could not read the system make and model. WMI did not answer in time.' }
if ($mb) {
    $rev = ''
    if ($mb.Version -and $mb.Version.Trim() -and $mb.Version -notmatch 'To Be Filled|Default string') { $rev = "  rev $($mb.Version.Trim())" }
    Line 'Motherboard' "$($mb.Manufacturer) $($mb.Product)$rev"
}
if ($bios) { Line 'Serial' $bios.SerialNumber }

# BIOS AGE, not just version. A version string means nothing to anyone
# who does not already know the vendor's numbering. Years since release
# is the number that tells you whether to care.
$biosDate = $null
try { if ($bios -and $bios.ReleaseDate) { $biosDate = [datetime]$bios.ReleaseDate } } catch { $biosDate = $null }
if (-not $bios) {
    Warn 'Could not read the BIOS. WMI did not answer in time, so the firmware version and age are unknown.'
} elseif ($biosDate) {
    $biosAge = [math]::Round(((Get-Date) - $biosDate).TotalDays / 365.25, 1)
    Line 'BIOS' "$($bios.SMBIOSBIOSVersion)  ($($biosDate.ToString('yyyy-MM-dd')), $biosAge years old)"
    if ($biosAge -ge 3) {
        Warn "The BIOS is $biosAge years old. Firmware updates carry CPU microcode fixes for security holes, and fixes for stability, memory compatibility and boot problems that no amount of work inside Windows can solve."
        if ($mb) { Info "Search the vendor's support page for exactly: $($mb.Manufacturer) $($mb.Product)" }
        Info "Current version is $($bios.SMBIOSBIOSVersion). Only ever take the file from the board maker's own site."
        Info 'Read their instructions before flashing. A BIOS update interrupted by a power cut can leave the board unbootable.'
    }
} else {
    Line 'BIOS' "$($bios.SMBIOSBIOSVersion)  (release date not reported)"
}
if ($os) {
    Line 'Windows'      "$($os.Caption) build $($os.BuildNumber)"
    if ($os.InstallDate) { Line 'Installed on' $os.InstallDate.ToString('yyyy-MM-dd') }
} else {
    Warn 'Could not read the Windows edition. WMI did not answer in time.'
}
$cpu = Spin 'reading the processor' {
    param($x)
    Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
} $null 20
if ($cpu) { Line 'CPU' $cpu.Name }
$gpu = AsArray (Spin 'reading the graphics adapter' {
    param($x)
    Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
} $null 20)
foreach ($g in $gpu) { if ($g.Name) { Line 'GPU' $g.Name } }

# ------------------------------------------------------- activation
Sec 'Windows activation'
# SoftwareLicensingProduct is the slowest thing in this report by a wide
# margin, and it prints nothing while it works, which is why this
# section is the one that looks frozen. It can also block for a long
# time when the machine tries to reach an activation server and the
# network will not let it, so it gets a hard limit rather than an
# unbounded wait. A check that cannot answer should say so and let the
# rest of the report finish.
$lic = Spin 'reading the Windows licence (the slowest check here)' {
    param($x)
    Get-CimInstance SoftwareLicensingProduct `
        -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" `
        -ErrorAction SilentlyContinue | Select-Object -First 1
} $null 60

if (-not $lic) {
    Warn 'Could not read the activation status within 60 seconds.'
    Line '' 'Check by hand:  Settings > System > Activation'
    Line '' 'This does not affect anything else in this report.'
}
if ($lic) {
    $stat = switch ($lic.LicenseStatus) {
        0 {'Unlicensed'} 1 {'Licensed'} 2 {'Out-of-box grace'} 3 {'Out-of-tolerance grace'}
        4 {'Non-genuine grace'} 5 {'NOTIFICATION (not activated)'} 6 {'Extended grace'} default {"Unknown ($($lic.LicenseStatus))"}
    }
    Line 'Status' $stat
    Line 'Channel' $lic.ProductKeyChannel
    if ($lic.LicenseStatus -eq 1) { Good 'Windows is properly activated' }
    else { Fail "Windows is NOT activated ($stat). A club laptop should be activated before handover." }
}

# ----------------------------------------------------------- battery
Sec 'Battery'
$batt = Spin 'asking the battery for its capacity' {
    param($x)
    [pscustomobject]@{
        Static = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue)
        Full   = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue)
    }
} $null 30
$bat  = $batt.Static
$full = $batt.Full
if ($bat -and $full) {
    $design = ($bat | Select-Object -First 1).DesignedCapacity
    $now    = ($full | Select-Object -First 1).FullChargedCapacity
    if ($design -gt 0 -and $now -gt 0) {
        $health = [math]::Round(($now / $design) * 100, 1)
        $wear   = [math]::Round(100 - $health, 1)
        Line 'Design capacity'  "$design mWh"
        Line 'Full charge now'  "$now mWh"
        Line 'Health'           "$health %"
        Line 'Wear'             "$wear %"
        if     ($health -ge 80) { Good "battery is healthy ($health %)" }
        elseif ($health -ge 60) { Warn "battery is worn ($health %). Usable, but expect short runtime." }
        else                    { Fail "battery is BADLY worn ($health %). Replace it before giving this to a child to carry around." }
    } else { Warn 'Battery reported zero capacity, the driver is not exposing it.' }

    # Cycle count, and how capacity has fallen over time. WMI does not
    # carry either, so ask powercfg for its own HTML report.
    $br = Join-Path $PSScriptRoot ("battery-$env:COMPUTERNAME-$(Get-Date -f 'yyyy-MM-dd').html")
    Spin 'building the battery history report' {
        param($path)
        powercfg /batteryreport /output "$path" 2>&1 | Out-Null
    } $br 45 | Out-Null
    if (Test-Path $br) {
        $html = Get-Content $br -Raw
        if ($html -match 'CYCLE COUNT[\s\S]{0,400}?<td[^>]*>\s*([\d,]+)\s*</td>') {
            $cycles = $matches[1]
            Line 'Charge cycles' $cycles
            $n = [int]($cycles -replace ',','')
            if     ($n -gt 1000) { Warn "$n charge cycles. Most laptop batteries are rated for 300 to 500, so this one is well past its design life." }
            elseif ($n -gt 500)  { Warn "$n charge cycles, past the typical 300-500 rating." }
            elseif ($n -gt 0)    { Good "$n charge cycles, within normal life" }
        } else { Line 'Charge cycles' 'not reported by this firmware (common on HP)' }
        Line 'Full battery report' (Split-Path $br -Leaf)
        Line '' 'open that HTML file for capacity history and usage'
    } else { Warn 'powercfg could not produce a battery report' }
} else {
    Line 'Battery' 'no capacity data from WMI'
    # Do NOT call this a missing driver. root\wmi BatteryStaticData is
    # simply not exposed by many modern laptops, and it reported "none
    # detected" on a Vivobook whose battery works perfectly well.
    Line '' 'Normal on a desktop and on many newer laptops. Not a fault.'
    Line '' 'For real figures run:  powercfg /batteryreport'
}

# -------------------------------------------------------------- disk
Sec 'Storage'
$disks = Spin 'asking each drive for its health and SMART data' {
    param($x)
    Get-PhysicalDisk -ErrorAction SilentlyContinue
} $null 45
foreach ($d in (AsArray $disks)) {
    $sz   = [math]::Round($d.Size / 1GB, 0)
    $hTxt = Get-DiskHealthText $d.HealthStatus
    $mTxt = Get-MediaTypeText  $d.MediaType
    Line "$($d.FriendlyName)" "$sz GB, $mTxt, health: $hTxt"
    if (-not (Test-DiskHealthy $d.HealthStatus)) {
        Fail "$($d.FriendlyName) reports health '$hTxt'. Confirm with CrystalDiskInfo before replacing anything."
    }
}
$rel = Spin 'reading the reliability counters' {
    param($x)
    Get-StorageReliabilityCounter -PhysicalDisk (Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object -First 1) -ErrorAction SilentlyContinue
} $null 30
if ($rel) {
    if ($rel.PowerOnHours) { Line 'Power-on hours' "$($rel.PowerOnHours)  (about $([math]::Round($rel.PowerOnHours/24/365,1)) years)" }
    if ($rel.Wear -ne $null) {
        Line 'SSD wear used' "$($rel.Wear) %"
        if ($rel.Wear -gt 80) { Fail "SSD is at $($rel.Wear)% of its rated write life" }
    }
    if ($rel.ReadErrorsTotal -gt 0)  { Warn "read errors: $($rel.ReadErrorsTotal)" }
    if ($rel.WriteErrorsTotal -gt 0) { Warn "write errors: $($rel.WriteErrorsTotal)" }
} else {
    # Never leave a heading with nothing under it. A section that prints
    # a spinner and then simply stops is what made this report look like
    # it "would not load some things": the check had returned nothing and
    # the whole block was skipped in silence.
    if (-not $Script:IsAdmin) { Warn 'Power-on hours and SSD wear need administrator rights. Start from Health-Report.bat, which elevates.' }
    else { Line 'Power-on hours' 'not reported by this drive or controller' }
}
$c = Get-PSDrive C
Line 'C: free' "$([math]::Round($c.Free/1GB,1)) GB of $([math]::Round(($c.Used+$c.Free)/1GB,1)) GB"
if (($c.Free / ($c.Used + $c.Free)) -lt 0.15) { Warn 'less than 15% free on C:' }

# --------------------------------------------------------------- RAM
Sec 'Memory'
$ram = AsArray (Spin 'reading the memory configuration' {
    param($x)
    Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
} $null 25)
if (-not $ram.Count) { Warn 'Could not read the memory configuration. The WMI service may be unhealthy on this machine.' }
else {
    Line 'Total' "$([math]::Round(($ram | Measure-Object Capacity -Sum).Sum/1GB,0)) GB across $($ram.Count) stick(s)"
    foreach ($m in $ram) { Line "  slot $($m.DeviceLocator)" "$([math]::Round($m.Capacity/1GB,0)) GB $($m.Speed)MHz $($m.Manufacturer)" }
}

# ----------------------------------------------------------- drivers
# Folded in from the old standalone Drivers tool, which was removed.
#
# That tool answered the wrong question. It installed the maker's updater
# (MSI Center, MyASUS and friends) and then asked Windows Update, which
# is deliberately conservative and ships drivers well behind the vendor's
# own releases. So it put heavy vendor software on a client machine and
# still reported "no driver updates needed" on a machine with genuinely
# stale drivers. Neither half told you what was actually wrong.
#
# This reads instead. Three questions, in the order that matters:
#   1. Is any device BROKEN right now (no driver, failed to start)?
#   2. Is Windows using its own generic driver where real hardware needs
#      the vendor's? That is why the graphics are slow and the WiFi drops.
#   3. How old is each driver, so "out of date" is a date, not a feeling.
# Installing is a separate, asked-for step in repair and recovery.
Sec 'Drivers'

$devProblem = AsArray (Spin 'looking for devices with driver problems' {
    param($x)
    Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 }
} $null 45)

# Only the codes that actually turn up on these machines, said in plain
# words. A bare "error 28" sends somebody searching the web instead of
# fixing the thing.
function Get-DeviceErrorText($code) {
    switch ("$code") {
        '1'  { 'not configured correctly' }
        '3'  { 'driver may be corrupt, or the system is low on memory' }
        '10' { 'cannot start' }
        '12' { 'cannot find enough free resources' }
        '14' { 'needs a restart to work' }
        '18' { 'drivers need reinstalling' }
        '19' { 'registry is corrupt for this device' }
        '21' { 'Windows is removing it' }
        '22' { 'DISABLED' }
        '24' { 'not present, not working, or missing drivers' }
        '28' { 'NO DRIVER INSTALLED' }
        '31' { 'not working because Windows cannot load its driver' }
        '43' { 'Windows stopped it after it reported problems' }
        '45' { 'not currently connected' }
        default { "problem code $code" }
    }
}

# HOW BAD IS IT. "5 devices have a driver problem" tells you nothing you
# can act on, because a missing network driver and a missing card reader
# driver are not remotely the same emergency.
#
# Network is CRITICAL on its own terms: a machine with no network driver
# cannot download its own network driver, so it is the one fault that
# blocks its own repair. Everything else can be fixed once you are online.
function Get-DeviceSeverity($pnpClass, $code) {
    $c = "$pnpClass"
    if ($c -match '^Net$|^NetAdapter')                          { return 'CRITICAL' }
    if ($c -match '^(SCSIAdapter|HDC|DiskDrive|Volume|System)$') { return 'CRITICAL' }
    if ($c -match '^(Display|USB|HIDClass|Keyboard|Mouse)$')     { return 'HIGH' }
    if ($c -match '^(Media|AudioEndpoint|Bluetooth|Image|Camera|Printer)$') { return 'MEDIUM' }
    if ("$code" -eq '28') { return 'MEDIUM' }
    return 'LOW'
}
function Get-SeverityMeaning($sev) {
    switch ($sev) {
        'CRITICAL' { 'the machine cannot work properly, and a missing network driver also blocks its own repair' }
        'HIGH'     { 'something obvious is broken: no display, no input, or no USB' }
        'MEDIUM'   { 'a real device is not working, but the machine is usable' }
        default    { 'minor, often a virtual or optional device' }
    }
}

if (-not $devProblem.Count) {
    Good 'no devices are reporting a driver problem'
} else {
    # Two codes are NOT faults, and calling them faults is how a real
    # fault three lines below gets skipped over.
    #
    # 45 means "was plugged in once, is not now". A dock that went home
    # with somebody is not a problem with this machine.
    #
    # 22 means somebody deliberately DISABLED it. Repair-Health has
    # excluded 22 from its own driver check since it was written, for
    # exactly this reason, and this section shipped without that filter
    # for one run: it reported "5 devices have a driver problem right
    # now" on a perfectly healthy PC, listing the high precision event
    # timer, a virtual display and the GS Wavetable Synth, all of which
    # are disabled as standard. Five red XX lines also drag the whole
    # report's verdict down to NOT READY.
    $realProblem = @($devProblem | Where-Object { $_.ConfigManagerErrorCode -notin @(22, 45) })
    $disabled    = @($devProblem | Where-Object { $_.ConfigManagerErrorCode -eq 22 })
    $absent      = @($devProblem | Where-Object { $_.ConfigManagerErrorCode -eq 45 })

    if ($realProblem.Count) {
        # Worst first. Somebody reading a wall of red starts at the top and
        # often stops there, so the top line has to be the one that matters.
        $rank = @{ 'CRITICAL' = 0; 'HIGH' = 1; 'MEDIUM' = 2; 'LOW' = 3 }
        $ranked = @($realProblem | ForEach-Object {
            [pscustomobject]@{
                Dev = $_
                Sev = (Get-DeviceSeverity $_.PNPClass $_.ConfigManagerErrorCode)
            }
        } | Sort-Object { $rank[$_.Sev] })

        $worst = $ranked[0].Sev
        Fail "$($realProblem.Count) device(s) have a driver problem. Worst is $worst."
        foreach ($r in $ranked) {
            Line "  [$($r.Sev)] $($r.Dev.Name)" (Get-DeviceErrorText $r.Dev.ConfigManagerErrorCode)
            # Hardware ID to the saved file only. On screen it is a wall of
            # unreadable identifiers between you and the next finding; in
            # the file it is what you paste into a search engine.
            if ($r.Dev.DeviceID) { [void]$out.Add("        $($r.Dev.DeviceID)") }
        }
        Write-Host ''
        foreach ($s in @('CRITICAL','HIGH','MEDIUM','LOW')) {
            $n = @($ranked | Where-Object { $_.Sev -eq $s }).Count
            if ($n) { Info "$s x$n : $(Get-SeverityMeaning $s)" }
        }
        # One instruction, not two. This used to say "use the Windows
        # Update driver step" here AND three lines earlier under the device
        # list. The network caveat only prints when it actually applies.
        Info 'Fix with "Install driver updates from Windows Update" in repair and recovery.'
        if (@($ranked | Where-Object { $_.Sev -eq 'CRITICAL' -and $_.Dev.PNPClass -match '^Net' }).Count) {
            Info 'The network driver is one of them, so this PC cannot fetch its own fix.'
            Info 'Get it on another machine, or USB-tether a phone for a temporary connection.'
        }
    } else {
        Good 'no devices are reporting a driver problem'
    }
    if ($disabled.Count) {
        Line 'Deliberately disabled' "$($disabled.Count) device(s), listed in the saved report"
        foreach ($d in $disabled) { [void]$out.Add("      (disabled) $($d.Name)") }
    }
    if ($absent.Count) {
        Line 'Not currently connected' "$($absent.Count) device(s), listed in the saved report"
        foreach ($d in $absent) { [void]$out.Add("      (not connected) $($d.Name)") }
    }
}

$drv = AsArray (Spin 'reading every installed driver and its date' {
    param($x)
    Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceName -and $_.DriverVersion }
} $null 90)

if (-not $drv.Count) {
    Warn 'Could not read the driver list. WMI did not answer in time, so driver ages are unknown.'
} else {
    Line 'Drivers installed' $drv.Count

    # The classes where a generic Microsoft driver is a real problem
    # rather than normal. Nobody needs a vendor driver for a keyboard.
    $keyClasses = 'DISPLAY|NET|MEDIA|SYSTEM|HDC|SCSIAdapter|Bluetooth|USB'
    $key = @($drv | Where-Object { $_.DeviceClass -match $keyClasses })

    # Windows shipping its own driver for graphics, network or audio means
    # the real one was never installed. This is the single most common
    # cause of "it works but it is slow" and "the WiFi keeps dropping",
    # and it is invisible in Device Manager unless you go looking.
    # A Microsoft driver on a MICROSOFT device is correct, not a gap.
    # Without this exclusion the warning fires on the Kernel Debug
    # Network Adapter, the Bluetooth A2DP sink, WAN miniports and the
    # streaming service proxy, which are all parts of Windows itself and
    # have no vendor driver to be missing. Nine such lines on a healthy
    # PC train the reader to skip the whole section, which then hides
    # the one line that is real.
    $msOwn = 'Kernel Debug|A2dp|Hands-Free|Streaming Service|WAN Miniport|RAS |Teredo|6to4|IP-HTTPS|Wi-Fi Direct|Virtual|Remote Desktop|Loopback|Personal Area Network'
    $generic = @($key | Where-Object {
        $_.DriverProviderName -match '^Microsoft' -and
        $_.DeviceClass -match 'DISPLAY|NET|MEDIA' -and
        $_.DeviceName -notmatch $msOwn -and
        $_.DeviceName -notmatch '^Microsoft '
    })
    # Count the list you are about to SHOW, not the list before dedup.
    # It said "3 important devices" and then printed 2, because the same
    # device name appears more than once and the display dedups it. A
    # count that disagrees with the list under it makes a reader distrust
    # both.
    $genericShown = @($generic | Sort-Object DeviceName -Unique)
    if ($genericShown.Count) {
        Warn "$($genericShown.Count) important device(s) are running Windows' own generic driver, not the manufacturer's."
        foreach ($g in ($genericShown | Select-Object -First 10)) {
            Line "  $($g.DeviceName)" "generic Microsoft driver, $($g.DeviceClass)"
        }
        Info 'They work, but slowly and with features missing. Usual cause of poor'
        Info 'graphics performance and WiFi that drops. The driver step often fixes it.'
    } else {
        Good 'no important device is stuck on a generic Microsoft driver'
    }

    # Age, on the devices that matter. A 2015 storage or network driver on
    # a machine you are handing over is worth saying out loud.
    $dated = @()
    foreach ($d in $key) {
        $dd = $null
        try { if ($d.DriverDate) { $dd = [datetime]$d.DriverDate } } catch { $dd = $null }
        # Provider is load bearing, not decoration: the age filter below
        # keys off it. It was missing from this object for one run, so
        # $_.Provider was $null, "$null -notmatch '^Microsoft'" is true,
        # and every single driver passed the vendor filter. The warning
        # still said 106.
        if ($dd) { $dated += [pscustomobject]@{ Name = $d.DeviceName; Class = $d.DeviceClass; Date = $dd; Ver = $d.DriverVersion; Provider = $d.DriverProviderName; Age = [math]::Round(((Get-Date) - $dd).TotalDays / 365.25, 1) } }
    }
    # AGE ONLY COUNTS FOR VENDOR DRIVERS.
    #
    # Microsoft's inbox drivers are dated by design, not by neglect. A
    # pile of them carry 2006 dates and are the current, correct, fully
    # supported driver for that device. Counting those produced "106
    # important drivers are 5 or more years old" on a healthy PC, which
    # is not a finding, it is a wall. Anything that reports 106 problems
    # teaches the reader to skip the section.
    #
    # A VENDOR driver going stale is the real signal, because that is the
    # one where a newer version plausibly exists and is worth chasing.
    if ($dated.Count) {
        # Two ways to spot a Windows inbox driver, because the provider
        # string alone is not enough. "Generic Access Profile" reported a
        # 2006 date with version 10.0.26100.8521 and a provider that is not
        # literally "Microsoft", so it was listed as a 20 year old
        # manufacturer driver. A version matching the OS build number is
        # Windows' own driver whatever the provider field says.
        $isInbox = { param($d) $d.Provider -match '^Microsoft' -or $d.Ver -match '^10\.0\.\d{5}' }
        $old   = @($dated | Where-Object { $_.Age -ge 5 -and -not (& $isInbox $_) } | Sort-Object Age -Descending)
        $msOld = @($dated | Where-Object { $_.Age -ge 5 -and (& $isInbox $_) })
        if ($old.Count) {
            Warn "$($old.Count) manufacturer driver(s) are 5 or more years old."
            foreach ($o in ($old | Select-Object -First 10)) {
                Line "  $($o.Name)" "$($o.Ver), $($o.Date.ToString('yyyy-MM-dd')), $($o.Age) years old"
            }
            if ($old.Count -gt 10) { Line '' "...and $($old.Count - 10) more, all listed in the saved report" }
            Info 'Old is not automatically broken. It matters when the device is also'
            Info 'misbehaving, or when it is the graphics, network or storage driver.'
        } else {
            Good 'no manufacturer driver is more than 5 years old'
        }
        if ($msOld.Count) {
            Line 'Microsoft drivers over 5yr' "$($msOld.Count), which is normal and not a fault"
            [void]$out.Add('        Microsoft ships inbox drivers with old dates on purpose. They are')
            [void]$out.Add('        the current supported driver for those devices.')
        }
        $newest = ($dated | Sort-Object Date -Descending | Select-Object -First 1)
        Line 'Most recent driver' "$($newest.Name), $($newest.Date.ToString('yyyy-MM-dd'))"
    }

    # Full inventory to the file, same reasoning as the software list:
    # on screen it buries the findings, in the file it is what you diff
    # before and after.
    [void]$out.Add('')
    [void]$out.Add('  FULL DRIVER LIST')
    foreach ($d in ($drv | Sort-Object DeviceClass, DeviceName)) {
        $dt = ''
        try { if ($d.DriverDate) { $dt = ([datetime]$d.DriverDate).ToString('yyyy-MM-dd') } } catch { $dt = '' }
        [void]$out.Add(("    {0,-14} {1,-46} {2,-18} {3}  {4}" -f $d.DeviceClass, $d.DeviceName, $d.DriverVersion, $dt, $d.DriverProviderName))
    }
    [void]$out.Add('')
}

# ---------------------------------------------------------- security
Sec 'Security'
# Every call in this section talks to a Windows SERVICE, and a wedged
# service does not return an error, it simply never answers. On a machine
# that has not been updated in years, or where a third-party antivirus has
# half-replaced Defender, these are the calls that hang forever. That is
# why the report froze on a desktop and finished on a laptop.
# These were 25 to 30 seconds and were timing out on almost every run,
# so the security section reported "could not read" as its normal state.
# A check that always gives up is worse than a slow one: it trains you to
# ignore the whole section. Defender and BitLocker in particular are slow
# to first response on a machine that has not been used in a while.
$mp = Spin 'asking Defender for its status' {
    param($x)
    Get-MpComputerStatus -ErrorAction SilentlyContinue
} $null 90
if (-not $mp) { Warn 'Could not read Defender status. It needs administrator rights, a third-party antivirus has replaced it, or the Defender service is not responding.' }
if ($mp) {
    Line 'Defender real-time' $(if($mp.RealTimeProtectionEnabled){'ON'}else{'OFF'})
    Line 'Signatures' $(if($mp.AntivirusSignatureLastUpdated){$mp.AntivirusSignatureLastUpdated.ToString('yyyy-MM-dd')}else{'unknown'})
    if (-not $mp.RealTimeProtectionEnabled) { Fail 'Defender real-time protection is OFF' }
    if ($mp.AntivirusSignatureLastUpdated -and $mp.AntivirusSignatureLastUpdated -lt (Get-Date).AddDays(-7)) { Warn 'antivirus signatures are over a week old' }
}
$fwAll = AsArray (Spin 'asking the firewall for its profiles' {
    param($x)
    Get-NetFirewallProfile -ErrorAction SilentlyContinue
} $null 60)
if (-not $fwAll.Count) { Warn 'Could not read the firewall profiles. The Windows Firewall service may not be running.' }
else {
    $fw = @($fwAll | Where-Object { -not $_.Enabled })
    if ($fw.Count) { Fail "firewall OFF for: $($fw.Name -join ', ')" } else { Good 'firewall on for all profiles' }
}

$bl = Spin 'checking BitLocker on C:' {
    param($x)
    Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
} $null 90
if ($bl) {
    Line 'BitLocker on C:' $bl.ProtectionStatus
    if ($bl.ProtectionStatus -eq 'On') {
        Warn 'BitLocker is ON. Get the recovery key BEFORE any repair or reinstall, or the data is gone for good.'
        $kp = ($bl.KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword')
        if ($kp) { Line '  recovery key ID' $kp.KeyProtectorId }
    }
} else {
    # This one MATTERS. "BitLocker line missing" and "BitLocker is off"
    # look identical on screen, and the difference is whether wiping the
    # disk loses the data for good. Never let it be silence.
    if (-not $Script:IsAdmin) { Warn 'Could not check BitLocker: it needs administrator rights. Do NOT assume the disk is unencrypted.' }
    else { Line 'BitLocker on C:' 'not enabled, or this volume is not BitLocker-capable' }
}

# Absolute (formerly Computrace) lives in the firmware of many
# ex-corporate Dell, HP and Lenovo laptops and can reinstall its agent
# after a wipe. Worth knowing about on a machine going to a child.
# Get-Service queries the Service Control Manager, and a wedged SCM does
# not error, it simply never answers. On a sick machine, which is what
# this tool is for, that is a silent hang with no heading printed yet.
$abs = AsArray (Spin 'checking for Absolute/Computrace persistence' {
    param($x)
    $found = @()
    if (Get-Service -Name 'rpcnet','rpcnetp' -ErrorAction SilentlyContinue) { $found += 'rpcnet service' }
    if (Test-Path 'HKLM:\SOFTWARE\Absolute')                                { $found += 'HKLM\SOFTWARE\Absolute' }
    if (Test-Path "$env:WINDIR\System32\rpcnet.exe")                        { $found += 'rpcnet.exe' }
    $found
} $null 30)
if ($abs.Count) {
    Warn "Absolute/Computrace persistence detected ($($abs -join ', ')). Ex-corporate laptops ship with this; it can phone home and reinstall itself after a wipe. Disable it in BIOS if the previous owner has released the machine."
} else { Good 'no Absolute/Computrace persistence found' }

# ------------------------------------------------------ system state
Sec 'System state'
$up = (Get-Date) - $os.LastBootUpTime
Line 'Uptime' "$([math]::Round($up.TotalDays,1)) days"
if ($up.TotalDays -gt 30) { Warn 'up for over a month. A lot of "slow computer" complaints are just this.' }

$rp = AsArray (Spin 'looking for restore points' {
    param($x)
    Get-ComputerRestorePoint -ErrorAction SilentlyContinue
} $null 45)
if ($rp.Count) {
    $newest = $rp | Sort-Object CreationTime -Descending | Select-Object -First 1
    # Get-ComputerRestorePoint returns CreationTime as a WMI datetime
    # STRING (20260813161500.000000-000), not a DateTime. Calling
    # .ToString('yyyy-MM-dd') on a string silently produced nothing, so
    # the report read "2, newest " with the date simply missing.
    $when = try { [Management.ManagementDateTimeConverter]::ToDateTime($newest.CreationTime).ToString('yyyy-MM-dd HH:mm') }
            catch { "$($newest.CreationTime)" }
    Line 'Restore points' "$($rp.Count), newest $when"
} else { Warn 'NO restore points. Nothing to roll back to if a repair goes wrong. Use the Restore Point tool first.' }

$pend = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
if (Test-Path $pend) { Warn 'a reboot is pending. Repairs can fail or half-apply until it is done.' }

# NAME them, do not just count them. "10 startup entries" tells you
# nothing you can act on. The list is where you spot the thing that
# should not be there.
$startup = AsArray (Spin 'listing the startup entries' {
    param($x)
    Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
} $null 30)
Line 'Startup entries' $startup.Count
foreach ($s in ($startup | Sort-Object Name)) {
    $cmd = "$($s.Command)"
    if ($cmd.Length -gt 70) { $cmd = $cmd.Substring(0, 70) + '...' }
    Line "  $($s.Name)" $cmd
}
if ($startup.Count -gt 20) { Warn "$($startup.Count) startup entries. Worth a look in Autoruns." }

$pageFile = Spin 'reading the page file' {
    param($x)
    Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
} $null 20
if ($pageFile) { Line 'Page file' "$([math]::Round($pageFile.AllocatedBaseSize/1024,1)) GB allocated" }

# Third-party antivirus alongside Defender is a classic cause of a
# machine crawling, and of Defender silently switching itself off.
#
# BUT "registered" IS NOT "installed". SecurityCenter2 lists products
# that have REGISTERED with Windows Security Center, and an OEM trial
# that was never activated, or a product that has been removed badly,
# stays on that list. This report said "AV registered: McAfee" on a
# client's laptop and sent us looking for McAfee to uninstall.
# It was not installed.
#
# So decode productState, which says whether it is actually switched ON
# and up to date, and cross-check the name against what is really in the
# uninstall registry. Only claim "installed" when both agree.
$av = AsArray (Spin 'asking Security Center which antivirus is registered' {
    param($x)
    Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
} $null 60)
if ($av) {
    # Both uninstall hives, one Get-ItemProperty per key. On a machine
    # with hundreds of installed programs that is hundreds of registry
    # reads and it is NOT instant, so it goes behind a spinner with a
    # timeout like every other slow read here. It sat silent before.
    $installedNames = AsArray (Spin 'cross-checking against installed programs' {
        param($x)
        $names = @()
        foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                         'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
            foreach ($i in (Get-ChildItem $k -ErrorAction SilentlyContinue)) {
                $p = Get-ItemProperty $i.PSPath -ErrorAction SilentlyContinue
                if ($p.DisplayName) { $names += [string]$p.DisplayName }
            }
        }
        $names
    } $null 60)

    foreach ($a in $av) {
        # productState is a bitfield. Byte 2 bit 0x10 means real-time
        # protection is on; byte 3 being zero means the signatures are
        # current. Verified against Defender on a live machine.
        $hex = '{0:X6}' -f $a.productState
        $on  = try { ([Convert]::ToInt32($hex.Substring(2,2),16) -band 0x10) -ne 0 } catch { $null }
        $utd = try { [Convert]::ToInt32($hex.Substring(4,2),16) -eq 0 } catch { $null }
        $state = "$(if ($on) { 'ON' } else { 'OFF' }), $(if ($utd) { 'up to date' } else { 'signatures OUT OF DATE' })"
        Line 'AV registered' "$($a.displayName)  [$state]"

        if ($a.displayName -notmatch 'Defender') {
            # Take the first word of the product name and look for it in
            # the real installed list. "McAfee LiveSafe" -> "McAfee".
            $stem = ($a.displayName -split '\s+')[0]
            $really = @($installedNames | Where-Object { $_ -like "*$stem*" })
            if ($really.Count) {
                Warn "$($a.displayName) is genuinely installed alongside Defender. Two real-time scanners fight."
                foreach ($r in ($really | Select-Object -Unique -First 4)) { Line '  installed as' $r }
            } else {
                # This is the case that wasted an afternoon.
                Warn "$($a.displayName) is REGISTERED with Windows Security Centre but is NOT installed."
                Line '' 'A stale registration, usually a dead OEM trial. Nothing to uninstall.'
                Line '' 'Clear it in Windows Security > Settings > Manage providers.'
            }
        }
    }
}

$net = AsArray (Spin 'listing the network adapters' {
    param($x)
    Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
} $null 60)
Line 'Network' $(if($net.Count){ ($net | ForEach-Object { $_.Name }) -join ', ' } else { 'NO active adapter' })
if (-not $net.Count) { Fail 'no active network adapter. Driver missing, or the hardware is off.' }

# ------------------------------------------------- installed software
# THIS IS THE LOG WE DID NOT HAVE.
#
# On one ex-corporate laptop, Malwarebytes found a bundled PUP browser
# and this report had said nothing about it, because it
# listed registered ANTIVIRUS and never listed installed PROGRAMS. An
# inventory would have shown it sitting there, and it is also the record
# you want when handing a machine over or comparing before and after.
Sec 'Installed software'
$apps = Spin 'reading the list of installed programs' {
    param($x)
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $out = @()
    foreach ($k in $keys) {
        foreach ($i in (Get-ChildItem $k -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty $i.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -and -not $p.SystemComponent) {
                $out += [pscustomobject]@{
                    Name      = [string]$p.DisplayName
                    Version   = [string]$p.DisplayVersion
                    Publisher = [string]$p.Publisher
                    Installed = [string]$p.InstallDate
                    Scope     = $(if ($k -like 'HKCU*') { 'this user' } else { 'all users' })
                }
            }
        }
    }
    $out | Sort-Object Name -Unique
} $null 60

if (-not (AsArray $apps).Count) { Warn 'Could not read the installed programs list.' }
else {
    Line 'Programs installed' (AsArray $apps).Count
    # The full list goes in the SAVED FILE, not on screen. 168 program
    # names scrolling past buries the battery, the disk and the security
    # findings, which are the things somebody is actually reading this
    # for. The file is where you go to compare before and after, or to
    # find the thing that should not be there.
    Line '' 'full list is in the saved report at the end'
    [void]$out.Add('')
    [void]$out.Add('  FULL INSTALLED SOFTWARE LIST')
    foreach ($a in (AsArray $apps)) {
        $v = if ($a.Version) { " $($a.Version)" } else { '' }
        $s = if ($a.Scope -eq 'this user') { '  [this user only]' } else { '' }
        [void]$out.Add(("    {0,-52} {1}{2}{3}" -f $a.Name, $a.Publisher, $v, $s))
    }
    [void]$out.Add('')

    # Things that are worth a second look on a machine you are handing to
    # somebody. Not a malware scanner: a prompt to go and check.
    $sus = @($apps | Where-Object {
        $_.Name -match 'Browser|Toolbar|Search|Coupon|Deal|PC ?Optimi|Driver ?(Updater|Booster)|Registry ?(Cleaner|Fix)|WebCompanion|OneLaunch|Wave ?Browser' -and
        $_.Name -notmatch 'Google Chrome|Microsoft Edge|Mozilla Firefox|Internet Explorer|Tor Browser'
    })
    if ($sus.Count) {
        Write-Host ''
        foreach ($s in $sus) { Warn "worth checking: $($s.Name)  ($($s.Publisher))" }
        Info 'Bundled browsers, toolbars and "optimiser" tools arrive with other installers.'
        Info 'A second browser also bypasses every Chrome policy on a club laptop.'
        Info 'Run a Malwarebytes scan and remove anything nobody chose to install.'
    }
}

# ---------------------------------------------------- Windows Update
# 161 of the 175 reliability events on one client laptop came from the
# Windows Update client, and this report had no way to say what they
# were. The install history is where "why does this machine keep
# failing updates" is actually answered.
Sec 'Windows Update history'
$wu = Spin 'reading the update history' {
    param($x)
    Get-WinEvent -FilterHashtable @{
        LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'
        StartTime = (Get-Date).AddDays(-60)
    } -ErrorAction SilentlyContinue | Select-Object -First 400
} $null 60

if (-not (AsArray $wu).Count) { Line 'Update events' 'none in the last 60 days' }
else {
    $ok   = @($wu | Where-Object { $_.Id -eq 19 })
    $fail = @($wu | Where-Object { $_.Id -in 20, 25, 31 })
    Line 'Update events (60 days)' "$((AsArray $wu).Count)  ($($ok.Count) installed, $($fail.Count) failed)"
    if ($ok.Count) {
        $last = $ok | Select-Object -First 1
        Line 'Last successful update' $last.TimeCreated.ToString('yyyy-MM-dd HH:mm')
    } else { Warn 'No update has installed successfully in 60 days.' }
    if ($fail.Count) {
        Warn "$($fail.Count) update failure(s) in 60 days."
        foreach ($f in ($fail | Select-Object -First 6)) {
            $m = (($f.Message -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1))
            Line "  $($f.TimeCreated.ToString('MM-dd HH:mm'))" $m
        }
        Info 'Repeated failures on the same update usually mean a damaged update store.'
        Info 'The repair and recovery step below can reset Windows Update.'
    }
}

# --------------------------------------------------- pending reboot
# A machine with a reboot pending gives misleading results from almost
# every other check, and repairs half-apply. Say so.
Sec 'Pending reboot'
$pend = @()
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pend += 'servicing' }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pend += 'Windows Update' }
if (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -EA SilentlyContinue) { $pend += 'files waiting to be renamed' }
if ($pend.Count) {
    Warn "A REBOOT IS PENDING ($($pend -join ', ')). Repairs can half-apply until it is done."
} else { Good 'no reboot pending' }

# ------------------------------------------------------------ verdict
Write-Host ''
Write-Host '   ==========================================' -ForegroundColor Cyan
[void]$out.Add(''); [void]$out.Add('VERDICT')
# EVERY issue is listed here, faults and warnings both.
#
# The warnings used to be counted on screen ("USABLE, with 6 things to
# note") and then written only into the saved file. So the closing
# summary, which is the part somebody actually reads before deciding what
# to do, named a number and not one of the six things. Worse, when there
# was a fault as well, the warnings were not shown at all: the run ended
# on "NOT READY: 1 problem" with six more findings invisible unless you
# scrolled back through the whole report or opened the file.
#
# This is the last thing on screen. It has to be the complete list.
if ($bad.Count) {
    Write-Host "    NOT READY: $($bad.Count) problem(s)" -ForegroundColor Red
    [void]$out.Add("NOT READY: $($bad.Count) problem(s)")
    foreach ($b in $bad) { Write-Host "      XX $b" -ForegroundColor Red; [void]$out.Add("  - $b") }
} elseif ($warn.Count) {
    Write-Host "    USABLE, with $($warn.Count) thing(s) to note" -ForegroundColor Yellow
    [void]$out.Add("USABLE, with $($warn.Count) thing(s) to note")
} else {
    Write-Host '    READY TO HAND OVER' -ForegroundColor Green
    [void]$out.Add('READY TO HAND OVER')
}
if ($warn.Count) {
    if ($bad.Count) {
        Write-Host ''
        Write-Host "    ...and $($warn.Count) thing(s) to note:" -ForegroundColor Yellow
    }
    foreach ($w in $warn) {
        Write-Host "      !! $w" -ForegroundColor Yellow
        [void]$out.Add("  ! $w")
    }
}
Write-Host '   ==========================================' -ForegroundColor Cyan

# DIAGNOSTICS. Anything that went wrong during the run, into the saved
# file only.
#
# A "CommandNotFoundException" or a typo'd property is a fault in this
# tool, not in the machine being examined, and it must never be presented
# to a client as a finding about their PC. It must also never be silently
# dropped, which is what SilentlyContinue does on its own and how a real
# bug survived a whole run undetected earlier in this tool's life.
#
# Filtered to the kinds that indicate a coding mistake. The expected
# noise (a WMI class that does not exist on this hardware) is exactly
# what SilentlyContinue is for and stays suppressed.
$ourFaults = @($Error | Where-Object {
    $_.CategoryInfo.Reason -match 'CommandNotFoundException|MethodInvocationException|RuntimeException|NullReferenceException|ParameterBindingException'
})
if ($ourFaults.Count) {
    [void]$out.Add('')
    [void]$out.Add('Tool diagnostics')
    [void]$out.Add('----------------')
    [void]$out.Add("$($ourFaults.Count) internal error(s) during this run. These are faults in this")
    [void]$out.Add('tool, NOT findings about this computer. Please report them.')
    foreach ($e in ($ourFaults | Select-Object -First 10)) {
        [void]$out.Add("  $($e.CategoryInfo.Reason): $($e.Exception.Message)")
        if ($e.InvocationInfo -and $e.InvocationInfo.ScriptLineNumber) {
            [void]$out.Add("    at line $($e.InvocationInfo.ScriptLineNumber) of $(Split-Path $e.InvocationInfo.ScriptName -Leaf)")
        }
    }
    Write-Host ''
    Write-Host "    ($($ourFaults.Count) internal tool error(s) recorded in the saved report. The" -ForegroundColor DarkGray
    Write-Host '     findings above are unaffected.)' -ForegroundColor DarkGray
}

# WHERE THE REPORT GOES.
#
# Next to the tool first, because on a USB stick that means every machine
# you touch collects in one folder, which is the whole point of carrying
# it. That is also "where it is installed" when somebody has copied this
# onto a PC.
#
# But that location is not always writable. Run from Program Files, from
# a read-only stick, or from a network share, and Set-Content throws. The
# old code caught that and printed "could not save", and the entire
# report was then LOST: minutes of checks on somebody's machine, gone,
# with the console about to close.
#
# So it falls back, in order of how findable the file is afterwards, and
# always says exactly where the file went. A report saved somewhere
# unexpected is recoverable; a report not saved at all is not.
function Get-ReportPath {
    # -PrimaryDir rather than reading $PSScriptRoot inside: a function
    # that reaches for an automatic variable cannot be tested, because
    # $PSScriptRoot is whatever the CALLER's file is. The first test of
    # this reported a failure that was purely an artefact of that.
    param(
        [string]$Leaf,
        [string]$PrimaryDir = $PSScriptRoot
    )
    $candidates = @(
        $PrimaryDir                                                      # beside the tool
        (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Lazarus Reports')
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Lazarus Reports')
        $env:TEMP                                                        # last resort
    )
    foreach ($dir in $candidates) {
        if (-not $dir) { continue }
        try {
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
            # Prove it is writable rather than assuming. A folder can
            # exist and still refuse a write.
            $probe = Join-Path $dir ('.w' + [guid]::NewGuid().ToString('N').Substring(0, 6))
            [System.IO.File]::WriteAllText($probe, 'x')
            [System.IO.File]::Delete($probe)
            return (Join-Path $dir $Leaf)
        } catch { continue }
    }
    return $null
}

$stamp = Get-Date -f 'yyyy-MM-dd_HHmm'
$file  = Get-ReportPath "report-$env:COMPUTERNAME-$stamp.txt"
if ($file) {
    try {
        $out -join "`r`n" | Set-Content $file -Encoding UTF8
        Write-Host ''
        Write-Host "    Saved: $file" -ForegroundColor DarkGray
        if ((Split-Path $file -Parent) -ne $PSScriptRoot) {
            Write-Host '           (the tool folder was not writable, so it went here instead)' -ForegroundColor DarkGray
        }
    } catch {
        Write-Host ''
        Write-Host "    Could not save the report: $($_.Exception.Message)" -ForegroundColor Red
        $file = $null
    }
} else {
    Write-Host ''
    Write-Host '    Could not find anywhere writable to save the report.' -ForegroundColor Red
    Write-Host '    Everything found is on screen above. Scroll up before closing this.' -ForegroundColor Yellow
}

# The readable copy. Failing to write it must never take the run down
# with it: the .txt above is the record that matters and it is already
# safely on disk by this point.
$verdictText = if ($bad.Count) { "NOT READY: $($bad.Count) fault(s) need attention" }
               elseif ($warn.Count) { "USABLE, with $($warn.Count) thing(s) to note" }
               else { 'READY TO HAND OVER' }
try {
    # Beside the .txt, wherever that ended up, so the pair never get
    # separated. Falls back the same way if the tool folder was read-only.
    $mdLeaf = "report-$env:COMPUTERNAME-$stamp.md"
    $mdFile = if ($file) { Join-Path (Split-Path $file -Parent) $mdLeaf } else { Get-ReportPath $mdLeaf }
    if (-not $mdFile) { throw 'nowhere writable' }
    Write-MarkdownReport -Lines $out -Path $mdFile -Verdict $verdictText -WarnCount $warn.Count -BadCount $bad.Count
    Write-Host "    Saved: $mdFile" -ForegroundColor DarkGray
    Write-Host '           (the readable copy: pastes into a ticket, or hand it to an AI)' -ForegroundColor DarkGray
} catch {
    Write-Host "    The Markdown copy could not be written: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host '           The .txt above is complete and unaffected.' -ForegroundColor DarkGray
}

# ---------------------------------------------------- repair and fix
# Everything above only READS. The repairs live behind this prompt so a
# report can never turn into a repair by accident.
#
# It used to be called the "deeper health check", which was wrong in the
# way that matters: it does not check anything. It repairs. SFC, DISM,
# the Windows Update reset, the network stack reset and the driver
# install all CHANGE the machine. Calling a repair step a "check" invites
# somebody to run it on a client PC believing it is read-only, which is
# exactly the mistake the y/n prompt exists to prevent.
$deep = Join-Path $PSScriptRoot 'Repair-Health.ps1'
if ($Script:Unattended) {
    Write-Host ''
    Write-Host '    Unattended run: repairs were not offered. Nothing was changed.' -ForegroundColor DarkGray
} elseif (Test-Path $deep) {
    Write-Host ''
    Write-Host '   ==========================================' -ForegroundColor Cyan
    Write-Host '    REPAIR AND RECOVERY' -ForegroundColor Cyan
    Write-Host '   ==========================================' -ForegroundColor Cyan
    Write-Host ''
    # The seven bullet lines that used to be here listed the repairs on
    # offer. The very next screen is a menu listing the same repairs with
    # fuller descriptions and time estimates, so this was the same
    # information twice, thirty seconds apart.
    Write-Host '    Everything above was read-only. This part CHANGES the machine.' -ForegroundColor DarkGray
    Write-Host '    You pick which repairs to run from a menu.' -ForegroundColor DarkGray
    Write-Host ''
    if ((Read-Host '    Run the repair and recovery now? (y/n)') -match '^y') {
        & $deep
        exit
    }
} else {
    Write-Host ''
    Write-Host "    (Repair-Health.ps1 is missing from $PSScriptRoot, so repair and recovery is unavailable.)" -ForegroundColor DarkGray
}

Write-Host ''
# The window is the report until somebody has read it, so it stays open.
# Unattended there is nobody to press anything, and a scheduled run that
# waits forever on a keystroke is a hung task, not a finished one.
if (-not $Script:Unattended) { Read-Host '    Press Enter to close' }
