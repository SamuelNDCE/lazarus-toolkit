@echo off
:: Opens the Drivers folder on the stick in Explorer.
::
:: Deliberately does NOT run anything. Driver and BIOS installers are
:: one wrong click away from a bricked machine, so they are reached
:: through a folder a person looks at, never as a launcher entry that
:: executes on a single click.
::
:: No elevation: opening a folder does not need it, and Explorer
:: launched from an elevated process runs as the wrong user anyway.
title Drivers

if not exist "%~dp0Drivers" (
    echo.
    echo   There is no Drivers folder next to this script.
    echo   Expected: %~dp0Drivers
    echo.
    echo   Create it and drop driver packages in, one folder per
    echo   package. Fix Network then matches them to the machine's
    echo   own hardware id and offers only the one that fits.
    echo.
    pause
    exit /b 1
)

start "" explorer "%~dp0Drivers"
exit /b 0
