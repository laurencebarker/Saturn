#!/usr/bin/env python3
# saturn_update_manager.py - Web-based Update Manager for various scripts via config.json and themes via themes.json
# Version: 3.03
# Written by: Jerry DeLong KD4YAL
# Date: August 01, 2025
# Changes: Added PYTHONPYCACHEPREFIX to redirect __pycache__ outside repo/runtime (prevents cache in tree),
#          updated paths to use ~/.saturn/runtime/scripts/ for runtime (consistent with user dir),
#          updated to use runtime dir if exists, else fallback to source (Phase 2 of separation),
#          original changes: Version 3.00 with Flask GUI, script running, themes, etc.
# Dependencies: flask, ansi2html (1.9.2), subprocess, os, threading, logging, re, shutil, select, urllib.error, json
# Usage: . ~/venv/bin/activate; gunicorn --chdir ~/.saturn/runtime/scripts -w 5 --worker-class gevent -b 0.0.0.0:5000 -t 600 saturn_update_manager:app

import logging
import os
import glob
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
import json
from flask import Flask, render_template, request, Response, jsonify
from ansi2html import Ansi2HTMLConverter
import psutil  # Added for monitoring
import signal  # For kill

# Redirect __pycache__ outside repo/runtime to ~/.cache/saturn-pycache
os.environ['PYTHONPYCACHEPREFIX'] = os.path.expanduser('~/.cache/saturn-pycache')
os.makedirs(os.environ['PYTHONPYCACHEPREFIX'], exist_ok=True)

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

app = Flask(__name__, template_folder=os.path.expanduser('~/.saturn/templates'))
shutdown_event = threading.Event()

