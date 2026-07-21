#!/bin/bash
# ============================================================
#  PDI Universal Silent Installer for Ubuntu 22.04
#  Mendukung PDI 7 CE, 8 CE, 9 CE, dan 11 DE
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "============================================================"
echo "  PDI Universal - Silent Installer for Ubuntu"
echo "============================================================"
echo ""

# ============================================================
#  STEP 1 - CEK ROOT / SUDO
# ============================================================
echo -e "${CYAN}[1/6] Memeriksa hak akses...${NC}"
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}"
    echo "      [ERROR] Script ini harus dijalankan sebagai root atau dengan sudo."
    echo "              Jalankan ulang dengan: sudo bash $(basename "$0")"
    echo -e "${NC}"
    exit 1
fi

# Simpan user asli yang memanggil sudo
REAL_USER="${SUDO_USER:-$USER}"
echo -e "      ${GREEN}OK${NC} - Berjalan sebagai root (user asli: $REAL_USER)."
echo ""

# ============================================================
#  STEP 2 - SCAN DAN PILIH FILE ZIP PDI
# ============================================================
echo -e "${CYAN}[2/6] Memindai file installer PDI di folder saat ini...${NC}"

# Mencari file dengan pattern pdi-ce* atau pdi-de*
shopt -s nullglob
ZIP_FILES=("$SCRIPT_DIR"/pdi-ce*.zip "$SCRIPT_DIR"/pdi-de*.zip)
shopt -u nullglob

