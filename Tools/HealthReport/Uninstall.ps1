<#
=======================================================================
 UNINSTALL - HEALTH REPORT AND REPAIR

     .\Uninstall.ps1                 # show what would go, remove nothing
     .\Uninstall.ps1 -Confirm        # do it
     .\Uninstall.ps1 -Confirm -RemoveReports

 DRY RUN BY DEFAULT, the same as Clear-Reports.ps1, and for the same
 reason: this deletes things, and the version of it that deletes on sight
 is the version that eats a folder somebody put their own files in.

 SAVED REPORTS ARE NOT DELETED unless you ask twice.

 A report contains the machine name, make, model, SERIAL NUMBER, event
 log entries and installed software of the computer it ran on. Do a dozen
 jobs and the install folder is quietly holding a dozen hardware
 inventories belonging to other people. Uninstalling the TOOL is not a
 statement about the RECORDS, so by default they are moved somewhere
 findable rather than destroyed, and where they went is printed.

 It removes exactly what installed.json says was installed. If that file
 is gone it falls back to the known layout and says so, because guessing
 quietly is how an uninstaller deletes the wrong folder.
=======================================================================
#>
param(
    [switch]$Confirm,
    # Delete the saved reports too. Two switches, on purpose: -Confirm
    # alone must never destroy another person's records.
    [switch]$RemoveReports,
    [string]$InstallDir
)

$ErrorActionPreference = 'Continue'

$ProductName = 'Health Report and Repair'
$ProductKey  = 'HealthReportAndRepair'

function Say-Step($m) { Write-Host "    >>   $m" -ForegroundColor Cyan }
function Say-Good($m) { Write-Host "    ok   $m" -ForegroundColor Green }
function Say-Warn($m) { Write-Host "    !!   $m" -ForegroundColor Yellow }
function Say-Info($m) { Write-Host "         $m" -ForegroundColor DarkGray }

# Common.ps1 is loaded only if it is next to us, and only for Show-Box.
# The uninstaller has to keep working on a broken or partial install,
# which is precisely when Common.ps1 might be the file that is missing.
$commonPath = Join-Path $PSScriptRoot 'Common.ps1'
$haveCommon = Test-Path $commonPath
if ($haveCommon) { . $commonPath }

function Show-Banner([string]$Colour, [string[]]$Lines) {
    if ($haveCommon) { Show-Box -Colour $Colour -Lines $Lines; return }
    Write-Host ''
    foreach ($l in $Lines) { Write-Host "    $l" -ForegroundColor $Colour }
    Write-Host ''
}

if (-not $InstallDir) { $InstallDir = $PSScriptRoot }

Write-Host ''
Show-Banner 'Cyan' @("UNINSTALL: $ProductName", "From: $InstallDir")
Write-Host ''

# --- What was installed ----------------------------------------------
$manifestPath = Join-Path $InstallDir 'installed.json'
$files = @(); $shortcuts = @(); $pathEntry = ''; $uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$ProductKey"

if (Test-Path $manifestPath) {
    try {
        $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
        $files      = @($m.Files)
        $shortcuts  = @($m.Shortcuts)
        $pathEntry  = [string]$m.PathEntry
        if ($m.UninstallKey) { $uninstallKey = [string]$m.UninstallKey }
        Say-Good "read installed.json: $($files.Count) file(s) recorded"
    } catch {
        Say-Warn "installed.json is unreadable: $($_.Exception.Message)"
    }
}

if (-not $files.Count) {
    Say-Warn 'no manifest, falling back to the known layout'
    Say-Info 'Only files this tool is known to install are considered.'
    $known = @('Common.ps1','Health-Report.ps1','Health-Report.bat','Repair-Health.ps1',
               'Clear-Reports.ps1','Collect-ToolLogs.ps1','Install.ps1','Uninstall.ps1',
               'health-report.cmd','healthreport.ico','installed.json')
    $files = @($known | ForEach-Object { Join-Path $InstallDir $_ } | Where-Object { Test-Path $_ })
    $shortcuts = @(
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$ProductName.lnk")
        (Join-Path ([Environment]::GetFolderPath('Desktop')) "$ProductName.lnk")
    ) | Where-Object { Test-Path $_ }
    $pathEntry = $InstallDir
}

