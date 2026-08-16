<#
=======================================================================
 INSTALL - HEALTH REPORT AND REPAIR

     .\Install.ps1               # install for the current user
     .\Install.ps1 -WhatIfOnly   # say what it WOULD do, touch nothing
     .\Install.ps1 -Destination 'D:\Tools\HealthReport'

 WHY THIS EXISTS

 The rest of the toolkit is a USB stick: you plug it in, you run it, you
 unplug it, and nothing is installed on the machine being fixed. That is
 deliberate and it stays that way.

 This is the other case. On YOUR OWN machine, the bench PC, the laptop
 you carry to a job, you want the report on the Start menu and in the
 terminal, not down four folders on a stick that is in a drawer. Copying
 the folder by hand is what happened instead, and a hand-copy has no
 version, no shortcut, no uninstall and no way to tell whether it is the
 current one.

 PER USER, ON PURPOSE. It installs under %LOCALAPPDATA%, so installing
 needs no administrator at all. The TOOL still elevates itself when it
 runs, because SMART, BitLocker, battery capacity and every repair need
 it. Those are two different permissions and conflating them is how you
 end up demanding admin to copy six files.

 Everything it writes is recorded in installed.json next to the tool, and
 Uninstall.ps1 removes exactly that and nothing else.
=======================================================================
#>
param(
    # Default resolved below rather than here, because a default that
    # calls Join-Path in the param block is evaluated before $env is
    # readable in some hosts and comes out as a bare relative path.
    [string]$Destination,
    [switch]$NoShortcuts,
    [switch]$NoPath,
    [switch]$NoUninstallEntry,
    [switch]$WhatIfOnly,
    # Answer the "already installed, overwrite?" question up front. For a
    # scripted or unattended install. No question is ever asked mid-run.
    [switch]$Force
)

# 'Continue', not 'SilentlyContinue'. Health-Report.ps1 runs quiet
# because it queries WMI that legitimately fails on some machines. An
# installer has no such excuse: every failure here is either a real
# problem or a bug in this file, and both must be visible. A silent
# installer that half-worked is the worst outcome available.
$ErrorActionPreference = 'Continue'

. (Join-Path $PSScriptRoot 'Common.ps1')
Set-ConsoleLook 'Install: Health Report and Repair'

$ProductName = 'Health Report and Repair'
$ProductKey  = 'HealthReportAndRepair'
$Publisher   = 'Perpetual Technologies'
$Version     = '1.0.0'

# Its OWN output helpers. Good, Warn and Info live in Health-Report.ps1
# and Repair-Health.ps1, and both versions also append to that script's
# report buffer, so calling them from here would find nothing and print
# nothing. Collect-ToolLogs.ps1 carries its own for the same reason.
function Say-Step($m) { Write-Host "    >>   $m" -ForegroundColor Cyan }
function Say-Good($m) { Write-Host "    ok   $m" -ForegroundColor Green }
function Say-Warn($m) { Write-Host "    !!   $m" -ForegroundColor Yellow }
function Say-Fail($m) { Write-Host "    XX   $m" -ForegroundColor Red }
function Say-Info($m) { Write-Host "         $m" -ForegroundColor DarkGray }

# ---------------------------------------------------------------------
#  WHAT GETS INSTALLED
#
#  Named explicitly rather than copied wholesale. A wildcard copy of this
#  folder would also take every report-<MACHINE>-<date>.md sitting in it,
#  and those contain another person's machine name, model, SERIAL NUMBER
#  and installed software. Installing the tool must never carry one
#  client's hardware inventory onto the next client's PC.
#
#  Required vs optional is stated, so a missing required file stops the
#  install rather than producing something that looks installed and dies
#  on first run.
# ---------------------------------------------------------------------
$payload = @(
    @{ Name = 'Common.ps1';           Required = $true  }
    @{ Name = 'Health-Report.ps1';    Required = $true  }
    @{ Name = 'Health-Report.bat';    Required = $true  }
    @{ Name = 'Repair-Health.ps1';    Required = $true  }
    @{ Name = 'Clear-Reports.ps1';    Required = $false }
    @{ Name = 'Collect-ToolLogs.ps1'; Required = $false }
    @{ Name = 'Uninstall.ps1';        Required = $false }
)