ZIP_COUNT=${#ZIP_FILES[@]}

if [ "$ZIP_COUNT" -eq 0 ]; then
    echo -e "${RED}"
    echo "      [ERROR] Tidak ditemukan file installer."
    echo "              Pastikan file pdi-ce*.zip atau pdi-de*.zip berada di"
    echo "              folder yang sama dengan script ini."
    echo -e "${NC}"
    exit 1
fi

if [ "$ZIP_COUNT" -eq 1 ]; then
    SELECTED_ZIP="${ZIP_FILES[0]}"
    echo -e "      ${GREEN}OK${NC} - Ditemukan 1 installer, otomatis digunakan:"
    echo "           $(basename "$SELECTED_ZIP")"
else
    echo "      Ditemukan $ZIP_COUNT installer PDI."
    echo ""
    for i in "${!ZIP_FILES[@]}"; do
        echo "      [$((i+1))] $(basename "${ZIP_FILES[$i]}")"
    done
    echo ""
    while true; do
        read -rp "      Pilih nomor installer yang akan di-install [1-$ZIP_COUNT]: " ZIP_CHOICE
        if [[ "$ZIP_CHOICE" =~ ^[0-9]+$ ]] && \
           [ "$ZIP_CHOICE" -ge 1 ] && \
           [ "$ZIP_CHOICE" -le "$ZIP_COUNT" ]; then
            SELECTED_ZIP="${ZIP_FILES[$((ZIP_CHOICE - 1))]}"
            break
        fi
        echo -e "      ${RED}[ERROR] Pilihan tidak valid.${NC}"
    done
fi

ZIP_FILENAME=$(basename "$SELECTED_ZIP")
echo ""

# ============================================================
#  MENENTUKAN VERSI PDI & KEBUTUHAN JAVA
# ============================================================
if [[ "$ZIP_FILENAME" == *pdi-ce-7* ]]; then
    PDI_VERSION="7"
    PDI_EDITION="CE"
    TARGET_JAVA="8"
elif [[ "$ZIP_FILENAME" == *pdi-ce-8* ]]; then
    PDI_VERSION="8"
    PDI_EDITION="CE"
    TARGET_JAVA="8"
elif [[ "$ZIP_FILENAME" == *pdi-ce-9* ]]; then
    PDI_VERSION="9"
    PDI_EDITION="CE"
    TARGET_JAVA="11"
elif [[ "$ZIP_FILENAME" == *pdi-de-11* ]]; then
    PDI_VERSION="11"
    PDI_EDITION="DE"
    TARGET_JAVA="17"
else
    echo -e "${RED}      [ERROR] Versi PDI dari file $ZIP_FILENAME tidak dikenali.${NC}"
    exit 1
fi

APP_NAME="PDI $PDI_VERSION $PDI_EDITION"
INSTALL_DIR="/opt/pentaho/design-tools/pdi-$PDI_VERSION"
TEMP_EXTRACT="/tmp/pdi${PDI_VERSION}_tmp"
LAUNCHER="$INSTALL_DIR/launch-pdi-$PDI_VERSION.sh"
SYMLINK="/usr/local/bin/pdi-$PDI_VERSION"
DESKTOP_FILE="/usr/share/applications/pdi-$PDI_VERSION.desktop"

echo -e "      Target Instalasi: ${GREEN}$APP_NAME${NC}"
echo -e "      Kebutuhan Java  : ${GREEN}Java $TARGET_JAVA${NC}"
echo ""

# ============================================================
#  STEP 3 - SCAN KEBUTUHAN JAVA
# ============================================================
echo -e "${CYAN}[3/6] Mencari instalasi JDK $TARGET_JAVA...${NC}"
echo ""

declare -a JAVA_PATHS=()

add_candidate() {
    local path="$1"
    [ -x "$path/bin/java" ] || return 0
    
    local version raw_ver major
    version=$("$path/bin/java" -version 2>&1 | head -1) || return 0
    
    # Ekstrak versi dari string "1.8.0_312" atau "17.0.2"
    raw_ver=$(echo "$version" | awk -F '"' '/version/ {print $2}') || return 0
    
    if [[ "$raw_ver" == 1.* ]]; then
        major=$(echo "$raw_ver" | cut -d'.' -f2) # "1.8" -> "8"
    else
        major=$(echo "$raw_ver" | cut -d'.' -f1) # "11.x" -> "11", "17.x" -> "17"
    fi
    
    [ "$major" = "$TARGET_JAVA" ] || return 0
    
    local existing
    for existing in "${JAVA_PATHS[@]:-}"; do
        [ "$existing" = "$path" ] && return 0
    done
    JAVA_PATHS+=("$path")
    echo -e "      [${#JAVA_PATHS[@]}] $path"
    return 0
}

safe_scan_dir() {
    local pattern="$1"
    local d
    for d in $pattern; do
        [ -d "$d" ] && add_candidate "$d" || true
    done
    return 0
}

# Scan berdasarkan versi Java target
safe_scan_dir "/usr/lib/jvm/temurin-$TARGET_JAVA*"
safe_scan_dir "/usr/lib/jvm/temurin-${TARGET_JAVA}-jdk*"
safe_scan_dir "/usr/lib/jvm/java-$TARGET_JAVA-openjdk*"
safe_scan_dir "/usr/lib/jvm/java-$TARGET_JAVA*"

SDKMAN_DIR="${SDKMAN_DIR:-$HOME/.sdkman}"
safe_scan_dir "$SDKMAN_DIR/candidates/java/$TARGET_JAVA*"
safe_scan_dir "/opt/java/jdk-$TARGET_JAVA*"
safe_scan_dir "/opt/jdk-$TARGET_JAVA*"
safe_scan_dir "/opt/amazon-corretto-$TARGET_JAVA*"

if command -v update-java-alternatives &>/dev/null; then
    while IFS= read -r line; do
        path=$(echo "$line" | awk '{print $3}')
        [ -d "$path" ] && add_candidate "$path" || true
    done < <(update-java-alternatives --list 2>/dev/null || true)
fi

if [ -n "${JAVA_HOME:-}" ] && [ -d "${JAVA_HOME:-}" ]; then
    add_candidate "$JAVA_HOME" || true
fi

JAVA_COUNT=${#JAVA_PATHS[@]}

if [ "$JAVA_COUNT" -eq 0 ]; then
    echo -e "${RED}"
    echo "      [ERROR] Tidak ditemukan instalasi JDK $TARGET_JAVA di sistem ini."
    echo ""
    echo "      Silakan install Eclipse Temurin JDK $TARGET_JAVA terlebih dahulu:"
    echo ""
    echo "        wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \\"
    echo "          | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/adoptium.gpg"
    echo "        echo \"deb https://packages.adoptium.net/artifactory/deb jammy main\" \\"
    echo "          | sudo tee /etc/apt/sources.list.d/adoptium.list"
    echo "        sudo apt update && sudo apt install -y temurin-${TARGET_JAVA}-jdk"
    echo ""
    echo "      Setelah install selesai, jalankan kembali script ini."
    echo -e "${NC}"
    exit 1
fi

if [ "$JAVA_COUNT" -eq 1 ]; then
    SELECTED_JAVA="${JAVA_PATHS[0]}"
    echo ""
    echo "      Ditemukan 1 instalasi JDK $TARGET_JAVA, otomatis digunakan:"
    echo -e "      ${GREEN}$SELECTED_JAVA${NC}"
else
    echo ""
    echo "      Ditemukan $JAVA_COUNT instalasi JDK $TARGET_JAVA."
    while true; do
        read -rp "      Pilih nomor JDK yang akan digunakan [1-$JAVA_COUNT]: " USER_CHOICE
        if [[ "$USER_CHOICE" =~ ^[0-9]+$ ]] && \
           [ "$USER_CHOICE" -ge 1 ] && \
           [ "$USER_CHOICE" -le "$JAVA_COUNT" ]; then
            SELECTED_JAVA="${JAVA_PATHS[$((USER_CHOICE - 1))]}"
            break
        fi
        echo -e "      ${RED}[ERROR] Pilihan tidak valid. Masukkan angka 1 sampai $JAVA_COUNT.${NC}"
    done
fi

echo ""
echo -e "      JDK yang dipilih: ${GREEN}$SELECTED_JAVA${NC}"
echo ""

# ============================================================
#  STEP 4 - EXTRACT ZIP
# ============================================================
echo -e "${CYAN}[4/6] Mengekstrak $APP_NAME...${NC}"

if ! command -v unzip &>/dev/null; then
    echo -e "      ${YELLOW}unzip tidak ditemukan, menginstall...${NC}"
    apt-get install -y unzip -qq
fi

if [ -d "$INSTALL_DIR" ]; then
    echo ""
    echo "============================================================"
    echo -e "${YELLOW} [PERINGATAN] Folder instalasi sudah ada:${NC}"
    echo "              $INSTALL_DIR"
    echo "============================================================"
    echo "  [1] Timpa         (Tumpuk file lama, plugin/kustom aman)"
    echo "  [2] Clean Install (Hapus total folder lama, ekstrak baru)"
    echo "  [3] Batal"
    echo "============================================================"
    echo ""
    while true; do
        read -rp "Pilih tindakan [1-3]: " ACTION_CHOICE
        case "$ACTION_CHOICE" in
            1)
                echo ""
                echo "      Perilaku dipilih: Menimpa file existing..."
                break
                ;;
            2)
                echo ""
                echo "      Perilaku dipilih: Clean Install..."
                echo "      Menghapus folder lama, harap tunggu..."
                rm -rf "$INSTALL_DIR"
                echo -e "      ${GREEN}OK${NC} - Folder lama dihapus."
                break
                ;;
            3)
                echo ""
                echo "      [INFO] Instalasi dibatalkan oleh pengguna."
                exit 0
                ;;
            *)
                echo -e "      ${RED}[ERROR] Pilihan tidak valid. Masukkan 1, 2, atau 3.${NC}"
                ;;
        esac
    done
