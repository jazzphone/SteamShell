@echo off
setlocal

pushd "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-SteamShellValidation.ps1"
set "STEAMSHELL_VALIDATION_EXIT=%ERRORLEVEL%"
popd

echo.
if "%STEAMSHELL_VALIDATION_EXIT%"=="0" (
    echo SteamShell validation completed successfully.
) else (
    echo SteamShell validation failed with exit code %STEAMSHELL_VALIDATION_EXIT%.
)
echo.
pause

exit /b %STEAMSHELL_VALIDATION_EXIT%
