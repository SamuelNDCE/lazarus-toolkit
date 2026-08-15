# Proves Invoke-WithRetry retries on a throw, gives up loudly, and does
# NOT retry a legitimate empty result.
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'HealthReport\Common.ps1')
$fail = 0

Write-Output '1. succeeds on the third attempt'
$script:n = 0
$r = Invoke-WithRetry -Label 'flaky thing' -DelaySeconds 1 -Work {
    $script:n++
    if ($script:n -lt 3) { throw "blip $($script:n)" }
    'finally worked'
}
if ($r -eq 'finally worked' -and $script:n -eq 3) { Write-Output "   PASS (took $($script:n) attempts)" }
else { Write-Output "   FAIL (result='$r', attempts=$($script:n))"; $fail++ }

Write-Output ''
Write-Output '2. gives up after the limit and rethrows'
$script:m = 0
$threw = $false
try {
    Invoke-WithRetry -Label 'always broken' -Attempts 2 -DelaySeconds 1 -Work {
        $script:m++
        throw 'permanently broken'
    }
} catch { $threw = $true }
if ($threw -and $script:m -eq 2) { Write-Output "   PASS (tried $($script:m), then rethrew)" }
else { Write-Output "   FAIL (threw=$threw, attempts=$($script:m))"; $fail++ }

Write-Output ''
Write-Output '3. does NOT retry an empty result (a legitimate answer)'
$script:k = 0
$e = Invoke-WithRetry -Label 'nothing found' -DelaySeconds 1 -Work {
    $script:k++
    @()
}
if ($script:k -eq 1) { Write-Output '   PASS (ran once, did not retry an empty answer)' }
else { Write-Output "   FAIL (ran $($script:k) times)"; $fail++ }

Write-Output ''
if ($fail -eq 0) { Write-Output 'PASS: retry behaves in all three cases'; exit 0 }
Write-Output "FAIL: $fail case(s)"
exit 1