# ---------------------------------------------------------------------
#  SHORTCUT, WITH THE RUN-AS-ADMINISTRATOR BIT SET
#
#  Health-Report.bat already elevates itself, so this is not what makes
#  admin work. What it changes is WHEN: without the bit, the shortcut
#  opens an unelevated console, that console relaunches itself, and you
#  watch a black window flash and vanish before the UAC prompt arrives.
#  It looks like the tool crashed. With the bit, the prompt is the first
#  thing that happens.
#
#  There is no property on WScript.Shell for this. The flag lives in the
#  .lnk header: LinkFlags is a 4-byte field at offset 20, and RunAsUser
#  is bit 5 of its second byte, so byte 21 OR 0x20. It is set by
#  rewriting the file after the shell has created it.
# ---------------------------------------------------------------------
function Set-ShortcutRunAsAdmin([string]$Path) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -lt 22) { return $false }
        $bytes[21] = $bytes[21] -bor 0x20
        [System.IO.File]::WriteAllBytes($Path, $bytes)
        # Read it BACK. Setting a byte and assuming is exactly the class
        # of "it returned without throwing, so it worked" that this
        # project keeps getting caught by.
        $check = [System.IO.File]::ReadAllBytes($Path)
        return (($check[21] -band 0x20) -eq 0x20)
    } catch { return $false }
}

function New-ToolShortcut {
    param([string]$Path, [string]$Target, [string]$WorkDir, [string]$Description, [string]$IconPath)
    try {
        $dir = Split-Path $Path -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($Path)
        $sc.TargetPath       = $Target
        $sc.WorkingDirectory = $WorkDir
        $sc.Description      = $Description
        if ($IconPath -and (Test-Path $IconPath)) { $sc.IconLocation = "$IconPath,0" }
        $sc.Save()
        # Releasing the COM object matters here. Without it the shortcut
        # file can still be held open when the byte-patch below tries to
        # rewrite it, and the patch fails with a sharing violation on
        # some machines and not others.
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sc)
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        return $true
    } catch {
        Say-Fail "could not create $(Split-Path $Path -Leaf): $($_.Exception.Message)"
        return $false
    }
}

# ---------------------------------------------------------------------
#  ICON
#
#  The repo ships PNGs for the launcher. A .lnk wants a .ico, so one is
#  built at install time from Icons\healthreport.png.
#
#  Entirely optional. If the PNG is missing, or System.Drawing is not
#  available on this host, the shortcut simply gets the default console
#  icon and the install carries on. An installer that fails over a
#  picture is a bad installer.
# ---------------------------------------------------------------------
function ConvertTo-Icon {
    param([string]$PngPath, [string]$IcoPath)
    try {
        if (-not (Test-Path $PngPath)) { return $false }
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $bmp = New-Object System.Drawing.Bitmap $PngPath
        $handle = $bmp.GetHicon()
        $icon = [System.Drawing.Icon]::FromHandle($handle)
        $fs = [System.IO.File]::Create($IcoPath)
        $icon.Save($fs)
        $fs.Close()
        $icon.Dispose()
        $bmp.Dispose()
        return (Test-Path $IcoPath)
    } catch { return $false }
}

# ---------------------------------------------------------------------
#  USER PATH
#
#  Read and written through the registry rather than through
#  [Environment]::SetEnvironmentVariable, which looks like the obvious
#  call and is a trap: it writes REG_SZ. A user PATH is normally
#  REG_EXPAND_SZ and frequently contains %USERPROFILE% or %LOCALAPPDATA%
#  literally, so rewriting it as REG_SZ turns those into dead literal
#  text and silently breaks every other tool the user installed.
#
#  DoNotExpandEnvironmentNames is the matching half on the read side:
#  without it, reading gives the EXPANDED value, and writing that back
#  bakes today's paths in permanently.
# ---------------------------------------------------------------------
function Get-UserPathRaw {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $false)
    if (-not $key) { return '' }
    try {
        $v = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        return [string]$v
    } finally { $key.Close() }
}

