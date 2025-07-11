#!/bin/bash
# create_files.sh - Creates index.html, saturn_update_manager.py, and SaturnUpdateManager.desktop
# Version: 1.0
# Written by: Jerry DeLong KD4YAL
# Dependencies: bash
# Usage: Called by setup_saturn_webserver.sh

set -e

# Paths
SCRIPTS_DIR="/home/pi/github/Saturn/scripts"
TEMPLATES_DIR="$SCRIPTS_DIR/templates"
LOG_DIR="/home/pi/saturn-logs"
DESKTOP_FILE="$SCRIPTS_DIR/SaturnUpdateManager.desktop"
DESKTOP_DEST="/home/pi/Desktop/SaturnUpdateManager.desktop"
SATURN_SCRIPT="$SCRIPTS_DIR/saturn_update_manager.py"
INDEX_HTML="$TEMPLATES_DIR/index.html"
LOG_FILE="$LOG_DIR/setup_saturn_webserver-$(date +%Y%m%d-%H%M%S).log"
VENV_PATH="/home/pi/venv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to log and echo output
log_and_echo() {
    echo -e "$1" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Create directories
log_and_echo "${CYAN}Creating directories...${NC}"
mkdir -p "$SCRIPTS_DIR" "$TEMPLATES_DIR" "$LOG_DIR"
chmod -R u+rwX "$SCRIPTS_DIR" "$TEMPLATES_DIR" "$LOG_DIR"
chown pi:pi "$LOG_DIR" "$TEMPLATES_DIR"
chmod 775 "$LOG_DIR"
log_and_echo "${GREEN}Directories created${NC}"

# Create index.html
log_and_echo "${CYAN}Creating index.html in $TEMPLATES_DIR (overwriting if exists)...${NC}"
rm -f "$INDEX_HTML"
cat > "$INDEX_HTML" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Saturn Update Manager</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        pre {
            white-space: pre-wrap;
            word-wrap: break-word;
            font-family: 'Courier New', monospace;
            background-color: #1a1a1a;
            color: #ffffff;
            padding: 1rem;
            overflow-y: auto;
            min-height: 400px;
            max-height: 500px;
            line-height: 1.4;
            margin: 0;
            border: 1px solid #444;
            box-sizing: border-box;
        }
        .output-container {
            width: 100%;
            min-height: 420px;
            background-color: #1a1a1a;
            padding: 0;
            border-radius: 0.5rem;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #f3f4f6; }
        .container { max-width: 800px; }
        .ansi_31 { color: #ff5555 !important; }
        .ansi_32 { color: #55ff55 !important; }
        .ansi_33 { color: #ffff55 !important; }
        .ansi_34 { color: #5555ff !important; }
        .ansi_36 { color: #55ffff !important; }
    </style>
</head>
<body class="bg-gray-100">
    <div class="container mx-auto p-4">
        <h1 class="text-3xl font-bold text-red-600 text-center mb-2">Saturn Update Manager</h1>
        <p class="text-lg text-gray-600 text-center mb-4">Build Version: 2.65 (Setup Script)</p>
        
        <div class="bg-white rounded-lg shadow-md p-4 mb-4">
            <h2 class="text-xl font-semibold text-gray-700 mb-2">Script Versions</h2>
            <ul id="version-list" class="list-disc pl-5 text-gray-600"></ul>
        </div>

        <div class="bg-white rounded-lg shadow-md p-4 mb-4">
            <form id="script-form" class="flex flex-col space-y-4">
                <div class="flex items-center space-x-4">
                    <label for="script" class="text-lg font-medium text-gray-700">Select Script:</label>
                    <select id="script" name="script" class="border rounded px-2 py-1 bg-blue-100 text-blue-800">
                        <option value="">Select a script</option>
                    </select>
                </div>
                <div id="flags" class="flex flex-wrap gap-4"></div>
                <div class="flex justify-center space-x-4">
                    <button type="submit" class="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600">Run</button>
                    <button type="button" id="change-password-btn" class="bg-green-500 text-white px-4 py-2 rounded hover:bg-green-600">Change Password</button>
                    <button type="button" id="exit-btn" class="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600">Exit</button>
                </div>
            </form>
        </div>

        <div class="output-container">
            <pre id="output" class="text-sm"></pre>
        </div>

        <!-- Backup Prompt Modal -->
        <div id="backup-modal" class="hidden fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center">
            <div class="bg-white rounded-lg p-6 max-w-sm w-full">
                <h2 class="text-xl font-bold mb-4">Backup Prompt</h2>
                <p class="mb-4">Create a backup? (Y/n)</p>
                <div class="flex justify-end space-x-4">
                    <button id="backup-yes" class="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600">Yes</button>
                    <button id="backup-no" class="bg-gray-500 text-white px-4 py-2 rounded hover:bg-gray-600">No</button>
                </div>
            </div>
        </div>

        <!-- Change Password Modal -->
        <div id="password-modal" class="hidden fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center">
            <div class="bg-white rounded-lg p-6 max-w-sm w-full">
                <h2 class="text-xl font-bold mb-4">Change Password</h2>
                <form id="password-form" class="flex flex-col space-y-4">
                    <div>
                        <label for="new-password" class="text-lg font-medium text-gray-700">New Password:</label>
                        <input type="password" id="new-password" name="new-password" class="border rounded px-2 py-1 w-full" required minlength="8">
                    </div>
                    <div>
                        <label for="confirm-password" class="text-lg font-medium text-gray-700">Confirm Password:</label>
                        <input type="password" id="confirm-password" name="confirm-password" class="border rounded px-2 py-1 w-full" required minlength="8">
                    </div>
                    <p id="password-error" class="text-red-500 hidden">Passwords do not match or are too short.</p>
                    <div class="flex justify-end space-x-4">
                        <button type="submit" class="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600">Submit</button>
                        <button type="button" id="password-cancel" class="bg-gray-500 text-white px-4 py-2 rounded hover:bg-gray-600">Cancel</button>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <script>
        async function loadVersions() {
            console.log('Attempting to load script versions from /saturn/get_versions');
            try {
                const response = await fetch('/saturn/get_versions', {
                    headers: {
                        'Cache-Control': 'no-cache'
                    }
                });
                if (!response.ok) {
                    const errorText = await response.text();
                    console.error('Fetch versions failed:', response.status, errorText);
                    throw new Error(`HTTP ${response.status}: ${errorText}`);
                }
                const data = await response.json();
                console.log('Versions response:', data);
                const versionList = document.getElementById('version-list');
                versionList.innerHTML = '';
                if (data.versions) {
                    Object.entries(data.versions).forEach(([script, version]) => {
                        const li = document.createElement('li');
                        li.textContent = `${script}: ${version}`;
                        versionList.appendChild(li);
                    });
                } else {
                    console.warn('No versions returned from /saturn/get_versions');
                    document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error: No versions available</span>\n`;
                }
            } catch (error) {
                console.error('Error loading versions:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error loading versions: ${error.message}</span>\n`;
            }
        }

        async function loadFlags(script) {
            console.log('Attempting to load flags for:', script);
            try {
                const response = await fetch(`/saturn/get_flags?script=${encodeURIComponent(script)}`, {
                    headers: {
                        'Cache-Control': 'no-cache'
                    }
                });
                if (!response.ok) {
                    const errorText = await response.text();
                    console.error('Fetch flags failed:', response.status, errorText);
                    throw new Error(`HTTP ${response.status}: ${errorText}`);
                }
                const data = await response.json();
                console.log('Flags response:', data);
                const flagsDiv = document.getElementById('flags');
                flagsDiv.innerHTML = '';
                if (data.error) {
                    console.error('Error from get_flags:', data.error);
                    document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error: ${data.error}</span>\n`;
                    return;
                }
                data.flags.forEach(flag => {
                    const label = document.createElement('label');
                    label.className = 'flex items-center space-x-2';
                    label.innerHTML = `<input type="checkbox" name="flags" value="${flag}" class="form-checkbox h-5 w-5 text-blue-600" ${flag === '--verbose' ? 'checked' : ''}> <span>${flag}</span>`;
                    flagsDiv.appendChild(label);
                });
                console.log(`Loaded flags for ${script}:`, data.flags);
            } catch (error) {
                console.error('Error loading flags:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error loading flags: ${error.message}</span>\n`;
            }
        }

        async function loadScripts() {
            console.log('Attempting to load scripts from /saturn/get_scripts');
            try {
                const response = await fetch('/saturn/get_scripts', {
                    headers: {
                        'Cache-Control': 'no-cache'
                    }
                });
                if (!response.ok) {
                    const errorText = await response.text();
                    console.error('Fetch scripts failed:', response.status, errorText);
                    throw new Error(`HTTP ${response.status}: ${errorText}`);
                }
                const data = await response.json();
                console.log('Scripts response:', data);
                const scriptSelect = document.getElementById('script');
                scriptSelect.innerHTML = '<option value="">Select a script</option>';
                if (data.scripts) {
                    data.scripts.forEach(script => {
                        const option = document.createElement('option');
                        option.value = script;
                        option.textContent = script;
                        scriptSelect.appendChild(option);
                    });
                    if (data.scripts.length > 0) {
                        console.log('Loading flags for first script:', data.scripts[0]);
                        loadFlags(data.scripts[0]);
                    }
                } else {
                    console.warn('No scripts returned from /saturn/get_scripts');
                    document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error: No scripts available</span>\n`;
                }
            } catch (error) {
                console.error('Error loading scripts:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error loading scripts: ${error.message}</span>\n`;
            }
        }

        document.getElementById('script-form').addEventListener('submit', async function(e) {
            e.preventDefault();
            const script = document.getElementById('script').value;
            const flags = Array.from(document.querySelectorAll('input[name="flags"]:checked')).map(cb => cb.value);
            const output = document.getElementById('output');
            output.innerHTML = '';
            console.log(`Submitting run request for ${script}, flags:`, flags);

            try {
                const formData = new FormData();
                formData.append('script', script);
                flags.forEach(flag => formData.append('flags', flag));
                const response = await fetch('/saturn/run', {
                    method: 'POST',
                    body: formData,
                    headers: {
                        'Accept': 'text/event-stream'
                    }
                });
                if (!response.ok) {
                    const errorText = await response.text();
                    console.error('Run request failed:', response.status, errorText);
                    throw new Error(`HTTP ${response.status}: ${errorText}`);
                }
                console.log('Run request sent successfully');
                const reader = response.body.getReader();
                const decoder = new TextDecoder();
                let buffer = '';
                while (true) {
                    const { done, value } = await reader.read();
                    if (done) {
                        console.log('Stream complete');
                        if (buffer) {
                            console.log('Processing buffered data:', buffer);
                            const lines = buffer.split('\n\n');
                            for (const line of lines) {
                                if (line.startsWith('data: ')) {
                                    const data = line.substring(6);
                                    console.log(`Received data: ${data}`);
                                    if (data === 'BACKUP_PROMPT') {
                                        console.log('Received BACKUP_PROMPT');
                                        document.getElementById('backup-modal').classList.remove('hidden');
                                    } else {
                                        output.innerHTML += data + '\n';
                                        console.log(`Appended HTML: ${data}`);
                                        output.scrollTop = output.scrollHeight;
                                        output.style.height = output.scrollHeight + 'px';
                                    }
                                }
                            }
                            buffer = '';
                        }
                        break;
                    }
                    const chunk = decoder.decode(value, { stream: true });
                    console.log('Received chunk:', chunk);
                    buffer += chunk;
                    const lines = buffer.split('\n\n');
                    buffer = lines.pop() || '';
                    for (const line of lines) {
                        if (line.startsWith('data: ')) {
                            const data = line.substring(6);
                            console.log(`Received data: ${data}`);
                            if (data === 'BACKUP_PROMPT') {
                                console.log('Received BACKUP_PROMPT');
                                document.getElementById('backup-modal').classList.remove('hidden');
                            } else {
                                output.innerHTML += data + '\n';
                                console.log(`Appended HTML: ${data}`);
                                output.scrollTop = output.scrollHeight;
                                output.style.height = output.scrollHeight + 'px';
                            }
                        }
                    }
                }
            } catch(error) {
                console.error('Run error:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error: ${error.message}</span>\n`;
            }
        });

        document.getElementById('script').addEventListener('change', function() {
            console.log('Script changed:', this.value);
            if (this.value) {
                loadFlags(this.value);
            }
        });

        document.getElementById('backup-yes').addEventListener('click', function() {
            console.log('Sending backup response: y');
            fetch('/saturn/backup_response', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: 'response=y'
            }).then(() => {
                console.log('Backup response sent: y');
                document.getElementById('backup-modal').classList.add('hidden');
            }).catch(error => {
                console.error('Backup yes error:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error sending backup response: ${error.message}</span>\n`;
            });
        });

        document.getElementById('backup-no').addEventListener('click', function() {
            console.log('Sending backup response: n');
            fetch('/saturn/backup_response', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: 'response=n'
            }).then(() => {
                console.log('Backup response sent: n');
                document.getElementById('backup-modal').classList.add('hidden');
            }).catch(error => {
                console.error('Backup no error:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error sending backup response: ${error.message}</span>\n`;
            });
        });

        document.getElementById('change-password-btn').addEventListener('click', function() {
            console.log('Opening password change modal');
            document.getElementById('password-modal').classList.remove('hidden');
            document.getElementById('new-password').value = '';
            document.getElementById('confirm-password').value = '';
            document.getElementById('password-error').classList.add('hidden');
        });

        document.getElementById('password-cancel').addEventListener('click', function() {
            console.log('Closing password change modal');
            document.getElementById('password-modal').classList.add('hidden');
        });

        document.getElementById('password-form').addEventListener('submit', async function(e) {
            e.preventDefault();
            const newPassword = document.getElementById('new-password').value;
            const confirmPassword = document.getElementById('confirm-password').value;
            const errorDiv = document.getElementById('password-error');
            if (newPassword !== confirmPassword || newPassword.length < 8) {
                console.error('Password validation failed');
                errorDiv.textContent = 'Passwords do not match or are too short (minimum 8 characters).';
                errorDiv.classList.remove('hidden');
                return;
            }
            try {
                const response = await fetch('/saturn/change_password', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: `new_password=${encodeURIComponent(newPassword)}`
                });
                const data = await response.json();
                if (response.ok && data.status === 'success') {
                    console.log('Password changed successfully');
                    document.getElementById('output').innerHTML += `<span style="color:#00FF00">Password changed successfully</span>\n`;
                    document.getElementById('password-modal').classList.add('hidden');
                } else {
                    throw new Error(data.message || `HTTP ${response.status}`);
                }
            } catch (error) {
                console.error('Error changing password:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error changing password: ${error.message}</span>\n`;
            }
        });

        document.getElementById('exit-btn').addEventListener('click', async function() {
            console.log('Initiating exit and logoff');
            try {
                const response = await fetch('/saturn/exit', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' }
                });
                if (!response.ok) {
                    const errorText = await response.text();
                    console.error('Exit request failed:', response.status, errorText);
                    document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error during exit: ${errorText}</span>\n`;
                    return;
                }
                const data = await response.json();
                console.log('Exit response:', data);
                if (data.status === 'shutting down') {
                    console.log('Server shutting down, forcing re-authentication');
                    // Force re-authentication by fetching a protected endpoint with invalid credentials
                    try {
                        await fetch('/saturn/', {
                            headers: {
                                'Authorization': 'Basic invalid_credentials',
                                'Cache-Control': 'no-cache'
                            }
                        });
                    } catch (error) {
                        console.log('Re-authentication triggered:', error);
                        // Redirect to /saturn/ to prompt login
                        window.location.href = '/saturn/';
                    }
                }
            } catch (error) {
                console.error('Exit error:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error during exit: ${error.message}</span>\n`;
            }
        });

        console.log('Loading initial scripts and versions');
        loadScripts();
        loadVersions();
    </script>
</body>
</html>
EOF
chmod -R u+rwX "$INDEX_HTML"
chown pi:pi "$INDEX_HTML"
log_and_echo "${GREEN}index.html created${NC}"
if ! grep -q "Saturn Update Manager" "$INDEX_HTML" || ! grep -q "script-form" "$INDEX_HTML" || ! grep -q "version-list" "$INDEX_HTML"; then
    log_and_echo "${RED}Error: Failed to create valid index.html${NC}"
    exit 1
fi
log_and_echo "${GREEN}Verified index.html content${NC}"

# Create saturn_update_manager.py
log_and_echo "${CYAN}Creating saturn_update_manager.py (overwriting if exists)...${NC}"
rm -f "$SATURN_SCRIPT"
cat > "$SATURN_SCRIPT" << 'EOF'
#!/usr/bin/env python3
# saturn_update_manager.py - Web-based Update Manager for update-G2.py and update-pihpsdr.py
# Runs from Raspberry Pi desktop, executing scripts within the GUI with a black background
# Version: 2.19
# Written by: Jerry DeLong KD4YAL, updated by Grok 3
# Dependencies: flask, ansi2html (1.9.2), subprocess, os, threading, logging, re, shutil, select, urllib.error
# Usage: . ~/venv/bin/activate; gunicorn -w 1 -b 0.0.0.0:5000 -t 600 saturn_update_manager:app

import logging
import os
from pathlib import Path
from datetime import datetime
import subprocess
import threading
import shlex
import re
import shutil
import signal
import sys
import time
import select
import urllib.error
from flask import Flask, render_template, request, Response, jsonify
from ansi2html import Ansi2HTMLConverter

# Initialize logging
log_dir = Path.home() / "saturn-logs"
log_dir.mkdir(parents=True, exist_ok=True)
os.chmod(log_dir, 0o775)
log_file = log_dir / f"saturn-update-manager-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.FileHandler(log_file)]
)
logging.info("Initializing Saturn Update Manager")

app = Flask(__name__, template_folder='/home/pi/github/Saturn/scripts/templates')
shutdown_event = threading.Event()

class SaturnUpdateManager:
    def __init__(self):
        logging.debug("Starting SaturnUpdateManager initialization")
        self.venv_path = Path.home() / "venv" / "bin" / "activate"
        self.scripts_dir = Path.home() / "github" / "Saturn" / "scripts"
        self.log_dir = Path.home() / "saturn-logs"
        self.scripts = {
            "update-G2.py": ["--skip-git", "-y", "-n", "--dry-run", "--verbose"],
            "update-pihpsdr.py": ["--skip-git", "-y", "--no-gpio", "--verbose"]
        }
        self.versions = {
            "saturn_update_manager.py": "2.19",
            "update-G2.py": "2.4",
            "update-pihpsdr.py": "1.7"
        }
        self.process = None
        self.backup_response = None
        self.running = False
        self.output_lock = threading.Lock()
        self.converter = Ansi2HTMLConverter(inline=True)
        logging.info(f"Starting Saturn Update Manager v2.19")

        error_message = self.validate_setup()
        if error_message:
            logging.error(f"Initialization failed: {error_message}")
            print(f"Error: {error_message}\nCheck log: {log_file}")
            sys.exit(1)

    def validate_setup(self):
        try:
            logging.debug("Validating setup...")
            logging.debug(f"Checking virtual environment at {self.venv_path}")
            if not self.venv_path.exists():
                logging.error(f"Virtual environment not found at {self.venv_path}")
                return f"Virtual environment not found at {self.venv_path}"
            for script in self.scripts:
                script_path = self.scripts_dir / script
                logging.debug(f"Checking script: {script_path}")
                if not script_path.exists():
                    logging.error(f"Script not found: {script_path}")
                    return f"Script not found: {script_path}"
                if not os.access(script_path, os.X_OK):
                    try:
                        os.chmod(script_path, 0o755)
                        logging.info(f"Set executable permissions for {script_path}")
                    except Exception as e:
                        logging.error(f"Cannot set executable permissions for {script_path}: {str(e)}")
                        return f"Cannot set executable permissions for {script_path}: {str(e)}"
            try:
                import flask
                import ansi2html
                import shutil
                import urllib.error
                logging.debug(f"ansi2html version: {ansi2html.__version__}")
                if ansi2html.__version__ != '1.9.2':
                    logging.error(f"Invalid ansi2html version: {ansi2html.__version__}. Requires 1.9.2")
                    return f"Invalid ansi2html version: {ansi2html.__version__}. Requires 1.9.2"
            except ImportError as e:
                logging.error(f"Missing dependency: {str(e)}. Install with: pip install flask ansi2html==1.9.2")
                return f"Missing dependency: {str(e)}. Install with: pip install flask ansi2html==1.9.2"
            python_version = subprocess.check_output(["python3", "--version"], stderr=subprocess.STDOUT).decode().strip()
            logging.info(f"Python version: {python_version}")
            if not python_version.startswith("Python 3"):
                logging.error(f"Incompatible Python version: {python_version}. Requires 3.x")
                return f"Incompatible Python version: {python_version}. Requires 3.x"
            logging.debug("Setup validation completed successfully")
            return None
        except Exception as e:
            logging.error(f"Setup validation failed: {str(e)}")
            return f"Setup validation failed: {str(e)}"

    def install_desktop_icons(self):
        logging.debug("Installing desktop icons...")
        desktop_dir = self.scripts_dir
        home_desktop = Path.home() / "Desktop"
        desktop_file = desktop_dir / "SaturnUpdateManager.desktop"
        dest_file = home_desktop / "SaturnUpdateManager.desktop"

        if not desktop_file.exists():
            logging.info(f"Creating desktop file: {desktop_file}")
            with desktop_file.open("w") as f:
                f.write(f"""[Desktop Entry]
Type=Application
Name=Saturn Update Manager
Comment=Web-based GUI to manage updates for update-G2.py and update-pihpsdr.py
Exec=xdg-open http://localhost/saturn/
Icon=system-software-update
Terminal=false
Categories=System;Utility;
""")
            try:
                os.chmod(desktop_file, 0o755)
                logging.info(f"Created desktop file: {desktop_file}")
            except Exception as e:
                logging.error(f"Failed to set permissions for {desktop_file}: {str(e)}")
                return False
        try:
            if not home_desktop.exists():
                logging.warning(f"Home Desktop directory does not exist: {home_desktop}")
                return False
            shutil.copy2(desktop_file, dest_file)
            os.chmod(dest_file, 0o755)
            logging.info(f"Installed desktop shortcut: {dest_file}")
            return True
        except Exception as e:
            logging.error(f"Shortcut install failed: {str(e)}")
            return False

    def change_password(self, new_password):
        logging.debug(f"Attempting to change password for user: admin")
        if len(new_password) < 8:
            logging.error("Password too short")
            return {"status": "error", "message": "Password must be at least 8 characters"}
        try:
            result = subprocess.run(
                ['sudo', '/usr/bin/htpasswd', '-b', '/etc/apache2/.htpasswd', 'admin', new_password],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                logging.info("Password changed successfully for user: admin")
                return {"status": "success", "message": "Password changed successfully"}
            else:
                logging.error(f"Failed to change password: {result.stderr}")
                return {"status": "error", "message": f"Failed to change password: {result.stderr}"}
        except Exception as e:
            logging.error(f"Error changing password: {str(e)}")
            return {"status": "error", "message": f"Error changing password: {str(e)}"}

    def run_script(self, script, flags):
        logging.debug(f"Running script: {script} with flags: {flags}")
        self.running = True
        self.process = None
        self.backup_response = None
        script_path = self.scripts_dir / script
        if not script_path.exists():
            logging.error(f"Script {script_path} does not exist")
            error_msg = f"Error: Script {script_path} does not exist\n"
            yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
            return
        cmd = f". {self.venv_path} && python3 {shlex.quote(str(script_path))} {' '.join(shlex.quote(flag) for flag in flags)} && deactivate"
        logging.info(f"Executing command: {cmd}")

        try:
            # Test script syntax
            test_cmd = f". {self.venv_path} && python3 -m py_compile {shlex.quote(str(script_path))}"
            logging.debug(f"Testing script syntax with: {test_cmd}")
            test_result = subprocess.run(test_cmd, shell=True, capture_output=True, text=True, timeout=10)
            if test_result.returncode != 0:
                logging.error(f"Syntax check failed: {test_result.stderr}")
                error_msg = f"Error: Syntax check failed: {test_result.stderr}\n"
                yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                return
            logging.debug(f"Syntax check passed")

            env = os.environ.copy()
            env["PYTHONUNBUFFERED"] = "1"
            env["PATH"] = f"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:{env.get('PATH', '')}"
            env["HOME"] = "/home/pi"
            env["PYTHONPATH"] = f"{self.venv_path.parent}/lib/python3.11/site-packages:{env.get('PYTHONPATH', '')}"
            env["LC_ALL"] = "en_US.UTF-8"
            env["TERM"] = env.get("TERM", "dumb")
            logging.debug(f"Environment: {env}")

            self.process = subprocess.Popen(
                cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                stdin=subprocess.PIPE, text=True, bufsize=1, universal_newlines=True, env=env
            )
            logging.debug(f"Started process with PID: {self.process.pid}")
            backup_prompt = re.compile(r'⚠?\s*Backup\?\s*Y/n\s*:?', re.IGNORECASE)
            timeout = 600
            start_time = datetime.now()
            output_buffer = []
            last_heartbeat = time.time()
            while self.process.poll() is None:
                try:
                    if time.time() - last_heartbeat > 5:
                        with self.output_lock:
                            yield "data: \n\n"
                            logging.debug("Sent heartbeat")
                            sys.stdout.flush()
                        last_heartbeat = time.time()

                    rlist, _, _ = select.select([self.process.stdout, self.process.stderr], [], [], 0.1)
                    for stream in rlist:
                        if stream is self.process.stdout:
                            line = stream.readline()
                        elif stream is self.process.stderr:
                            line = stream.readline()
                        else:
                            continue

                        if not line:
                            continue

                        with self.output_lock:
                            clean_line = re.sub(r'\x1B\[[0-?]*[ -/]*[@-~]', '', line)
                            converted_line = self.converter.convert(line.rstrip('\n'), full=False)
                            output_buffer.append(converted_line)

                            if stream is self.process.stdout:
                                logging.debug(f"stdout: {clean_line.strip()}")
                                if backup_prompt.search(clean_line) and '-y' not in flags and '-n' not in flags:
                                    logging.info("Detected backup prompt")
                                    yield "data: BACKUP_PROMPT\n\n"
                                    sys.stdout.flush()
                                    while self.backup_response is None and self.process.poll() is None:
                                        if (datetime.now() - start_time).seconds > timeout:
                                            logging.error("Backup prompt timed out")
                                            error_msg = "Error: Backup prompt timed out after 600 seconds\n"
                                            yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                                            sys.stdout.flush()
                                            self.process.terminate()
                                            break
                                        time.sleep(0.2)
                                    if self.backup_response:
                                        try:
                                            self.process.stdin.write(self.backup_response + '\n')
                                            self.process.stdin.flush()
                                            logging.info(f"Sent backup response: {self.backup_response}")
                                        except Exception as e:
                                            logging.error(f"Failed to send backup response: {str(e)}")
                                            error_msg = f"Error sending backup response: {e}\n"
                                            yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                                            sys.stdout.flush()
                            else:
                                logging.error(f"stderr: {clean_line.strip()}")
                                if "tput: No value for $TERM" in clean_line:
                                    logging.warning(f"Ignoring tput error: {clean_line.strip()}")
                                elif "network error" in clean_line.lower():
                                    logging.error(f"Network error detected in stderr: {clean_line.strip()}")
                                    error_msg = f"Error: Network issue during script execution: {clean_line.strip()}. Check connectivity and try again.\n"
                                    yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                                    sys.stdout.flush()

                            if len(output_buffer) >= 10:
                                chunk = "\n".join(output_buffer)
                                logging.debug(f"Streaming chunk: {chunk}")
                                yield f"data: {chunk}\n\n"
                                sys.stdout.flush()
                                output_buffer = []

                    time.sleep(0.005)
                except (BrokenPipeError, ConnectionResetError) as e:
                    logging.error(f"Stream interrupted: {str(e)}")
                    error_msg = f"Error: Stream interrupted: {str(e)}\n"
                    yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                    sys.stdout.flush()
                    break
                except urllib.error.URLError as e:
                    logging.error(f"Network error during script execution: {str(e)}")
                    error_msg = f"Error: Network failure: {str(e)}. Please check your internet connection and try again.\n"
                    yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                    sys.stdout.flush()
                    break

            with self.output_lock:
                if output_buffer:
                    chunk = "\n".join(output_buffer)
                    logging.debug(f"Streaming final chunk: {chunk}")
                    yield f"data: {chunk}\n\n"
                    sys.stdout.flush()

            stdout, stderr = self.process.communicate()
            if stdout:
                with self.output_lock:
                    logging.debug(f"Final script stdout: {stdout.strip()}")
                    converted_output = self.converter.convert(stdout.rstrip('\n'), full=False)
                    yield f"data: {converted_output}\n\n"
                    sys.stdout.flush()
            if stderr:
                with self.output_lock:
                    logging.error(f"Final script stderr: {stderr.strip()}")
                    converted_err = self.converter.convert(stderr.rstrip('\n'), full=False)
                    yield f"data: {converted_err}\n\n"
                    sys.stdout.flush()
                    if "tput: No value for $TERM" in stderr:
                        logging.warning(f"Ignoring tput error in final stderr: {stderr.strip()}")
                    elif "network error" in stderr.lower():
                        logging.error(f"Network error in final stderr: {stderr.strip()}")
                        error_msg = f"Error: Network issue in final output: {stderr.strip()}. Check connectivity and retry.\n"
                        yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                        sys.stdout.flush()
            if self.process.returncode == 0:
                success_msg = f"Completed: Log at ~/saturn-logs/{script.replace('.py', '')}-*.log\n"
                with self.output_lock:
                    converted_success = self.converter.convert(success_msg, full=False)
                    logging.debug(f"Success message HTML: {converted_success}")
                    yield f"data: {converted_success}\n\n"
                    sys.stdout.flush()
                    logging.info(f"Script {script} completed successfully with PID {self.process.pid}")
            else:
                error_msg = f"Failed: Check output for errors (return code: {self.process.returncode})\n"
                with self.output_lock:
                    converted_error = self.converter.convert(error_msg, full=False)
                    logging.debug(f"Error message HTML: {converted_error}")
                    yield f"data: {converted_error}\n\n"
                    sys.stdout.flush()
                    logging.error(f"Script {script} failed with return code {self.process.returncode}")
        except Exception as e:
            logging.error(f"Script execution failed: {str(e)}")
            error_msg = f"Error: {str(e)}\n"
            if isinstance(e, urllib.error.URLError):
                error_msg = f"Error: Network failure: {str(e)}. Please check your internet connection and try again.\n"
            with self.output_lock:
                converted_error = self.converter.convert(error_msg, full=False)
                yield f"data: {converted_error}\n\n"
                sys.stdout.flush()
        finally:
            self.running = False
            self.process = None
            logging.debug("Script execution completed")

    def get_versions(self):
        logging.debug("Fetching script versions")
        versions = self.versions
        logging.info(f"Returning versions: {versions}")
        return versions

@app.route('/ping')
def ping():
    logging.debug(f"Ping request received, client: {request.remote_addr}, headers: {request.headers}")
    response = Response("pong")
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response

@app.route('/saturn/')
def index():
    logging.debug(f"Serving index page for /saturn/, client: {request.remote_addr}, headers: {request.headers}")
    if not os.path.exists('/home/pi/github/Saturn/scripts/templates/index.html'):
        logging.error("index.html not found")
        return "Error: index.html not found", 500
    try:
        with open('/home/pi/github/Saturn/scripts/templates/index.html', 'r') as f:
            content = f.read()
        if "script-form" not in content:
            logging.error("index.html does not contain expected content (script-form)")
            return "Error: Invalid index.html content", 500
        response = Response(content)
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
        return response
    except Exception as e:
        logging.error(f"Error reading index.html: {str(e)}")
        return f"Error reading index.html: {str(e)}", 500

@app.route('/saturn/get_scripts', methods=['GET'])
def get_scripts():
    logging.debug(f"Fetching available scripts for /saturn/get_scripts, client: {request.remote_addr}, headers: {request.headers}")
    scripts = list(app.saturn.scripts.keys())
    logging.info(f"Returning scripts: {scripts}")
    response = jsonify({"scripts": scripts})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 200

@app.route('/saturn/get_versions', methods=['GET'])
def get_versions():
    logging.debug(f"Fetching script versions for /saturn/get_versions, client: {request.remote_addr}, headers: {request.headers}")
    versions = app.saturn.get_versions()
    response = jsonify({"versions": versions})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 200

@app.route('/saturn/get_flags', methods=['GET'])
def get_flags():
    script = request.args.get('script')
    logging.debug(f"Fetching flags for script: {script} on /saturn/get_flags, client: {request.remote_addr}, headers: {request.headers}")
    if script in app.saturn.scripts:
        logging.info(f"Returning flags for {script}: {app.saturn.scripts[script]}")
        response = jsonify({"flags": app.saturn.scripts[script]})
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
        return response, 200
    logging.warning(f"Invalid script requested: {script}")
    response = jsonify({"flags": [], "error": f"Invalid script: {script}"})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 404

@app.route('/saturn/run', methods=['POST'])
def run():
    script = request.form.get('script')
    flags = request.form.getlist('flags')
    logging.debug(f"Received run request for script: {script}, flags: {flags} on /saturn/run, client: {request.remote_addr}, headers: {request.headers}")
    if not script or script not in app.saturn.scripts:
        logging.error(f"Invalid script: {script}")
        error_msg = f"Error: Invalid script {script}\n"
        response = Response(f"data: {app.saturn.converter.convert(error_msg, full=False)}\n\n", mimetype='text/event-stream', status=400)
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
        response.headers['Content-Type'] = 'text/event-stream; charset=utf-8'
        response.headers['X-Accel-Buffering'] = 'no'
        return response

    def generate():
        try:
            for output in app.saturn.run_script(script, flags):
                logging.debug(f"Streaming event: {output}")
                yield output
                sys.stdout.flush()
        except Exception as e:
            logging.error(f"Run endpoint error: {str(e)}")
            error_msg = f"Error: {str(e)}\n"
            if isinstance(e, urllib.error.URLError):
                error_msg = f"Error: Network failure: {str(e)}. Please check your internet connection and try again.\n"
            converted_error = app.saturn.converter.convert(error_msg, full=False)
            yield f"data: {converted_error}\n\n"
            sys.stdout.flush()

    response = Response(generate(), mimetype='text/event-stream')
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    response.headers['Content-Type'] = 'text/event-stream; charset=utf-8'
    response.headers['X-Accel-Buffering'] = 'no'
    return response

@app.route('/saturn/backup_response', methods=['POST'])
def backup_response():
    script = request.form.get('script')
    response = request.form.get('response')
    logging.debug(f"Received backup response: {response} for script: {script} on /saturn/backup_response, client: {request.remote_addr}, headers: {request.headers}")
    if response in ['y', 'n']:
        app.saturn.backup_response = response
        logging.info(f"Backup response set: {response}")
        response = jsonify({"status": "success"})
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
        return response, 200
    logging.error(f"Invalid backup response: {response}")
    response = jsonify({"status": "error", "message": "Invalid response"})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 400

@app.route('/saturn/change_password', methods=['POST'])
def change_password():
    new_password = request.form.get('new_password')
    logging.debug(f"Received change password request, client: {request.remote_addr}, headers: {request.headers}")
    result = app.saturn.change_password(new_password)
    response = jsonify(result)
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 200 if result['status'] == 'success' else 400

@app.route('/saturn/exit', methods=['POST'])
def exit_app():
    logging.debug(f"Received exit request on /saturn/exit, client: {request.remote_addr}, headers: {request.headers}")
    if app.saturn.process:
        try:
            app.saturn.process.terminate()
            app.saturn.process.wait(timeout=5)
            logging.info("Terminated running script")
        except subprocess.TimeoutExpired:
            app.saturn.process.kill()
            logging.warning("Forced termination of running script")
    logging.info("Initiating server shutdown and logoff")
    response = jsonify({"status": "shutting down"})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    response.headers['WWW-Authenticate'] = 'Basic realm="Saturn Update Manager - Restricted Access"'
    # Start shutdown in a separate thread
    def shutdown():
        try:
            time.sleep(1)  # Brief delay to allow response to be sent
            os.kill(os.getpid(), signal.SIGINT)
        except Exception as e:
            logging.error(f"Shutdown error: {str(e)}")
            sys.exit(1)
    threading.Thread(target=shutdown, daemon=True).start()
    return response, 401

try:
    logging.debug("Creating SaturnUpdateManager instance")
    app.saturn = SaturnUpdateManager()
    app.saturn.install_desktop_icons()
except Exception as e:
    error_log = Path.home() / "saturn-logs" / f"saturn-update-manager-error-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"
    with open(error_log, "w") as f:
        f.write(f"Web server initialization error: {str(e)}\n")
    logging.error(f"Web server initialization error: {str(e)}")
    sys.exit(1)
EOF
chmod -R u+rwX "$SATURN_SCRIPT"
chown pi:pi "$SATURN_SCRIPT"
log_and_echo "${GREEN}saturn_update_manager.py created${NC}"
log_and_echo "${CYAN}Validating saturn_update_manager.py syntax...${NC}"
if output=$(sudo -u pi bash -c ". $VENV_PATH/bin/activate && python3 -m py_compile $SATURN_SCRIPT" 2>&1); then
    log_and_echo "${GREEN}Syntax validation passed${NC}"
else
    log_and_echo "${RED}Error: Syntax validation failed${NC}"
    log_and_echo "$output"
    exit 1
fi
log_and_echo "${GREEN}Verified Flask-based saturn_update_manager.py${NC}"

# Create SaturnUpdateManager.desktop
log_and_echo "${CYAN}Creating SaturnUpdateManager.desktop (overwriting if exists)...${NC}"
rm -f "$DESKTOP_FILE"
cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=Saturn Update Manager
Comment=Web-based GUI to manage updates for update-G2.py and update-pihpsdr.py
Exec=xdg-open http://localhost/saturn/
Icon=system-software-update
Terminal=false
Categories=System;Utility;
EOF
chmod u+rwX "$DESKTOP_FILE"
chown pi:pi "$DESKTOP_FILE"
log_and_echo "${GREEN}SaturnUpdateManager.desktop created${NC}"

# Install desktop shortcut
log_and_echo "${CYAN}Installing desktop shortcut...${NC}"
if [ ! -d "/home/pi/Desktop" ]; then
    log_and_echo "${YELLOW}Warning: Desktop directory not found at /home/pi/Desktop${NC}"
else
    cp "$DESKTOP_FILE" "$DESKTOP_DEST"
    chmod u+rwX "$DESKTOP_DEST"
    chown pi:pi "$DESKTOP_DEST"
    log_and_echo "${GREEN}Desktop shortcut installed to $DESKTOP_DEST${NC}"
fi

# Verify scripts
log_and_echo "${CYAN}Checking for update-G2.py and update-pihpsdr.py...${NC}"
for script in "update-G2.py" "update-pihpsdr.py"; do
    if [ ! -f "$SCRIPTS_DIR/$script" ]; then
        log_and_echo "${RED}Error: $script not found at $SCRIPTS_DIR/$script. Please ensure it exists.${NC}"
        exit 1
    else
        chmod u+rwX "$SCRIPTS_DIR/$script"
        chown pi:pi "$SCRIPTS_DIR/$script"
        if [ "$script" = "update-G2.py" ]; then
            version=$(grep "Version:" "$SCRIPTS_DIR/$script" | head -n1 | awk '{print $NF}')
            if [ "$version" != "2.4" ]; then
                log_and_echo "${YELLOW}Warning: $script version is $version, expected 2.4. Please update.${NC}"
            fi
        elif [ "$script" = "update-pihpsdr.py" ]; then
            version=$(grep "Version:" "$SCRIPTS_DIR/$script" | head -n1 | awk '{print $NF}')
            if [ "$version" != "1.7" ]; then
                log_and_echo "${YELLOW}Warning: $script version is $version, expected 1.7. Please update.${NC}"
            fi
        fi
        log_and_echo "${GREEN}$script verified and permissions set${NC}"
    fi
done
