@echo off
setlocal enabledelayedexpansion
title PDI Universal Installer

:: ============================================================
::  VARIABLES & INIT
:: ============================================================
set "SCRIPT_DIR=%~dp0"
set ZIP_COUNT=0
set JAVA_COUNT=0

echo.
echo ============================================================
echo   PDI Universal - Silent Installer for Windows
echo ============================================================
echo.

:: ============================================================
::  STEP 1 - SCAN AND SELECT PDI ZIP FILE
:: ============================================================
echo [1/5] Scanning for PDI installer files in current folder...

for %%F in ("%SCRIPT_DIR%pdi-ce*.zip" "%SCRIPT_DIR%pdi-de*.zip") do (
    if exist "%%F" (
        set /a ZIP_COUNT+=1
        set "ZIP_PATH_!ZIP_COUNT!=%%~F"
        set "ZIP_NAME_!ZIP_COUNT!=%%~nxF"
    )
)

if !ZIP_COUNT!==0 (
    echo.
    echo [ERROR] No installer file found.
    echo         Make sure pdi-ce*.zip or pdi-de*.zip is located in
    echo         the same folder as this script.
    echo.
    pause
    exit /b 1
)

if !ZIP_COUNT!==1 (
    set "SELECTED_ZIP_PATH=!ZIP_PATH_1!"
    set "SELECTED_ZIP_NAME=!ZIP_NAME_1!"
    echo       OK - Found 1 installer, automatically selected:
    echo            !SELECTED_ZIP_NAME!
    goto :zip_selected
)

echo       Found !ZIP_COUNT! PDI installers.
echo.
for /l %%I in (1,1,!ZIP_COUNT!) do (
    echo       [%%I] !ZIP_NAME_%%I!
)
echo.
:prompt_zip
set /p "ZIP_CHOICE=      Select installer number to install [1-!ZIP_COUNT!]: "

set "SELECTED_ZIP_PATH="
for /l %%I in (1,1,!ZIP_COUNT!) do (
    if "!ZIP_CHOICE!"=="%%I" (
        set "SELECTED_ZIP_PATH=!ZIP_PATH_%%I!"
        set "SELECTED_ZIP_NAME=!ZIP_NAME_%%I!"
    )
)

if not defined SELECTED_ZIP_PATH (
    echo       [ERROR] Invalid choice.
    goto :prompt_zip
)

:zip_selected
echo.

:: ============================================================
::  DETERMINE PDI VERSION & JAVA REQUIREMENT
:: ============================================================
echo !SELECTED_ZIP_NAME! | findstr /i "pdi-ce-7" >nul
if not errorlevel 1 (
    set PDI_VERSION=7
    set PDI_EDITION=CE
    set TARGET_JAVA=8
    goto :version_set
)
echo !SELECTED_ZIP_NAME! | findstr /i "pdi-ce-8" >nul
if not errorlevel 1 (
    set PDI_VERSION=8
    set PDI_EDITION=CE
    set TARGET_JAVA=8
    goto :version_set
)
echo !SELECTED_ZIP_NAME! | findstr /i "pdi-ce-9" >nul
if not errorlevel 1 (
    set PDI_VERSION=9
    set PDI_EDITION=CE
    set TARGET_JAVA=11
    goto :version_set
)
echo !SELECTED_ZIP_NAME! | findstr /i "pdi-de-11" >nul
if not errorlevel 1 (
    set PDI_VERSION=11
    set PDI_EDITION=DE
    set TARGET_JAVA=17
    goto :version_set
)

echo [ERROR] PDI version from file !SELECTED_ZIP_NAME! is not recognized.
pause
exit /b 1

:version_set
set "APP_NAME=PDI !PDI_VERSION! !PDI_EDITION!"
set "INSTALL_DIR=C:\pentaho\design-tools\pdi-!PDI_VERSION!"
set "TEMP_EXTRACT=C:\pdi!PDI_VERSION!_tmp"
set "LAUNCHER=!INSTALL_DIR!\launch-pdi-!PDI_VERSION!.bat"

echo       Install target  : !APP_NAME!
echo       Java required   : Java !TARGET_JAVA!
echo.

:: ============================================================
::  STEP 2 - SCAN JAVA REQUIREMENT
:: ============================================================
echo [2/5] Looking for JDK !TARGET_JAVA! installation...
echo.

