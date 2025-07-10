#!/bin/bash
# setup_saturn_webserver.sh - Setup web server for saturn_update_manager.py on Raspberry Pi Bookworm
# Version: 2.14
# Written by: Jerry DeLong KD4YAL
# Dependencies: python3, python3-pip, chromium-browser, lsof
# Usage: bash ~/github/Saturn/scripts/setup_saturn_webserver.sh

set -e

# Paths
VENV_PATH="$HOME/venv"
SCRIPTS_DIR="$HOME/github/Saturn/scripts"
TEMPLATES_DIR="$SCRIPTS_DIR/templates"
LOG_DIR="$HOME/saturn-logs"
DESKTOP_FILE="$SCRIPTS_DIR/SaturnUpdateManager.desktop"
DESKTOP_DEST="$HOME/Desktop/SaturnUpdateManager.desktop"
SATURN_SCRIPT="$SCRIPTS_DIR/saturn_update_manager.py"

# Log file
LOG_FILE="$LOG_DIR/setup_saturn_webserver-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR" || { echo "Error: Failed to create $LOG_DIR"; exit 1; }

# Function to log and echo output
log_and_echo() {
    echo "$1"
    echo "$1" >> "$LOG_FILE"
}

# Function to run command, log, and echo output
run_command() {
    local cmd="$1"
    local desc="$2"
    log_and_echo "$desc..."
    if output=$($cmd 2>&1); then
        log_and_echo "$output"
        log_and_echo "$desc completed"
    else
        log_and_echo "Error: $desc failed"
        log_and_echo "$output"
        exit 1
    fi
}

# Function to install system dependencies
install_system_deps() {
    run_command "sudo apt-get update" "Updating package lists"
    run_command "sudo apt-get install -y python3 python3-pip chromium-browser lsof" "Installing system dependencies"
}

# Function to setup virtual environment
setup_venv() {
    log_and_echo "Creating virtual environment at $VENV_PATH..."
    if [ ! -d "$VENV_PATH" ]; then
        run_command "python3 -m venv $VENV_PATH" "Creating virtual environment"
        chmod -R u+rwX "$VENV_PATH" || { log_and_echo "Error: Failed to set permissions for $VENV_PATH"; exit 1; }
    else
        log_and_echo "Virtual environment already exists"
    fi
    . "$VENV_PATH/bin/activate"
    run_command "pip install flask ansi2html==1.9.2 psutil==7.0.0 pyfiglet" "Installing Python dependencies"
    deactivate
}

# Function to create directories
create_dirs() {
    log_and_echo "Creating directories..."
    mkdir -p "$SCRIPTS_DIR" "$TEMPLATES_DIR" "$LOG_DIR" || { log_and_echo "Error: Failed to create directories"; exit 1; }
    chmod -R u+rwX "$SCRIPTS_DIR" "$TEMPLATES_DIR" "$LOG_DIR" || { log_and_echo "Error: Failed to set permissions for directories"; exit 1; }
    log_and_echo "Directories created"
}

