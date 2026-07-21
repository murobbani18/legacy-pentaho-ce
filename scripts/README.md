# PDI Universal Installer

Scripts to install Pentaho Data Integration (PDI) on Linux (Ubuntu) and Windows.

**Supported versions:**

| Version | Edition | Required Java |
|---------|---------|---------------|
| PDI 7   | CE      | Java 8        |
| PDI 8   | CE      | Java 8        |
| PDI 9   | CE      | Java 11       |
| PDI 11  | DE      | Java 17       |

---

## Prerequisites

1. Download the PDI zip file for your target version from the [Pentaho releases page](https://sourceforge.net/projects/pentaho/files/).
   The filename must match the pattern `pdi-ce-*.zip` (Community Edition) or `pdi-de-*.zip` (Developer Edition).

2. Place the zip file in the **same folder as the installer script** before running.

3. Install the required JDK for your PDI version (see table above) if not already present.

---

## Linux (Ubuntu 22.04)

**Script:** `install-pdi.sh`

### Requirements

- Ubuntu 22.04 or compatible
- `sudo` / root access
- `unzip` (installed automatically if missing)

### How to run

```bash
sudo bash install-pdi.sh
```

### Installation steps

| Step | Description |
|------|-------------|
| 1/7  | Checks for root / sudo permissions |
| 2/7  | Scans for PDI zip files in the script folder |
| 3/7  | Prompts for installation destination path |
| 4/7  | Locates an installed JDK matching the required version |
| 5/7  | Extracts the PDI zip to the install directory |
| 6/7  | Sets folder ownership to the original user |
| 7/7  | Creates a launcher script, global symlink, and desktop shortcut |

### Custom installation path

When prompted at step 3, press `y` to enter a custom path.
If the path does not exist, the script will create it automatically.
Pressing `N` (or Enter) uses the default path:

```
/opt/pentaho/design-tools/pdi-<version>
```

### Launching PDI after installation

```bash
# Via global command
pdi-9

# Or directly via the launcher
bash /opt/pentaho/design-tools/pdi-9/launch-pdi-9.sh
```

### Uninstalling

An uninstall script is generated inside the install directory:

```bash
sudo bash /opt/pentaho/design-tools/pdi-<version>/uninstall-pdi-<version>.sh
```

---

## Windows

**Script:** `install-pdi.bat`

### Requirements

- Windows 10 / 11
- Run as **Administrator**
- PowerShell (used for zip extraction and optional desktop shortcut)

### How to run

1. Right-click `install-pdi.bat`
2. Select **Run as administrator**

Or from an elevated Command Prompt:

```cmd
install-pdi.bat
```

### Installation steps

| Step | Description |
|------|-------------|
| 1/6  | Scans for PDI zip files in the script folder |
| 2/6  | Prompts for installation destination path |
| 3/6  | Locates an installed JDK matching the required version |
| 4/6  | Extracts the PDI zip to the install directory |
| 5/6  | Creates a launcher `.bat` file |
| 6/6  | Optionally creates a Desktop shortcut |

### Custom installation path

When prompted at step 2, enter `Y` to specify a custom path.
If the path does not exist, the script will create it automatically.
Entering `N` uses the default path:

```
C:\pentaho\design-tools\pdi-<version>
```

### Launching PDI after installation

```cmd
C:\pentaho\design-tools\pdi-<version>\launch-pdi-<version>.bat
```

---

## Notes

- If multiple PDI zip files are found, the script will list them and ask you to choose one.
- If multiple compatible JDK installations are found, the script will list them and ask you to choose one.
- If the installation directory already exists, the script will ask whether to **overwrite** (keep existing plugins/customizations) or do a **clean install** (delete and re-extract).
