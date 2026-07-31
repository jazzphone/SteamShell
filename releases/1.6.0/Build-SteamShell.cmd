@echo off
setlocal

pushd "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-SteamShell.ps1"
set "STEAMSHELL_BUILD_EXIT=%ERRORLEVEL%"
popd

echo.
if "%STEAMSHELL_BUILD_EXIT%"=="0" (
    echo SteamShell build completed successfully.
) else (
    echo SteamShell build failed with exit code %STEAMSHELL_BUILD_EXIT%.
)
echo.
pause

exit /b %STEAMSHELL_BUILD_EXIT%
