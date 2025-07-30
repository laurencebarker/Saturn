# Saturn Update Manager 3.0 Setup Documentation

## Overview
The **Saturn Update Manager** is a web-based application designed to manage and execute update and maintenance scripts for various software components (e.g., Saturn G2, piHPSDR) on a Raspberry Pi running Debian Bookworm. It provides a user-friendly interface to select scripts, configure execution flags, manage backups, and apply themes, all served through a Flask-based webapp behind an Apache proxy with basic authentication.

### Key Features
- **Web Interface**: A browser-based GUI (`index.html`) served at `http://<IP or localhost>/saturn/` with Tailwind CSS styling.
- **Script Management**: Executes scripts listed in `config.json` (e.g., `update-G2.py`, `log_cleaner.sh`) with configurable flags.
- **Theme Support**: Applies customizable themes from `themes.json` for UI styling.
- **Backup Handling**: Supports listing and restoring from backup directories (e.g., `pihpsdr-backup-*`).
- **Authentication**: Secured with Apache's basic auth (`admin:password123` by default).
- **Logging**: Detailed logs for installation, script execution, and errors in `~/saturn-logs/`.
- **Modular Design**: Separates concerns into Python modules for installation, logging, and service setup.

## End-to-End System Workflow

### 1. Installation
The system is installed by running `install_update_manager.py` with sudo privileges:
```bash
sudo python3 ~/github/Saturn/update_manager/install_update_manager.py
```

#### Steps Performed by `install_update_manager.py`:
- **OS Detection**: Identifies the OS (Bookworm or Buster) using `os_detector.py`.
- **System Dependencies**: Installs required Debian packages (e.g., `python3`, `apache2`, `libapache2-mod-proxy-uwsgi`) via `dependencies.py`.
- **Virtual Environment**: Creates a Python virtual environment (`~/venv/`) and installs Python packages (`flask`, `ansi2html==1.9.2`, `psutil==7.0.0`, `pyfiglet`, `gunicorn`, `gevent`) via `venv_setup.py`.
- **Apache Configuration**: Sets up a virtual host (`/etc/apache2/sites-available/saturn.conf`) with proxy to Gunicorn (`127.0.0.1:5000`) and basic auth (`/etc/apache2/.htpasswd`) via `apache_config.py`.
- **File Copying**: Copies configuration files (`config.json`, `themes.json`), templates (`index.html`), and the desktop shortcut (`SaturnUpdateManager.desktop`) to `~/.saturn/` and `~/Desktop/`, overwriting existing files and backing up JSON files with timestamps (e.g., `20250728-193511-config.json`) via `copy_files()` in `install_update_manager.py`.
- **Systemd Service**: Sets up a systemd service (`saturn-update-manager.service`) to run the Flask app with Gunicorn via `service_setup.py`.
- **Validation**: Checks Apache status, Gunicorn processes, and tests the endpoint (`http://localhost/saturn/`) with curl.

#### Output
- Logs are written to `~/saturn-logs/setup_saturn_webserver-<timestamp>.log`.
- The webapp is accessible at `http://<IP>/saturn/` or `http://localhost/saturn/` with credentials `admin:password123`.

### 2. Webapp Operation
The webapp is served by `saturn_update_manager.py` running under Gunicorn, proxied by Apache.

#### Components
- **Flask App**: Defined in `saturn_update_manager.py`, it handles routes (`/`, `/get_scripts`, `/run`, etc.) and serves `index.html` from `~/.saturn/templates/`.
- **Gunicorn**: Runs the Flask app with 5 gevent workers on `0.0.0.0:5000`.
- **Apache Proxy**: Forwards requests from `/saturn/` to Gunicorn, enforcing basic auth and IP restrictions (local subnet, 127.0.0.1, ::1).
- **index.html**: Provides the UI with JavaScript to fetch scripts, themes, and execute scripts via AJAX (fetch to `./get_scripts`, `./run`, etc.).
- **config.json**: Lists scripts with metadata (filename, name, description, directory, category, flags).
- **themes.json**: Defines UI themes with CSS variables (e.g., `--bg-color`).

#### Workflow
1. **Startup**:
   - Gunicorn starts `saturn_update_manager.py` as `pi` user.
   - The `SaturnUpdateManager` class initializes, loading `config.json` and `themes.json` from `~/.saturn/`.
   - It validates the virtual environment (`~/venv/`) and required packages (e.g., `flask`, `ansi2html==1.9.2`).

