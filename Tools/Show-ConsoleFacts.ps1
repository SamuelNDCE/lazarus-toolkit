<#
 Prints what THIS console actually is, which is the thing that decides
 how the menu redraws.

     .\Show-ConsoleFacts.ps1

 The picker has now been "fixed" four times against a console I could
 only reason about. Every fix was verified by capturing the escape
 sequences it writes, and every one of those captures was taken in a
 redirected shell, which takes a different code path to a real terminal.
 So this prints the facts from the console you are actually looking at.
#>
. (Join-Path $PSScriptRoot 'Common.ps1')
Write-Host ''
Write-Host "  Health Report and Repair  v$Script:ToolVersion" -ForegroundColor Cyan
Write-Host ''
Write-Host "  ANSI enabled (VtEnabled) : $Script:VtEnabled" -ForegroundColor $(if ($Script:VtEnabled) { 'Green' } else { 'Yellow' })
Write-Host "  Can animate              : $Script:CanAnimate"
Write-Host "  Output redirected        : $([Console]::IsOutputRedirected)"
Write-Host "  Input redirected         : $([Console]::IsInputRedirected)"
Write-Host "  Windows Terminal         : $(if ($env:WT_SESSION) { 'yes' } else { 'no' })"
try {
    $ws = $Host.UI.RawUI.WindowSize
    $bs = $Host.UI.RawUI.BufferSize
    $wp = $Host.UI.RawUI.WindowPosition
    Write-Host "  Window                   : $($ws.Width) x $($ws.Height)"
    Write-Host "  Buffer                   : $($bs.Width) x $($bs.Height)"
    Write-Host "  WindowPosition.Y         : $($wp.Y)"
    Write-Host "  Picker usable here       : $(Test-CanPick)" -ForegroundColor $(if (Test-CanPick) { 'Green' } else { 'Yellow' })
    Write-Host ''
    # The frame the report's chooser would build, at this window size.
    $hdr = 10; $rows = 20
    $budget = $ws.Height - $hdr - 2 - 4 - 1
    $db = 6; while ($db -gt 2 -and ($db + 3) -gt $budget) { $db-- }
    $vc = [Math]::Min($rows, [Math]::Max(1, $budget - $db))
    $fh = $hdr + 1 + $vc + 1 + 1 + 1 + $db + 1 + 1
    Write-Host "  Chooser frame would be   : $fh lines"
    Write-Host "  Fits this window         : $($fh -lt $ws.Height)" -ForegroundColor $(if ($fh -lt $ws.Height) { 'Green' } else { 'Red' })
    if ($fh -ge $ws.Height) {
        Write-Host ''
        Write-Host '  THIS IS THE PROBLEM. A frame that does not fit scrolls the' -ForegroundColor Red
        Write-Host '  console, and the cursor cannot step back above the top of' -ForegroundColor Red
        Write-Host '  the screen, so each repaint lands lower than the last.' -ForegroundColor Red
    }
} catch { Write-Host "  RawUI not available: $($_.Exception.Message)" -ForegroundColor Yellow }
Write-Host ''
Write-Host '  Send this whole screen back and the menu can be fixed against' -ForegroundColor DarkGray
Write-Host '  what your console actually does, rather than against a guess.' -ForegroundColor DarkGray
Write-Host ''
