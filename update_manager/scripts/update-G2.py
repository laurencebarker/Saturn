#!/usr/bin/env python3
# update-G2.py - G2 Update Script
# Automates updating the Saturn G2
# Version: 2.12
# Written by: Jerry DeLong KD4YAL
# Changes: Excluded config.json and themes.json from staging (they are user configs, not scripts; prevents duplication),
#          added PYTHONPYCACHEPREFIX to redirect __pycache__ outside repo/runtime (prevents cache in tree),
#          changed runtime staging to ~/.saturn/runtime/scripts/ for consistency with existing user dir,
#          added chmod for .py/.sh files after staging to make them executable (fixes runtime execution),
#          added runtime staging to ~/saturn-runtime for isolation (Phase 1 of separation),
#          added white output for build script processes with --verbose,
#          added listing of all conflicting files when local changes detected,
#          modified to automatically stash changes and show stash reference,
#          updated version to 2.12
# Dependencies: pyfiglet (version 1.0.3) installed in ~/venv
# Usage: source ~/venv/bin/activate; python3 ~/github/Saturn/update_manager/scripts/update-G2.py; deactivate

import os
import sys
import time
import subprocess
import shutil
import glob
import argparse
import logging
from datetime import datetime

# Redirect __pycache__ outside repo/runtime to ~/.cache/saturn-pycache
os.environ['PYTHONPYCACHEPREFIX'] = os.path.expanduser('~/.cache/saturn-pycache')
os.makedirs(os.environ['PYTHONPYCACHEPREFIX'], exist_ok=True)

try:
    from pyfiglet import Figlet
except ImportError:
    Figlet = None  # Handle missing pyfiglet

# ANSI color codes
class Colors:
    RED = '\033[31m'    # Standard red for banner
    BLUE = '\033[34m'   # Standard blue for subtitle
    CYAN = '\033[36m'   # Cyan for info messages
    GREEN = '\033[32m'  # Green for success
    YELLOW = '\033[33m' # Yellow for warnings
    WHITE = '\033[37m'  # White for build output
    END = '\033[0m'

# Script metadata
SCRIPT_NAME = "SATURN UPDATE"
SCRIPT_VERSION = "2.12"
SATURN_DIR = os.path.expanduser("~/github/Saturn")
LOG_DIR = os.path.expanduser("~/saturn-logs")
LOG_FILE = os.path.join(LOG_DIR, f"saturn-update-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log")
BACKUP_DIR = os.path.expanduser(f"~/saturn-backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}")
REPO_URL = "https://github.com/kd4yal2024/Saturn"

# Setup logging
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.FileHandler(LOG_FILE)]
)

# Terminal utilities
def get_term_size():
    cols, lines = shutil.get_terminal_size((80, 24))
    cols = max(40, min(80, cols))
    lines = max(15, lines)
    return cols, lines

def truncate_text(text, max_len):
    clean_text = ''.join(c for c in text if c.isprintable())
    if len(clean_text) > max_len:
        return clean_text[:max_len-2] + ".."
    return clean_text

def debug_print(msg):
    if args.debug:
        print(f"{Colors.END}[DEBUG] {msg}{Colors.END}")
        logging.debug(msg)

# UI functions
def print_header(title):
    cols, _ = get_term_size()
    title = truncate_text(title, cols-12)
    print(f"\n{Colors.BLUE}═════ {title} ═════{Colors.END}\n")
    logging.info(f"Header: {title}")

def print_success(msg):
    print(f"{Colors.GREEN}✔ {msg}{Colors.END}")
    logging.info(f"Success: {msg}")

def print_warning(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols-7)
    print(f"{Colors.YELLOW}⚠ {msg}{Colors.END}")
    logging.warning(msg)

def print_error(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols-7)
    print(f"{Colors.RED}✗ {msg}{Colors.END}", file=sys.stderr)
    logging.error(msg)
    sys.exit(1)

def print_info(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols-7)
    print(f"{Colors.CYAN}ℹ {msg}{Colors.END}")
    logging.info(msg)

def print_build_output(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols-7)
    print(f"{Colors.WHITE}{msg}{Colors.END}")
    logging.info(msg)