2. **User Access**:
   - User opens `http://localhost/saturn/` or `http://<IP>/saturn/` (e.g., `192.168.0.225`).
   - Apache prompts for credentials (`admin:password123`).
   - The Flask app serves `index.html` via the `/` route.

3. **UI Interaction**:
   - JavaScript in `index.html` fetches:
     - `./get_scripts`: Populates the script dropdown from `config.json`.
     - `./get_themes`: Populates the theme dropdown from `themes.json`.
     - `./get_versions`: Displays script versions.
     - `./get_flags?script=<filename>`: Shows flags for the selected script.
     - `./get_backups?type=<pihpsdr|saturn>`: Lists backup directories for `restore-backup.sh`.
   - User selects a script, checks flags, and clicks "Run" to POST to `./run`.
   - The `/run` endpoint executes the script via `subprocess.Popen`, streaming output to the `<pre id="output">` element.
   - Backup prompts (`BACKUP_PROMPT`) trigger a modal for user input (`y`/`n`), sent to `./backup_response`.

4. **Script Execution**:
   - Scripts are run in the virtual environment (`~/venv/`) for Python scripts or as shell scripts (`bash`).
   - Output is processed by `ansi2html` for color formatting and streamed to the client.
   - Backup outputs (e.g., `Available pihpsdr backups: pihpsdr-backup-20250715-225810`) are formatted without literal `\n`.

5. **Logging**:
   - Gunicorn logs to `~/saturn-logs/saturn-update-manager-<timestamp>.log` (stdout) and `saturn-update-manager-error-<timestamp>.log` (stderr).
   - Apache logs to `/var/log/apache2/saturn_access.log` and `saturn_error.log`.

### Current Directory Structure
Below is the directory structure as of your latest interactions:

```
~/github/Saturn/
├── update_manager/
│   ├── install_update_manager.py  # Main installer script
│   ├── modules/
│   │   ├── apache_config.py       # Configures Apache virtual host
│   │   ├── dependencies.py        # Installs system dependencies
│   │   ├── logger.py              # Sets up logging
│   │   ├── os_detector.py         # Detects OS version (Bookworm/Buster)
│   │   ├── service_setup.py       # Configures systemd service
│   │   ├── venv_setup.py          # Sets up virtual environment
│   │   ├── __init__.py            # Makes modules a package
│   │   ├── __pycache__/           # Python cache files
│   ├── README.md                  # Project documentation
│   ├── scripts/
│   │   ├── saturn_update_manager.py  # Flask webapp (version 3.00)
│   │   ├── log_cleaner.sh         # Maintenance script (version 3.00)
│   │   ├── restore-backup.sh      # Restore script (version 3.00)
│   │   ├── config.json            # Default script configurations
│   │   ├── themes.json            # Default theme configurations
│   │   ├── update-G2.py           # Update script for Saturn G2
│   │   ├── update-pihpsdr.py      # Update script for piHPSDR
│   │   ├── SaturnUpdateManager.desktop  # Desktop shortcut
│   ├── templates/
│   │   ├── index.html             # Webapp UI template
│   │   ├── SaturnUpdateManager.desktop  # Desktop shortcut (duplicated)
~/.saturn/
│   ├── config.json                # Active script configurations
│   ├── themes.json                # Active theme configurations
│   ├── templates/
│   │   ├── index.html               # Active webapp UI template
│   ├── 20250728-193511-config.json  # Backup of config.json
│   ├── 20250728-193511-themes.json  # Backup of themes.json
~/saturn-logs/
│   ├── setup_saturn_webserver-<timestamp>.log       # Installer logs
│   ├── saturn-update-manager-<timestamp>.log        # Gunicorn stdout logs
│   ├── saturn-update-manager-error-<timestamp>.log  # Gunicorn stderr logs
│   ├── flask_*.log                                  # Endpoint verification logs
│   ├── auth_*.log                                   # Apache authentication logs
│   ├── pihpsdr-update-<timestamp>.log  # piHPSDR update logs
│   ├── saturn-update-<timestamp>.log   # Saturn update logs
│   ├── log_cleaner-<timestamp>.log     # Log cleaner script logs
│   ├── restore-backup-<timestamp>.log  # Restore backup script logs
~/venv/
│   ├── bin/                       # Virtual env binaries (activate, flask, gunicorn, etc.)
│   ├── lib/                       # Installed packages (flask, ansi2html, etc.)
│   ├── include/
│   ├── lib64/                     # Symlink to lib/
│   ├── pyvenv.cfg                 # Virtual env config
/etc/apache2/
│   ├── .htpasswd                  # Basic auth credentials (admin:password123)
│   ├── sites-available/
│   │   ├── saturn.conf            # Virtual host config for /saturn/
│   ├── sites-enabled/
│   │   ├── saturn.conf            # Symlink to sites-available/saturn.conf
│   ├── conf-available/
│   │   ├── servername.conf        # ServerName localhost
│   ├── apache2.conf
│   ├── envvars
│   ├── mods-available/
│   ├── mods-enabled/
│   ├── ports.conf
/etc/systemd/system/
│   ├── saturn-update-manager.service  # Systemd service for Gunicorn
~/Desktop/
│   ├── SaturnUpdateManager.desktop    # Shortcut to open http://localhost/saturn/
~/
│   ├── pihpsdr-backup-20250715-225810/  # Example backup directory
│   ├── saturn-backup-20250715-225656/   # Example backup directory
```

