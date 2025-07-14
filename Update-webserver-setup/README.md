# Saturn Update Manager Web Server Setup

## Overview
The Saturn Update Manager is a web-based GUI designed to manage and execute update scripts (e.g., update-G2.py, update-pihpsdr.py, and maintenance tools like log_cleaner.sh and restore-backup.sh) for the Saturn project on a Raspberry Pi running Bookworm or Buster. The setup is modularized into multiple Bash scripts located in ~/github/Saturn/Update-webserver-setup, providing a robust and maintainable way to configure a Flask-based web server with Gunicorn and an Apache reverse proxy. The system includes password protection, subnet restrictions, enhanced output streaming for script execution, custom themes for UI personalization, and systemd integration for auto-restart and boot persistence. For Buster support, specific dependency and startup scripts are used to ensure compatibility with Python 3.7.

## Key Features
- **Web Interface**: Accessible via a browser at http://<private_ip>/saturn/ with credentials (admin:password123 by default).
- **Script Execution**: Runs scripts defined in config.json (e.g., update-G2.py version 2.7, update-pihpsdr.py version 1.10, log_cleaner.sh, restore-backup.sh) with configurable flags.
- **Custom Themes**: Load and apply themes from themes.json via a dropdown selector, using CSS variables for dynamic styling (e.g., colors for background, text, buttons, and card backgrounds for better visibility in dark mode).
- **Modular Setup**: Split into scripts for easier maintenance:
  - setup_saturn_webserver.sh (version 2.69): Main orchestration script, detects OS and calls Buster-specific scripts if needed; sets up systemd service.
  - install_deps.sh (version 1.1): Installs dependencies for Bookworm, including gevent for async workers.
  - install_deps_buster.sh (version 1.0): Installs Buster-compatible dependencies (e.g., Flask 3.1.1, ansi2html 1.9.2, psutil 7.0.0, gevent).
  - configure_apache.sh (version 1.3): Configures Apache proxy with increased timeouts (3600s) and chunked transfer for reliable SSE streaming.
  - create_files.sh (version 1.6): Creates index.html, saturn_update_manager.py (version 2.22), themes.json, and desktop shortcut; backs up existing config.json if present.
  - start_server.sh (version 1.8): Starts and verifies Flask server for Bookworm with 5 gevent workers.
  - start_server_buster.sh (version 1.7): Starts and verifies Flask server for Buster with 5 gevent workers and robust port freeing.
- **Error Handling**: Fixes tput errors in update scripts by setting TERM=dumb for non-interactive environments, ensuring banners display correctly; custom Flask error handlers for user-friendly messages; rotating logs for Gunicorn.
- **Security**: Enforces Apache authentication and subnet restrictions.
- **Forced Logoff**: The "Exit" button terminates the server and prompts re-authentication.
- **Output Streaming**: Streams script output in batches of up to 10 lines, displayed in a <pre> element with a max-height of 500px; heartbeats prevent timeouts.
- **Version Display**: Optionally shows script versions in the web interface via a "Show Versions" checkbox (default off), toggled next to the Exit button; fetched from /saturn/get_versions endpoint.
- **Theme Persistence**: Selected theme saved in browser localStorage for reloads.
- **Restore Backup**: Supports restoring from Saturn or piHPSDR backups with directory selection in the UI.
- **Removed Features**: --show-compile merged into --verbose for update-pihpsdr.py; script search input removed.
- **Systemd Integration**: Auto-starts on boot and restarts on failure with Restart=always.

## Prerequisites
- **Operating System**: Raspberry Pi OS Bookworm (64-bit) or Buster (32-bit).
- **Hardware**: Raspberry Pi with network connectivity.
- **Dependencies**: python3, python3-pip, lsof, apache2, apache2-utils, python3-gunicorn; gevent for async.
- **Scripts**: update-G2.py (version 2.7), update-pihpsdr.py (version 1.10), and others in ~/scripts.
- **User**: Commands must be run as the pi user with sudo privileges.

