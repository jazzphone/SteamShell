@echo off
setlocal

pushd "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-SteamShell-XFE.ps1"
set "STEAMSHELL_XFE_BUILD_EXIT=%ERRORLEVEL%"
popd

echo.
if "%STEAMSHELL_XFE_BUILD_EXIT%"=="0" (
    echo SteamShell XFE build completed successfully.
) else (
    echo SteamShell XFE build failed with exit code %STEAMSHELL_XFE_BUILD_EXIT%.
)
echo.
pause

exit /b %STEAMSHELL_XFE_BUILD_EXIT%