### Modular Design Overview
The system is designed with modularity to separate concerns, making it easier to maintain and extend:

1. **install_update_manager.py**:
   - **Purpose**: Orchestrates the installation process.
   - **Components**:
     - `run()`: Main installation flow (OS detection, dependencies, venv, Apache, files, systemd, validation).
     - `copy_files()`: Copies/overwrites config files and templates, backs up JSON files.
     - `get_eth0_ip()`: Detects local IP for access instructions.
     - `validate()`: Checks Apache, Gunicorn, and endpoint status.
   - **Dependencies**: Imports modules for specific tasks.

2. **Modules** (in `~/github/Saturn/update_manager/modules/`):
   - **`apache_config.py`**: Configures Apache virtual host, proxy, and basic auth.
   - **`dependencies.py`**: Installs system dependencies (e.g., `apt-get install python3 apache2`).
   - **`logger.py`**: Sets up logging to `~/saturn-logs/`.
   - **`os_detector.py`**: Detects OS (Bookworm/Buster) for package compatibility.
   - **`service_setup.py`**: Creates and enables the `saturn-update-manager.service`.
   - **`venv_setup.py`**: Manages virtual environment creation and package installation.
   - **`__init__.py`**: Makes `modules/` a Python package.

3. **saturn_update_manager.py**:
   - **Purpose**: Runs the Flask webapp.
   - **Components**:
     - `SaturnUpdateManager` class: Manages script execution, config/themes loading, and validation.
     - Routes: `/` (serves `index.html`), `/get_scripts`, `/get_themes`, `/run`, etc.
     - `run_script()`: Executes scripts, streams output with `ansi2html` formatting.
     - `get_backups()`: Lists backup directories.
   - **Dependencies**: `flask`, `ansi2html`, `subprocess`, etc.

4. **Scripts** (in `~/github/Saturn/update_manager/scripts/`):
   - `update-G2.py`, `update-pihpsdr.py`: Python scripts for updating specific software.
   - `log_cleaner.sh`: Shell script to manage log files.
   - `restore-backup.sh`: Shell script to restore from backups.
   - `config.json`, `themes.json`: Configuration files (copied to `~/.saturn/`).

5. **Templates** (in `~/github/Saturn/update_manager/templates/` and `~/.saturn/templates/`):
   - `index.html`: Webapp UI with JavaScript for dynamic content.
   - `SaturnUpdateManager.desktop`: Desktop shortcut for browser access.

### Adding a Custom Script
To add a custom script to the Saturn Update Manager, it must be executable, located in a trusted directory (e.g., `~/github/` or `~`), and listed in `config.json`.

#### Steps
1. **Create or Place the Script**:
   - Example: Create `my-custom-script.py` in `~/github/Saturn/update_manager/scripts/`:
     ```python
     #!/usr/bin/env python3
     # my-custom-script.py
     # Version: 1.0
     print("Running custom script...")
     ```
   - Make it executable:
     ```bash
     chmod +x ~/github/Saturn/update_manager/scripts/my-custom-script.py
     ```