class SaturnUpdateManager:
    def __init__(self):
        logging.debug("Starting SaturnUpdateManager initialization")
        self.venv_path = Path.home() / "venv" / "bin" / "activate"
        # Use runtime dir if exists, else fallback to source
        runtime_scripts = Path.home() / ".saturn/runtime/scripts"
        if runtime_scripts.exists():
            self.scripts_dir = runtime_scripts
            logging.info(f"Using runtime dir: {self.scripts_dir}")
        else:
            self.scripts_dir = Path.home() / "github/Saturn/update_manager/scripts"
            logging.warning(f"Runtime dir not found—falling back to source: {self.scripts_dir}")
        self.log_dir = Path.home() / "saturn-logs"
        self.config_path = Path(os.path.expanduser("~/.saturn/config.json"))
        self.themes_path = Path(os.path.expanduser("~/.saturn/themes.json"))
        self.config = []
        self.themes = []
        self.versions = {
            "saturn_update_manager.py": "3.03"
        }
        self.process = None
        self.backup_response = None
        self.running = False
        self.output_lock = threading.Lock()
        self.converter = Ansi2HTMLConverter(inline=True)
        logging.info(f"Starting Saturn Update Manager v3.03")

        error_message = self.validate_setup()
        if error_message:
            logging.error(f"Initialization failed: {error_message}")
            print(f"Error: {error_message}\\nCheck log: {log_file}")
            sys.exit(1)

        self.load_config()
        self.load_themes()

    def load_config(self):
        logging.debug(f"Loading config from {self.config_path}")
        self.script_warnings = []
        self.grouped_scripts = {}
        if not self.config_path.exists():
            logging.error(f"Config file not found: {self.config_path}")
            self.script_warnings.append("Config file missing—using empty config")
            return
        try:
            with open(self.config_path, 'r') as f:
                data = json.load(f)
            if not isinstance(data, list):
                raise ValueError("config.json must be a list of script entries")
            home = os.path.expanduser("~")
            trusted_dirs = [os.path.join(home, "github"), os.path.join(home, ".saturn/runtime"), home]  # Add runtime to trusted
            for entry in data:
                directory = os.path.expanduser(entry.get("directory", ""))
                filename = entry.get("filename", "")
                path = os.path.join(directory, filename)
                if os.path.isfile(path):
                    if filename.endswith('.html') or os.access(path, os.X_OK):  # Allow .html without exec check
                        if any(path.startswith(d) for d in trusted_dirs):
                            entry["category"] = entry.get("category", "Uncategorized")
                            entry["type"] = "view" if filename.endswith('.html') else "script"  # Add type for JS handling
                            self.config.append(entry)
                            # Extract version if present (for scripts)
                            if not filename.endswith('.html'):
                                with open(path, 'r') as script_file:
                                    for line in script_file:
                                        if line.startswith("# Version:"):
                                            self.versions[filename] = line.split(":", 1)[-1].strip()
                                            break
                        else:
                            self.script_warnings.append(f"Skipped {filename}: outside trusted directories")
                    else:
                        self.script_warnings.append(f"Skipped {filename}: not executable (for non-HTML)")
                else:
                    self.script_warnings.append(f"Skipped {filename}: not a file")
            for script in self.config:
                cat = script["category"]
                if cat not in self.grouped_scripts:
                    self.grouped_scripts[cat] = []
                self.grouped_scripts[cat].append(script)
            logging.info(f"Loaded {len(self.config)} valid items from config")
        except (json.JSONDecodeError, ValueError) as e:
            logging.error(f"Config error: {str(e)}")
            self.script_warnings.append(f"Invalid config.json: {str(e)} - using empty config")
        except Exception as e:
            logging.error(f"Error loading config: {str(e)}")
            self.script_warnings.append(f"Config load error: {str(e)} - using empty config")

    def load_themes(self):
        logging.debug(f"Loading themes from {self.themes_path}")
        self.theme_warnings = []
        if not self.themes_path.exists():
            logging.error(f"Themes file not found: {self.themes_path}")
            self.theme_warnings.append("Themes file missing—using empty themes")
            return
        try:
            with open(self.themes_path, 'r') as f:
                data = json.load(f)
            if not isinstance(data, list):
                raise ValueError("themes.json must be a list of theme entries")
            for entry in data:
                if "name" in entry and "styles" in entry and isinstance(entry["styles"], dict):
                    valid_styles = {}
                    for key, value in entry["styles"].items():
                        if value.startswith('#'):  # Assume it's a color
                            if re.match(r'^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$', value):
                                valid_styles[key] = value
                            else:
                                self.theme_warnings.append(f"Invalid color '{value}' in theme '{entry['name']}' for key '{key}' – skipped")
                        else:
                            valid_styles[key] = value  # Non-color styles pass through
                    if valid_styles:  # Only add if some styles are valid
                        entry["styles"] = valid_styles
                        self.themes.append(entry)
                    else:
                        self.theme_warnings.append(f"Skipped theme '{entry['name']}' – no valid styles")
                else:
                    self.theme_warnings.append(f"Skipped invalid theme: {entry.get('name', 'unnamed')}")
            logging.info(f"Loaded {len(self.themes)} valid themes from themes.json")
        except (json.JSONDecodeError, ValueError) as e:
            logging.error(f"Themes error: {str(e)}")
            self.theme_warnings.append(f"Invalid themes.json: {str(e)} - using empty themes")
        except Exception as e:
            logging.error(f"Error loading themes: {str(e)}")
            self.theme_warnings.append(f"Themes load error: {str(e)} - using empty themes")

    def validate_setup(self):
        logging.debug("Validating setup...")
        if not self.venv_path.exists():
            logging.error(f"Virtual environment not found at {self.venv_path}")
            return f"Virtual environment not found at {self.venv_path}"
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
Comment=Web-based GUI to manage updates for various scripts
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

    def get_backups(self, type):
        if type not in ['pihpsdr', 'saturn']:
            return {"error": "Invalid type"}
        pattern = f"~/{type}-backup-*"
        backups = sorted(glob.glob(os.path.expanduser(pattern)), key=os.path.getmtime, reverse=True)
        backups = [os.path.basename(b) for b in backups]
        return {"backups": backups}

    def run_script(self, filename, flags):
        logging.debug(f"Running script: {filename} with flags: {flags}")
        self.running = True
        self.process = None
        self.backup_response = None
        script_entry = next((s for s in self.config if s["filename"] == filename), None)
        if not script_entry:
            logging.error(f"Script not found in config: {filename}")
            error_msg = f"Error: Script {filename} not found\n"
            yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
            return
        script_path = os.path.join(os.path.expanduser(script_entry["directory"]), filename)
        if not os.path.isfile(script_path):
            logging.error(f"Script path invalid: {script_path}")
            error_msg = f"Error: Script path invalid {script_path}\n"
            yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
            return
        if filename.endswith('.sh'):
            cmd = f"bash {shlex.quote(script_path)} {' '.join(shlex.quote(flag) for flag in flags)}"
            test_cmd = f"bash -n {shlex.quote(script_path)}"
        else:
            cmd = f". {self.venv_path} && python3 {shlex.quote(script_path)} {' '.join(shlex.quote(flag) for flag in flags)} && deactivate"
            test_cmd = f". {self.venv_path} && python3 -m py_compile {shlex.quote(script_path)}"
        logging.info(f"Executing command: {cmd}")

        try:
            # Test script syntax
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
            env["HOME"] = str(Path.home())
            if not filename.endswith('.sh'):
                env["PYTHONPATH"] = f"{str(self.venv_path.parent / 'lib' / 'python3.11' / 'site-packages')}:{env.get('PYTHONPATH', '')}"
            env["LC_ALL"] = "en_US.UTF-8"
            env["TERM"] = env.get("TERM", "dumb")
            logging.debug(f"Environment: {env}")

            self.process = subprocess.Popen(
                cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                stdin=subprocess.PIPE, text=True, bufsize=1, universal_newlines=True, env=env
            )
            logging.debug(f"Started process with PID: {self.process.pid}")
            backup_prompt = re.compile(r'⚠?\s*Backup\? \s*Y/n\s*:?', re.IGNORECASE)
            timeout = 600
            start_time = datetime.now()
            output_buffer = []
            last_heartbeat = time.time()
            while self.process.poll() is None:
                try:
                    if time.time() - last_heartbeat > 5:
                        with self.output_lock:
                            yield "data: <br>\n\n"  # Use <br> for HTML line break
                            logging.debug("Sent heartbeat")
                            sys.stdout.flush()
                        last_heartbeat = time.time()

                    rlist, _, _ = select.select([self.process.stdout, self.process.stderr], [], [], 0.1)
                    for stream in rlist:
                        line = stream.readline()
                        if not line:
                            continue
                        with self.output_lock:
                            clean_line = re.sub(r'\x1B\[[0-?]*[ -/]*[@-~]', '', line)
                            converted_line = self.converter.convert(line.rstrip('\n'), full=False)
                            output_buffer.append(converted_line)

                            if stream == self.process.stdout:
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
                                chunk = "<br>".join(output_buffer)
                                logging.debug(f"Streaming chunk: {chunk}")
                                yield f"data: {chunk}\n\n"
                                sys.stdout.flush()
                                output_buffer = []

                        time.sleep(0.005)
                    if (datetime.now() - start_time).seconds > timeout:
                        logging.error("Script execution timed out")
                        error_msg = f"Error: Script execution timed out after {timeout} seconds\n"
                        yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                        sys.stdout.flush()
                        self.process.terminate()
                        break

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
                    chunk = "<br>".join(output_buffer)
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
                success_msg = f"Completed: Log at ~/saturn-logs/{filename.replace('.py', '').replace('.sh', '')}-*.log"
                with self.output_lock:
                    converted_success = self.converter.convert(success_msg, full=False)
                    yield f"data: {converted_success}\n\n"
                    sys.stdout.flush()
                    logging.info(f"Script {filename} completed successfully with PID {self.process.pid}")
            else:
                error_msg = f"Failed: Check output for errors (return code: {self.process.returncode})\n"
                with self.output_lock:
                    converted_error = self.converter.convert(error_msg, full=False)
                    yield f"data: {converted_error}\n\n"
                    sys.stdout.flush()
                    logging.error(f"Script {filename} failed with return code {self.process.returncode}")
        except Exception as e:
            logging.error(f"Script execution failed: {str(e)}")
            error_msg = f"Error: {str(e)}\n"
            if isinstance(e, urllib.error.URLError):
                error_msg = f"Error: Network failure: {str(e)}. Please check your internet connection and try again.\n"
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

    def get_system_data(self):
        try:
            cpu = psutil.cpu_percent(percpu=True)
            mem = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            net = psutil.net_io_counters()
            processes = []
            for proc in psutil.process_iter(['pid', 'username', 'cpu_percent', 'memory_percent', 'cmdline']):
                try:
                    cmd = ' '.join(proc.info['cmdline']) or '[no command]'
                    processes.append({
                        'pid': proc.info['pid'],
                        'user': proc.info['username'],
                        'cpu': proc.info['cpu_percent'],
                        'memory': proc.info['memory_percent'],
                        'command': cmd
                    })
                except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                    pass
            processes = sorted(processes, key=lambda p: p['cpu'], reverse=True)[:50]
            return {
                'cpu': cpu,
                'memory': {
                    'used': round(mem.used / (1024 ** 3), 2),  # GB
                    'total': round(mem.total / (1024 ** 3), 2),  # GB
                    'percent': mem.percent
                },
                'disk': {
                    'used': round(disk.used / (1024 ** 3), 2),  # GB
                    'total': round(disk.total / (1024 ** 3), 2),  # GB
                    'percent': disk.percent
                },
                'network': {
                    'sent': net.bytes_sent,
                    'recv': net.bytes_recv
                },
                'processes': processes
            }
        except Exception as e:
            logging.error(f"Error fetching system data: {str(e)}")
            return {'error': str(e)}

    def kill_process(self, pid):
        try:
            p = psutil.Process(pid)
            p.terminate()
            p.wait(timeout=3)
            return {'status': 'success', 'message': f'Process {pid} terminated'}
        except psutil.TimeoutExpired:
            p.kill()
            return {'status': 'success', 'message': f'Process {pid} killed'}
        except (psutil.NoSuchProcess, psutil.AccessDenied) as e:
            return {'status': 'error', 'message': str(e)}
        except Exception as e:
            logging.error(f"Error killing process {pid}: {str(e)}")
            return {'status': 'error', 'message': str(e)}

