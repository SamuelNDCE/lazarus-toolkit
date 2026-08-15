param([string[]]$Files)
<#
 Finds work that can BLOCK with nothing on screen.

 A silent pause is indistinguishable from a crash, and this toolkit is
 run on other people's machines while they watch. Every slow thing must
 either animate, print before it starts, or be a bare external tool that
 draws its own progress.

 Three ways a call is considered covered:

   Spin ...                     animates and enforces a timeout
   Work / Write-Host before it  says what is starting
   Start-ProgressTicker         animates over a call that cannot be moved
                                onto a runspace

 Bare external tools (sfc, dism, chkdsk) draw their own live percentage
 and must NOT be wrapped, because a pipeline or a spinner destroys it.
 They are covered by a watchdog instead, checked separately.
#>
$slow = @(
    'Get-CimInstance','Get-WmiObject','Get-PhysicalDisk','Get-StorageReliabilityCounter',
    'Get-BitLockerVolume','Get-MpComputerStatus','Get-NetAdapter','Get-NetFirewallProfile',
    'Get-WinEvent','Get-ComputerRestorePoint','Get-Disk','Get-Volume','Get-ItemProperty',
    'Checkpoint-Computer','Get-AppxPackage','Get-Service','Test-NetConnection'
)
$issues = 0

foreach ($file in $Files) {
    $name = Split-Path $file -Leaf
    $lines = Get-Content $file
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
    if (-not $ast) { continue }

    # Line ranges covered by a Spin scriptblock, a ticker, or a runspace.
    $covered = @()
    foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $cn = $c.GetCommandName()
        if ($cn -in 'Spin','Start-ProgressTicker','Start-DismWatchdog') {
            $covered += [pscustomobject]@{ S = $c.Extent.StartLineNumber; E = $c.Extent.EndLineNumber }
        }
    }
    # AddScript{...} bodies run on a runspace with a ticker over them.
    foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)) {
        if ($c.Member.Extent.Text -eq 'AddScript') {
            $covered += [pscustomobject]@{ S = $c.Extent.StartLineNumber; E = $c.Extent.EndLineNumber }
        }
    }

    foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $cn = $c.GetCommandName()
        if ($cn -notin $slow) { continue }
        $ln = $c.Extent.StartLineNumber

        $inside = $false
        foreach ($b in $covered) { if ($ln -ge $b.S -and $ln -le $b.E) { $inside = $true; break } }
        if ($inside) { continue }

        # A read of ONE named registry key is a single hive lookup and is
        # effectively instant, so it does not need announcing. Enumerating
        # a hive is not, and is still flagged.
        #
        # This exemption is deliberately narrow: only Get-ItemProperty,
        # only against a literal HKLM:/HKCU: path. It exists so the check
        # stays believable. A checker that cries wolf on five instant
        # reads gets its output skimmed, and then the one real finding in
        # the list gets skimmed with it.
        if ($cn -eq 'Get-ItemProperty') {
            $argText = ($c.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.Extent.Text }) -join ' '
            if ($argText -match "^'?HK(LM|CU|CR|U|CC):" ) { continue }
        }

        # Or something said what was about to happen, within 10 lines
        # above. Three was too tight and produced a false positive on a
        # block whose "Work 'creating a restore point'" sat eight lines up
        # with only comments and a variable assignment between. The
        # announcement is still on screen and still describes what is
        # happening, which is the whole point. A checker that flags
        # correct code trains you to ignore it.
        $announced = $false
        for ($k = [Math]::Max(0, $ln - 11); $k -lt $ln - 1; $k++) {
            if ($lines[$k] -match '^\s*(Work|Info|Write-Host|Sec)\s') { $announced = $true; break }
        }
        if ($announced) { continue }

        Write-Host ("  ISSUE  {0}:{1}  {2} can block with nothing on screen" -f $name, $ln, $cn) -ForegroundColor Red
        $issues++
    }
}

if ($issues -eq 0) { Write-Host '  PASS  every slow call animates, announces itself, or draws its own progress' -ForegroundColor Green }
exit $issues