2. **Update config.json**:
   - Edit `~/.saturn/config.json` (or `~/github/Saturn/update_manager/scripts/config.json` for the source, then re-run installer):
     ```json
     [
       {
         "filename": "my-custom-script.py",
         "name": "Custom Script",
         "description": "Runs a custom update or task",
         "directory": "~/github/Saturn/update_manager/scripts",
         "category": "Custom",
         "flags": ["--verbose", "--dry-run"]
       },
       ...
     ]
     ```
   - Ensure the `directory` is correct and in a trusted path (`~/github/` or `~`).

3. **Re-run Installer (Optional)**:
   - If you edited the source `config.json`, re-run:
     ```bash
     sudo python3 ~/github/Saturn/update_manager/install_update_manager.py
     ```
     This backs up the existing `~/.saturn/config.json` and overwrites it.

4. **Restart the Service**:
   ```bash
   sudo systemctl restart saturn-update-manager
   ```

5. **Test in Webapp**:
   - Reload `http://localhost/saturn/`.
   - Verify the script appears in the dropdown under the "Custom" category.
   - Select and run it to confirm execution.

#### Notes
- Scripts must be executable (`chmod +x`) and have a shebang (e.g., `#!/usr/bin/env python3` or `#!/bin/bash`).
- The `directory` must be in `trusted_dirs` (defined in `saturn_update_manager.py`).
- Flags should match the script’s supported options.

### Troubleshooting
Here are common issues and steps to diagnose/fix them:

#### 1. Webapp Not Loading (Access Denied)
- **Symptoms**: "Access denied" or 403/401 errors on `http://localhost/saturn/`.
- **Check**:
  - Apache logs: `cat /var/log/apache2/saturn_error.log`
    - Look for `AH01630: client denied by server configuration` (IP restriction) or `AH01797: client denied by server authentication` (auth issue).
  - Verify `/etc/hosts` has `127.0.0.1 localhost` and `::1 localhost`.
  - Check Apache config: `cat /etc/apache2/sites-available/saturn.conf`
- **Fix**:
  - Ensure `Require ip 127.0.0.1 ::1 <subnet>` includes the local subnet.
  - Test auth: `curl -u admin:password123 http://localhost/saturn/`
  - Clear browser cache or use incognito mode.

#### 2. Scripts Not Appearing
- **Symptoms**: Script dropdown is empty or shows "Error: No scripts available".
- **Check**:
  - Gunicorn logs: `cat ~/saturn-logs/saturn-update-manager-*.log`
    - Look for `Loaded X valid scripts` or `Config error`.
  - Validate `~/.saturn/config.json`:
    ```bash
    cat ~/.saturn/config.json
    python3 -m json.tool ~/.saturn/config.json
    ```
  - Check script permissions: `ls -l ~/github/Saturn/update_manager/scripts/`
    - Scripts must be executable (`-rwxr-xr-x`).
- **Fix**:
  - Remove comments from `config.json` (e.g., `//`).
  - Ensure `directory` paths are correct and in `trusted_dirs`.
  - Re-run installer or restart service: `sudo systemctl restart saturn-update-manager`.

#### 3. Literal `\n` in Output
- **Symptoms**: Output shows `\n` (e.g., `No *.log files found in /home/pi.\nCompleted...`).
- **Check**:
  - Verify `index.html` uses `<br>` for line breaks:
    ```bash
    grep "output.innerHTML" ~/.saturn/templates/index.html
    ```
  - Check `saturn_update_manager.py` for correct output handling:
    ```bash
    grep "join.*br" ~/github/Saturn/update_manager/scripts/saturn_update_manager.py
    ```
- **Fix**:
  - Update `index.html` to use `output.innerHTML += data + '<br>'`.
  - Ensure `saturn_update_manager.py` joins output with `<br>` (as in the latest version provided).

#### 4. Apache Config Test Failure
- **Symptoms**: `[ERROR] Apache config test - FAIL` during install, but Apache starts.
- **Check**:
  - Run: `sudo apache2ctl configtest`
  - Check logs: `cat /var/log/apache2/error.log`
  - Inspect: `cat /etc/apache2/sites-available/saturn.conf`
