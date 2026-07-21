#!/bin/bash
# ============================================================
#  PDI Universal Silent Installer for Ubuntu 22.04
#  Supports PDI 7 CE, 8 CE, 9 CE, and 11 DE
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
#  STEP 1 - CHECK ROOT / SUDO
# ============================================================
echo -e "${CYAN}[1/6] Checking permissions...${NC}"
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}"
    echo "      [ERROR] This script must be run as root or with sudo."
    echo "              Re-run with: sudo bash $(basename "$0")"
    echo -e "${NC}"
    exit 1
fi

# Store the original user who called sudo
REAL_USER="${SUDO_USER:-$USER}"
echo -e "      ${GREEN}OK${NC} - Running as root (original user: $REAL_USER)."
echo ""

# ============================================================
#  STEP 2 - SCAN AND SELECT PDI ZIP FILE
# ============================================================
echo -e "${CYAN}[2/6] Scanning for PDI installer files in current folder...${NC}"

# Search for files matching pdi-ce* or pdi-de*
shopt -s nullglob
ZIP_FILES=("$SCRIPT_DIR"/pdi-ce*.zip "$SCRIPT_DIR"/pdi-de*.zip)
shopt -u nullglob

ZIP_COUNT=${#ZIP_FILES[@]}

if [ "$ZIP_COUNT" -eq 0 ]; then
    echo -e "${RED}"
    echo "      [ERROR] No installer file found."
    echo "              Make sure pdi-ce*.zip or pdi-de*.zip is located in"
    echo "              the same folder as this script."
    echo -e "${NC}"
    exit 1
fi

if [ "$ZIP_COUNT" -eq 1 ]; then
    SELECTED_ZIP="${ZIP_FILES[0]}"
    echo -e "      ${GREEN}OK${NC} - Found 1 installer, automatically selected:"
    echo "           $(basename "$SELECTED_ZIP")"
else
    echo "      Found $ZIP_COUNT PDI installers."
    echo ""
    for i in "${!ZIP_FILES[@]}"; do
        echo "      [$((i+1))] $(basename "${ZIP_FILES[$i]}")"
    done
    echo ""
    while true; do
        read -rp "      Select installer number to install [1-$ZIP_COUNT]: " ZIP_CHOICE
        if [[ "$ZIP_CHOICE" =~ ^[0-9]+$ ]] && \
           [ "$ZIP_CHOICE" -ge 1 ] && \
           [ "$ZIP_CHOICE" -le "$ZIP_COUNT" ]; then
            SELECTED_ZIP="${ZIP_FILES[$((ZIP_CHOICE - 1))]}"
            break
        fi
        echo -e "      ${RED}[ERROR] Invalid choice.${NC}"
    done
fi

ZIP_FILENAME=$(basename "$SELECTED_ZIP")
echo ""

# ============================================================
#  DETERMINE PDI VERSION & JAVA REQUIREMENT
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
    echo -e "${RED}      [ERROR] PDI version from file $ZIP_FILENAME is not recognized.${NC}"
    exit 1
fi

APP_NAME="PDI $PDI_VERSION $PDI_EDITION"
INSTALL_DIR="/opt/pentaho/design-tools/pdi-$PDI_VERSION"
TEMP_EXTRACT="/tmp/pdi${PDI_VERSION}_tmp"
LAUNCHER="$INSTALL_DIR/launch-pdi-$PDI_VERSION.sh"
SYMLINK="/usr/local/bin/pdi-$PDI_VERSION"
DESKTOP_FILE="/usr/share/applications/pdi-$PDI_VERSION.desktop"

echo -e "      Install target  : ${GREEN}$APP_NAME${NC}"
echo -e "      Java required   : ${GREEN}Java $TARGET_JAVA${NC}"
echo ""

# ============================================================
#  STEP 3 - SCAN JAVA REQUIREMENT
# ============================================================
echo -e "${CYAN}[3/6] Looking for JDK $TARGET_JAVA installation...${NC}"
echo ""

declare -a JAVA_PATHS=()

add_candidate() {
    local path="$1"
    [ -x "$path/bin/java" ] || return 0

    local version raw_ver major
    version=$("$path/bin/java" -version 2>&1 | head -1) || return 0

    # Extract version from "1.8.0_312" or "17.0.2"
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

# Scan based on target Java version
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
    echo "      [ERROR] No JDK $TARGET_JAVA installation found on this system."
    echo ""
    echo "      Please install Eclipse Temurin JDK $TARGET_JAVA first:"
    echo ""
    echo "        wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \\"
    echo "          | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/adoptium.gpg"
    echo "        echo \"deb https://packages.adoptium.net/artifactory/deb jammy main\" \\"
    echo "          | sudo tee /etc/apt/sources.list.d/adoptium.list"
    echo "        sudo apt update && sudo apt install -y temurin-${TARGET_JAVA}-jdk"
    echo ""
    echo "      After installation is complete, re-run this script."
    echo -e "${NC}"
    exit 1
fi

if [ "$JAVA_COUNT" -eq 1 ]; then
    SELECTED_JAVA="${JAVA_PATHS[0]}"
    echo ""
    echo "      Found 1 JDK $TARGET_JAVA installation, automatically selected:"
    echo -e "      ${GREEN}$SELECTED_JAVA${NC}"
else
    echo ""
    echo "      Found $JAVA_COUNT JDK $TARGET_JAVA installations."
    while true; do
        read -rp "      Select JDK number to use [1-$JAVA_COUNT]: " USER_CHOICE
        if [[ "$USER_CHOICE" =~ ^[0-9]+$ ]] && \
           [ "$USER_CHOICE" -ge 1 ] && \
           [ "$USER_CHOICE" -le "$JAVA_COUNT" ]; then
            SELECTED_JAVA="${JAVA_PATHS[$((USER_CHOICE - 1))]}"
            break
        fi
        echo -e "      ${RED}[ERROR] Invalid choice. Enter a number between 1 and $JAVA_COUNT.${NC}"
    done
fi

echo ""
echo -e "      Selected JDK: ${GREEN}$SELECTED_JAVA${NC}"
echo ""

# ============================================================
#  STEP 4 - EXTRACT ZIP
# ============================================================
echo -e "${CYAN}[4/6] Extracting $APP_NAME...${NC}"

if ! command -v unzip &>/dev/null; then
    echo -e "      ${YELLOW}unzip not found, installing...${NC}"
    apt-get install -y unzip -qq
fi

if [ -d "$INSTALL_DIR" ]; then
    echo ""
    echo "============================================================"
    echo -e "${YELLOW} [WARNING] Install folder already exists:${NC}"
    echo "              $INSTALL_DIR"
    echo "============================================================"
    echo "  [1] Overwrite     (Overlay old files, plugins/custom files safe)"
    echo "  [2] Clean Install (Delete old folder entirely, extract fresh)"
    echo "  [3] Cancel"
    echo "============================================================"
    echo ""
    while true; do
        read -rp "Select action [1-3]: " ACTION_CHOICE
        case "$ACTION_CHOICE" in
            1)
                echo ""
                echo "      Action selected: Overwriting existing files..."
                break
                ;;
            2)
                echo ""
                echo "      Action selected: Clean Install..."
                echo "      Removing old folder, please wait..."
                rm -rf "$INSTALL_DIR"
                echo -e "      ${GREEN}OK${NC} - Old folder removed."
                break
                ;;
            3)
                echo ""
                echo "      [INFO] Installation cancelled by user."
                exit 0
                ;;
            *)
                echo -e "      ${RED}[ERROR] Invalid choice. Enter 1, 2, or 3.${NC}"
                ;;
        esac
    done
