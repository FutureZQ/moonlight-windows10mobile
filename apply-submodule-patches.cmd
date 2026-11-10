@echo off
rem Apply w10m-port patches to the upstream submodule checkouts.
set "EXTRA="
if /I "%W10M_SKIP_VCPKG_PATCH%"=="1" set "EXTRA=-SkipVcpkg"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply-submodule-patches.ps1" %* %EXTRA%
exit /b %ERRORLEVEL%