- **Fix**:
  - Look for syntax errors (e.g., missing directives, typos).
  - Remove conflicting virtual hosts:
    ```bash
    sudo rm /etc/apache2/sites-enabled/*.conf
    sudo ln -sf /etc/apache2/sites-available/saturn.conf /etc/apache2/sites-enabled/
    sudo systemctl restart apache2
    ```

#### 5. Gunicorn Service Failing
- **Symptoms**: `sudo systemctl status saturn-update-manager` shows `Failed with result 'exit-code'`.
- **Check**:
  - Logs: `cat ~/saturn-logs/saturn-update-manager-error-*.log`
  - Journal: `sudo journalctl -u saturn-update-manager -e`
  - Test manually:
    ```bash
    . ~/venv/bin/activate
    python3 ~/github/Saturn/update_manager/scripts/saturn_update_manager.py
    ```
- **Fix**:
  - Check for import errors or missing dependencies.
  - Ensure `~/venv/` is owned by `pi`: `sudo chown -R pi:pi ~/venv`
  - Verify `saturn_update_manager.py` syntax: `python3 -m py_compile ~/github/Saturn/update_manager/scripts/saturn_update_manager.py`

#### 6. Duplicated Output
- **Symptoms**: Script output appears multiple times (e.g., `No *.log files found...` twice).
- **Check**:
  - Script content: `cat ~/github/Saturn/update_manager/scripts/log_cleaner.sh`
  - Gunicorn logs: `cat ~/saturn-logs/saturn-update-manager-*.log`
- **Fix**:
  - Update `index.html` to clear output before each run (`output.innerHTML = ''`).
  - Check script for duplicate `echo` statements.

#### 7. Browser Issues
- **Symptoms**: Browser shows errors or fails to load resources.
- **Check**:
  - Browser console (F12) for JS errors.
  - Network tab for failed fetches (e.g., 403, 404).
- **Fix**:
  - Clear cache (Ctrl+Shift+R) or use incognito mode.
  - Ensure `index.html` uses relative fetches (`./get_scripts`).
  - Verify Apache proxy settings in `saturn.conf`.

### Additional Considerations
- **Portability**: The system uses dynamic subnet detection (`ip a show`) to allow access from the local network, making it portable across different IP configurations. The `localhost` fix ensures the desktop shortcut works universally.
- **Security**:
  - Basic auth uses a hardcoded `admin:password123` in `.htpasswd`. Consider changing the password via the webapp’s "Change Password" feature or updating `apache_config.py` for stronger defaults.
  - The `Require ip` directive restricts access to the local subnet and loopback. Adjust `apache_config.py` if broader access is needed (e.g., `Require all granted` with caution).
- **Backup Management**: JSON files are backed up with timestamps during install. Monitor `~/.saturn/` for old backups to avoid clutter.
- **Logging**: Logs in `~/saturn-logs/` can grow large. Use `log_cleaner.sh` to manage them.
- **Extensibility**: Add new scripts or themes by updating `config.json` or `themes.json`. Ensure scripts are executable and follow the expected format.

### Example: Adding a Theme
To add a new theme:
- Edit `~/.saturn/themes.json`:
  ```json
  [
    {
      "name": "Dark",
      "description": "Dark theme",
      "styles": {
        "--bg-color": "#1a1a1a",
        "--text-color": "#ffffff",
        "--primary-color": "#4b9bff",
        "--secondary-color": "#34d399",
        "--card-bg": "#2d2d2d"
      }
    },
    ...
  ]
  ```
- Restart: `sudo systemctl restart saturn-update-manager`
- Verify the theme appears in the dropdown.

### Monitoring and Maintenance
- **Check Service Status**:
  ```bash
  sudo systemctl status saturn-update-manager
  sudo systemctl status apache2
  ```
- **Clean Logs**:
  ```bash
  bash ~/github/Saturn/update_manager/scripts/log_cleaner.sh --dry-run
  ```
- **Backup System**:
  - Use `restore-backup.sh` to restore from backups.
  - Monitor `~/pihpsdr-backup-*` and `~/saturn-backup-*`.

This documentation covers the system’s operation, configuration, and troubleshooting, ensuring other users can maintain and extend the Saturn Update Manager effectively. 
If you encounter specific issues or need further clarification, provide relevant logs or error messages for targeted assistance.

Author: Jerry DeLong KD4YAL Last Updated: July 28, 2025