fi

mkdir -p "$INSTALL_DIR" 2>/dev/null || {
    echo -e "${RED}"
    echo "      [ERROR] Gagal membuat direktori: $INSTALL_DIR"
    echo "              Pastikan script dijalankan dengan sudo."
    echo -e "${NC}"
    exit 1
}

rm -rf "$TEMP_EXTRACT"
mkdir -p "$TEMP_EXTRACT"

echo "      Mengekstrak zip, harap tunggu..."
unzip -q "$SELECTED_ZIP" -d "$TEMP_EXTRACT"

echo "      Verifikasi hasil ekstraksi..."
if [ ! -d "$TEMP_EXTRACT/data-integration" ]; then
    echo -e "${RED}"
    echo "      [ERROR] Folder 'data-integration' tidak ditemukan setelah ekstraksi."
    echo "      Isi folder temp:"
    ls "$TEMP_EXTRACT"
    echo -e "${NC}"
    rm -rf "$TEMP_EXTRACT"
    exit 1
fi

echo "      Memindahkan file ke $INSTALL_DIR..."
cp -r "$TEMP_EXTRACT/data-integration/." "$INSTALL_DIR/"
rm -rf "$TEMP_EXTRACT"

find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
echo -e "      ${GREEN}OK${NC} - Ekstraksi selesai."
echo ""

