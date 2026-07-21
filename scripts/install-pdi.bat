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
::  STEP 1 - SCAN DAN PILIH FILE ZIP PDI
:: ============================================================
echo [1/5] Memindai file installer PDI di folder saat ini...

for %%F in ("%SCRIPT_DIR%pdi-ce*.zip" "%SCRIPT_DIR%pdi-de*.zip") do (
    if exist "%%F" (
        set /a ZIP_COUNT+=1
        set "ZIP_PATH_!ZIP_COUNT!=%%~F"
        set "ZIP_NAME_!ZIP_COUNT!=%%~nxF"
    )
)

if !ZIP_COUNT!==0 (
    echo.
    echo [ERROR] Tidak ditemukan file installer.
    echo         Pastikan file pdi-ce*.zip atau pdi-de*.zip berada di
    echo         folder yang sama dengan script ini.
    echo.
    pause
    exit /b 1
)

if !ZIP_COUNT!==1 (
    set "SELECTED_ZIP_PATH=!ZIP_PATH_1!"
    set "SELECTED_ZIP_NAME=!ZIP_NAME_1!"
    echo       OK - Ditemukan 1 installer, otomatis digunakan:
    echo            !SELECTED_ZIP_NAME!
    goto :zip_selected
)

echo       Ditemukan !ZIP_COUNT! installer PDI.
echo.
for /l %%I in (1,1,!ZIP_COUNT!) do (
    echo       [%%I] !ZIP_NAME_%%I!
)
echo.
:prompt_zip
set /p "ZIP_CHOICE=      Pilih nomor installer yang akan di-install [1-!ZIP_COUNT!]: "

set "SELECTED_ZIP_PATH="
for /l %%I in (1,1,!ZIP_COUNT!) do (
    if "!ZIP_CHOICE!"=="%%I" (
        set "SELECTED_ZIP_PATH=!ZIP_PATH_%%I!"
        set "SELECTED_ZIP_NAME=!ZIP_NAME_%%I!"
    )
)

if not defined SELECTED_ZIP_PATH (
    echo       [ERROR] Pilihan tidak valid.
    goto :prompt_zip
)

:zip_selected
echo.

:: ============================================================
::  MENENTUKAN VERSI PDI & KEBUTUHAN JAVA
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

echo [ERROR] Versi PDI dari file !SELECTED_ZIP_NAME! tidak dikenali.
pause
exit /b 1

:version_set
set "APP_NAME=PDI !PDI_VERSION! !PDI_EDITION!"
set "INSTALL_DIR=C:\pentaho\design-tools\pdi-!PDI_VERSION!"
set "TEMP_EXTRACT=C:\pdi!PDI_VERSION!_tmp"
set "LAUNCHER=!INSTALL_DIR!\launch-pdi-!PDI_VERSION!.bat"

echo       Target Instalasi: !APP_NAME!
echo       Kebutuhan Java  : Java !TARGET_JAVA!
echo.

:: ============================================================
::  STEP 2 - SCAN KEBUTUHAN JAVA
:: ============================================================
echo [2/5] Mencari instalasi JDK !TARGET_JAVA!...
echo.

:: --- Scan Registry JavaSoft (Oracle, dsb) ---
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
    echo [ERROR] Tidak ditemukan instalasi JDK !TARGET_JAVA! di sistem ini.
    echo         Silakan install Temurin JDK !TARGET_JAVA! terlebih dahulu dari:
    echo         https://adoptium.net/temurin/releases/?version=!TARGET_JAVA!
    echo.
    pause
    exit /b 1
)

if !JAVA_COUNT!==1 (
    set "SELECTED_JAVA=!JAVA_PATH_1!"
    echo.
    echo       Ditemukan 1 instalasi JDK !TARGET_JAVA!, otomatis digunakan:
    echo       !SELECTED_JAVA!
    goto :java_selected
)

echo.
echo       Ditemukan !JAVA_COUNT! instalasi JDK !TARGET_JAVA!.
:prompt_java
set /p "USER_CHOICE=      Pilih nomor JDK yang akan digunakan [1-!JAVA_COUNT!]: "

set "SELECTED_JAVA="
for /l %%I in (1,1,!JAVA_COUNT!) do (
    if "!USER_CHOICE!"=="%%I" set "SELECTED_JAVA=!JAVA_PATH_%%I!"
)

if not defined SELECTED_JAVA (
    echo       [ERROR] Pilihan tidak valid.
    goto :prompt_java
)

:java_selected
echo.
echo       JDK yang dipilih: !SELECTED_JAVA!
echo.

:: ============================================================
::  STEP 3 - EXTRACT ZIP
:: ============================================================
echo [3/5] Mengekstrak !APP_NAME!...

if not exist "!INSTALL_DIR!" goto :proceed_install

echo.
echo ============================================================
echo [PERINGATAN] Folder instalasi sudah ada: 
echo              !INSTALL_DIR!
echo ============================================================
echo  [1] Timpa         (Langsung tumpuk file lama, file kustom/plugin tetap aman)
echo  [2] Clean Install (Hapus total folder lama sebelum ekstrak baru)
echo  [3] Batal         (Hentikan proses instalasi)
echo ============================================================
echo.

