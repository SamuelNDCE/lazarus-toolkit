@echo off
:: =====================================================================
::  INSTALL - HEALTH REPORT AND REPAIR
::
::  Double-click this. It installs the health report and repair tool for
::  the current user and puts it on the Start menu, the desktop and the
::  PATH.
::
::  IT DELIBERATELY DOES NOT ASK FOR ADMINISTRATOR.
::
::  That looks like an oversight and is the opposite. The install goes
::  into %LOCALAPPDATA%, which belongs to whoever is signed in, so
::  elevating would install it into the ADMINISTRATOR's profile instead:
::  the shortcuts, the PATH entry and the Add/Remove Programs entry would
::  all land on an account nobody is using, and the person who ran this
::  would see a successful install and then find nothing on their Start
::  menu. That is a real and common installer bug, not a hypothetical.
::
::  The TOOL still elevates itself every time it runs, because SMART
::  data, BitLocker, battery capacity and every repair need it.
::  Health-Report.bat does that. Two different permissions.
:: =====================================================================
title Install Health Report and Repair
color 0F
cd /d "%~dp0"

:: Already elevated? Say so rather than silently installing into the
:: wrong profile. Not a hard stop: on a machine where the signed-in
:: account IS the administrator account, this is exactly right.
net session >nul 2>&1
if %errorlevel% equ 0 (
    echo.
    echo   ------------------------------------------------------------
    echo    Running as administrator.
    echo.
    echo    This installs into the profile of the account it runs as.
    echo    If you right-clicked "Run as administrator" and you normally
    echo    sign in as somebody else, close this and just double-click
    echo    it instead. Installing needs no administrator at all.
    echo   ------------------------------------------------------------
    echo.
    pause
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
set RC=%errorlevel%
if not "%RC%"=="0" (
    echo.
    echo    Install.ps1 exited with code %RC%.
)
echo.
pause
exit /b %RC%
