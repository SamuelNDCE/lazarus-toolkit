param([string[]]$Files)
# Catches "function used before it is defined".
#
# check-commands.ps1 proves every invoked name resolves to a function
# somewhere in the file. That is not the same as it existing YET.
# PowerShell runs a script top to bottom, so a function defined at line
# 1372 does not exist at a top-level call on line 957, and the script
# dies there at runtime with CommandNotFoundException. That shipped.
#
# Only TOP-LEVEL calls matter. A call inside another function body is
# resolved when that function RUNS, by which point the whole file has
# been read, so order is irrelevant there.
$fail = 0
foreach ($file in $Files) {
    $errs = $null; $toks = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$toks, [ref]$errs)
    if ($errs -and $errs.Count) { Write-Host "  FAIL  $file does not parse" -ForegroundColor Red; $fail++; continue }

    $funcs = @{}
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if (-not $funcs.ContainsKey($fn.Name)) { $funcs[$fn.Name] = $fn.Extent.StartLineNumber }
    }
    # .PSBase.Count, not .Count. $funcs is keyed by function NAME, so a
    # function called Count, Keys or Values would shadow the member and
    # this would silently compare against a line number. Exactly the bug
    # that made the audit's dead-variable check a no-op.
    if (-not $funcs.PSBase.Count) { continue }

    # Line ranges covered by any function body, so calls inside them can
    # be ignored.
    $bodies = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
                ForEach-Object { [pscustomobject]@{ S = $_.Extent.StartLineNumber; E = $_.Extent.EndLineNumber } })

    foreach ($call in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $name = $call.GetCommandName()
        if (-not $name -or -not $funcs.ContainsKey($name)) { continue }
        $line = $call.Extent.StartLineNumber
        $inside = $false
        foreach ($b in $bodies) { if ($line -ge $b.S -and $line -le $b.E) { $inside = $true; break } }
        if ($inside) { continue }
        if ($line -lt $funcs[$name]) {
            Write-Host ("  FAIL  {0}: '{1}' called at line {2} but not defined until line {3}" -f (Split-Path $file -Leaf), $name, $line, $funcs[$name]) -ForegroundColor Red
            $fail++
        }
    }
}
if ($fail -eq 0) { Write-Host '  PASS  every top-level call happens after its function is defined' -ForegroundColor Green }
exit $fail
