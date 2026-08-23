@echo off
:: Fix a Wi-Fi adapter that DISAPPEARS from Windows and comes back later.
:: Elevates itself: power plan values, the adapter's registry key, the
:: driver keywords and the WLAN service all need admin to change.
::
:: color 0F sets black background, bright white text, BEFORE PowerShell
:: starts. Without it the elevated window flashes up in the default
:: console colours first, and on the PowerShell host that is the old
:: navy blue. The script sets the same thing from inside, but only once
:: PowerShell is loaded, which is a visible half second too late.
title Fix Network
color 0F

cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel% equ 0 goto :run

:: Ask for admin, and if Windows refuses, say so rather than closing an
:: empty window, which is indistinguishable from a broken script.
::
:: %* is forwarded through the elevation as well, or a switch given to
:: this file is thrown away the moment it relaunches itself as admin, and
:: the flag silently does nothing. -ArgumentList is only added when there
:: are arguments, because an empty one makes Start-Process fail.
if "%~1"=="" (
    powershell -NoProfile -Command "try { Start-Process -FilePath '%~f0' -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
) else (
    powershell -NoProfile -Command "try { Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
)
if %errorlevel% equ 0 exit /b 0
echo.
echo   ------------------------------------------------------------
echo    Windows would not grant administrator rights to
echo    %USERDOMAIN%\%USERNAME%.
echo.
echo    The power settings, the adapter registry key and the WLAN
echo    service all need them. Sign in as an administrator and run
echo    this again.
echo   ------------------------------------------------------------
echo.
pause
exit /b 1

:run
:: -------------------------------------------------------------------
:: Run in Windows Terminal when the machine has it.
::
:: The legacy console host is what the Windows PowerShell profile still
:: opens in, navy blue background and all, and it makes a working tool
:: look like an unfinished script.
::
:: Windows Terminal is present on Windows 11 and absent on plenty of the
:: old Windows 10 laptops this stick exists for, so it is a preference,
:: never a requirement. WT_SESSION is set by Terminal itself, so it also
:: stops this relaunching itself forever when already inside one.
:: -------------------------------------------------------------------
if defined WT_SESSION goto :classic
where wt.exe >nul 2>&1
if errorlevel 1 goto :classic

start "" wt.exe --title "Fix Network" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-Network.ps1" %*
exit /b 0

:classic
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-Network.ps1" %*
if %errorlevel% neq 0 (
    echo.
    echo    Fix-Network.ps1 exited with code %errorlevel%.
    pause
)
exit /b
