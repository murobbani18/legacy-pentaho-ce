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
echo -e "${CYAN}[1/7] Checking permissions...${NC}"
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}"
    echo "      [ERROR] This script must be run as root or with sudo."
    echo "              Re-run with: sudo bash $(basename "$0")"
    echo -e "${NC}"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
echo -e "      ${GREEN}OK${NC} - Running as root (original user: $REAL_USER)."
echo ""

# ============================================================
#  STEP 2 - SCAN AND SELECT PDI ZIP FILE
# ============================================================
echo -e "${CYAN}[2/7] Scanning for PDI installer files in current folder...${NC}"

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
    PDI_VERSION="7"; PDI_EDITION="CE"; TARGET_JAVA="8"
elif [[ "$ZIP_FILENAME" == *pdi-ce-8* ]]; then
    PDI_VERSION="8"; PDI_EDITION="CE"; TARGET_JAVA="8"
elif [[ "$ZIP_FILENAME" == *pdi-ce-9* ]]; then
    PDI_VERSION="9"; PDI_EDITION="CE"; TARGET_JAVA="11"
elif [[ "$ZIP_FILENAME" == *pdi-de-11* ]]; then
    PDI_VERSION="11"; PDI_EDITION="DE"; TARGET_JAVA="17"
else
    echo -e "${RED}      [ERROR] PDI version from file $ZIP_FILENAME is not recognized.${NC}"
    exit 1
fi

APP_NAME="PDI $PDI_VERSION $PDI_EDITION"
INSTALL_DIR="/opt/pentaho/design-tools/pdi-$PDI_VERSION"
TEMP_EXTRACT="/tmp/pdi${PDI_VERSION}_tmp"
SYMLINK="/usr/local/bin/pdi-$PDI_VERSION"
DESKTOP_FILE="/usr/share/applications/pdi-$PDI_VERSION.desktop"

echo -e "      Install target  : ${GREEN}$APP_NAME${NC}"
echo -e "      Java required   : ${GREEN}Java $TARGET_JAVA${NC}"
echo ""

# ============================================================
#  STEP 3 - INSTALLATION PATH
# ============================================================
echo -e "${CYAN}[3/7] Installation destination...${NC}"
echo ""
echo -e "      Default path: ${GREEN}$INSTALL_DIR${NC}"
echo ""
read -rp "      Use a custom installation path? [y/N]: " CUSTOM_PATH_CHOICE

if [[ "$CUSTOM_PATH_CHOICE" =~ ^[yY]$ ]]; then
    while true; do
        read -rp "      Enter installation path: " CUSTOM_DIR
        CUSTOM_DIR="${CUSTOM_DIR#"${CUSTOM_DIR%%[![:space:]]*}"}"  # strip leading spaces
        if [ -z "$CUSTOM_DIR" ]; then
            echo -e "      ${RED}[ERROR] Path cannot be empty.${NC}"
            continue
        fi
        INSTALL_DIR="$CUSTOM_DIR"
        break
    done
    echo ""
    if [ ! -d "$INSTALL_DIR" ]; then
        echo "      Path does not exist, creating..."
        mkdir -p "$INSTALL_DIR" 2>/dev/null || {
            echo -e "${RED}"
            echo "      [ERROR] Failed to create directory: $INSTALL_DIR"
            echo "              Make sure the script is run with sudo."
            echo -e "${NC}"
            exit 1
        }
        echo -e "      ${GREEN}OK${NC} - Directory created: $INSTALL_DIR"
    else
        echo -e "      ${GREEN}OK${NC} - Path exists: $INSTALL_DIR"
    fi
else
    echo -e "      Using default path: ${GREEN}$INSTALL_DIR${NC}"
fi

# Set LAUNCHER here, AFTER INSTALL_DIR is finalized
LAUNCHER="$INSTALL_DIR/launch-pdi-$PDI_VERSION.sh"
echo ""

# ============================================================
#  STEP 4 - SCAN JAVA REQUIREMENT
# ============================================================
echo -e "${CYAN}[4/7] Looking for JDK $TARGET_JAVA installation...${NC}"
echo ""

declare -a JAVA_PATHS=()

