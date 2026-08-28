@echo off
:: Health report and repair. Elevates itself: battery, SMART,
:: activation and BitLocker all need admin to read.
:: Offers the repair and recovery menu at the end.
::
:: color 0F sets black background, bright white text, BEFORE PowerShell
:: starts. Without it the elevated window flashes up in the default
:: console colours first, and on the PowerShell host that is the old
:: navy blue. Common.ps1 sets the same thing from inside, but only once
:: PowerShell is loaded, which is a visible half second too late.
title Health Report and Repair
color 0F

cd /d "%~dp0"

:: -------------------------------------------------------------------
:: THE TOOLS ARE NOT STANDALONE FILES.
::
:: Saving Health-Report and Repair-Health out of the GitHub web view
:: without Common.ps1 beside them does not fail cleanly. Verified by
:: deleting Common.ps1 and running it: nothing crashed, every hardware
:: check silently returned nothing, and the report called a machine
:: with working WMI faulty. A confident wrong diagnosis is worse than
:: no diagnosis, so this refuses to start instead.
::
:: Checked here as well as inside the script, because on Windows 11
:: the launcher hands off to Windows Terminal, and a script that dies
:: before it draws anything takes its own error message with it.
:: -------------------------------------------------------------------
if not exist "%~dp0Health-Report.ps1" goto :incomplete
if not exist "%~dp0Common.ps1" goto :incomplete
goto :ready

:incomplete
echo.
echo   ------------------------------------------------------------
echo    This folder is missing files the tool needs.
echo.
echo    Folder: %~dp0
echo.
echo    These scripts are not standalone. Download the whole
echo    repository as a ZIP and extract it, or copy the entire
echo    Tools folder, rather than saving files one at a time.
echo   ------------------------------------------------------------
echo.
pause
exit /b 1

:ready

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
echo    Battery wear, SMART data, activation and BitLocker all need
echo    them. Sign in as an administrator and run this again.
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
:: look like an unfinished script. That matters: the person watching
:: this run is often the client deciding whether to trust the machine.
::
:: Windows Terminal is present on Windows 11 and absent on plenty of the
:: old Windows 10 laptops this stick exists for, so it is a preference,
:: never a requirement. WT_SESSION is set by Terminal itself, so it also
:: stops this relaunching itself forever when already inside one.
:: -------------------------------------------------------------------
if defined WT_SESSION goto :classic
where wt.exe >nul 2>&1
if errorlevel 1 goto :classic

:: %* forwards whatever was passed to this file, so -Unattended actually
:: reaches the script. Without it the switch was accepted, ignored, and
:: the run then sat forever on "Press Enter to close": a scheduled task
:: that never finishes and gives no clue why.
start "" wt.exe --title "Health Report and Repair" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Health-Report.ps1" %*
exit /b 0

:classic
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Health-Report.ps1" %*
if %errorlevel% neq 0 (
    echo.
    echo    Health-Report.ps1 exited with code %errorlevel%.
    pause
)
exit /b