@app.route('/ping')
def ping():
    logging.debug(f"Ping request received, client: {request.remote_addr}, headers: {request.headers}")
    response = Response("pong")
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response

@app.route('/')
def index():
    logging.debug(f"Serving index page, client: {request.remote_addr}, headers: {request.headers}")
    try:
        return render_template('index.html')
    except Exception as e:
        logging.error(f"Error rendering index.html: {str(e)}")
        return f"Error rendering index.html: {str(e)}", 500

@app.route('/get_scripts', methods=['GET'])
def get_scripts():
    logging.debug(f"Fetching available scripts for /get_scripts, client: {request.remote_addr}, headers: {request.headers}")
    response = jsonify({"scripts": app.saturn.grouped_scripts, "warnings": app.saturn.script_warnings})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 200

@app.route('/get_themes', methods=['GET'])
def get_themes():
    logging.debug(f"Fetching available themes for /get_themes, client: {request.remote_addr}, headers: {request.headers}")
    themes = [{"name": t["name"], "description": t.get("description", "")} for t in app.saturn.themes]
    response = jsonify({"themes": themes, "warnings": app.saturn.theme_warnings})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 200

@app.route('/get_theme', methods=['GET'])
def get_theme():
    name = request.args.get('name')
    logging.debug(f"Fetching theme {name} for /get_theme, client: {request.remote_addr}, headers: {request.headers}")
    theme = next((t for t in app.saturn.themes if t["name"] == name), None)
    if theme:
        response = jsonify({"styles": theme["styles"]})
    else:
        response = jsonify({"error": f"Theme not found: {name}"})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 200 if theme else 404