add_candidate() {
    local path="$1"
    [ -x "$path/bin/java" ] || return 0

    local version raw_ver major
    version=$("$path/bin/java" -version 2>&1 | head -1) || return 0
    raw_ver=$(echo "$version" | awk -F '"' '/version/ {print $2}') || return 0

    if [[ "$raw_ver" == 1.* ]]; then
        major=$(echo "$raw_ver" | cut -d'.' -f2)
    else
        major=$(echo "$raw_ver" | cut -d'.' -f1)
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
#  STEP 5 - EXTRACT ZIP
# ============================================================
echo -e "${CYAN}[5/7] Extracting $APP_NAME...${NC}"

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
#  STEP 6 - FIX OWNERSHIP
# ============================================================
echo -e "${CYAN}[6/7] Fixing folder ownership...${NC}"
chown -R "$REAL_USER:$REAL_USER" "$INSTALL_DIR"
echo -e "      ${GREEN}OK${NC} - Ownership set to: $REAL_USER"
echo ""

# ============================================================
#  STEP 7 - LAUNCHERS (SPOON, PAN, KITCHEN), SYMLINKS, DESKTOP
# ============================================================
echo -e "${CYAN}[7/7] Creating launchers and shortcuts...${NC}"

LAUNCHER_PAN="$INSTALL_DIR/launch-pan-$PDI_VERSION.sh"
LAUNCHER_KITCHEN="$INSTALL_DIR/launch-kitchen-$PDI_VERSION.sh"
SYMLINK_PAN="/usr/local/bin/pan-$PDI_VERSION"
SYMLINK_KITCHEN="/usr/local/bin/kitchen-$PDI_VERSION"
DESKTOP_FILE_PAN="/usr/share/applications/pdi-pan-$PDI_VERSION.desktop"
DESKTOP_FILE_KITCHEN="/usr/share/applications/pdi-kitchen-$PDI_VERSION.desktop"

# --- Spoon launcher ---
cat > "$LAUNCHER" << LAUNCHER_EOF
#!/bin/bash
export PENTAHO_JAVA_HOME="$SELECTED_JAVA"
export JAVA_HOME="$SELECTED_JAVA"
export PATH="\$JAVA_HOME/bin:\$PATH"
cd "$INSTALL_DIR"
bash spoon.sh
LAUNCHER_EOF

# --- Pan launcher ---
cat > "$LAUNCHER_PAN" << LAUNCHER_PAN_EOF
#!/bin/bash
export PENTAHO_JAVA_HOME="$SELECTED_JAVA"
export JAVA_HOME="$SELECTED_JAVA"
export PATH="\$JAVA_HOME/bin:\$PATH"
cd "$INSTALL_DIR"
bash pan.sh "\$@"
LAUNCHER_PAN_EOF

# --- Kitchen launcher ---
cat > "$LAUNCHER_KITCHEN" << LAUNCHER_KITCHEN_EOF
#!/bin/bash
export PENTAHO_JAVA_HOME="$SELECTED_JAVA"
export JAVA_HOME="$SELECTED_JAVA"
export PATH="\$JAVA_HOME/bin:\$PATH"
cd "$INSTALL_DIR"
bash kitchen.sh "\$@"
LAUNCHER_KITCHEN_EOF

chmod +x "$LAUNCHER" "$LAUNCHER_PAN" "$LAUNCHER_KITCHEN"
chown "$REAL_USER:$REAL_USER" "$LAUNCHER" "$LAUNCHER_PAN" "$LAUNCHER_KITCHEN"
echo -e "      ${GREEN}OK${NC} - Spoon   launcher: $LAUNCHER"
echo -e "      ${GREEN}OK${NC} - Pan     launcher: $LAUNCHER_PAN"
echo -e "      ${GREEN}OK${NC} - Kitchen launcher: $LAUNCHER_KITCHEN"

ln -sf "$LAUNCHER"         "$SYMLINK"
ln -sf "$LAUNCHER_PAN"     "$SYMLINK_PAN"
ln -sf "$LAUNCHER_KITCHEN" "$SYMLINK_KITCHEN"
echo -e "      ${GREEN}OK${NC} - Global symlinks: spoon-$PDI_VERSION / pan-$PDI_VERSION / kitchen-$PDI_VERSION"

# ============================================================
#  DESKTOP ENTRIES - PER-TOOL CUSTOM NAME PROMPTS
# ============================================================
ICON_PATH="$INSTALL_DIR/spoon.png"
DESKTOP_NAME_SPOON="$APP_NAME"
DESKTOP_NAME_PAN="$APP_NAME Pan"
DESKTOP_NAME_KITCHEN="$APP_NAME Kitchen"

echo ""
echo "  --- Desktop entries ---"

# Spoon desktop
echo ""
read -rp "      Create Spoon desktop entry? [y/N]: " SC_SPOON
if [[ "$SC_SPOON" =~ ^[yY]$ ]]; then
    read -rp "      Use custom name? [y/N]: " SC_SPOON_CUSTOM
    if [[ "$SC_SPOON_CUSTOM" =~ ^[yY]$ ]]; then
        while true; do
            echo -e "      Default name: ${GREEN}$APP_NAME${NC}"
            read -rp "      Enter name: " _NAME
            _NAME="${_NAME#"${_NAME%%[![:space:]]*}"}"
            [ -z "$_NAME" ] && echo -e "      ${RED}[ERROR] Name cannot be empty.${NC}" && continue
            DESKTOP_NAME_SPOON="$_NAME"
            break
        done
    fi
    cat > "$DESKTOP_FILE" << DESKTOP_EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$DESKTOP_NAME_SPOON
GenericName=Pentaho Data Integration $PDI_VERSION
Comment=PDI $PDI_EDITION - Spoon GUI ($ZIP_FILENAME)
Exec=$LAUNCHER
Icon=$ICON_PATH
Terminal=true
Categories=Development;Database;DataVisualization;
Keywords=PDI;Pentaho;ETL;Kettle;Spoon;DataIntegration;
StartupNotify=true
DESKTOP_EOF
    echo -e "      ${GREEN}OK${NC} - Spoon desktop entry: $DESKTOP_NAME_SPOON"
else
    echo "      Spoon desktop entry skipped."
    DESKTOP_FILE=""
fi

# Pan desktop
echo ""
read -rp "      Create Pan desktop entry? [y/N]: " SC_PAN
if [[ "$SC_PAN" =~ ^[yY]$ ]]; then
    read -rp "      Use custom name? [y/N]: " SC_PAN_CUSTOM
    if [[ "$SC_PAN_CUSTOM" =~ ^[yY]$ ]]; then
        while true; do
            echo -e "      Default name: ${GREEN}$APP_NAME Pan${NC}"
            read -rp "      Enter name: " _NAME
            _NAME="${_NAME#"${_NAME%%[![:space:]]*}"}"
            [ -z "$_NAME" ] && echo -e "      ${RED}[ERROR] Name cannot be empty.${NC}" && continue
            DESKTOP_NAME_PAN="$_NAME"
            break
        done
    fi
    cat > "$DESKTOP_FILE_PAN" << DESKTOP_PAN_EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$DESKTOP_NAME_PAN
GenericName=Pentaho Pan $PDI_VERSION
Comment=PDI $PDI_EDITION - Pan transformation runner ($ZIP_FILENAME)
Exec=$LAUNCHER_PAN
Icon=$ICON_PATH
Terminal=true
Categories=Development;Database;DataVisualization;
Keywords=PDI;Pentaho;ETL;Kettle;Pan;DataIntegration;
StartupNotify=true
DESKTOP_PAN_EOF
    echo -e "      ${GREEN}OK${NC} - Pan desktop entry: $DESKTOP_NAME_PAN"
else
    echo "      Pan desktop entry skipped."
    DESKTOP_FILE_PAN=""
fi

# Kitchen desktop
echo ""
read -rp "      Create Kitchen desktop entry? [y/N]: " SC_KITCHEN
if [[ "$SC_KITCHEN" =~ ^[yY]$ ]]; then
    read -rp "      Use custom name? [y/N]: " SC_KITCHEN_CUSTOM
    if [[ "$SC_KITCHEN_CUSTOM" =~ ^[yY]$ ]]; then
        while true; do
            echo -e "      Default name: ${GREEN}$APP_NAME Kitchen${NC}"
            read -rp "      Enter name: " _NAME
            _NAME="${_NAME#"${_NAME%%[![:space:]]*}"}"
            [ -z "$_NAME" ] && echo -e "      ${RED}[ERROR] Name cannot be empty.${NC}" && continue
            DESKTOP_NAME_KITCHEN="$_NAME"
            break
        done
    fi
    cat > "$DESKTOP_FILE_KITCHEN" << DESKTOP_KITCHEN_EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$DESKTOP_NAME_KITCHEN
GenericName=Pentaho Kitchen $PDI_VERSION
Comment=PDI $PDI_EDITION - Kitchen job runner ($ZIP_FILENAME)
Exec=$LAUNCHER_KITCHEN
Icon=$ICON_PATH
Terminal=true
Categories=Development;Database;DataVisualization;
Keywords=PDI;Pentaho;ETL;Kettle;Kitchen;DataIntegration;
StartupNotify=true
DESKTOP_KITCHEN_EOF
    echo -e "      ${GREEN}OK${NC} - Kitchen desktop entry: $DESKTOP_NAME_KITCHEN"
else
    echo "      Kitchen desktop entry skipped."
    DESKTOP_FILE_KITCHEN=""
fi

update-desktop-database 2>/dev/null || true
echo ""

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
SYMLINK_PAN="$SYMLINK_PAN"
SYMLINK_KITCHEN="$SYMLINK_KITCHEN"
DESKTOP_FILE="${DESKTOP_FILE:-}"
DESKTOP_FILE_PAN="${DESKTOP_FILE_PAN:-}"
DESKTOP_FILE_KITCHEN="${DESKTOP_FILE_KITCHEN:-}"

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
[ -d "\$INSTALL_DIR" ]                                         && FOUND=1 && echo "        ✓ Install folder      : \$INSTALL_DIR"
[ -L "\$SYMLINK" ]                                             && FOUND=1 && echo "        ✓ Symlink (spoon)     : \$SYMLINK"
[ -L "\$SYMLINK_PAN" ]                                         && FOUND=1 && echo "        ✓ Symlink (pan)       : \$SYMLINK_PAN"
[ -L "\$SYMLINK_KITCHEN" ]                                     && FOUND=1 && echo "        ✓ Symlink (kitchen)   : \$SYMLINK_KITCHEN"
[ -n "\$DESKTOP_FILE" ] && [ -f "\$DESKTOP_FILE" ]             && FOUND=1 && echo "        ✓ Desktop (spoon)     : \$DESKTOP_FILE"
[ -n "\$DESKTOP_FILE_PAN" ] && [ -f "\$DESKTOP_FILE_PAN" ]     && FOUND=1 && echo "        ✓ Desktop (pan)       : \$DESKTOP_FILE_PAN"
[ -n "\$DESKTOP_FILE_KITCHEN" ] && [ -f "\$DESKTOP_FILE_KITCHEN" ] && FOUND=1 && echo "        ✓ Desktop (kitchen)   : \$DESKTOP_FILE_KITCHEN"

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

for _SL in "\$SYMLINK" "\$SYMLINK_PAN" "\$SYMLINK_KITCHEN"; do
    if [ -L "\$_SL" ]; then
        rm -f "\$_SL"
        echo -e "      \${GREEN}OK\${NC} - Symlink removed: \$_SL"
    else
        echo -e "      \${YELLOW}SKIP\${NC} - Symlink not found: \$_SL"
    fi
done

for _DF in "\$DESKTOP_FILE" "\$DESKTOP_FILE_PAN" "\$DESKTOP_FILE_KITCHEN"; do
    [ -z "\$_DF" ] && continue
    if [ -f "\$_DF" ]; then
        rm -f "\$_DF"
        echo -e "      \${GREEN}OK\${NC} - Desktop entry removed: \$_DF"
    else
        echo -e "      \${YELLOW}SKIP\${NC} - Desktop entry not found: \$_DF"
    fi
done

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
echo "  Ownership         : $REAL_USER"
echo ""
echo "  Launchers:"
echo "    Spoon   : $LAUNCHER"
echo "    Pan     : $LAUNCHER_PAN"
echo "    Kitchen : $LAUNCHER_KITCHEN"
echo ""
echo "  Global commands:"
echo "    spoon-$PDI_VERSION  /  pan-$PDI_VERSION  /  kitchen-$PDI_VERSION"
echo ""
[ -n "$DESKTOP_FILE" ]         && echo "  Desktop (Spoon)   : $DESKTOP_NAME_SPOON"
[ -n "$DESKTOP_FILE_PAN" ]     && echo "  Desktop (Pan)     : $DESKTOP_NAME_PAN"
[ -n "$DESKTOP_FILE_KITCHEN" ] && echo "  Desktop (Kitchen) : $DESKTOP_NAME_KITCHEN"
echo ""
echo "  Uninstaller       : $INSTALL_DIR/uninstall-pdi-$PDI_VERSION.sh"
echo ""
echo "  To launch Spoon:"
echo "    spoon-$PDI_VERSION   or: bash $LAUNCHER"
echo ""
echo "  To run a transformation:"
echo "    pan-$PDI_VERSION -file=/path/to/trans.ktr"
echo ""
echo "  To run a job:"
echo "    kitchen-$PDI_VERSION -file=/path/to/job.kjb"
echo ""
echo "  To uninstall:"
echo "    sudo bash $INSTALL_DIR/uninstall-pdi-$PDI_VERSION.sh"
echo ""
echo "============================================================"
echo ""