# --- Reports ----------------------------------------------------------
# Found by pattern, never by "everything that is not one of ours",
# because that second rule is what deletes a person's unrelated files.
$reports = @(Get-ChildItem $InstallDir -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match '^(report|repairlog)-' })
$logFolders = @(Get-ChildItem $InstallDir -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^toollogs-' })

Write-Host ''
Say-Step 'to be removed'
foreach ($f in $files)     { Say-Info "file      $(Split-Path $f -Leaf)" }
foreach ($s in $shortcuts) { Say-Info "shortcut  $s" }
if ($pathEntry)            { Say-Info "PATH      $pathEntry" }
if (Test-Path $uninstallKey) { Say-Info 'registry  Add/Remove Programs entry' }

if ($reports.Count -or $logFolders.Count) {
    Write-Host ''
    if ($RemoveReports) {
        Say-Warn "$($reports.Count) report(s) and $($logFolders.Count) collected-log folder(s) will be DELETED (-RemoveReports)"
    } else {
        Say-Step "$($reports.Count) report(s) and $($logFolders.Count) collected-log folder(s) will be KEPT"
        Say-Info 'They hold other machines'' names, models and serial numbers.'
        Say-Info 'They will be moved to your Documents folder, not deleted.'
    }
}

if (-not $Confirm) {
    Write-Host ''
    Show-Banner 'Yellow' @(
        'DRY RUN. Nothing was removed.',
        'Run  .\Uninstall.ps1 -Confirm  to do it.'
    )
    exit 0
}

# --- Rescue the reports before anything is deleted --------------------
# First, deliberately. If this ran last and the folder delete went wrong
# halfway, the records would already be gone.
Write-Host ''
if ($reports.Count -or $logFolders.Count) {
    if ($RemoveReports) {
        Say-Step 'deleting reports (-RemoveReports)'
        foreach ($r in $reports) { Remove-Item $r.FullName -Force -ErrorAction SilentlyContinue }
        foreach ($d in $logFolders) { Remove-Item $d.FullName -Recurse -Force -ErrorAction SilentlyContinue }
        Say-Good "$($reports.Count + $logFolders.Count) item(s) deleted"
    } else {
        Say-Step 'moving reports somewhere findable'
        $keep = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Lazarus Reports'
        try {
            if (-not (Test-Path $keep)) { New-Item -ItemType Directory -Path $keep -Force -ErrorAction Stop | Out-Null }
            $moved = 0
            foreach ($r in $reports) {
                Move-Item $r.FullName (Join-Path $keep $r.Name) -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path $r.FullName)) { $moved++ }
            }
            foreach ($d in $logFolders) {
                Move-Item $d.FullName (Join-Path $keep $d.Name) -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path $d.FullName)) { $moved++ }
            }
            Say-Good "$moved item(s) moved to $keep"
        } catch {
            # Left in place rather than deleted. An uninstall that cannot
            # rescue the records must not proceed to remove the folder.
            Say-Warn "could not move the reports: $($_.Exception.Message)"
            Say-Info "They are still in $InstallDir and were not touched."
        }
    }
}

# --- Shortcuts --------------------------------------------------------
Say-Step 'removing shortcuts'
$gone = 0
foreach ($s in $shortcuts) {
    if (-not (Test-Path $s)) { continue }
    Remove-Item $s -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $s)) { $gone++ } else { Say-Warn "could not remove $s" }
}
Say-Good "$gone shortcut(s) removed"

# --- PATH -------------------------------------------------------------
if ($pathEntry) {
    Say-Step 'taking it off your PATH'
    # Read raw. Get-ItemProperty expands REG_EXPAND_SZ, and writing the
    # expanded value back would bake today's paths in permanently for
    # every other tool that uses %USERPROFILE% in its PATH entry.
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if ($key) {
        try {
            $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $entries = @($raw -split ';' | Where-Object { $_ -ne '' })
            $kept = @($entries | Where-Object { $_.TrimEnd('\') -ine $pathEntry.TrimEnd('\') })
            if ($kept.Count -eq $entries.Count) {
                Say-Info 'it was not on your PATH'
            } else {
                $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
                try { $kind = $key.GetValueKind('Path') } catch { }
                $key.SetValue('Path', ($kept -join ';'), $kind)
                Say-Good 'removed from your PATH'
            }
        } catch { Say-Warn "could not edit the PATH: $($_.Exception.Message)" }
        finally { $key.Close() }
    } else { Say-Warn 'could not open your environment registry key' }
}

# --- Add/Remove Programs ---------------------------------------------
if (Test-Path $uninstallKey) {
    Say-Step 'removing the Add/Remove Programs entry'
    Remove-Item $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $uninstallKey) { Say-Warn 'the registry entry is still there' } else { Say-Good 'deregistered' }
}

# --- Files ------------------------------------------------------------
Say-Step 'removing the tool'
# Out of the folder first, or the directory delete below fails with
# "the process cannot access the file because it is being used by
# another process" and the message says nothing about the current
# directory being the cause.
Set-Location ([Environment]::GetFolderPath('MyDocuments'))
$self = $PSCommandPath
$removed = 0
foreach ($f in $files) {
    if (-not (Test-Path $f)) { continue }
    # This very file goes last. Deleting the running script mid-run works
    # on Windows PowerShell but there is no reason to rely on it.
    if ($f -ieq $self) { continue }
    Remove-Item $f -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $f)) { $removed++ }
}
Say-Good "$removed file(s) removed"

# --- The folder, only if it is genuinely empty ------------------------
$leftover = @(Get-ChildItem $InstallDir -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -ine $self })
if ($leftover.Count) {
    Write-Host ''
    Say-Warn "$($leftover.Count) item(s) this tool did not install are still in $InstallDir"
    foreach ($l in ($leftover | Select-Object -First 8)) { Say-Info $l.Name }
    Say-Info 'The folder was left in place. Nothing unrecognised is ever deleted.'
} else {
    Remove-Item $self -Force -ErrorAction SilentlyContinue
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $InstallDir) { Say-Warn "$InstallDir could not be removed; delete it by hand" }
    else { Say-Good 'install folder removed' }
}

Write-Host ''
Show-Banner 'Green' @(
    'UNINSTALLED',
    'Open terminals need reopening before health-report stops resolving.'
)
Write-Host ''
exit 0