@app.route('/get_versions', methods=['GET'])
def get_versions():
    logging.debug(f"Fetching script versions for /get_versions, client: {request.remote_addr}, headers: {request.headers}")
    versions = app.saturn.get_versions()
    response = jsonify({"versions": versions})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 200

@app.route('/get_flags', methods=['GET'])
def get_flags():
    filename = request.args.get('script')
    logging.debug(f"Fetching flags for script: {filename} on /get_flags, client: {request.remote_addr}, headers: {request.headers}")
    for script in app.saturn.config:
        if script["filename"] == filename:
            logging.info(f"Returning flags for {filename}: {script['flags']}")
            response = jsonify({"flags": script["flags"]})
            response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
            response.headers['Pragma'] = 'no-cache'
            response.headers['Expires'] = '0'
            return response, 200
    logging.warning(f"Invalid script requested: {filename}")
    response = jsonify({"flags": [], "error": f"Invalid script: {filename}"})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 404

@app.route('/get_backups', methods=['GET'])
def get_backups():
    type = request.args.get('type')
    logging.debug(f"Fetching backups for type: {type}")
    backups = app.saturn.get_backups(type)
    status = 200
    if "error" in backups:
        status = 400
    return jsonify(backups), status

@app.route('/run', methods=['POST'])
def run():
    filename = request.form.get('script')
    flags = request.form.getlist('flags')
    backup_dir = request.form.get('backup_dir', '')
    logging.debug(f"Received run request for script: {filename}, flags: {flags}, backup_dir: {backup_dir}")
    if backup_dir:
        flags.append('--backup-dir')
        flags.append(backup_dir)
    if not filename:
        logging.error(f"Invalid script: {filename}")
        error_msg = f"Error: Invalid script {filename}\n"
        response = Response(f"data: {app.saturn.converter.convert(error_msg, full=False)}\n\n", mimetype='text/event-stream', status=400)
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
        response.headers['Content-Type'] = 'text/event-stream; charset=utf-8'
        response.headers['X-Accel-Buffering'] = 'no'
        return response

    def generate():
        try:
            for output in app.saturn.run_script(filename, flags):
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

