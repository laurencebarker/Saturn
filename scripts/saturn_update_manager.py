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