function Set-UserPathRaw([string]$Value) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if (-not $key) { $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment') }
    try {
        # Preserve whatever kind it already was; only default to
        # ExpandString when there is no Path value at all yet.
        $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
        try { $kind = $key.GetValueKind('Path') } catch { }
        $key.SetValue('Path', $Value, $kind)
        return $true
    } catch {
        Say-Fail "could not write the user PATH: $($_.Exception.Message)"
        return $false
    } finally { $key.Close() }
}

# A PATH change written to the registry is invisible to every process
# already running, including Explorer, so a new terminal opened from the
# Start menu inherits the OLD one. Explorer only re-reads on
# WM_SETTINGCHANGE. Broadcast it, with a timeout, because a hung window
# on the desktop would otherwise block this forever.
function Publish-EnvironmentChange {
    try {
        if (-not ('HealthKit.EnvBroadcast' -as [type])) {
            Add-Type -ErrorAction Stop -Namespace HealthKit -Name EnvBroadcast -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@
        }
        $result = [System.UIntPtr]::Zero
        # HWND_BROADCAST 0xFFFF, WM_SETTINGCHANGE 0x1A, SMTO_ABORTIFHUNG 0x2,
        # 3000 ms. The timeout is the point: without it this is a blocking
        # call whose duration is set by the slowest window on the desktop.
        [void][HealthKit.EnvBroadcast]::SendMessageTimeout(
            [System.IntPtr]0xFFFF, 0x1A, [System.IntPtr]::Zero, 'Environment', 0x2, 3000, [ref]$result)
        return $true
    } catch { return $false }
}

# ---------------------------------------------------------------------
#  START
# ---------------------------------------------------------------------
Clear-Host
Write-Host ''
Show-Box -Colour Cyan -Lines @(
    "INSTALL: $ProductName  v$Version",
    'Installs for you only. No administrator needed to install.',
    'The tool asks for administrator itself when you run it.'
)
Write-Host ''

if (-not $Destination) { $Destination = Join-Path $env:LOCALAPPDATA (Join-Path 'Programs' $ProductName) }
$source = $PSScriptRoot