fi

mkdir -p "$INSTALL_DIR" 2>/dev/null || {
    echo -e "${RED}"
    echo "      [ERROR] Failed to create directory: $INSTALL_DIR"
    echo "              Make sure the script is run with sudo."
    echo -e "${NC}"
    exit 1
}

rm -rf "$TEMP_EXTRACT"
mkdir -p "$TEMP_EXTRACT"

echo "      Extracting zip, please wait..."
unzip -q "$SELECTED_ZIP" -d "$TEMP_EXTRACT"

echo "      Verifying extraction result..."
if [ ! -d "$TEMP_EXTRACT/data-integration" ]; then
    echo -e "${RED}"
    echo "      [ERROR] Folder 'data-integration' not found after extraction."
    echo "      Temp folder contents:"
    ls "$TEMP_EXTRACT"
    echo -e "${NC}"
    rm -rf "$TEMP_EXTRACT"
    exit 1
fi

echo "      Moving files to $INSTALL_DIR..."
cp -r "$TEMP_EXTRACT/data-integration/." "$INSTALL_DIR/"
rm -rf "$TEMP_EXTRACT"

find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
echo -e "      ${GREEN}OK${NC} - Extraction complete."
echo ""

# ============================================================
#  STEP 5 - FIX OWNERSHIP
# ============================================================
echo -e "${CYAN}[5/6] Fixing folder ownership...${NC}"
chown -R "$REAL_USER:$REAL_USER" "$INSTALL_DIR"
echo -e "      ${GREEN}OK${NC} - Ownership set to: $REAL_USER"
echo ""

# ============================================================
#  STEP 6 - LAUNCHER, SYMLINK, DESKTOP
# ============================================================
echo -e "${CYAN}[6/6] Creating launcher and shortcuts...${NC}"

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
echo -e "      ${GREEN}OK${NC} - Launcher created: $LAUNCHER"

