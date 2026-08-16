<#
=======================================================================
 CLEAR-REPORTS

 Deletes the saved reports and repair logs that these tools write.

     .\Clear-Reports.ps1              # show what would go, delete nothing
     .\Clear-Reports.ps1 -Confirm     # actually delete
     .\Clear-Reports.ps1 -Keep 'MYPC' # delete everything except that PC

 WHY THIS EXISTS

 Every run writes a report next to the tool, and that report contains the
 machine name, make, model, SERIAL NUMBER, installed software and event
 log entries of whatever computer it ran on. Do a dozen repairs and the
 stick is quietly carrying a dozen strangers' hardware inventories.

 That is fine while it is your stick in your pocket. It stops being fine
 the moment the stick is lost, lent, or imaged. This is the tool that
 clears it, so the answer to "how do I get rid of these" is a command
 rather than picking through a folder by hand.

 It DEFAULTS TO A DRY RUN. Deleting someone's records because they typed
 a command they had not finished reading is not a good trade.
=======================================================================
#>
param(
    [switch]$Confirm,
    [string[]]$Keep = @(),
    [string]$Path,
    # Copy every report here before deleting anything. Reports are
    # diagnostic records of somebody's machine, and on 2026-08-15
    # nineteen of them were deleted off a USB stick on request, with no
    # copy anywhere. Removable drives bypass the Recycle Bin, so they
    # were unrecoverable, including the evidence of a failing SSD taken
    # that afternoon.
    #
    # -ArchiveTo makes "clear" mean "file away, then clear". If the copy
    # fails, NOTHING is deleted.
    [string]$ArchiveTo
)

if (-not $Path) { $Path = $PSScriptRoot }

$files = @(Get-ChildItem $Path -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -match '^(report|repairlog)-' })

if (-not $files.Count) {
    Write-Host ''
    Write-Host "  No saved reports in $Path" -ForegroundColor Green
    exit 0
}

# Machine name is the middle field: report-<MACHINE>-<date>.<ext>
function Get-MachineName($name) {
    if ($name -match '^(?:report|repairlog)-(.+)-\d{4}-\d{2}-\d{2}_\d{4}') { return $matches[1] }
    return '(unknown)'
}

$keeping = @($files | Where-Object { (Get-MachineName $_.Name) -in $Keep })
$going   = @($files | Where-Object { (Get-MachineName $_.Name) -notin $Keep })

$machines = @($files | ForEach-Object { Get-MachineName $_.Name } | Sort-Object -Unique)
Write-Host ''
Write-Host "  $($files.Count) saved report(s) from $($machines.Count) machine(s)" -ForegroundColor Cyan
Write-Host "  $('-' * 52)" -ForegroundColor DarkCyan
foreach ($m in $machines) {
    $n = @($files | Where-Object { (Get-MachineName $_.Name) -eq $m }).Count
    $verb = if ($m -in $Keep) { 'KEEP  ' } else { 'delete' }
    $col  = if ($m -in $Keep) { 'Green' } else { 'Yellow' }
    Write-Host ("    {0}  {1,-24} {2} file(s)" -f $verb, $m, $n) -ForegroundColor $col
}

$mb = [math]::Round((($going | Measure-Object Length -Sum).Sum) / 1KB, 1)
Write-Host ''
if (-not $Confirm) {
    Write-Host "  DRY RUN. Nothing has been deleted." -ForegroundColor Yellow
    Write-Host "  $($going.Count) file(s), $mb KB would go." -ForegroundColor DarkGray
    Write-Host '  Re-run with -Confirm to delete them.' -ForegroundColor DarkGray
    exit 0
}

# ARCHIVE BEFORE DELETE. A failure here stops the whole thing: losing
# the records is the outcome this exists to prevent, so a half-finished
# copy must never be followed by a delete.
if ($ArchiveTo) {
    Write-Host ''
    Write-Host "  Archiving to $ArchiveTo before deleting anything" -ForegroundColor Cyan
    try {
        if (-not (Test-Path $ArchiveTo)) { New-Item -ItemType Directory -Path $ArchiveTo -Force -ErrorAction Stop | Out-Null }
        $copied = 0
        foreach ($f in $going) {
            $dest = Join-Path $ArchiveTo $f.Name
            Copy-Item $f.FullName $dest -Force -ErrorAction Stop
            # Verify the copy by size, not by the absence of an error.
            $d = Get-Item $dest -ErrorAction Stop
            if ($d.Length -ne $f.Length) { throw "size mismatch on $($f.Name): $($f.Length) -> $($d.Length)" }
            $copied++
        }
        Write-Host "  archived $copied of $($going.Count) file(s), each verified by size" -ForegroundColor Green
    } catch {
        Write-Host "  ARCHIVE FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '  NOTHING HAS BEEN DELETED. Fix the archive location and run this again.' -ForegroundColor Yellow
        exit 1
    }
}

$failed = @()
foreach ($f in $going) {
    try { Remove-Item $f.FullName -Force -ErrorAction Stop }
    catch { $failed += $f.Name }
}

$left = @(Get-ChildItem $Path -File -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -match '^(report|repairlog)-' })

# Verified by re-reading the folder, not by assuming the deletes worked.
Write-Host "  Deleted $($going.Count - $failed.Count) of $($going.Count) file(s), $mb KB." -ForegroundColor Green
if ($keeping.Count) {
    Write-Host "  Kept $($keeping.Count) file(s) for: $($Keep -join ', ')" -ForegroundColor Green
}
if ($failed.Count) {
    Write-Host "  COULD NOT DELETE $($failed.Count):" -ForegroundColor Red
    foreach ($n in ($failed | Select-Object -First 5)) { Write-Host "    $n" -ForegroundColor Red }
    Write-Host '  Usually means the file is open. Close it and run this again.' -ForegroundColor DarkGray
}
Write-Host "  $($left.Count) report(s) remain in $Path" -ForegroundColor DarkGray
exit $failed.Count