:prompt_action
set /p "ACTION_CHOICE=Pilih tindakan [1-3]: "

if "!ACTION_CHOICE!"=="1" goto :handle_overwrite
if "!ACTION_CHOICE!"=="2" goto :handle_clean
if "!ACTION_CHOICE!"=="3" goto :handle_cancel

echo [ERROR] Pilihan tidak valid. Silakan pilih 1, 2, atau 3.
goto :prompt_action

:handle_overwrite
echo.
echo Perilaku dipilih: Menimpa file existing...
goto :proceed_install

:handle_clean
echo.
echo Perilaku dipilih: Melakukan Clean Install...
echo Menghapus folder lama, harap tunggu...
rmdir /s /q "!INSTALL_DIR!"
if errorlevel 1 (
    echo [ERROR] Gagal menghapus folder existing.
    echo         Pastikan tidak ada aplikasi atau CMD lain yang sedang membuka folder tersebut.
    pause
    exit /b 1
)
goto :proceed_install

:handle_cancel
echo.
echo [INFO] Instalasi dibatalkan oleh pengguna.
pause
exit /b 0

:proceed_install
if not exist "!INSTALL_DIR!" (
    mkdir "!INSTALL_DIR!" 2>nul
    if errorlevel 1 (
        echo.
        echo [ERROR] Gagal membuat direktori: !INSTALL_DIR!
        echo         Coba jalankan script ini sebagai Administrator.
        echo.
        pause
        exit /b 1
    )
)

if exist "!TEMP_EXTRACT!" rmdir /s /q "!TEMP_EXTRACT!"
mkdir "!TEMP_EXTRACT!"

echo         Mengekstrak zip, harap tunggu...

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Expand-Archive -LiteralPath '!SELECTED_ZIP_PATH!' -DestinationPath '!TEMP_EXTRACT!' -Force"

if errorlevel 1 (
    echo.
    echo [ERROR] Gagal mengekstrak file zip.
    echo.
    rmdir /s /q "!TEMP_EXTRACT!" 2>nul
    pause
    exit /b 1
)

echo         Verifikasi hasil ekstraksi...
if not exist "!TEMP_EXTRACT!\data-integration\" (
    echo.
    echo [ERROR] Folder 'data-integration' tidak ditemukan setelah ekstraksi.
    echo         Isi folder temp:
    dir "!TEMP_EXTRACT!" /b
    echo.
    rmdir /s /q "!TEMP_EXTRACT!" 2>nul
    pause
    exit /b 1
)

echo         Memindahkan file ke !INSTALL_DIR!...
xcopy "!TEMP_EXTRACT!\data-integration\*" "!INSTALL_DIR!\" /E /H /Y /Q >nul 2>&1
if errorlevel 1 (
    echo.
    echo [ERROR] Gagal memindahkan file ke direktori instalasi.
    echo.
    rmdir /s /q "!TEMP_EXTRACT!" 2>nul
    pause
    exit /b 1
)

rmdir /s /q "!TEMP_EXTRACT!" 2>nul
echo         OK - Ekstraksi selesai.
echo.

:: ============================================================
::  STEP 4 - GENERATE LAUNCHER
:: ============================================================
echo [4/5] Membuat file launcher...

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
    echo [ERROR] Gagal membuat file launcher.
    echo.
    pause
    exit /b 1
)
echo       OK - Launcher dibuat: !LAUNCHER!
echo.

:: ============================================================
::  STEP 5 - SHORTCUT DESKTOP (OPSIONAL)
:: ============================================================
echo [5/5] Shortcut desktop...
echo.
set /p "SHORTCUT_CHOICE=      Buat shortcut !APP_NAME! di Desktop? [Y/N]: "

if /i "!SHORTCUT_CHOICE!"=="Y" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$ws = New-Object -ComObject WScript.Shell; $sc = $ws.CreateShortcut('%USERPROFILE%\Desktop\!APP_NAME!.lnk'); $sc.TargetPath = '!LAUNCHER!'; $sc.WorkingDirectory = '!INSTALL_DIR!'; $sc.Description = 'Pentaho Data Integration !PDI_VERSION! !PDI_EDITION!'; $sc.Save()"

    if exist "%USERPROFILE%\Desktop\!APP_NAME!.lnk" (
        echo       OK - Shortcut dibuat di Desktop.
    ) else (
        echo       [WARN] Shortcut gagal dibuat, tapi instalasi tetap berhasil.
    )
) else (
    echo       Shortcut dilewati.
)

:: ============================================================
::  SUMMARY
:: ============================================================
echo.
echo ============================================================
echo   Instalasi !APP_NAME! Selesai!
echo ============================================================
echo.
echo   Direktori instalasi : !INSTALL_DIR!
echo   JDK yang digunakan  : !SELECTED_JAVA!
echo   Launcher            : !LAUNCHER!
echo.
echo   Untuk menjalankan !APP_NAME!, eksekusi:
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
:: Cek duplikat
if !JAVA_COUNT! GTR 0 (
    for /l %%I in (1,1,!JAVA_COUNT!) do (
        if /i "!JAVA_PATH_%%I!"=="!CANDIDATE!" exit /b
    )
)
:: Cek versi melalui java -version (Dibungkus extra quotes "" agar CMD tidak memotong C:\Program Files)
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