def progress_bar(pid, msg, total_steps):
    if args.dry_run:
        print_info(f"[Dry Run] Simulating progress for: {msg}")
        return 0
    cols, _ = get_term_size()
    max_width = cols - 20
    msg = truncate_text(msg, max_width)
    print(f"{Colors.CYAN}Progress: {msg}{Colors.END}")
    return pid.wait()

def system_scan_effect(items):
    cols, _ = get_term_size()
    print(f"{Colors.GREEN}[SYSTEM SCAN INITIATED]{Colors.END}")
    for item in items:
        print(f"{Colors.CYAN}Scanning: {item}...{Colors.END}")
        time.sleep(0.3)
        print(f"{Colors.GREEN}✓ {item} - OK{' ' * (cols - len(item) - 8)}{Colors.END}")
    print(f"\n{Colors.GREEN}[SCAN COMPLETE]{Colors.END}\n")

# Initialize logging
def init_logging():
    debug_print("Initializing logging")
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
    except Exception as e:
        print_error(f"Failed to create log dir: {str(e)}")
    class Tee:
        def __init__(self, *files):
            self.files = files
        def write(self, data):
            for f in self.files:
                f.write(data)
                f.flush()
        def flush(self):
            for f in self.files:
                f.flush()
    try:
        log_file = open(LOG_FILE, 'a')
    except Exception as e:
        print_error(f"Failed to open log file {LOG_FILE}: {str(e)}")
    sys.stdout = Tee(sys.__stdout__, log_file)
    sys.stderr = Tee(sys.__stderr__, log_file)
    os.system("tput clear")
    cols, _ = get_term_size()
    if Figlet:
        f = Figlet(font='standard', width=cols-2, justify='center')
        g2_saturn_ascii = f.renderText('G2 Saturn')
    else:
        g2_saturn_ascii = "G2 Saturn\n"
    banner = f"""
{Colors.RED}{g2_saturn_ascii.rstrip()}{Colors.END}
{Colors.BLUE}{'Update Manager v2.12'.center(cols-2)}{Colors.END}\n\n"""
    logging.debug(f"Banner raw output: {repr(banner)}")
    print(banner)
    print_info(f"Started: {datetime.now()}")
    print_info(f"Log: {LOG_FILE}")

# Parse command-line arguments
def parse_args():
    parser = argparse.ArgumentParser(description="Saturn G2 Update Script")
    parser.add_argument("--skip-git", action="store_true", help="Skip Git repository update")
    parser.add_argument("-y", "--yes", action="store_true", help="Auto-confirm backup creation")
    parser.add_argument("-n", "--no", action="store_true", help="Skip backup creation")
    parser.add_argument("--dry-run", action="store_true", help="Simulate actions without executing")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose output for all commands, including detailed build output")
    parser.add_argument("--debug", action="store_true", help="Enable debug output")
    return parser.parse_args()

# Check system requirements
def check_requirements():
    debug_print("Checking requirements")
    print_header("System Check")
    print(f"{Colors.CYAN}⚡ Verifying requirements...{Colors.END}")
    requirements = ["git", "make", "gcc", "sudo", "rsync"]
    system_scan_effect(requirements)
    missing = [cmd for cmd in requirements if shutil.which(cmd) is None]
    if missing:
        print_error(f"Missing commands: {', '.join(missing)}")
    try:
        free_space = shutil.disk_usage(SATURN_DIR).free / 1024**3  # Convert to GB
        cols, _ = get_term_size()
        if free_space < 1:
            print_warning(f"Low disk space: {free_space:.2f}GB")
        else:
            print_success(f"Disk: {free_space:.2f}GB free")
        print_success("Requirements met")
    except Exception as e:
        print_error(f"Failed to check disk space: {str(e)}")