# ============================================================
#  STEP 5 - FIX OWNERSHIP
# ============================================================
echo -e "${CYAN}[5/6] Memperbaiki ownership folder...${NC}"
chown -R "$REAL_USER:$REAL_USER" "$INSTALL_DIR"
echo -e "      ${GREEN}OK${NC} - Ownership disetel ke: $REAL_USER"
echo ""

# ============================================================
#  STEP 6 - LAUNCHER, SYMLINK, DESKTOP
# ============================================================
echo -e "${CYAN}[6/6] Membuat launcher dan shortcut...${NC}"

cat > "$LAUNCHER" << LAUNCHER_EOF
#!/bin/bash
export PENTAHO_JAVA_HOME="$SELECTED_JAVA"
export JAVA_HOME="$SELECTED_JAVA"
export PATH="\$JAVA_HOME/bin:\$PATH"
cd "$INSTALL_DIR"
bash spoon.sh
LAUNCHER_EOF

chmod +x "$LAUNCHER"
chown "$REAL_USER:$REAL_USER" "$LAUNCHER"
echo -e "      ${GREEN}OK${NC} - Launcher dibuat: $LAUNCHER"

ln -sf "$LAUNCHER" "$SYMLINK"
echo -e "      ${GREEN}OK${NC} - Symlink global: $SYMLINK"

ICON_PATH="$INSTALL_DIR/spoon.png"

cat > "$DESKTOP_FILE" << DESKTOP_EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
GenericName=Pentaho Data Integration $PDI_VERSION
Comment=Pentaho Data Integration $PDI_EDITION ($ZIP_FILENAME)
Exec=$LAUNCHER
Icon=$ICON_PATH
Terminal=true
Categories=Development;Database;DataVisualization;
Keywords=PDI;Pentaho;ETL;Kettle;Spoon;DataIntegration;
StartupNotify=true
DESKTOP_EOF

update-desktop-database 2>/dev/null || true
echo -e "      ${GREEN}OK${NC} - Application shortcut dibuat: $DESKTOP_FILE"

# Generate uninstaller
UNINSTALL_SCRIPT="$INSTALL_DIR/uninstall-pdi-$PDI_VERSION.sh"
cat > "$UNINSTALL_SCRIPT" << UNINSTALL_EOF
#!/bin/bash
# ============================================================
#  $APP_NAME - Uninstaller
#  Tanggal install : $(date '+%Y-%m-%d %H:%M:%S')
#  User            : $REAL_USER
# ============================================================

set -euo pipefail

INSTALL_DIR="$INSTALL_DIR"
SYMLINK="$SYMLINK"
DESKTOP_FILE="$DESKTOP_FILE"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "============================================================"
echo "  $APP_NAME - Uninstaller"
echo "============================================================"
echo ""

echo -e "\${CYAN}[1/4] Memeriksa hak akses...\${NC}"
if [ "\$EUID" -ne 0 ]; then
    echo -e "\${RED}"
    echo "      [ERROR] Jalankan dengan: sudo bash \$(basename "\$0")"
    echo -e "\${NC}"
    exit 1
fi
echo -e "      \${GREEN}OK\${NC} - Berjalan sebagai root."
echo ""