## Directory Structure
```
~/github/Saturn/
├── Update-webserver-setup/
│   ├── setup_saturn_webserver.sh  # Main setup script
│   ├── install_deps.sh            # Installs dependencies for Bookworm
│   ├── install_deps_buster.sh     # Installs dependencies for Buster
│   ├── configure_apache.sh        # Configures Apache proxy
│   ├── create_files.sh            # Creates web app files
│   ├── start_server.sh            # Starts and verifies Flask server for Bookworm
│   ├── start_server_buster.sh     # Starts and verifies Flask server for Buster
├── scripts/
│   ├── update-G2.py               # Update script (version 2.7)
│   ├── update-pihpsdr.py          # Update script (version 1.10)
~/scripts/
│   ├── saturn_update_manager.py   # Flask app (version 2.22)
│   ├── templates/
│   │   ├── index.html             # Web interface
│   ├── config.json                # Script configurations
│   ├── themes.json                # Theme configurations
│   ├── log_cleaner.sh             # Maintenance script
│   ├── restore-backup.sh          # Restore script
│   ├── SaturnUpdateManager.desktop  # Desktop shortcut
~/saturn-logs/
│   ├── setup_saturn_webserver-.log  # Setup logs
│   ├── saturn-update-manager-.log   # Gunicorn stdout logs
│   ├── saturn-update-manager-error-.log  # Gunicorn stderr logs
│   ├── flask_.log                  # Endpoint verification logs
│   ├── auth_*.log                   # Apache authentication logs
```
## Installation
1. **Clone or Create Repository**:
   - Ensure the scripts are in ~/github/Saturn/Update-webserver-setup.
   - If not present, create the directory and copy the scripts:

mkdir -p ~/github/Saturn/Update-webserver-setup
2. **Set Permissions**:
- Make all scripts executable:

chmod +x ~/github/Saturn/Update-webserver-setup/*.sh

3. **Run the Setup Script**:
- Execute the main setup script as root:

sudo bash ~/github/Saturn/Update-webserver-setup/setup_saturn_webserver.sh
- This script detects the OS from /etc/os-release and runs:
- install_deps.sh or install_deps_buster.sh: Installs system packages and Python dependencies in a virtual environment (~/venv), including gevent.
- configure_apache.sh: Sets up Apache as a reverse proxy with password protection, subnet restrictions, and streaming optimizations.
- create_files.sh: Creates index.html, saturn_update_manager.py (version 2.22), themes.json, and a desktop shortcut; backs up existing config.json if present.
- start_server.sh or start_server_buster.sh: Starts the Flask server with Gunicorn (5 gevent workers) and verifies endpoints.
- Sets up a systemd service for auto-boot/restart.

4. **Verify Setup**:
- Check the log file for success:
cat ~/saturn-logs/setup_saturn_webserver-*.log

- Look for the final message: Setup completed at <date>. Log: <log_file>.
- Note the LAN access command: curl -u admin:password123 http://<private_ip>/saturn/.

## Usage
1. **Access the Web Interface**:
- Open a browser and navigate to http://<private_ip>/saturn/ (e.g., http://192.168.0.139/saturn/).
- Log in with credentials admin:password123 (default).

2. **Interface Features**:
- **Script Versions**: Optionally displays versions of saturn_update_manager.py (2.22), update-G2.py (2.7), update-pihpsdr.py (1.10), and others via a "Show Versions" checkbox (default off).
- **Script Selection**: Choose a script from a dropdown (grouped by category, e.g., "Update Scripts" or "Maintenance").
- **Flags**: Select flags (e.g., --verbose pre-checked; others vary by script).
- **Run Button**: Executes the selected script with chosen flags, streaming output to a black-background <pre> element (max-height 500px).
- **Change Password**: Updates the Apache authentication password (minimum 8 characters).
- **Exit Button**: Terminates the server and forces re-authentication.
- **Theme Selection**: Choose a theme from the "Select Theme" dropdown; applies CSS variables dynamically and persists via localStorage.
- **Backup Prompt**: Appears if -y or -n flags are not selected, asking "Create a backup? (Y/n)".
- **Restore Backup**: For restore-backup.sh, select --pihpsdr or --saturn and a backup directory from the dropdown.

3. **Customizing Themes**:
- Edit ~/scripts/themes.json to add/modify themes (restart server to reload).
- Select a theme in the UI to apply it instantly (e.g., "Dark Mode" changes colors, with --card-bg for panel backgrounds).

4. **Testing Script Execution**:
- Select a script and run it with --verbose to verify banners appear in the output.
- Check that output streams in batches (up to 10 lines) and displays correctly.

5. **Testing Exit Functionality**:
- Click "Exit" and confirm the browser prompts for re-authentication (401 Unauthorized).

## Troubleshooting
### Common Issues and Solutions
- **Error: ModuleNotFoundError: No module named 'saturn_update_manager'**
- **Cause**: Gunicorn cannot find saturn_update_manager.py.
- **Solution**:
- Verify the file exists: `ls -l ~/scripts/saturn_update_manager.py`.
- Re-run create_files.sh to recreate it: `sudo bash ~/github/Saturn/Update-webserver-setup/create_files.sh`.
- Check PYTHONPATH in start_server.sh includes ~/scripts.

- **Error: Failed to obtain valid SERVER_PID for Flask server**
- **Cause**: Gunicorn failed to start or write the PID file.
- **Solution**:
- Check Gunicorn logs: `cat ~/saturn-logs/saturn-update-manager-*.log` and `cat ~/saturn-logs/saturn-update-manager-error-*.log`.
- Ensure the virtual environment is set up: `. ~/venv/bin/activate && which gunicorn`.
- Increase the sleep delay in start_server.sh (e.g., from 10 to 15 seconds).

- **Error: Flask /saturn/get_versions endpoint failed - expected versions not found**
- **Cause**: Version mismatch between start_server.sh and saturn_update_manager.py.
- **Solution**:
- Check the version in saturn_update_manager.py: `grep "Version:" ~/scripts/saturn_update_manager.py`.
- Update start_server.sh to match (currently expects 2.22) or re-run create_files.sh to set version 2.22: `sudo bash ~/github/Saturn/Update-webserver-setup/create_files.sh`.
- Edit start_server.sh to expect version 2.22 if updated: `sed -i 's/"saturn_update_manager.py":"2.19"/"saturn_update_manager.py":"2.22"/' ~/github/Saturn/Update-webserver-setup/start_server.sh`.

- **Error: tput: No value for $TERM and no -T specified in Web Output**
- **Cause**: Update scripts use tput in a non-interactive environment.
- **Solution**: The fix is already implemented in saturn_update_manager.py (sets TERM=dumb). Verify by running a script with --verbose and checking for banners.

- **Apache Authentication Fails (HTTP 401 or 403)**
- **Cause**: Incorrect .htpasswd file or subnet configuration.
- **Solution**:
- Check Apache logs: `cat /var/log/apache2/saturn_error.log`.
- Re-run configure_apache.sh: `sudo bash ~/github/Saturn/Update-webserver-setup/configure_apache.sh`.
- Verify .htpasswd: `cat /etc/apache2/.htpasswd`.

- **Web Interface Not Loading**:
- **Cause**: Apache or Gunicorn not running, or network issues.
- **Solution**:
- Check Apache status: `sudo systemctl status apache2`.
- Check Gunicorn process: `ps aux | grep gunicorn`.
- Verify port 5000: `netstat -tuln | grep 5000`.
- Restart the server: `sudo bash ~/github/Saturn/Update-webserver-setup/start_server.sh`.

- **Theme Dropdown Not Showing or Not Working**:
- **Cause**: Themes not loaded (invalid themes.json) or JS fetch error.
- **Solution**:
- Check server logs for theme warnings: `cat ~/saturn-logs/saturn-update-manager-*.log | grep themes`.
- Validate themes.json: `python3 -c "import json; json.load(open('/home/pi/scripts/themes.json'))"`.
- Ensure loadThemes() is called in index.html's script.
- Clear browser cache/localStorage and reload.

- **Script Flags Not Visible in Dark Mode**:
- **Cause**: Insufficient contrast in dark theme.
- **Solution**: The --card-bg variable in themes.json has been updated for Dark Mode to #333333 for better visibility. Re-apply the theme or restart the server.

- **Streaming Stops Prematurely**:
- **Cause**: Proxy timeouts or buffering.
- **Solution**: The fix is in configure_apache.sh (timeouts 3600s, chunked transfer). Re-run and restart Apache: `sudo bash configure_apache.sh && sudo systemctl restart apache2`.

## Log Files
- Setup Logs: ~/saturn-logs/setup_saturn_webserver-*.log
- Gunicorn Logs: ~/saturn-logs/saturn-update-manager-*.log (stdout), ~/saturn-logs/saturn-update-manager-error-*.log (stderr)
- Endpoint Logs: ~/saturn-logs/flask_*.log, ~/saturn-logs/auth_*.log
- Apache Logs: /var/log/apache2/saturn_error.log, /var/log/apache2/saturn_access.log

## Additional Notes
- **Version Consistency**: If saturn_update_manager.py is version 2.22 but other scripts expect older versions, re-run create_files.sh to update.
- **Config Backup**: Existing config.json is backed up (e.g., config.json.bak.<timestamp>) before overwriting.
- **Network Issues**: Ensure the Raspberry Pi has a valid IP (e.g., 192.168.0.139) and is on the same subnet as the client.
- **Backup Prompt**: If the backup prompt does not appear, ensure -y or -n flags are not selected when running scripts.
- **Buster Compatibility**: On Buster, uses Flask 3.1.1, ansi2html 1.9.2, and psutil 7.0.0 for Python 3.7 compatibility; gevent added for async.

## Support
For further assistance, check the logs and share relevant outputs with your query. Ensure all scripts are in ~/github/Saturn/Update-webserver-setup and have correct permissions (chmod +x).

Author: Jerry DeLong KD4YAL
Last Updated: July 13, 2025