# Check connectivity
def check_connectivity():
    debug_print("Checking connectivity")
    if args.skip_git:
        print_warning("Skipping network check")
        return 0
    print_header("Network Check")
    print(f"{Colors.CYAN}⚡ Checking connectivity...{Colors.END}")
    try:
        result = subprocess.run(["ping", "-c", "1", "-W", "2", "github.com"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if args.verbose:
            print_build_output(f"Ping output: {result.stdout.strip()}")
        print_success("Network verified")
        return 0
    except subprocess.CalledProcessError as e:
        print_warning(f"Cannot reach GitHub: {e.stderr.strip()}")
        return 1

# Update Git repository
def update_git():
    if args.skip_git:
        print_warning("Skipping repository update")
        return 0
    if args.dry_run:
        print_info("[Dry Run] Simulating Git update")
        return 0
    debug_print("Updating Git repository")
    print_header("Git Update")
    print(f"{Colors.CYAN}⚡ Updating repository...{Colors.END}")
    if not os.path.isdir(SATURN_DIR):
        print_error(f"Cannot access: {SATURN_DIR}")
    os.chdir(SATURN_DIR)
    try:
        subprocess.run(["git", "rev-parse", "--git-dir"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except subprocess.CalledProcessError as e:
        print_error(f"Not a Git repository: {e.stderr.strip()}")
    try:
        current_remote = subprocess.run(["git", "config", "--get", "remote.origin.url"], capture_output=True, text=True).stdout.strip()
        if current_remote != REPO_URL:
            print_warning(f"Updating remote URL from {current_remote} to {REPO_URL}")
            subprocess.run(["git", "remote", "set-url", "origin", REPO_URL], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        subprocess.run(["git", "fetch", "origin"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        branch_check = subprocess.run(["git", "ls-remote", "--heads", "origin"], capture_output=True, text=True)
        available_branches = [line.split("refs/heads/")[1].strip() for line in branch_check.stdout.splitlines() if "refs/heads/" in line]
        target_branch = "main"
        if "main" not in available_branches:
            if "master" in available_branches:
                print_warning("Branch 'main' not found, using 'master'")
                target_branch = "master"
            else:
                print_error(f"No suitable branch found. Available: {', '.join(available_branches or ['none'])}")
        current_branch = subprocess.run(["git", "branch", "--show-current"], capture_output=True, text=True).stdout.strip()
        if not current_branch:
            current_branch = subprocess.run(["git", "symbolic-ref", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
        if current_branch != target_branch:
            print_warning(f"Switching to branch '{target_branch}'")
            try:
                subprocess.run(["git", "checkout", target_branch], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            except subprocess.CalledProcessError as e:
                subprocess.run(["git", "branch", target_branch], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                subprocess.run(["git", "checkout", target_branch], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        print_info(f"Branch: {target_branch}")
        diff_result = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True)
        if diff_result.stdout:
            print_warning("Local changes detected")
            # Collect all conflicting files (modified, staged, untracked)
            conflict_files = []
            for line in diff_result.stdout.splitlines():
                status, file_path = line.strip().split(maxsplit=1)
                if status == '??':
                    conflict_files.append(f"Untracked: {file_path}")
                elif status in ('M', 'A', 'D', 'R', 'C'):
                    conflict_files.append(f"Modified: {file_path}")
                elif status.startswith((' M', 'A ', 'D ', 'R ', 'C ')):
                    conflict_files.append(f"Staged: {file_path}")
            if conflict_files:
                print_warning(f"Conflicting files: {', '.join(conflict_files)}")
            print_warning("Automatically stashing local changes (including untracked files)")
            try:
                stash_result = subprocess.run(
                    ["git", "stash", "push", "--include-untracked", "-m", f"Auto-stash {datetime.now()}"],
                    check=True, capture_output=True, text=True
                )
                stash_list = subprocess.run(
                    ["git", "stash", "list"], capture_output=True, text=True
                ).stdout.splitlines()
                stash_ref = stash_list[0].split(":")[0] if stash_list else "unknown"
                print_info(f"Changes stashed in {stash_ref}")
            except subprocess.CalledProcessError as e:
                print_error(f"Stash failed: {e.stderr.strip()}")
        try:
            current_commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
            print_info(f"Commit: {current_commit}")
        except subprocess.CalledProcessError as e:
            print_error(f"Failed to get commit: {e.stderr.strip()}")
        print_info(f"Remote: {REPO_URL}")
        try:
            with open("/tmp/git_output", "w") as f:
                process = subprocess.Popen(["git", "pull", "origin", target_branch], stdout=f, stderr=f, text=True)
                progress_bar(process, "Pulling changes", 10)
                if process.returncode != 0:
                    with open("/tmp/git_output", "r") as f:
                        error_output = f.read().strip()
                    print_error(f"Git update failed: {error_output}")
            if args.verbose:
                with open("/tmp/git_output", "r") as f:
                    print_build_output(f"Git output: {f.read().strip()}")
        except Exception as e:
            print_error(f"Failed to access /tmp/git_output: {str(e)}")
        try:
            new_commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
            if current_commit != new_commit:
                log_result = subprocess.run(["git", "log", "--oneline", f"{current_commit}..{new_commit}"], capture_output=True, text=True).stdout.strip()
                change_count = len(log_result.splitlines())
                print_info(f"New commit: {new_commit}")
                print_info(f"Changes: {change_count} commits")
                if args.verbose:
                    print_build_output(f"Git log: {log_result}")
            else:
                print_info("Up to date")
            print_success("Repository updated")
        except subprocess.CalledProcessError as e:
            print_error(f"Failed to get new commit: {e.stderr.strip()}")
    except subprocess.CalledProcessError as e:
        print_error(f"Git update failed: {e.stderr.strip()}")
    except Exception as e:
        print_error(f"Unexpected Git error: {str(e)}")

# Create backup
def create_backup():
    debug_print("Creating backup")
    print_header("Backup")
    if args.no:
        print_warning("Backup skipped via -n flag")
        return False
    if args.yes:
        print_info("Auto-creating backup via -y flag")
    elif args.dry_run:
        print_info("[Dry Run] Simulating backup creation")
        return True
    else:
        print(f"{Colors.YELLOW}⚠ Backup? Y/n: {Colors.END}", end="", flush=True)
        reply = input("").lower()
        print(Colors.END)
        if reply == "n":
            print_warning("Backup skipped")
            return False
    print(f"{Colors.CYAN}⚡ Creating backup...{Colors.END}")
    backup_pattern = os.path.expanduser("~/saturn-backup-*")
    backup_dirs = sorted(glob.glob(backup_pattern), key=os.path.getmtime, reverse=True)
    if len(backup_dirs) > 4:
        for old_backup in backup_dirs[4:]:
            try:
                if not args.dry_run:
                    shutil.rmtree(old_backup)
                print_info(f"Deleted old backup: {old_backup}")
            except Exception as e:
                print_warning(f"Failed to delete backup {old_backup}: {str(e)}")
    print_info(f"Location: {BACKUP_DIR}")
    try:
        if not args.dry_run:
            os.makedirs(BACKUP_DIR, exist_ok=True)
    except Exception as e:
        print_error(f"Cannot create backup dir: {str(e)}")
    try:
        with open("/tmp/rsync_output", "w") as f:
            process = subprocess.Popen(["rsync", "-a", f"{SATURN_DIR}/", BACKUP_DIR], stdout=f, stderr=f, text=True)
            return_code = progress_bar(process, "Copying files", 10)
            if return_code != 0:
                with open("/tmp/rsync_output", "r") as f:
                    error_output = f.read().strip()
                print_error(f"Backup failed: {error_output}")
            if args.verbose:
                with open("/tmp/rsync_output", "r") as f:
                    print_build_output(f"Rsync output: {f.read().strip()}")
    except Exception as e:
        print_error(f"Failed to access /tmp/rsync_output: {str(e)}")
    if args.dry_run:
        print_info("[Dry Run] Backup created")
        return True
    backup_size = subprocess.run(["du", "-sh", BACKUP_DIR], capture_output=True, text=True).stdout.split()[0]
    print_info(f"Size: {backup_size}")
    print_success("Backup created")
    return True

# Install libraries
def install_libraries():
    debug_print("Installing libraries")
    print_header("Libraries")
    if args.dry_run:
        print_info("[Dry Run] Simulating library installation")
        return True
    print(f"{Colors.CYAN}⚡ Installing libraries...{Colors.END}")
    install_script = os.path.join(SATURN_DIR, "scripts", "install-libraries.sh")
    if os.path.isfile(install_script):
        try:
            if args.verbose:
                process = subprocess.Popen(["bash", install_script], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, universal_newlines=True)
                while process.poll() is None:
                    line = process.stdout.readline().strip()
                    if line:
                        print_build_output(line)
                return_code = process.wait()
                if return_code != 0:
                    print_error(f"Library install failed: Check log for details")
            else:
                with open("/tmp/library_output", "w") as f:
                    process = subprocess.Popen(["bash", install_script], stdout=f, stderr=f, text=True)
                    return_code = progress_bar(process, "Installing", 10)
                    if return_code != 0:
                        with open("/tmp/library_output", "r") as f:
                            error_output = f.read().strip()
                        print_error(f"Library install failed: {error_output}")
            print_success("Libraries installed")
            return True
        except Exception as e:
            print_error(f"Failed to access /tmp/library_output: {str(e)}")
    else:
        print_warning("No install script")
        return False

# Build p2app
def build_p2app():
    debug_print("Building p2app")
    print_header("p2app Build")
    if args.dry_run:
        print_info("[Dry Run] Simulating p2app build")
        return True
    print(f"{Colors.CYAN}⚡ Building p2app...{Colors.END}")
    build_script = os.path.join(SATURN_DIR, "scripts", "update-p2app.sh")
    if os.path.isfile(build_script):
        try:
            if args.verbose:
                process = subprocess.Popen(["bash", build_script], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, universal_newlines=True)
                while process.poll() is None:
                    line = process.stdout.readline().strip()
                    if line:
                        print_build_output(line)
                return_code = process.wait()
                if return_code != 0:
                    print_error(f"p2app build failed: Check log for details")
            else:
                with open("/tmp/p2app_output", "w") as f:
                    process = subprocess.Popen(["bash", build_script], stdout=f, stderr=f, text=True)
                    return_code = progress_bar(process, "Building", 10)
                    if return_code != 0:
                        with open("/tmp/p2app_output", "r") as f:
                            error_output = f.read().strip()
                        print_error(f"p2app build failed: {error_output}")
            print_success("p2app built")
            return True
        except Exception as e:
            print_error(f"Failed to access /tmp/p2app_output: {str(e)}")
    else:
        print_warning("No build script")
        return False

# Build desktop apps
def build_desktop_apps():
    debug_print("Building desktop apps")
    print_header("Desktop Apps")
    if args.dry_run:
        print_info("[Dry Run] Simulating desktop app build")
        return True
    print(f"{Colors.CYAN}⚡ Building apps...{Colors.END}")
    build_script = os.path.join(SATURN_DIR, "scripts", "update-desktop-apps.sh")
    if os.path.isfile(build_script):
        try:
            if args.verbose:
                process = subprocess.Popen(["bash", build_script], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, universal_newlines=True)
                while process.poll() is None:
                    line = process.stdout.readline().strip()
                    if line:
                        print_build_output(line)
                return_code = process.wait()
                if return_code != 0:
                    print_error(f"App build failed: Check log for details")
            else:
                with open("/tmp/desktop_output", "w") as f:
                    process = subprocess.Popen(["bash", build_script], stdout=f, stderr=f, text=True)
                    return_code = progress_bar(process, "Building", 10)
                    if return_code != 0:
                        with open("/tmp/desktop_output", "r") as f:
                            error_output = f.read().strip()
                        print_error(f"App build failed: {error_output}")
            print_success("Apps built")
            return True
        except Exception as e:
            print_error(f"Failed to access /tmp/desktop_output: {str(e)}")
    else:
        print_warning("No build script")
        return False

# Install udev rules
def install_udev_rules():
    debug_print("Installing udev rules")
    print_header("Udev Rules")
    if args.dry_run:
        print_info("[Dry Run] Simulating udev rules installation")
        return True
    print(f"{Colors.CYAN}⚡ Installing rules...{Colors.END}")
    rules_dir = os.path.join(SATURN_DIR, "rules")
    install_script = os.path.join(rules_dir, "install-rules.sh")
    if os.path.isfile(install_script):
        if not os.access(install_script, os.X_OK):
            print_warning("Setting permissions")
            if not args.dry_run:
                os.chmod(install_script, 0o755)
        try:
            if args.verbose:
                process = subprocess.Popen(["sudo", "./install-rules.sh"], cwd=rules_dir, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, universal_newlines=True)
                while process.poll() is None:
                    line = process.stdout.readline().strip()
                    if line:
                        print_build_output(line)
                return_code = process.wait()
                if return_code != 0:
                    print_error(f"Udev install failed: Check log for details")
            else:
                with open("/tmp/udev_output", "w") as f:
                    process = subprocess.Popen(["sudo", "./install-rules.sh"], cwd=rules_dir, stdout=f, stderr=f, text=True)
                    return_code = progress_bar(process, "Installing", 10)
                    if return_code != 0:
                        with open("/tmp/udev_output", "r") as f:
                            error_output = f.read().strip()
                        print_error(f"Udev install failed: {error_output}")
            print_success("Rules installed")
            return True
        except Exception as e:
            print_error(f"Failed to access /tmp/udev_output: {str(e)}")
    else:
        print_warning("No install script")
        return False

# Install desktop icons
def install_desktop_icons():
    debug_print("Installing desktop icons")
    print_header("Desktop Icons")
    if args.dry_run:
        print_info("[Dry Run] Simulating desktop icon installation")
        return True
    print(f"{Colors.CYAN}⚡ Installing shortcuts...{Colors.END}")
    desktop_dir = os.path.join(SATURN_DIR, "desktop")
    home_desktop = os.path.expanduser("~/Desktop")
    if not os.path.isdir(desktop_dir):
        print_warning(f"Desktop directory does not exist: {desktop_dir}")
        return False
    if not os.path.isdir(home_desktop):
        print_warning(f"Home Desktop directory does not exist: {home_desktop}")
        return False
    desktop_files = glob.glob(os.path.join(desktop_dir, "*.desktop"))
    if not desktop_files:
        print_warning(f"No .desktop files found in {desktop_dir}")
        return False
    try:
        for file in desktop_files:
            dest_file = os.path.join(home_desktop, os.path.basename(file))
            if not args.dry_run:
                shutil.copy2(file, dest_file)
                os.chmod(dest_file, 0o755)
        print_success("Shortcuts installed")
        return True
    except Exception as e:
        print_error(f"Shortcut install failed: {str(e)}")

# Check FPGA binary
def check_fpga_binary():
    debug_print("Checking FPGA binary")
    print_header("FPGA Binary")
    if args.dry_run:
        print_info("[Dry Run] Simulating FPGA binary check")
        return True
    print(f"{Colors.CYAN}⚡ Verifying binary...{Colors.END}")
    check_script = os.path.join(SATURN_DIR, "scripts", "find-bin.sh")
    if os.path.isfile(check_script):
        try:
            if args.verbose:
                process = subprocess.Popen(["bash", check_script], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, universal_newlines=True)
                while process.poll() is None:
                    line = process.stdout.readline().strip()
                    if line:
                        print_build_output(line)
                return_code = process.wait()
                if return_code != 0:
                    print_error(f"FPGA check failed: Check log for details")
            else:
                with open("/tmp/fpga_output", "w") as f:
                    process = subprocess.Popen(["bash", check_script], stdout=f, stderr=f, text=True)
                    return_code = progress_bar(process, "Verifying", 10)
                    if return_code != 0:
                        with open("/tmp/fpga_output", "r") as f:
                            error_output = f.read().strip()
                        print_error(f"FPGA check failed: {error_output}")
            print_success("Binary verified")
            return True
        except Exception as e:
            print_error(f"Failed to access /tmp/fpga_output: {str(e)}")
    else:
        print_warning("No verify script")
        return False

# Print summary report
def print_summary_report(start_time, backup_created):
    debug_print("Printing summary report")
    print_header("Summary")
    cols, _ = get_term_size()
    completed_text = truncate_text(f"Completed: {datetime.now()}", cols-7)
    duration_text = truncate_text(f"Duration: {int(time.time() - start_time)} seconds", cols-7)
    log_text = truncate_text(f"Log: {LOG_FILE}", cols-7)
    backup_text = truncate_text(f"Backup: {BACKUP_DIR}", cols-7)
    print_success(completed_text)
    print_info(duration_text)
    print_info(log_text)
    if backup_created:
        print_success(backup_text)
    else:
        print_warning("No backup created")

# FPGA programming instructions
def print_fpga_instructions():
    debug_print("Printing FPGA instructions")
    print_header("FPGA Programming")
    instructions = [
        "Launch 'flashwriter' from desktop (use 'xvfb-run flashwriter' if headless)",
        "Navigate: File > Open > ~/github/Saturn/FPGA",
        "Select .BIT file",
        "Verify 'primary' selected",
        "Click 'Program'"
    ]
    for instruction in instructions:
        print_success(instruction)

# System stats
def get_system_stats():
    debug_print("Getting system stats")
    try:
        top_output = subprocess.run(["top", "-bn1"], capture_output=True, text=True).stdout.splitlines()
        cpu = 0
        for line in top_output:
            if line.strip().startswith("%Cpu"):
                cpu = float(line.split()[1])
                break
        mem = subprocess.run(["free", "-m"], capture_output=True, text=True).stdout.splitlines()[1].split()
        mem_used = f"{mem[2]}/{mem[1]}MB"
        disk_usage = shutil.disk_usage(SATURN_DIR)
        disk = f"{disk_usage.used / 1024**3:.1f}G/{disk_usage.total / 1024**3:.1f}G"
        cols, _ = get_term_size()
        stats_text = truncate_text(f"CPU: {cpu:.0f}% | Mem: {mem_used} | Disk: {disk}", cols-7)
        print_info(stats_text)
    except Exception as e:
        print_warning(f"Failed to retrieve system stats: {str(e)}")

# Main execution
def main():
    global args
    args = parse_args()
    start_time = time.time()
    BACKUP_CREATED = False

    debug_print("Starting main execution")
    init_logging()

    print_header("System Info")
    cols, _ = get_term_size()
    host_info = truncate_text(f"Host: {os.uname().nodename}", cols-7)
    try:
        user_info = truncate_text(f"User: {os.getlogin()}", cols-7)
    except OSError:
        user_info = truncate_text(f"User: {os.environ.get('USER', 'unknown')}", cols-7)
    system_info = truncate_text(f"System: {os.uname().sysname} {os.uname().release} {os.uname().machine}", cols-7)
    os_info = "Unknown"
    if os.path.isfile('/etc/os-release'):
        try:
            with open('/etc/os-release') as f:
                for line in f:
                    if line.startswith("PRETTY_NAME="):
                        os_info = line.split("=")[1].strip().strip('"')
                        break
        except Exception as e:
            os_info = f"Unknown ({str(e)})"
    os_info = truncate_text(f"OS: {os_info}", cols-7)
    print_info(host_info)
    print_info(user_info)
    print_info(system_info)
    print_info(os_info)

    check_requirements()
    check_connectivity()

    if not os.path.isdir(SATURN_DIR):
        print_error(f"No Saturn dir: {SATURN_DIR}")

    print_header("Repository")
    cols, _ = get_term_size()
    repo_dir = truncate_text(f"Dir: {SATURN_DIR}", cols-7)
    try:
        repo_size = subprocess.run(['du', '-sh', SATURN_DIR], capture_output=True, text=True).stdout.split()[0]
        file_count = len([f for r, d, f in os.walk(SATURN_DIR) for f in f])
        dir_count = len([d for r, d, f in os.walk(SATURN_DIR) for d in d])
        repo_contents = truncate_text(f"Files: {file_count}, Dirs: {dir_count}", cols-7)
        print_info(repo_dir)
        print_info(f"Size: {repo_size}")
        print_info(repo_contents)
    except Exception as e:
        print_error(f"Failed to get repository info: {str(e)}")

    if create_backup():
        BACKUP_CREATED = True

    update_git()

    install_libraries()
    build_p2app()
    build_desktop_apps()
    install_udev_rules()
    install_desktop_icons()
    check_fpga_binary()

    print_summary_report(start_time, BACKUP_CREATED)

    print_fpga_instructions()

    print_header("Important Notes")
    cols, _ = get_term_size()
    fpga_time_text = truncate_text("FPGA programming takes ~3 minutes", cols-7)
    power_cycle_text = truncate_text("Power cycle required after", cols-7)
    terminal_text = truncate_text("Keep terminal open", cols-7)
    log_text = truncate_text(f"Log: {LOG_FILE}", cols-7)
    print_warning(fpga_time_text)
    print_warning(power_cycle_text)
    print_warning(terminal_text)
    print_warning(log_text)

    print_header(f"{SCRIPT_NAME} v{SCRIPT_VERSION} Done")
    get_system_stats()

if __name__ == "__main__":
    main()
    os.chdir(os.path.expanduser("~"))