echo -e "\${CYAN}[2/4] Memeriksa komponen yang akan dihapus...\${NC}"
FOUND=0
[ -d "\$INSTALL_DIR" ]  && FOUND=1 && echo "        ✓ Folder instalasi : \$INSTALL_DIR"
[ -L "\$SYMLINK" ]      && FOUND=1 && echo "        ✓ Symlink global   : \$SYMLINK"
[ -f "\$DESKTOP_FILE" ] && FOUND=1 && echo "        ✓ Desktop shortcut : \$DESKTOP_FILE"

if [ "\$FOUND" -eq 0 ]; then
    echo -e "\${YELLOW}      [INFO] Tidak ada komponen $APP_NAME yang ditemukan.\${NC}"
    exit 0
fi
echo ""

echo -e "\${CYAN}[3/4] Konfirmasi uninstall...\${NC}"
echo ""
echo -e "  \${YELLOW}[PERINGATAN]\${NC} Tindakan ini tidak bisa dibatalkan."
echo "  Yang TIDAK dihapus: file .ktr/.kjb dan instalasi Java."
echo ""
while true; do
    read -rp "  Lanjutkan uninstall $APP_NAME? [y/N]: " CONFIRM
    case "\$CONFIRM" in
        [yY]|[yY][eE][sS]) echo ""; break ;;
        [nN]|[nN][oO]|"")
            echo "      [INFO] Uninstall dibatalkan."
            exit 0 ;;
        *) echo "      Masukkan y atau n." ;;
    esac
done

echo -e "\${CYAN}[4/4] Menghapus komponen...\${NC}"

if [ -d "\$INSTALL_DIR" ]; then
    rm -rf "\$INSTALL_DIR"
    echo -e "      \${GREEN}OK\${NC} - Folder instalasi dihapus."
else
    echo -e "      \${YELLOW}SKIP\${NC} - Folder tidak ditemukan."
fi

if [ -L "\$SYMLINK" ]; then
    rm -f "\$SYMLINK"
    echo -e "      \${GREEN}OK\${NC} - Symlink dihapus: \$SYMLINK"
else
    echo -e "      \${YELLOW}SKIP\${NC} - Symlink tidak ditemukan."
fi

if [ -f "\$DESKTOP_FILE" ]; then
    rm -f "\$DESKTOP_FILE"
    echo -e "      \${GREEN}OK\${NC} - Desktop shortcut dihapus."
else
    echo -e "      \${YELLOW}SKIP\${NC} - Desktop shortcut tidak ditemukan."
fi

update-desktop-database 2>/dev/null || true
echo -e "      \${GREEN}OK\${NC} - Application drawer diperbarui."
echo ""

echo "============================================================"
echo -e "  \${GREEN}Uninstall Selesai!\${NC}"
echo "============================================================"
echo ""
UNINSTALL_EOF

chmod +x "$UNINSTALL_SCRIPT"
chown "$REAL_USER:$REAL_USER" "$UNINSTALL_SCRIPT"
echo -e "      ${GREEN}OK${NC} - Uninstaller dibuat: $UNINSTALL_SCRIPT"
echo ""

# ============================================================
#  SUMMARY
# ============================================================
echo "============================================================"
echo -e "  ${GREEN}Instalasi $APP_NAME Selesai!${NC}"
echo "============================================================"
echo ""
echo "  Direktori instalasi : $INSTALL_DIR"
echo "  JDK yang digunakan  : $SELECTED_JAVA"
echo "  Launcher            : $LAUNCHER"
echo "  Global command      : pdi-$PDI_VERSION"
echo "  Ownership           : $REAL_USER"
echo "  Uninstaller         : $INSTALL_DIR/uninstall-pdi-$PDI_VERSION.sh"
echo ""
echo "  Cara menjalankan $APP_NAME:"
echo "    pdi-$PDI_VERSION"
echo "    atau: bash $LAUNCHER"
echo ""
echo "  Untuk uninstall:"
echo "    sudo bash $INSTALL_DIR/uninstall-pdi-$PDI_VERSION.sh"
echo ""
echo "  Aplikasi juga tersedia di Application Drawer (cari 'PDI $PDI_VERSION')"
echo ""
echo "============================================================"
echo ""