@app.route('/backup_response', methods=['POST'])
def backup_response():
    response = request.form.get('response')
    logging.debug(f"Received backup response: {response} on /backup_response, client: {request.remote_addr}, headers: {request.headers}")
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

@app.route('/change_password', methods=['POST'])
def change_password():
    new_password = request.form.get('new_password')
    logging.debug(f"Received change password request, client: {request.remote_addr}, headers: {request.headers}")
    result = app.saturn.change_password(new_password)
    response = jsonify(result)
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 200 if result['status'] == 'success' else 400

@app.route('/exit', methods=['POST'])
def exit_app():
    logging.debug(f"Received exit request on /exit, client: {request.remote_addr}, headers: {request.headers}")
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

@app.route('/monitor')
def monitor():
    logging.debug(f"Serving monitor page, client: {request.remote_addr}, headers: {request.headers}")
    try:
        return render_template('monitor.html')
    except Exception as e:
        logging.error(f"Error rendering monitor.html: {str(e)}")
        return f"Error rendering monitor.html: {str(e)}", 500

@app.route('/get_system_data', methods=['GET'])
def get_system_data_route():
    data = app.saturn.get_system_data()
    if 'error' in data:
        return jsonify(data), 500
    return jsonify(data)

@app.route('/kill_process/<int:pid>', methods=['POST'])
def kill_process_route(pid):
    result = app.saturn.kill_process(pid)
    status = 200 if result['status'] == 'success' else 400
    return jsonify(result), status

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
