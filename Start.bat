@echo off
rem Lazarus launcher. %~dp0 is this file's own folder, so the drive letter
rem never matters: this works whether the stick mounts as D:, E: or Z:.
start "" mshta.exe "%~dp0Lazarus.hta"