# Installing a folder onto itself deletes the thing being installed on
# any implementation that clears the destination first. Caught here
# rather than trusted not to happen.
if ([System.IO.Path]::GetFullPath($source).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($Destination).TrimEnd('\')) {
    Say-Fail 'the destination is the folder this installer is running from.'
    Say-Info 'Nothing to do. Pass -Destination to install somewhere else.'
    exit 1
}

Say-Info "From:  $source"
Say-Info "To:    $Destination"
Write-Host ''

# --- 1. Is everything here to install? -------------------------------
Say-Step 'checking the source folder'
$missingRequired = @()
foreach ($p in $payload) {
    if (-not (Test-Path (Join-Path $source $p.Name)) -and $p.Required) { $missingRequired += $p.Name }
}
if ($missingRequired.Count) {
    Say-Fail "cannot install: missing $($missingRequired -join ', ')"
    Say-Info 'Run this from inside the HealthReport folder of a complete checkout.'
    exit 1
}
Say-Good 'all required files present'

# --- 2. Existing install ---------------------------------------------
# Asked BEFORE any work starts, never in the middle of it. A prompt
# underneath a wall of output is indistinguishable from a freeze, which
# is a standing rule in this toolkit.
$existing = Test-Path $Destination
if ($existing -and -not $WhatIfOnly -and -not $Force) {
    Write-Host ''
    Say-Warn "$Destination already exists."
    Say-Info 'The scripts will be overwritten. Saved reports are left alone.'
    $answer = Read-Host '         Continue? (y/n)'
    if ($answer -notmatch '^[Yy]') { Write-Host ''; Say-Info 'Nothing was changed.'; exit 0 }
    Write-Host ''
}

if ($WhatIfOnly) {
    Write-Host ''
    Say-Warn 'WHAT-IF: nothing below is actually written.'
    Write-Host ''
}

# --- 3. Copy ----------------------------------------------------------
Say-Step 'copying the tool'
$installed = @()
$copyFailed = 0
foreach ($p in $payload) {
    $src = Join-Path $source $p.Name
    if (-not (Test-Path $src)) { Say-Info "$($p.Name) not in this checkout, skipped"; continue }
    $dst = Join-Path $Destination $p.Name
    if (-not $WhatIfOnly) {
        try {
            if (-not (Test-Path $Destination)) { New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop | Out-Null }
            Copy-Item $src $dst -Force -ErrorAction Stop
        } catch {
            Say-Fail "$($p.Name): $($_.Exception.Message)"
            $copyFailed++
            continue
        }
    }
    $installed += $dst
}
if ($copyFailed) {
    Say-Fail "$copyFailed file(s) could not be copied. Stopping rather than leaving a half install."
    exit 1
}
Say-Good "$($installed.Count) file(s) copied"

# --- 4. The terminal command -----------------------------------------
# A .cmd rather than a .ps1, so `health-report` works from cmd, from
# PowerShell and from Windows Terminal without an execution policy
# argument or a .ps1 file association. It forwards its arguments, so
# `health-report -Unattended` reaches the script.
Say-Step 'writing the health-report command'
$shim = Join-Path $Destination 'health-report.cmd'
$shimBody = @"
@echo off
:: Written by Install.ps1. Runs the installed Health Report and Repair.
:: Health-Report.bat elevates itself, so this does not need to.
call "%~dp0Health-Report.bat" %*
"@
if (-not $WhatIfOnly) {
    try {
        # ASCII, deliberately. A .cmd saved as UTF-8 with a BOM has three
        # stray bytes in front of @echo off, and cmd.exe reports
        # "'∩╗┐@echo' is not recognized" on the first line of every run.
        Set-Content -Path $shim -Value $shimBody -Encoding Ascii -ErrorAction Stop
        $installed += $shim
        Say-Good 'health-report.cmd written'
    } catch { Say-Fail "could not write health-report.cmd: $($_.Exception.Message)" }
} else { Say-Good 'health-report.cmd would be written' }

# --- 5. Icon ----------------------------------------------------------
$icoPath = Join-Path $Destination 'healthreport.ico'
# Icons\ sits at the REPO ROOT, and this file now lives two levels down
# at Tools\HealthReport\. It was one level down before, so a hardcoded
# "parent + Icons" silently started resolving to Tools\Icons, which does
# not exist. The icon is optional, so that failure would have been
# invisible: shortcuts would just quietly have gone back to the default
# console icon and nothing would have said why.
#
# Walk up instead of counting levels, so moving this folder again does
# not break it a second time.
$pngPath = ''
$probe = $source
for ($up = 0; $up -lt 4 -and $probe; $up++) {
    $cand = Join-Path (Join-Path $probe 'Icons') 'healthreport.png'
    if (Test-Path $cand) { $pngPath = $cand; break }
    $probe = Split-Path $probe -Parent
}
if (-not $WhatIfOnly -and -not $NoShortcuts) {
    Say-Step 'building the icon'
    if (ConvertTo-Icon -PngPath $pngPath -IcoPath $icoPath) {
        $installed += $icoPath
        Say-Good 'icon built from Icons\healthreport.png'
    } else {
        $icoPath = ''
        Say-Info 'no icon built, shortcuts will use the default console icon'
    }
}

# --- 6. Shortcuts -----------------------------------------------------
$shortcuts = @()
if ($NoShortcuts) {
    Say-Info 'shortcuts skipped (-NoShortcuts)'
} else {
    Say-Step 'creating shortcuts'
    $target   = Join-Path $Destination 'Health-Report.bat'
    $startDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $wanted = @(
        (Join-Path $startDir "$ProductName.lnk")
        (Join-Path ([Environment]::GetFolderPath('Desktop')) "$ProductName.lnk")
    )
    foreach ($lnk in $wanted) {
        $where = if ($lnk -like "$startDir*") { 'Start menu' } else { 'Desktop' }
        if ($WhatIfOnly) { Say-Good "$where shortcut would be created"; continue }
        if (New-ToolShortcut -Path $lnk -Target $target -WorkDir $Destination `
                             -Description 'Survey and repair this PC' -IconPath $icoPath) {
            # Recorded in $shortcuts ONLY, not also in $installed. Being
            # in both listed every shortcut twice in the uninstaller's
            # dry run, once as a "file" and once as a "shortcut", which
            # reads like the uninstaller has lost track of what it put
            # where. It removes them from $shortcuts.
            $shortcuts += $lnk
            if (Set-ShortcutRunAsAdmin $lnk) {
                Say-Good "$where shortcut, marked run as administrator"
            } else {
                # Not fatal, and worth saying out loud rather than
                # leaving somebody to discover it. The .bat still
                # elevates; the window just flashes first.
                Say-Warn "$where shortcut created, but the run-as-administrator flag would not set"
                Say-Info 'The tool still elevates itself when it starts.'
            }
        }
    }
}

# --- 7. PATH ----------------------------------------------------------
$pathAdded = $false
if ($NoPath) {
    Say-Info 'PATH left alone (-NoPath)'
} else {
    Say-Step 'adding the tool to your PATH'
    $raw = Get-UserPathRaw
    # Split and compare entry by entry. A substring test reports "already
    # there" for a path that merely CONTAINS this one as a prefix, and
    # then the command never works and nothing ever says why.
    $entries = @($raw -split ';' | Where-Object { $_ -ne '' })
    $already = @($entries | Where-Object { $_.TrimEnd('\') -ieq $Destination.TrimEnd('\') }).Count -gt 0
    if ($already) {
        Say-Good 'already on your PATH'
        $pathAdded = $true
    } elseif ($WhatIfOnly) {
        Say-Good 'would be added to your PATH'
    } else {
        $new = if ($entries.Count) { ($entries -join ';') + ';' + $Destination } else { $Destination }
        if (Set-UserPathRaw $new) {
            $pathAdded = $true
            # Same session too, or the person who just ran the installer
            # types health-report in this very window and is told it does
            # not exist.
            $env:Path = $env:Path + ';' + $Destination
            if (Publish-EnvironmentChange) { Say-Good 'added to your PATH, and open programs told to re-read it' }
            else { Say-Good 'added to your PATH (open terminals need reopening)' }
        }
    }
}

# --- 8. Add/Remove Programs ------------------------------------------
$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$ProductKey"
if ($NoUninstallEntry) {
    Say-Info 'Add/Remove Programs entry skipped (-NoUninstallEntry)'
} elseif ($WhatIfOnly) {
    Say-Step 'registering with Add/Remove Programs'
    Say-Good 'would appear in Settings > Apps'
} else {
    Say-Step 'registering with Add/Remove Programs'
    try {
        if (-not (Test-Path $uninstallKey)) { New-Item -Path $uninstallKey -Force -ErrorAction Stop | Out-Null }
        $size = 0
        foreach ($f in $installed) { if (Test-Path $f) { $size += (Get-Item $f).Length } }
        $uninstaller = Join-Path $Destination 'Uninstall.ps1'
        $props = @{
            DisplayName     = $ProductName
            DisplayVersion  = $Version
            Publisher       = $Publisher
            InstallLocation = $Destination
            UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$uninstaller`""
            NoModify        = 1
            NoRepair        = 1
            EstimatedSize   = [int]($size / 1KB)
        }
        if ($icoPath) { $props['DisplayIcon'] = $icoPath }
        foreach ($k in $props.Keys) {
            Set-ItemProperty -Path $uninstallKey -Name $k -Value $props[$k] -Force -ErrorAction Stop
        }
        Say-Good 'listed in Settings > Apps > Installed apps'
    } catch {
        Say-Warn "could not register for uninstall: $($_.Exception.Message)"
        Say-Info 'Everything else installed. Uninstall.ps1 still removes it.'
    }
}

# --- 9. The manifest --------------------------------------------------
# Uninstall reads this and removes exactly what was written. Without it
# an uninstaller has to guess, and guessing means either leaving litter
# behind or deleting a folder somebody put their own files in.
if (-not $WhatIfOnly) {
    # The manifest LISTS ITSELF.
    #
    # It is written after everything else, so it was not in its own Files
    # list, and the uninstaller then found a file it did not recognise
    # sitting in the install folder. That check exists to protect
    # anything the user put there, so it correctly refused to delete the
    # folder, and an uninstall could therefore never fully finish: it
    # removed 8 files and left installed.json, Uninstall.ps1 and the
    # directory behind every time. Verified by running a real uninstall.
    $manifestPath = Join-Path $Destination 'installed.json'
    $manifest = [pscustomobject]@{
        Product     = $ProductName
        Version     = $Version
        InstalledAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Destination = $Destination
        Files       = @($installed + $manifestPath)
        Shortcuts   = @($shortcuts)
        PathEntry   = $(if ($pathAdded) { $Destination } else { '' })
        UninstallKey= $uninstallKey
    }
    try {
        $manifest | ConvertTo-Json -Depth 4 |
            Set-Content -Path $manifestPath -Encoding UTF8 -ErrorAction Stop
    } catch { Say-Warn "could not write installed.json: $($_.Exception.Message)" }
}

# --- 10. Prove it, rather than announce it ----------------------------
# Everything above reports on the call it just made. This checks the
# machine instead. "Copy-Item did not throw" and "the file is there" are
# different claims, and only the second one is the install.
Write-Host ''
Say-Step 'verifying the install'
$problems = @()
if (-not $WhatIfOnly) {
    foreach ($p in $payload) {
        if (-not $p.Required) { continue }
        if (-not (Test-Path (Join-Path $Destination $p.Name))) { $problems += "$($p.Name) is not in the install folder" }
    }
    if (-not (Test-Path $shim)) { $problems += 'health-report.cmd is missing' }
    foreach ($lnk in $shortcuts) {
        if (-not (Test-Path $lnk)) { $problems += "$(Split-Path $lnk -Leaf) is missing" }
    }
    # Does the installed copy actually parse? A truncated or half-written
    # copy passes Test-Path and fails on first run, in front of a client.
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $Destination 'Health-Report.ps1'), [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count) { $problems += "the copied Health-Report.ps1 does not parse (line $($errs[0].Extent.StartLineNumber))" }
}
if ($problems.Count) {
    foreach ($p in $problems) { Say-Fail $p }
} elseif (-not $WhatIfOnly) {
    Say-Good 'every installed file is present and the main script parses'
}

# --- Done -------------------------------------------------------------
Write-Host ''
if ($WhatIfOnly) {
    Show-Box -Colour Yellow -Lines @(
        'WHAT-IF ONLY. Nothing was installed.',
        'Run .\Install.ps1 without -WhatIfOnly to do it.'
    )
    exit 0
}
if ($problems.Count) {
    Show-Box -Colour Red -Lines @(
        'INSTALLED, WITH PROBLEMS',
        'The list above says what is wrong. Fix it or run',
        'Uninstall.ps1 and try again.'
    )
    exit 1
}

$lines = @(
    'INSTALLED',
    '',
    "Folder:      $Destination"
)
if ($shortcuts.Count) { $lines += 'Start menu:  search for "Health Report"' }
if ($pathAdded)       { $lines += 'Terminal:    health-report' }
$lines += ''
$lines += 'It asks for administrator when it runs. Say yes: battery'
$lines += 'wear, SMART data, activation and BitLocker all need it.'
$lines += ''
$lines += 'Remove it from Settings > Apps, or run Uninstall.ps1.'
Show-Box -Colour Green -Lines $lines
Write-Host ''
if ($pathAdded) { Say-Info 'Terminals that were already open need reopening before health-report works in them.' }
Write-Host ''
exit 0
