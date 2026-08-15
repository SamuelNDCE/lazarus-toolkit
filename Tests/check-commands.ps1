# Parsing proves the file is grammatical. It does NOT prove the commands
# exist. Two live bugs in this toolkit parsed perfectly:
#   Info 'text'          - called 7 times, defined nowhere
#   Spin'label' { }      - a lost space turned a call into a command name
# Both vanished silently under $ErrorActionPreference = 'SilentlyContinue'.
# This resolves every command name instead.
param([string[]]$Files)

$defined = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
$calls   = @()

foreach ($f in $Files) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
    foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        [void]$defined.Add($fn.Name)
    }
}

foreach ($f in $Files) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
    foreach ($c in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $nameAst = $c.CommandElements[0]
        if ($nameAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $calls += [pscustomobject]@{
                File = Split-Path $f -Leaf
                Line = $c.Extent.StartLineNumber
                Name = $nameAst.Value
                Text = $c.Extent.Text
            }
        }
    }
}

$bad = @()
foreach ($c in ($calls | Sort-Object Name -Unique)) {
    if ($defined.Contains($c.Name)) { continue }
    if (Get-Command $c.Name -ErrorAction SilentlyContinue) { continue }
    $bad += $c
}

Write-Host ""
Write-Host ("functions defined across the set : {0}" -f $defined.Count)
Write-Host ("distinct commands invoked        : {0}" -f (@($calls | Sort-Object Name -Unique).Count))
Write-Host ""
if (-not $bad.Count) {
    Write-Host "OK  every command invoked resolves to a function, cmdlet or program." -ForegroundColor Green
    exit 0
}
Write-Host "UNRESOLVED COMMANDS:" -ForegroundColor Red
foreach ($b in $bad) {
    $hits = @($calls | Where-Object { $_.Name -eq $b.Name })
    Write-Host ("  {0}   ({1} call site(s))" -f $b.Name, $hits.Count) -ForegroundColor Red
    foreach ($h in ($hits | Select-Object -First 4)) {
        $t = $h.Text -replace '\s+', ' '
        if ($t.Length -gt 90) { $t = $t.Substring(0, 90) + '...' }
        Write-Host ("      {0}:{1}  {2}" -f $h.File, $h.Line, $t) -ForegroundColor DarkGray
    }
}
exit 1