:: --- Registry Scan (Oracle, etc.) ---
for /f "tokens=2*" %%A in ('reg query "HKLM\SOFTWARE\JavaSoft\Java Development Kit" /s /v "JavaHome" 2^>nul ^| findstr /i "JavaHome"') do (
    if exist "%%B\bin\java.exe" call :check_java_version "%%B"
)

:: --- Folder Scan (Adoptium, Oracle, Microsoft, Amazon) ---
for %%B in (
    "C:\Program Files\Eclipse Adoptium"
    "C:\Program Files\Java"
    "C:\Program Files\Microsoft"
    "C:\Program Files\Amazon Corretto"
) do (
    if exist "%%~B\" (
        for /d %%D in ("%%~B\*") do (
            if exist "%%~D\bin\java.exe" call :check_java_version "%%~D"
        )
    )
)

if !JAVA_COUNT!==0 (
    echo.
    echo [ERROR] No JDK !TARGET_JAVA! installation found on this system.
    echo         Please install Temurin JDK !TARGET_JAVA! first from:
    echo         https://adoptium.net/temurin/releases/?version=!TARGET_JAVA!
    echo.
    pause
    exit /b 1
)

if !JAVA_COUNT!==1 (
    set "SELECTED_JAVA=!JAVA_PATH_1!"
    echo.
    echo       Found 1 JDK !TARGET_JAVA! installation, automatically selected:
    echo       !SELECTED_JAVA!
    goto :java_selected
)

echo.
echo       Found !JAVA_COUNT! JDK !TARGET_JAVA! installations.
:prompt_java
set /p "USER_CHOICE=      Select JDK number to use [1-!JAVA_COUNT!]: "

set "SELECTED_JAVA="
for /l %%I in (1,1,!JAVA_COUNT!) do (
    if "!USER_CHOICE!"=="%%I" set "SELECTED_JAVA=!JAVA_PATH_%%I!"
)

if not defined SELECTED_JAVA (
    echo       [ERROR] Invalid choice.
    goto :prompt_java
)

:java_selected
echo.
echo       Selected JDK: !SELECTED_JAVA!
echo.

:: ============================================================
::  STEP 3 - EXTRACT ZIP
:: ============================================================
echo [3/5] Extracting !APP_NAME!...

if not exist "!INSTALL_DIR!" goto :proceed_install

echo.
echo ============================================================
echo [WARNING] Install folder already exists:
echo           !INSTALL_DIR!
echo ============================================================
echo  [1] Overwrite     (Overlay old files, custom/plugin files safe)
echo  [2] Clean Install (Delete old folder entirely before extracting)
echo  [3] Cancel        (Stop the installation process)
echo ============================================================
echo.

:prompt_action
set /p "ACTION_CHOICE=Select action [1-3]: "

if "!ACTION_CHOICE!"=="1" goto :handle_overwrite
if "!ACTION_CHOICE!"=="2" goto :handle_clean
if "!ACTION_CHOICE!"=="3" goto :handle_cancel

echo [ERROR] Invalid choice. Please select 1, 2, or 3.
goto :prompt_action

:handle_overwrite
echo.
echo Action selected: Overwriting existing files...
goto :proceed_install

:handle_clean
echo.
echo Action selected: Clean Install...
echo Removing old folder, please wait...
rmdir /s /q "!INSTALL_DIR!"
if errorlevel 1 (
    echo [ERROR] Failed to remove existing folder.
    echo         Make sure no other application or CMD window has the folder open.
    pause
    exit /b 1
)
goto :proceed_install

:handle_cancel
echo.
echo [INFO] Installation cancelled by user.
pause
exit /b 0

:proceed_install
if not exist "!INSTALL_DIR!" (
    mkdir "!INSTALL_DIR!" 2>nul
    if errorlevel 1 (
        echo.
        echo [ERROR] Failed to create directory: !INSTALL_DIR!
        echo         Try running this script as Administrator.
        echo.
        pause
        exit /b 1
    )
)

if exist "!TEMP_EXTRACT!" rmdir /s /q "!TEMP_EXTRACT!"
mkdir "!TEMP_EXTRACT!"

echo         Extracting zip, please wait...

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Expand-Archive -LiteralPath '!SELECTED_ZIP_PATH!' -DestinationPath '!TEMP_EXTRACT!' -Force"

if errorlevel 1 (
    echo.
    echo [ERROR] Failed to extract zip file.
    echo.
    rmdir /s /q "!TEMP_EXTRACT!" 2>nul
    pause
    exit /b 1
)

