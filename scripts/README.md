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

> [!WARNING]
> **PDI 10 and above — License Change**
>
> Starting from version **10.2 (August 2024)**, Hitachi Vantara replaced the traditional Community Edition with **Developer Edition (DE)**, released under the **Business Source License 1.1 (BSL 1.1)**.
>
> **BSL 1.1 prohibits production use.** PDI DE is only permitted for learning, testing, proof of concept, and local development.
>
> - **Do not use PDI DE in a production environment.**
> - For production use of PDI 10.x and above, you must purchase a **Pentaho Enterprise Edition** subscription from Hitachi Vantara.
>
> **PDI 9.3 CE** is the last version licensed as open-source (LGPL/Apache) that can be used in production for free — however it reaches **End of Support on July 1, 2026** and will no longer receive official security patches after that date.
>
> | | PDI 9.3 CE | PDI 10.x Developer | PDI 10.x Enterprise |
> |---|---|---|---|
> | **License** | Open Source (LGPL/Apache) | BSL 1.1 | Commercial Subscription |
> | **Production use** | Allowed (free) | **Not allowed** | Allowed |
> | **Support status** | End of Support Jul 1 2026 | No official SLA | Active patching / LTS |

---

## Prerequisites

1. Download the PDI zip file for your target version.

   > **Note:** Older PDI CE versions have been removed from Sourceforge. Use the links below instead.

   - **PDI CE 7.x – 9.x** — [github.com/ambientelivre/legacy-pentaho-ce/releases](https://github.com/ambientelivre/legacy-pentaho-ce/releases)
   - **PDI CE (latest)** — [Hitachi Vantara Pentaho Community Edition](https://www.hitachivantara.com/en-us/products/pentaho-platform/data-integration-analytics/pentaho-community-edition.html)

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
