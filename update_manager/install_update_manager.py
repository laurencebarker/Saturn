#!/usr/bin/env python3
# install_update_manager.py - Main installer for Saturn Update Manager
# Version: 3.03
# Written by: Jerry DeLong KD4YAL
# Date: August 11, 2025
# Changes (3.03):
# - Removed hardcoded 'pi' user. Now uses SUDO_USER (or current user if not run via sudo)
#   for: file ownership; paths; systemd service user; runtime directory; desktop shortcut;
#   and service WorkingDirectory.
# - Left behavior & logging unchanged otherwise.

import os
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'  # Disable bytecode cache

import sys
import io
# Force UTF-8 for stdout/stderr to fix UnicodeEncodeError
sys.stdout = io.TextIOWrapper(sys.stdout.detach(), encoding='utf-8', errors='replace')
sys.stderr = io.TextIOWrapper(sys.stderr.detach(), encoding='utf-8', errors='replace')

import argparse
from pathlib import Path
import shutil
import subprocess
import re
from datetime import datetime
import time
import json
import getpass
import pwd
import grp

from modules.logger import setup_logging
from modules.os_detector import detect_os
from modules.dependencies import install_system_deps
from modules.venv_setup import setup_venv
from modules.apache_config import configure_apache
from modules.service_setup import setup_systemd
from modules.verify_executables import verify_executables
from modules.migrate_scripts import migrate_old_scripts

