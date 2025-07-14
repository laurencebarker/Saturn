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
