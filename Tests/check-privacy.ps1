param([string]$Root)
<#
 Fails if anything personal or machine-specific is about to be published.

 WHY THIS EXISTS

 This repo was made public with five code comments naming a real client,
 one of which disclosed that a bundled adware browser had been found on
 her machine. She never agreed to be in a public repo. Nine more comments
 named the author in the third person, and a setup instruction named the
 brand of USB stick it happened to be written on.

 Every secrets scan run beforehand came back clean, and every one of them
 was beside the point. A credential regex is built for high-entropy
 strings and has nothing to say about somebody's first name.

 So this is not a secrets scanner. It looks for PEOPLE and for the one
 machine the code was written on, and it runs on every check rather than
 being a thing somebody is supposed to remember before a launch.

 NO CLIENT NAME IS WRITTEN IN THIS FILE. A checker that hardcodes the
 names it is protecting has published them itself, which is what the
 first version of this file did. Instead:

   1. Optional Tests\private-names.txt, one name per line, gitignored.
      Never committed, so it can hold real client names safely.
   2. A backstop that surfaces EVERY capitalised possessive not on the
      known-technical allowlist. That is what would have caught the
      original leak with no list at all, because "<Name>'s laptop"
      matches it and "chkdsk's" does not.
#>
if (-not $Root) { $Root = Join-Path (Split-Path $PSScriptRoot -Parent) 'HealthReport' }
$repo = Split-Path $PSScriptRoot -Parent

# This file names patterns for a living, so scanning it finds only itself.
$self = $MyInvocation.MyCommand.Path
$files = @(Get-ChildItem $repo -Recurse -File -ErrorAction SilentlyContinue |
           Where-Object {
               $_.FullName -notmatch '\\\.git\\' -and
               $_.Extension -notin '.png','.jpg','.ico' -and
               $_.FullName -ne $self -and
               $_.Name -ne 'private-names.txt'
           })

$issues = 0
function Bad($what, $hits) {
    Write-Host "  ISSUE  $what" -ForegroundColor Red
    foreach ($h in ($hits | Select-Object -First 6)) {
        Write-Host ("           {0}:{1}  {2}" -f $h.Filename, $h.LineNumber, $h.Line.Trim()) -ForegroundColor DarkGray
    }
    $script:issues++
}

# 1. Names from the gitignored local list, if there is one.
$listPath = Join-Path $PSScriptRoot 'private-names.txt'
if (Test-Path $listPath) {
    $names = @(Get-Content $listPath | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^#' })
    if ($names.Count) {
        $pat = ($names | ForEach-Object { "\b$([regex]::Escape($_))\b" }) -join '|'
        $hits = @($files | Select-String -Pattern $pat -ErrorAction SilentlyContinue)
        if ($hits.Count) { Bad 'a name from Tests\private-names.txt appears' $hits }
    }
}

# 2. Family words identify a person by relation without naming them.
$hits = @($files | Select-String -Pattern '\bbrother\b|\bsister\b|\bmy mum\b|\bmy dad\b|\bmy wife\b|\bmy husband\b' -ErrorAction SilentlyContinue)
if ($hits.Count) { Bad 'somebody is identified by family relation' $hits }

# 3. Hostnames. Real ones end up in comments and example output easily.
$hits = @($files | Select-String -Pattern '\bDESKTOP-[A-Z0-9]{7}\b|\bLAPTOP-[A-Z0-9]{7}\b' -ErrorAction SilentlyContinue)
if ($hits.Count) { Bad 'a real machine hostname' $hits }

# 4. Paths that exist on exactly one computer.
$hits = @($files | Select-String -Pattern '[A-Z]:\\Users\\[A-Za-z0-9_.-]+' -ErrorAction SilentlyContinue)
if ($hits.Count) { Bad 'a machine-specific absolute path' $hits }

# 5. Saved reports carry a machine name, model and serial by design.
$reports = @($files | Where-Object { $_.Name -match '^(report|repairlog)-' })
if ($reports.Count) {
    Write-Host "  ISSUE  $($reports.Count) saved report(s) are tracked in the repo" -ForegroundColor Red
    foreach ($f in ($reports | Select-Object -First 6)) { Write-Host "           $($f.Name)" -ForegroundColor DarkGray }
    $issues++
}

# 6. Credentials. Kept for completeness; never the thing that leaked.
$hits = @($files | Select-String -Pattern 'password\s*=\s*\S|api[_-]?key|secret\s*=\s*\S|token\s*=\s*\S|BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY|ghp_|gho_|github_pat_|xox[baprs]-|AKIA[0-9A-Z]{16}|discord\.com/api/webhooks' -ErrorAction SilentlyContinue)
if ($hits.Count) { Bad 'something credential-shaped' $hits }

# 7. THE BACKSTOP. Every capitalised possessive that is not a known
#    technical term. "<Name>'s laptop" lands here with no list required,
#    which is how the original leak should have been caught. Add genuine
#    technical terms to $allow; anything else is a person until a human
#    says otherwise.
$allow = @(
    'Windows','Microsoft','Update','Defender','Explorer','PowerShell','Terminal','Google',
    'SFC','DISM','HWiNFO','KVRT','Ventoy','Picocrypt','WindTerm','Hiren','Lenovo','Realtek',
    'Intel','MICRO','Spin','Box','ENTRY','Test','Tests','README','GitHub','Apache'
)
# -CaseSensitive is load bearing. Select-String ignores case by default,
# so [A-Z] happily matched "caller's" and "chkdsk's" and buried the one
# capitalised name in a list of thirty common nouns.
$poss = @($files | Select-String -Pattern "\b([A-Z][a-z]{2,})'s\b" -AllMatches -CaseSensitive -ErrorAction SilentlyContinue)
$unknown = @()
foreach ($h in $poss) {
    foreach ($m in $h.Matches) {
        $w = $m.Groups[1].Value
        if ($w -notin $allow) {
            $unknown += [pscustomobject]@{ Filename = $h.Filename; LineNumber = $h.LineNumber; Line = $h.Line; Word = $w }
        }
    }
}
if ($unknown.Count) {
    $words = @($unknown | ForEach-Object { $_.Word } | Sort-Object -Unique)
    Write-Host "  ISSUE  unrecognised capitalised possessive(s): $($words -join ', ')" -ForegroundColor Red
    Write-Host '           If any of those is a person, remove it. If it is a technical' -ForegroundColor DarkGray
    Write-Host '           term, add it to $allow in this file.' -ForegroundColor DarkGray
    foreach ($u in ($unknown | Select-Object -First 5)) {
        Write-Host ("           {0}:{1}  {2}" -f $u.Filename, $u.LineNumber, $u.Line.Trim()) -ForegroundColor DarkGray
    }
    $issues++
}

if ($issues -eq 0) {
    Write-Host '  PASS  no people, machines, personal paths, reports or credentials' -ForegroundColor Green
}
exit $issues