ln -sf "$LAUNCHER" "$SYMLINK"
echo -e "      ${GREEN}OK${NC} - Global symlink: $SYMLINK"

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
echo -e "      ${GREEN}OK${NC} - Application shortcut created: $DESKTOP_FILE"

# Generate uninstaller
UNINSTALL_SCRIPT="$INSTALL_DIR/uninstall-pdi-$PDI_VERSION.sh"
cat > "$UNINSTALL_SCRIPT" << UNINSTALL_EOF
#!/bin/bash
# ============================================================
#  $APP_NAME - Uninstaller
#  Install date : $(date '+%Y-%m-%d %H:%M:%S')
#  User         : $REAL_USER
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

echo -e "\${CYAN}[1/4] Checking permissions...\${NC}"
if [ "\$EUID" -ne 0 ]; then
    echo -e "\${RED}"
    echo "      [ERROR] Run with: sudo bash \$(basename "\$0")"
    echo -e "\${NC}"
    exit 1
fi
echo -e "      \${GREEN}OK\${NC} - Running as root."
echo ""

echo -e "\${CYAN}[2/4] Checking components to remove...\${NC}"
FOUND=0
[ -d "\$INSTALL_DIR" ]  && FOUND=1 && echo "        ✓ Install folder : \$INSTALL_DIR"
[ -L "\$SYMLINK" ]      && FOUND=1 && echo "        ✓ Global symlink : \$SYMLINK"
[ -f "\$DESKTOP_FILE" ] && FOUND=1 && echo "        ✓ Desktop shortcut: \$DESKTOP_FILE"

if [ "\$FOUND" -eq 0 ]; then
    echo -e "\${YELLOW}      [INFO] No $APP_NAME components found.\${NC}"
    exit 0
fi
echo ""

echo -e "\${CYAN}[3/4] Confirm uninstall...\${NC}"
echo ""
echo -e "  \${YELLOW}[WARNING]\${NC} This action cannot be undone."
echo "  What will NOT be removed: .ktr/.kjb files and Java installation."
echo ""
while true; do
    read -rp "  Proceed with uninstalling $APP_NAME? [y/N]: " CONFIRM
    case "\$CONFIRM" in
        [yY]|[yY][eE][sS]) echo ""; break ;;
        [nN]|[nN][oO]|"")
            echo "      [INFO] Uninstall cancelled."
            exit 0 ;;
        *) echo "      Enter y or n." ;;
    esac
done

echo -e "\${CYAN}[4/4] Removing components...\${NC}"

if [ -d "\$INSTALL_DIR" ]; then
    rm -rf "\$INSTALL_DIR"
    echo -e "      \${GREEN}OK\${NC} - Install folder removed."
else
    echo -e "      \${YELLOW}SKIP\${NC} - Folder not found."
fi

if [ -L "\$SYMLINK" ]; then
    rm -f "\$SYMLINK"
    echo -e "      \${GREEN}OK\${NC} - Symlink removed: \$SYMLINK"
else
    echo -e "      \${YELLOW}SKIP\${NC} - Symlink not found."
fi

if [ -f "\$DESKTOP_FILE" ]; then
    rm -f "\$DESKTOP_FILE"
    echo -e "      \${GREEN}OK\${NC} - Desktop shortcut removed."
else
    echo -e "      \${YELLOW}SKIP\${NC} - Desktop shortcut not found."
fi

update-desktop-database 2>/dev/null || true
echo -e "      \${GREEN}OK\${NC} - Application drawer updated."
echo ""

echo "============================================================"
echo -e "  \${GREEN}Uninstall Complete!\${NC}"
echo "============================================================"
echo ""
UNINSTALL_EOF

chmod +x "$UNINSTALL_SCRIPT"
chown "$REAL_USER:$REAL_USER" "$UNINSTALL_SCRIPT"
echo -e "      ${GREEN}OK${NC} - Uninstaller created: $UNINSTALL_SCRIPT"
echo ""

# ============================================================
#  SUMMARY
# ============================================================
echo "============================================================"
echo -e "  ${GREEN}$APP_NAME Installation Complete!${NC}"
echo "============================================================"
echo ""
echo "  Install directory : $INSTALL_DIR"
echo "  JDK used          : $SELECTED_JAVA"
echo "  Launcher          : $LAUNCHER"
echo "  Global command    : pdi-$PDI_VERSION"
echo "  Ownership         : $REAL_USER"
echo "  Uninstaller       : $INSTALL_DIR/uninstall-pdi-$PDI_VERSION.sh"
echo ""
echo "  To launch $APP_NAME:"
echo "    pdi-$PDI_VERSION"
echo "    or: bash $LAUNCHER"
echo ""
echo "  To uninstall:"
echo "    sudo bash $INSTALL_DIR/uninstall-pdi-$PDI_VERSION.sh"
echo ""
echo "  The app is also available in the Application Drawer (search 'PDI $PDI_VERSION')"
echo ""
echo "============================================================"
echo ""
