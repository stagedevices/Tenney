@echo off
setlocal
set SCRIPT_DIR=%~dp0
set PROPS_FILE=%SCRIPT_DIR%gradle\wrapper\gradle-wrapper.properties
for /f "tokens=2 delims==" %%a in ('findstr /b distributionUrl= "%PROPS_FILE%"') do set DISTRIBUTION_URL=%%a
set DISTRIBUTION_URL=%DISTRIBUTION_URL:\:=:%
if "%DISTRIBUTION_URL%"=="" (
  echo distributionUrl not set in %PROPS_FILE%
  exit /b 1
)
for %%f in (%DISTRIBUTION_URL%) do set ZIP_NAME=%%~nxf
set VERSION=%ZIP_NAME:-bin.zip=%
set INSTALL_BASE=%USERPROFILE%\.gradle\tenney-wrapper
set INSTALL_DIR=%INSTALL_BASE%\%VERSION%
set GRADLE_HOME=%INSTALL_DIR%\%VERSION%
if not exist "%GRADLE_HOME%\bin\gradle.bat" (
  if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
  set ZIP_PATH=%INSTALL_DIR%\%ZIP_NAME%
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%DISTRIBUTION_URL%' -OutFile '%ZIP_PATH%'"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%ZIP_PATH%' -DestinationPath '%INSTALL_DIR%' -Force"
)
call "%GRADLE_HOME%\bin\gradle.bat" %*
endlocal