# Function to create saturn_update_manager.py
create_saturn_script() {
    log_and_echo "Creating saturn_update_manager.py (overwriting if exists)..."
    rm -f "$SATURN_SCRIPT"
    cat > "$SATURN_SCRIPT" << 'EOF'
#!/usr/bin/env python3
# saturn_update_manager.py - Web-based Update Manager for update-G2.py and update-pihpsdr.py
# Runs from Raspberry Pi desktop, executing scripts within the GUI with a black background
# Version: 2.11
# Written by: Jerry DeLong KD4YAL
# Dependencies: flask, ansi2html (1.9.2), subprocess, os, threading, logging, re, shutil, chromium-browser
# Usage: . ~/venv/bin/activate; pip install flask ansi2html; python3 ~/github/Saturn/scripts/saturn_update_manager.py

from flask import Flask, render_template, request, Response, jsonify
import subprocess
import os
import threading
import shlex
from pathlib import Path
import logging
from datetime import datetime
import re
import shutil
import signal
import sys
from ansi2html import Ansi2HTMLConverter

app = Flask(__name__)
shutdown_event = threading.Event()

class SaturnUpdateManager:
    def __init__(self):
        self.venv_path = Path.home() / "venv" / "bin" / "activate"
        self.scripts_dir = Path.home() / "github" / "Saturn" / "scripts"
        self.log_dir = Path.home() / "saturn-logs"
        self.scripts = {
            "update-G2.py": ["--skip-git", "-y", "-n", "--dry-run", "--verbose"],
            "update-pihpsdr.py": ["--skip-git", "-y", "-n", "--no-gpio", "--dry-run", "--verbose", "--show-compile"]
        }
        self.process = None
        self.backup_response = None
        self.running = False
        self.converter = Ansi2HTMLConverter(inline=True)  # Default scheme for standard colors

        # Setup logging
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.log_file = self.log_dir / f"saturn-update-manager-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"
        logging.basicConfig(
            level=logging.DEBUG,
            format="%(asctime)s [%(levelname)s] %(message)s",
            handlers=[logging.FileHandler(self.log_file)]
        )
        logging.info(f"Starting Saturn Update Manager v2.11")

        # Validate setup
        error_message = self.validate_setup()
        if error_message:
            logging.error(f"Initialization failed: {error_message}")
            print(f"Error: {error_message}\nCheck log: {self.log_file}")
            exit(1)

    def validate_setup(self):
        """Validate script paths, virtual environment, and dependencies."""
        try:
            logging.debug("Validating setup...")
            if not self.venv_path.exists():
                return f"Virtual environment not found at {self.venv_path}"
            for script in self.scripts:
                script_path = self.scripts_dir / script
                if not script_path.exists():
                    return f"Script not found: {script_path}"
                if not os.access(script_path, os.X_OK):
                    try:
                        os.chmod(script_path, 0o755)
                        logging.info(f"Set executable permissions for {script_path}")
                    except Exception as e:
                        return f"Cannot set executable permissions for {script_path}: {str(e)}"
            try:
                import flask
                import ansi2html
                if ansi2html.__version__ != '1.9.2':
                    return f"Invalid ansi2html version: {ansi2html.__version__}. Requires 1.9.2"
                import shutil
            except ImportError as e:
                return f"Missing dependency: {str(e)}. Install with: pip install flask ansi2html==1.9.2"
            if not shutil.which("chromium-browser"):
                return "chromium-browser not found. Install with: sudo apt-get install chromium-browser"
            python_version = subprocess.check_output(["python3", "--version"], stderr=subprocess.STDOUT).decode().strip()
            logging.info(f"Python version: {python_version}")
            if not python_version.startswith("Python 3"):
                return f"Incompatible Python version: {python_version}. Requires Python 3.x"
            logging.debug("Setup validation completed successfully")
            return None
        except Exception as e:
            logging.error(f"Setup validation failed: {str(e)}")
            return f"Setup validation failed: {str(e)}"

    def install_desktop_icons(self):
        """Install desktop shortcut for this web app."""
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
Exec=bash -c ". %h/venv/bin/activate && export DISPLAY=:0 && python3 %h/github/Saturn/scripts/saturn_update_manager.py >> %h/saturn-logs/saturn-update-manager.log 2>&1 & sleep 2; chromium-browser http://localhost:5000"
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

    def run_script(self, script, flags):
        """Run the selected script and yield ANSI-colored HTML output."""
        logging.debug(f"Running script: {script} with flags: {flags}")
        self.running = True
        self.process = None
        self.backup_response = None
        script_path = self.scripts_dir / script
        cmd = f". {self.venv_path} && python3 {shlex.quote(str(script_path))} {' '.join(shlex.quote(flag) for flag in flags)} && deactivate"
        logging.info(f"Executing command: {cmd}")

        try:
            env = os.environ.copy()
            env["PYTHONUNBUFFERED"] = "1"  # Force unbuffered output
            self.process = subprocess.Popen(
                cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                stdin=subprocess.PIPE, text=True, bufsize=0, universal_newlines=True, env=env
            )
            logging.debug(f"Started process with PID: {self.process.pid}")
            backup_prompt = re.compile(r'⚠?\s*Backup\?\s*Y/n\s*:?', re.IGNORECASE)
            timeout = 30
            start_time = datetime.now()
            while self.process.poll() is None:
                line = self.process.stdout.readline()
                if line:
                    logging.debug(f"Raw output: {repr(line)}")
                    clean_line = re.sub(r'\x1B\[[0-?]*[ -/]*[@-~]', '', line)
                    logging.debug(f"Clean output: {clean_line.strip()}")
                    converted_line = self.converter.convert(line.rstrip('\n'), full=False)
                    logging.debug(f"Converted HTML: {converted_line}")
                    if backup_prompt.search(clean_line) and '-y' not in flags and '-n' not in flags:
                        logging.info("Detected backup prompt")
                        yield "BACKUP_PROMPT"
                        while self.backup_response is None and self.process.poll() is None:
                            if (datetime.now() - start_time).seconds > timeout:
                                logging.error("Backup prompt timed out")
                                yield self.converter.convert("Error: Backup prompt timed out after 30 seconds\n", full=False)
                                self.process.terminate()
                                break
                            threading.Event().wait(0.1)
                        if self.backup_response:
                            try:
                                self.process.stdin.write(self.backup_response + '\n')
                                self.process.stdin.flush()
                                logging.info(f"Sent backup response: {self.backup_response}")
                            except Exception as e:
                                logging.error(f"Failed to send backup response: {str(e)}")
                                yield self.converter.convert(f"Error sending backup response: {e}\n", full=False)
                    else:
                        logging.debug(f"No backup prompt match for line: {clean_line.strip()}")
                    yield converted_line
                threading.Event().wait(0.01)
            output, _ = self.process.communicate()
            if output:
                logging.debug(f"Final script output: {output.strip()}")
                converted_output = self.converter.convert(output.rstrip('\n'), full=False)
                logging.debug(f"Final converted HTML: {converted_output}")
                yield converted_output
            if self.process.returncode == 0:
                success_msg = f"Completed: Log at ~/saturn-logs/{script.replace('.py', '')}-*.log\n"
                converted_success = self.converter.convert(success_msg, full=False)
                logging.debug(f"Success message HTML: {converted_success}")
                yield converted_success
                logging.info(f"Script {script} completed successfully with PID {self.process.pid}")
            else:
                error_msg = f"Failed: Check output for errors\n"
                converted_error = self.converter.convert(error_msg, full=False)
                logging.debug(f"Error message HTML: {converted_error}")
                yield converted_error
                logging.error(f"Script {script} failed with return code {self.process.returncode}")
        except Exception as e:
            logging.error(f"Script execution failed: {str(e)}")
            error_msg = f"Error: {e}\n"
            yield self.converter.convert(error_msg, full=False)
        finally:
            self.running = False
            self.process = None
            logging.debug("Script execution completed")

@app.route('/')
def index():
    logging.debug("Serving index page")
    return render_template('index.html', scripts=app.saturn.scripts.keys())

@app.route('/get_flags', methods=['GET'])
def get_flags():
    script = request.args.get('script')
    logging.debug(f"Fetching flags for script: {script}")
    if script in app.saturn.scripts:
        logging.info(f"Returning flags for {script}: {app.saturn.scripts[script]}")
        return jsonify({"flags": app.saturn.scripts[script]})
    logging.warning(f"Invalid script requested: {script}")
    return jsonify({"flags": [], "error": f"Invalid script: {script}"}), 404

@app.route('/run', methods=['POST'])
def run():
    script = request.form.get('script')
    flags = request.form.getlist('flags')
    logging.debug(f"Received run request for script: {script}, flags: {flags}")
    if not script or script not in app.saturn.scripts:
        logging.error(f"Invalid script: {script}")
        error_msg = f"Error: Invalid script {script}\n"
        return Response(app.saturn.converter.convert(error_msg, full=False), mimetype='text/plain', status=400)

    def generate():
        try:
            for output in app.saturn.run_script(script, flags):
                logging.debug(f"Yielding output: {output}")
                yield f"data: {output}\n\n"
        except Exception as e:
            logging.error(f"Run endpoint error: {str(e)}")
            error_msg = f"Error: {str(e)}\n"
            yield f"data: {app.saturn.converter.convert(error_msg, full=False)}\n\n"

    return Response(generate(), mimetype='text/event-stream')

@app.route('/backup_response', methods=['POST'])
def backup_response():
    response = request.form.get('response')
    logging.debug(f"Received backup response: {response}")
    if response in ['y', 'n']:
        app.saturn.backup_response = response
        logging.info(f"Backup response set: {response}")
        return jsonify({"status": "success"})
    logging.error(f"Invalid backup response: {response}")
    return jsonify({"status": "error", "message": "Invalid response"}), 400

@app.route('/exit', methods=['POST'])
def exit_app():
    logging.debug("Received exit request")
    if app.saturn.process:
        try:
            app.saturn.process.terminate()
            app.saturn.process.wait(timeout=5)
            logging.info("Terminated running script")
        except subprocess.TimeoutExpired:
            app.saturn.process.kill()
            logging.warning("Forced termination of running script")
    logging.info("Initiating server shutdown")
    shutdown_event.set()
    def shutdown():
        try:
            shutdown_func = request.environ.get('werkzeug.server.shutdown')
            if shutdown_func:
                shutdown_func()
            else:
                logging.warning("No shutdown function available, using sys.exit")
                sys.exit(0)
        except Exception as e:
            logging.error(f"Shutdown error: {str(e)}")
            sys.exit(1)
    threading.Thread(target=shutdown, daemon=True).start()
    return jsonify({"status": "success"})

if __name__ == "__main__":
    try:
        app.saturn = SaturnUpdateManager()
        app.saturn.install_desktop_icons()
        private_ip = subprocess.check_output("ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n1", shell=True).decode().strip()
        logging.info(f"Starting Flask server on http://localhost:5000 and http://{private_ip}:5000")
        subprocess.Popen(["chromium-browser", "http://localhost:5000"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=dict(os.environ, DISPLAY=":0"))
        app.run(host="0.0.0.0", port=5000, debug=False)
    except Exception as e:
        with open(Path.home() / "saturn-logs" / f"saturn-update-manager-error-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log", "w") as f:
            f.write(f"Web server startup error: {str(e)}\n")
        raise
EOF
    chmod -R u+rwX "$SATURN_SCRIPT" || { log_and_echo "Error: Failed to set permissions for $SATURN_SCRIPT"; exit 1; }
    log_and_echo "saturn_update_manager.py created"
    # Validate syntax
    log_and_echo "Validating saturn_update_manager.py syntax..."
    if output=$(python3 -m py_compile "$SATURN_SCRIPT" 2>&1); then
        log_and_echo "Syntax validation passed"
    else
        log_and_echo "Error: Syntax validation failed"
        log_and_echo "$output"
        exit 1
    fi
    log_and_echo "Verified Flask-based saturn_update_manager.py"
}

# Function to create index.html
create_index_html() {
    local INDEX_HTML="$TEMPLATES_DIR/index.html"
    log_and_echo "Creating index.html (overwriting if exists)..."
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
            background-color: #000;
            color: inherit; /* Rely on ansi2html inline styles */
            padding: 1rem;
            overflow-y: auto;
            min-height: 400px;
            max-height: 400px;
            line-height: 1.2;
            margin: 0;
            border: 1px solid #333;
            box-sizing: border-box;
        }
        .output-container {
            width: 100%;
            min-height: 420px;
            background-color: #000;
            padding: 0;
            border-radius: 0.5rem;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #f3f4f6; }
        .container { max-width: 800px; }
    </style>
</head>
<body class="bg-gray-100">
    <div class="container mx-auto p-4">
        <h1 class="text-3xl font-bold text-red-600 text-center mb-6">Saturn Update Manager</h1>

        <div class="bg-white rounded-lg shadow-md p-4 mb-4">
            <form id="script-form" class="flex flex-col space-y-4">
                <div class="flex items-center space-x-4">
                    <label for="script" class="text-lg font-medium text-gray-700">Select Script:</label>
                    <select id="script" name="script" class="border rounded px-2 py-1 bg-blue-100 text-blue-800">
                        {% for script in scripts %}
                            <option value="{{ script }}">{{ script }}</option>
                        {% endfor %}
                    </select>
                </div>
                <div id="flags" class="flex flex-wrap gap-4"></div>
                <div class="flex justify-center space-x-4">
                    <button type="submit" class="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600">Run</button>
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
    </div>

    <script>
        async function loadFlags(script) {
            try {
                const response = await fetch(`/get_flags?script=${encodeURIComponent(script)}`);
                if (!response.ok) throw new Error(`HTTP ${response.status}: ${await response.text()}`);
                const data = await response.json();
                const flagsDiv = document.getElementById('flags');
                flagsDiv.innerHTML = '';
                if (data.error) {
                    document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error: ${data.error}</span>\n`;
                    return;
                }
                data.flags.forEach(flag => {
                    const label = document.createElement('label');
                    label.className = 'flex items-center space-x-2';
                    label.innerHTML = `<input type="checkbox" name="flags" value="${flag}" class="form-checkbox h-5 w-5 text-blue-600"> <span>${flag}</span>`;
                    flagsDiv.appendChild(label);
                });
                console.log(`Loaded flags for ${script}:`, data.flags);
            } catch (error) {
                console.error('Error loading flags:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error loading flags: ${error.message}</span>\n`;
            }
        }

        document.getElementById('script-form').addEventListener('submit', async function(e) {
            e.preventDefault();
            const script = document.getElementById('script').value;
            const flags = Array.from(document.querySelectorAll('input[name="flags"]:checked')).map(cb => cb.value);
            const output = document.getElementById('output');
            output.innerHTML = '';
            console.log(`Submitting run request for script: ${script}, flags:`, flags);

            try {
                const formData = new FormData();
                formData.append('script', script);
                flags.forEach(flag => formData.append('flags', flag));
                const response = await fetch('/run', {
                    method: 'POST',
                    body: formData
                });
                if (!response.ok) throw new Error(`HTTP ${response.status}: ${await response.text()}`);
                console.log('Run request sent successfully');
                const reader = response.body.getReader();
                const decoder = new TextDecoder();
                while (true) {
                    const { done, value } = await reader.read();
                    if (done) {
                        console.log('Stream complete');
                        break;
                    }
                    const chunk = decoder.decode(value, { stream: true });
                    const lines = chunk.split('\n\n');
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
            } catch (error) {
                console.error('Run error:', error);
                output.innerHTML += `<span style="color:#FF0000">Error: ${error.message}</span>\n`;
            }
        });

        document.getElementById('script').addEventListener('change', function() {
            console.log('Script changed:', this.value);
            loadFlags(this.value);
        });

        document.getElementById('backup-yes').addEventListener('click', function() {
            console.log('Sending backup response: y');
            fetch('/backup_response', {
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
            fetch('/backup_response', {
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

        document.getElementById('exit-btn').addEventListener('click', function() {
            console.log('Sending exit request');
            fetch('/exit', { method: 'POST' })
                .then(response => response.json())
                .then(data => {
                    if (data.status === 'success') {
                        console.log('Exit request successful, closing window');
                        window.close();
                    } else {
                        throw new Error('Exit failed');
                    }
                })
                .catch(error => {
                    console.error('Exit error:', error);
                    document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error exiting: ${error.message}</span>\n`;
                });
        });

        console.log('Loading initial flags');
        loadFlags(document.getElementById('script').value);
    </script>
</body>
</html>
EOF
    chmod -R u+rwX "$INDEX_HTML" || { log_and_echo "Error: Failed to set permissions for $INDEX_HTML"; exit 1; }
    log_and_echo "index.html created"
    # Verify index.html content
    if ! grep -q "Saturn Update Manager" "$INDEX_HTML"; then
        log_and_echo "Error: Failed to create valid index.html"
        exit 1
    fi
    log_and_echo "Verified index.html content"
}

# Function to create SaturnUpdateManager.desktop
create_desktop_file() {
    log_and_echo "Creating SaturnUpdateManager.desktop (overwriting if exists)..."
    rm -f "$DESKTOP_FILE"
    cat > "$DESKTOP_FILE" << 'EOF'
[Desktop Entry]
Type=Application
Name=Saturn Update Manager
Comment=Web-based GUI to manage updates for update-G2.py and update-pihpsdr.py
Exec=bash -c ". %h/venv/bin/activate && export DISPLAY=:0 && python3 %h/github/Saturn/scripts/saturn_update_manager.py >> %h/saturn-logs/saturn-update-manager.log 2>&1 & sleep 2; chromium-browser http://localhost:5000"
Icon=system-software-update
Terminal=false
Categories=System;Utility;
EOF
    chmod u+rwX "$DESKTOP_FILE" || { log_and_echo "Error: Failed to set permissions for $DESKTOP_FILE"; exit 1; }
    log_and_echo "SaturnUpdateManager.desktop created"
}

# Function to install desktop shortcut
install_desktop_shortcut() {
    log_and_echo "Installing desktop shortcut..."
    if [ ! -d "$HOME/Desktop" ]; then
        log_and_echo "Warning: Desktop directory not found at $HOME/Desktop"
    else
        cp "$DESKTOP_FILE" "$DESKTOP_DEST" || { log_and_echo "Error: Failed to copy desktop shortcut to $DESKTOP_DEST"; exit 1; }
        chmod u+rwX "$DESKTOP_DEST" || { log_and_echo "Error: Failed to set permissions for $DESKTOP_DEST"; exit 1; }
        log_and_echo "Desktop shortcut installed to $DESKTOP_DEST"
    fi
}

# Function to verify scripts
verify_scripts() {
    log_and_echo "Checking for update-G2.py and update-pihpsdr.py..."
    for script in "update-G2.py" "update-pihpsdr.py"; do
        if [ ! -f "$SCRIPTS_DIR/$script" ]; then
            log_and_echo "Warning: $script not found at $SCRIPTS_DIR/$script. Please ensure it exists."
        else
            chmod u+rwX "$SCRIPTS_DIR/$script" || { log_and_echo "Error: Failed to set permissions for $SCRIPTS_DIR/$script"; exit 1; }
            if [ "$script" = "update-G2.py" ]; then
                version=$(grep "Version:" "$SCRIPTS_DIR/$script" | head -n1 | awk '{print $NF}')
                if [ "$version" != "2.4" ]; then
                    log_and_echo "Warning: $script version is $version, expected 2.4. Please update."
                fi
            elif [ "$script" = "update-pihpsdr.py" ]; then
                version=$(grep "Version:" "$SCRIPTS_DIR/$script" | head -n1 | awk '{print $NF}')
                if [ "$version" != "1.6" ]; then
                    log_and_echo "Warning: $script version is $version, expected 1.6. Please update."
                fi
            fi
            log_and_echo "$script verified and permissions set"
        fi
    done
}

# Function to stop existing server on port 5000
stop_existing_server() {
    log_and_echo "Checking for existing server on port 5000..."
    max_attempts=3
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        if netstat -tuln | grep ":5000 " >/dev/null; then
            log_and_echo "Port 5000 is in use. Attempt $attempt/$max_attempts to terminate process..."
            PID=$(lsof -t -i:5000)
            if [ -n "$PID" ]; then
                kill -9 "$PID" || { log_and_echo "Error: Failed to terminate process $PID on port 5000"; exit 1; }
                log_and_echo "Terminated process $PID on port 5000"
                sleep 2
                if ! netstat -tuln | grep ":5000 " >/dev/null; then
                    log_and_echo "Port 5000 is free"
                    return 0
                fi
            else
                log_and_echo "Error: Could not identify process on port 5000"
                exit 1
            fi
        else
            log_and_echo "Port 5000 is free"
            return 0
        fi
        attempt=$((attempt + 1))
    done
    log_and_echo "Error: Port 5000 still in use after $max_attempts attempts"
    exit 1
}

# Function to start web server
start_web_server() {
    log_and_echo "Starting web server..."
    if ! . "$VENV_PATH/bin/activate"; then
        log_and_echo "Error: Failed to activate virtual environment at $VENV_PATH"
        exit 1
    fi
    stop_existing_server
    # Run Flask server and capture output
    python3 "$SATURN_SCRIPT" >> "$LOG_DIR/saturn-update-manager-$(date +%Y%m%d-%H%M%S).log" 2>&1 &
    SERVER_PID=$!
    if [ -z "$SERVER_PID" ]; then
        log_and_echo "Error: Failed to obtain SERVER_PID for Flask server"
        deactivate
        exit 1
    fi
    sleep 2
    if ps -p "$SERVER_PID" >/dev/null 2>&1; then
        private_ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n1)
        log_and_echo "Flask server started with PID $SERVER_PID"
        log_and_echo "Web server started. Access at http://localhost:5000 or http://$private_ip:5000"
        # Verify server is listening
        if netstat -tuln | grep ":5000 " >/dev/null; then
            log_and_echo "Server confirmed listening on port 5000"
        else
            log_and_echo "Error: Server not listening on port 5000. Check $LOG_DIR/saturn-update-manager-*.log"
            kill -9 "$SERVER_PID" 2>/dev/null
            deactivate
            exit 1
        fi
        # Launch browser
        export DISPLAY=:0
        if ! chromium-browser "http://localhost:5000" >/dev/null 2>&1 & then
            log_and_echo "Warning: Failed to launch Chromium browser. Try manually: chromium-browser http://localhost:5000"
        fi
    else
        log_and_echo "Error: Flask server process $SERVER_PID not running. Check $LOG_DIR/saturn-update-manager-*.log"
        deactivate
        exit 1
    fi
    deactivate
}

# Main execution
main() {
    log_and_echo "Starting setup at $(date)"
    install_system_deps
    setup_venv
    create_dirs
    create_saturn_script
    create_index_html
    create_desktop_file
    install_desktop_shortcut
    verify_scripts
    start_web_server
    private_ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n1)
    log_and_echo "Setup completed at $(date). Log: $LOG_FILE"
    log_and_echo "Test LAN access with: curl http://$private_ip:5000"
}

# Validate script syntax before execution
log_and_echo "Validating script syntax..."
if output=$(bash -n "$0" 2>&1); then
    log_and_echo "Script syntax validation passed"
else
    log_and_echo "Error: Script syntax validation failed"
    log_and_echo "$output"
    exit 1
fi

# Run main with error handling
main || {
    log_and_echo "Setup failed. Check log: $LOG_FILE"
    exit 1
}