echo         Verifying extraction result...
if not exist "!TEMP_EXTRACT!\data-integration\" (
    echo.
    echo [ERROR] Folder 'data-integration' not found after extraction.
    echo         Temp folder contents:
    dir "!TEMP_EXTRACT!" /b
    echo.
    rmdir /s /q "!TEMP_EXTRACT!" 2>nul
    pause
    exit /b 1
)

echo         Moving files to !INSTALL_DIR!...
xcopy "!TEMP_EXTRACT!\data-integration\*" "!INSTALL_DIR!\" /E /H /Y /Q >nul 2>&1
if errorlevel 1 (
    echo.
    echo [ERROR] Failed to move files to install directory.
    echo.
    rmdir /s /q "!TEMP_EXTRACT!" 2>nul
    pause
    exit /b 1
)

rmdir /s /q "!TEMP_EXTRACT!" 2>nul
echo         OK - Extraction complete.
echo.

:: ============================================================
::  STEP 4 - GENERATE LAUNCHER
:: ============================================================
echo [4/5] Creating launcher file...

(
    echo @echo off
    echo set PENTAHO_JAVA_HOME=!SELECTED_JAVA!
    echo set JAVA_HOME=!SELECTED_JAVA!
    echo set PATH=!SELECTED_JAVA!\bin;%%SystemRoot%%\system32;%%SystemRoot%%
    echo cd /d "!INSTALL_DIR!"
    echo call Spoon.bat
) > "!LAUNCHER!"

if not exist "!LAUNCHER!" (
    echo.
    echo [ERROR] Failed to create launcher file.
    echo.
    pause
    exit /b 1
)
echo       OK - Launcher created: !LAUNCHER!
echo.

:: ============================================================
::  STEP 5 - DESKTOP SHORTCUT (OPTIONAL)
:: ============================================================
echo [5/5] Desktop shortcut...
echo.
set /p "SHORTCUT_CHOICE=      Create !APP_NAME! shortcut on Desktop? [Y/N]: "

if /i "!SHORTCUT_CHOICE!"=="Y" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$ws = New-Object -ComObject WScript.Shell; $sc = $ws.CreateShortcut('%USERPROFILE%\Desktop\!APP_NAME!.lnk'); $sc.TargetPath = '!LAUNCHER!'; $sc.WorkingDirectory = '!INSTALL_DIR!'; $sc.Description = 'Pentaho Data Integration !PDI_VERSION! !PDI_EDITION!'; $sc.Save()"

    if exist "%USERPROFILE%\Desktop\!APP_NAME!.lnk" (
        echo       OK - Shortcut created on Desktop.
    ) else (
        echo       [WARN] Shortcut creation failed, but installation succeeded.
    )
) else (
    echo       Shortcut skipped.
)

:: ============================================================
::  SUMMARY
:: ============================================================
echo.
echo ============================================================
echo   !APP_NAME! Installation Complete!
echo ============================================================
echo.
echo   Install directory : !INSTALL_DIR!
echo   JDK used          : !SELECTED_JAVA!
echo   Launcher          : !LAUNCHER!
echo.
echo   To launch !APP_NAME!, run:
echo   !LAUNCHER!
echo.
echo ============================================================
echo.
pause
goto :eof


:: ============================================================
::  SUBROUTINE: CHECK JAVA VERSION
:: ============================================================
:check_java_version
set "CANDIDATE=%~1"
:: Check for duplicates
if !JAVA_COUNT! GTR 0 (
    for /l %%I in (1,1,!JAVA_COUNT!) do (
        if /i "!JAVA_PATH_%%I!"=="!CANDIDATE!" exit /b
    )
)
:: Check version via java -version (extra quotes "" prevent CMD from splitting C:\Program Files)
for /f "usebackq tokens=3" %%V in (`""!CANDIDATE!\bin\java.exe" -version 2^>^&1 ^| findstr /i "version""`) do (
    set "VER=%%V"
    set "VER=!VER:"=!"
    for /f "tokens=1,2 delims=." %%A in ("!VER!") do (
        if "%%A"=="1" (set "MAJOR=%%B") else (set "MAJOR=%%A")
    )
    if "!MAJOR!"=="!TARGET_JAVA!" (
        set /a JAVA_COUNT+=1
        set "JAVA_PATH_!JAVA_COUNT!=!CANDIDATE!"
        echo       [!JAVA_COUNT!] !CANDIDATE!
    )
)
exit /b