class SaturnInstaller:
    def __init__(self, args):
        self.args = args

        # Resolve target username & home:
        # Use the invoking user when run via sudo; otherwise use the current user.
        self.username = os.environ.get('SUDO_USER') or getpass.getuser()
        self.user_home = Path(os.path.expanduser(f"~{self.username}"))

        self.repo_root = Path(__file__).parent
        self.scripts_source = self.repo_root / "scripts"
        self.templates_source = self.repo_root / "templates"

        self.scripts_dir = self.user_home / "github/Saturn/update_manager/scripts"
        self.config_dir = self.user_home / ".saturn"
        self.templates_dir = self.config_dir / "templates"
        self.log_dir = self.user_home / "saturn-logs"
        self.venv_path = self.user_home / "venv"

        self.htpasswd_file = Path("/etc/apache2/.htpasswd")
        self.apache_conf = Path("/etc/apache2/sites-available/saturn.conf")
        self.systemd_service = Path("/etc/systemd/system/saturn-update-manager.service")
        self.port = 5000
        self.logger = setup_logging(args.verbose, self.log_dir)

        if os.geteuid() != 0:
            self.logger.error("This script must be run with sudo.")
            sys.exit(1)

        if not self.scripts_dir.exists():
            self.logger.error(f"Repo scripts directory not found: {self.scripts_dir}")
            sys.exit(1)

        # Cache uid/gid for ownership
        try:
            pw = pwd.getpwnam(self.username)
            self.uid = pw.pw_uid
            self.gid = pw.pw_gid
        except KeyError:
            self.logger.error(f"User '{self.username}' not found on system.")
            sys.exit(1)

    def run(self):
        self.logger.info("Starting Saturn Update Manager Installer v3.03")

        # Ensure key dirs exist and are owned by the target user
        self.log_dir.mkdir(parents=True, exist_ok=True)
        subprocess.run(["chown", "-R", f"{self.username}:{self.username}", str(self.log_dir)], check=True)

        self.config_dir.mkdir(parents=True, exist_ok=True)
        subprocess.run(["chown", "-R", f"{self.username}:{self.username}", str(self.config_dir)], check=True)

        migrate_old_scripts(self.logger, self.user_home, self.args.dry_run)

        is_buster = detect_os(self.logger, self.args.buster)

        install_system_deps(self.logger, is_buster, self.args.dry_run, autoremove=not self.args.no_autoremove)

        setup_venv(self.logger, is_buster, self.venv_path, self.args.no_clean, self.args.dry_run)
        subprocess.run(["chown", "-R", f"{self.username}:{self.username}", str(self.venv_path)], check=True)

        configure_apache(self.logger, self.htpasswd_file, self.apache_conf, self.port, self.user_home, self.args.dry_run)

        self.copy_files()

        # Stage & verify runtime copies; ensure target ownership
        verify_executables(
            self.logger,
            [self.repo_root / "modules", self.scripts_source],
            self.args.dry_run,
            self.user_home,
            self.username
        )

        # Kill any existing Gunicorn processes before setting up the service
        self.kill_existing_gunicorn()

        setup_systemd(
            self.logger,
            self.systemd_service,
            self.scripts_dir,
            self.venv_path,
            self.port,
            self.log_dir,
            self.args.dry_run,
            self.user_home,
            self.username
        )

        time.sleep(5)  # Wait for service startup
        self.validate()
        ip = self.get_eth0_ip()
        self.logger.info(f"Installation complete. Access via curl -u admin:password123 http://{ip}/saturn/")

    def kill_existing_gunicorn(self):
        self.logger.info("Checking for existing Gunicorn processes...")
        gunicorn_result = subprocess.run(["pgrep", "gunicorn"], capture_output=True, text=True, check=False)
        if gunicorn_result.stdout.strip():
            self.logger.info("Existing Gunicorn processes found. Killing them...")
            if not self.args.dry_run:
                subprocess.run(["pkill", "gunicorn"], check=True)
            self.logger.info("Existing Gunicorn processes killed")
        else:
            self.logger.info("No existing Gunicorn processes found")

    def copy_files(self):
        self.logger.info("Copying customizable files (overwriting with backups for JSON)...")
        if self.args.dry_run:
            self.logger.info("[Dry Run] Skipping file copy")
            return

        self.templates_dir.mkdir(parents=True, exist_ok=True)
        subprocess.run(["chown", "-R", f"{self.username}:{self.username}", str(self.templates_dir)], check=True)
        os.chmod(self.templates_dir, 0o775)

        # Timestamp for backups
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")

        # Configurable JSON files: backup and overwrite
        for file_name in ["config.json", "themes.json"]:
            source = self.scripts_source / file_name
            dest = self.config_dir / file_name
            if source.exists():
                # Backup existing file if it exists
                if dest.exists():
                    backup_dest = self.config_dir / f"{timestamp}-{file_name}"
                    shutil.copy(dest, backup_dest)
                    os.chown(backup_dest, self.uid, self.gid)
                    os.chmod(backup_dest, 0o644)
                    self.logger.info(f"Backed up {file_name} to {backup_dest}")
                # Overwrite with source file
                shutil.copy(source, dest)
                os.chown(dest, self.uid, self.gid)
                os.chmod(dest, 0o644)
                self.logger.info(f"{file_name} overwritten to {dest}")
                # If config.json, update directories to point to runtime
                if file_name == "config.json":
                    with open(dest, 'r+', encoding='utf-8') as f:
                        data = json.load(f)
                        for entry in data:
                            entry["directory"] = "~/.saturn/runtime/scripts"  # Update to runtime
                        f.seek(0)
                        json.dump(data, f, indent=2)
                        f.truncate()
                    self.logger.info("Updated config.json directories to runtime path")
            else:
                self.logger.warning(f"{file_name} not found in repository, skipping")

        # index.html: overwrite
        index_source = self.templates_source / "index.html"
        index_dest = self.templates_dir / "index.html"
        if index_source.exists():
            shutil.copy(index_source, index_dest)
            os.chown(index_dest, self.uid, self.gid)
            os.chmod(index_dest, 0o644)
            self.logger.info(f"index.html overwritten to {index_dest}")
        else:
            self.logger.warning(f"index.html not found in repository, skipping")

        # monitor.html: overwrite (if present)
        monitor_source = self.templates_source / "monitor.html"
        monitor_dest = self.templates_dir / "monitor.html"
        if monitor_source.exists():
            shutil.copy(monitor_source, monitor_dest)
            os.chown(monitor_dest, self.uid, self.gid)
            os.chmod(monitor_dest, 0o644)
            self.logger.info(f"monitor.html overwritten to {monitor_dest}")
        else:
            self.logger.warning(f"monitor.html not found in repository, skipping")

        # Copy SaturnUpdateManager.desktop (overwrite) to the target user's Desktop
        desktop_source = self.templates_source / "SaturnUpdateManager.desktop"
        desktop_dest = self.user_home / "Desktop" / "SaturnUpdateManager.desktop"
        if desktop_source.exists():
            desktop_dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(desktop_source, desktop_dest)
            os.chown(desktop_dest, self.uid, self.gid)
            os.chmod(desktop_dest, 0o755)
            self.logger.info("SaturnUpdateManager.desktop copied to Desktop")
        else:
            self.logger.warning("SaturnUpdateManager.desktop not found in repository, skipping")

        self.logger.info("File setup complete")

    def get_eth0_ip(self):
        result = subprocess.run(["ip", "addr", "show", "eth0"], capture_output=True, text=True)
        match = re.search(r'inet (\d+\.\d+\.\d+\.\d+)', result.stdout)
        if match:
            return match.group(1)
        return "localhost"

    def validate(self):
        self.logger.info("Validating installation...")
        # Check Apache status
        apache_result = subprocess.run(["systemctl", "status", "apache2"], capture_output=True, text=True, check=False)
        if "active (running)" in apache_result.stdout:
            self.logger.info("Apache status - PASS")
        else:
            self.logger.error("Apache status - FAIL")

        # Check Gunicorn running
        gunicorn_result = subprocess.run(["pgrep", "gunicorn"], capture_output=True, text=True, check=False)
        if gunicorn_result.stdout.strip():
            self.logger.info("Gunicorn running - PASS")
        else:
            self.logger.error("Gunicorn running - FAIL")

        # Check endpoint with curl and display output only on error
        self.logger.info("Testing web server availability with curl...")
        curl_result = subprocess.run(
            ["curl", "-u", "admin:password123", "http://localhost/saturn/"],
            capture_output=True, text=True, check=False
        )
        if "Saturn Update Manager" in curl_result.stdout:
            self.logger.info("Endpoint test - PASS")
        else:
            self.logger.info("Retrying endpoint test after 5 seconds...")
            time.sleep(5)
            curl_result = subprocess.run(
                ["curl", "-u", "admin:password123", "http://localhost/saturn/"],
                capture_output=True, text=True, check=False
            )
            if "Saturn Update Manager" in curl_result.stdout:
                self.logger.info("Endpoint test - PASS (on retry)")
            else:
                print(curl_result.stdout)
                self.logger.error("Endpoint test - FAIL")
                if curl_result.stderr:
                    self.logger.error(f"Curl error: {curl_result.stderr}")

def main():
    parser = argparse.ArgumentParser(description="Install Saturn Update Manager")
    parser.add_argument("--dry-run", action="store_true", help="Simulate actions without making changes")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose logging")
    parser.add_argument("--buster", action="store_true", help="Force Debian Buster compatibility")
    parser.add_argument("--no-clean", action="store_true", help="Do not remove/clean existing virtualenv before setup")
    parser.add_argument("--no-autoremove", action="store_true", help="Skip apt-get autoremove after install")
    args = parser.parse_args()

    installer = SaturnInstaller(args)
    installer.run()

if __name__ == "__main__":
    main()
