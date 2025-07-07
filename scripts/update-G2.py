#!/usr/bin/env python3

import os
import sys
import time
import subprocess
import shutil
import glob
from datetime import datetime

# ANSI color codes
RED = '\033[1;31m'
GREEN = '\033[1;32m'
YELLOW = '\033[1;33m'
BLUE = '\033[1;34m'
CYAN = '\033[1;36m'
PURPLE = '\033[1;35m'
DIM_CYAN = '\033[48;5;24m'  # Background cyan for headers
NC = '\033[0m'
BOLD = '\033[1m'
RESET = '\033[0m'

# Script metadata
SCRIPT_NAME = "Saturn Update"
SCRIPT_VERSION = "2.1"
SATURN_DIR = os.path.expanduser("~/github/Saturn")
LOG_DIR = os.path.expanduser("~/saturn-logs")
LOG_FILE = os.path.join(LOG_DIR, f"saturn-update-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log")
BACKUP_DIR = os.path.expanduser(f"~/saturn-backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}")
REPO_URL = "https://github.com/kd4yal2024/Saturn"

# Flags
SKIP_GIT = False
DEBUG = False

# Terminal utilities
def get_term_size():
    cols, lines = shutil.get_terminal_size((80, 24))
    cols = max(20, min(80, cols))
    lines = max(8, lines)
    return cols, lines

def is_minimal_mode():
    cols, lines = get_term_size()
    return cols < 40 or lines < 15

def truncate_text(text, max_len):
    clean_text = ''.join(c for c in text if c.isprintable())
    if len(clean_text) > max_len:
        return text[:max_len-2] + ".."
    return text

def debug_print(msg):
    if DEBUG:
        print(f"\033[0m[DEBUG] {msg}\033[0m")

def draw_double_line_top():
    cols, _ = get_term_size()
    print(f"\033[0m╔{'═' * (cols-2)}╗\033[0m")

def draw_double_line_bottom():
    cols, _ = get_term_size()
    print(f"\033[0m╚{'═' * (cols-2)}╝\033[0m")

def draw_transition():
    if is_minimal_mode():
        return
    cols, _ = get_term_size()
    for _ in range(3):
        print(f"\r{CYAN}{'.' * cols}\033[0m", end="", flush=True)
        time.sleep(0.1)
        print(f"\r{' ' * cols}\033[0m", end="", flush=True)
        time.sleep(0.1)
    print("\033[0m")

def progress_bar(pid, msg, total_steps):
    cols, _ = get_term_size()
    max_width = cols - 20
    msg = truncate_text(msg, max_width)
    bar_width = cols - 20
    step = 0
    os.system("tput civis")
    while pid.poll() is None:
        step += 1
        percent = min(100, (step * 100) // total_steps)
        filled = (bar_width * percent) // 100
        empty = bar_width - filled
        bar = "█" * filled + " " * empty
        print(f"\r{BLUE}[{bar}] {percent:2d}% {msg}\033[0m", end="", flush=True)
        time.sleep(0.5)
    print(f"\033[2K\r{' ' * cols}\033[0m\033[0G", end="", flush=True)  # Clear line and reset cursor
    debug_print("Progress bar completed, cursor reset")
    os.system("tput cnorm")
    return pid.wait()

def render_section(title):
    cols, _ = get_term_size()
    title = truncate_text(title, cols-4)
    debug_print(f"Rendering section: {title}")
    print("\033[0m", end="")
    draw_double_line_top()
    print(f"\033[0m{CYAN}{BOLD}{DIM_CYAN}{' ' * ((cols - len(title) - 2) // 2)}{title}{' ' * ((cols - len(title) - 2) // 2)}\033[0m")
    draw_double_line_bottom()
    print("\033[0m", end="")
    draw_transition()

def render_top_section(title):
    cols, _ = get_term_size()
    title = truncate_text(title, cols-4)
    debug_print(f"Rendering top section: {title}")
    print("\033[0m", end="")
    draw_double_line_top()
    print(f"\033[0m{CYAN}{BOLD}{DIM_CYAN}{' ' * ((cols - len(title) - 2) // 2)}{title}{' ' * ((cols - len(title) - 2) // 2)}\033[0m")
    draw_double_line_bottom()
    print("\033[0m", end="")
    draw_transition()

def completion_animation():
    if is_minimal_mode():
        return
    cols, _ = get_term_size()
    for _ in range(3):
        print(f"\r{GREEN}{'✔' * cols}\033[0m", end="", flush=True)
        time.sleep(0.1)
        print(f"\r{' ' * cols}\033[0m", end="", flush=True)
        time.sleep(0.1)
    print(f"{GREEN}✔ Complete!\033[0m")

# Status reporting
def status_start(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols-7)
    if is_minimal_mode():
        print(f"{PURPLE}> {msg}\033[0m")
    else:
        print(f"{PURPLE}{BOLD}⏳ {msg}\033[0m")
    print("\033[0m", end="")

def status_success(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols-7)
    if is_minimal_mode():
        print(f"{GREEN}  + {msg}\033[0m")
    else:
        print(f"{GREEN}  ✔ {msg}\033[0m")
    print("\033[0m", end="")

def status_warning(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols-7)
    if is_minimal_mode():
        print(f"{YELLOW}  ! {msg}\033[0m")
    else:
        print(f"{YELLOW}  ⚠ {msg}\033[0m")
    print("\033[0m", end="")

def status_error(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols-7)
    print(f"{RED}  ✗ {msg}\033[0m", file=sys.stderr)
    print("\033[0m", end="")
    draw_double_line_bottom()
    sys.exit(1)

# Initialize logging
def init_logging():
    debug_print("Initializing logging")
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
    except Exception as e:
        status_error(f"Failed to create log dir: {str(e)}")
    # Use Tee to write to both terminal and log file
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
        status_error(f"Failed to open log file {LOG_FILE}: {str(e)}")
    sys.stdout = Tee(sys.__stdout__, log_file)
    sys.stderr = Tee(sys.__stderr__, log_file)
    os.system("tput clear")  # Clear screen at start
    debug_print("Rendering top section")
    render_top_section(f"{SCRIPT_NAME} v{SCRIPT_VERSION}")
    cols, _ = get_term_size()
    if is_minimal_mode():
        print(f"{BLUE}  > {truncate_text(f'Started: {datetime.now()}', cols-2)}\033[0m")
        print(f"{BLUE}  > {truncate_text(f'Log: {LOG_FILE}', cols-2)}\033[0m")
    else:
        print(f"{BLUE}  ℹ {truncate_text(f'Started: {datetime.now()}', cols-3)}\033[0m")
        print(f"{BLUE}  ℹ {truncate_text(f'Log: {LOG_FILE}', cols-3)}\033[0m")
    print("\033[0m", end="")

# Parse command-line arguments
def parse_args(args):
    global SKIP_GIT, DEBUG
    debug_print("Parsing arguments")
    for arg in args:
        if arg == "--skip-git":
            SKIP_GIT = True
            status_warning("Skipping Git update")
        if arg == "--debug":
            DEBUG = True
            debug_print("Debug mode enabled")

# Check system requirements
def check_requirements():
    debug_print("Checking requirements")
    render_section("System Check")
    status_start("Verifying requirements")
    missing = [cmd for cmd in ["git", "make", "gcc", "sudo", "rsync"] if shutil.which(cmd) is None]
    if missing:
        status_error(f"Missing commands: {', '.join(missing)}")
    try:
        free_space = shutil.disk_usage(SATURN_DIR).free
        cols, _ = get_term_size()
        if free_space < 1048576:
            status_warning(f"Low disk space: {free_space // 1024}MB")
        else:
            if is_minimal_mode():
                print(f"{GREEN}  + {truncate_text(f'Disk: {free_space // 1024}MB free', cols-2)}\033[0m")
            else:
                print(f"{GREEN}  ✔ {truncate_text(f'Disk: {free_space // 1024}MB free', cols-3)}\033[0m")
        status_success("Requirements met")
    except Exception as e:
        status_error(f"Failed to check disk space: {str(e)}")

# Check connectivity
def check_connectivity():
    debug_print("Checking connectivity")
    if SKIP_GIT:
        status_warning("Skipping network check")
        return 0
    render_section("Network Check")
    status_start("Checking connectivity")
    try:
        subprocess.run(["ping", "-c", "1", "-W", "2", "github.com"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        status_success("Network verified")
        return 0
    except subprocess.CalledProcessError as e:
        status_warning(f"Cannot reach GitHub: {e.stderr.strip()}")
        return 1

# Update Git repository
def update_git():
    if SKIP_GIT:
        status_warning("Skipping repository update")
        return 0
    debug_print("Updating Git repository")
    render_section("Git Update")
    status_start("Updating repository")
    if not os.path.isdir(SATURN_DIR):
        status_error(f"Cannot access: {SATURN_DIR}")
    os.chdir(SATURN_DIR)
    try:
        subprocess.run(["git", "rev-parse", "--git-dir"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except subprocess.CalledProcessError as e:
        status_error(f"Not a Git repository: {e.stderr.strip()}")
    try:
        # Check and set remote URL
        current_remote = subprocess.run(["git", "config", "--get", "remote.origin.url"], capture_output=True, text=True).stdout.strip()
        if current_remote != REPO_URL:
            status_warning(f"Updating remote URL from {current_remote} to {REPO_URL}")
            subprocess.run(["git", "remote", "set-url", "origin", REPO_URL], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        # Check available branches
        subprocess.run(["git", "fetch", "origin"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        branch_check = subprocess.run(["git", "ls-remote", "--heads", "origin"], capture_output=True, text=True)
        available_branches = [line.split("refs/heads/")[1].strip() for line in branch_check.stdout.splitlines() if "refs/heads/" in line]
        target_branch = "main"
        if "main" not in available_branches:
            if "master" in available_branches:
                status_warning("Branch 'main' not found, using 'master'")
                target_branch = "master"
            else:
                status_error(f"No suitable branch found. Available: {', '.join(available_branches or ['none'])}")
        # Ensure local branch is 'main'
        current_branch = subprocess.run(["git", "branch", "--show-current"], capture_output=True, text=True).stdout.strip()
        if not current_branch:
            current_branch = subprocess.run(["git", "symbolic-ref", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
        if current_branch != target_branch:
            status_warning(f"Switching to branch '{target_branch}'")
            try:
                subprocess.run(["git", "checkout", target_branch], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            except subprocess.CalledProcessError as e:
                subprocess.run(["git", "branch", target_branch], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                subprocess.run(["git", "checkout", target_branch], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        cols, _ = get_term_size()
        if is_minimal_mode():
            print(f"{BLUE}  > {truncate_text(f'Branch: {target_branch}', cols-2)}\033[0m")
        else:
            print(f"{BLUE}  ℹ {truncate_text(f'Branch: {target_branch}', cols-3)}\033[0m")
        # Check for local changes (tracked and untracked)
        diff_result = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True)
        untracked_files = [line.strip().split()[1] for line in diff_result.stdout.splitlines() if line.startswith("??")]
        if diff_result.stdout:
            status_warning("Local changes detected")
            if untracked_files:
                untracked_text = f"Untracked files: {', '.join(untracked_files)}"
                if is_minimal_mode():
                    print(f"{YELLOW}  > {truncate_text(untracked_text, cols-2)}\033[0m")
                else:
                    print(f"{YELLOW}  ⚠ {truncate_text(untracked_text, cols-3)}\033[0m")
            print(f"{YELLOW}  ⚠ Stash changes or reset to remote? [S/r/n]: \033[0m", end="", flush=True)
            reply = input("").lower()
            print("\033[0m")
            if reply == "r":
                status_warning("Resetting to remote state (discards local changes)")
                try:
                    subprocess.run(["git", "reset", "--hard", f"origin/{target_branch}"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    subprocess.run(["git", "clean", "-fd"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    if is_minimal_mode():
                        print(f"{BLUE}  > {truncate_text(f'Reset to origin/{target_branch}', cols-2)}\033[0m")
                    else:
                        print(f"{BLUE}  ℹ {truncate_text(f'Reset to origin/{target_branch}', cols-3)}\033[0m")
                except subprocess.CalledProcessError as e:
                    status_error(f"Reset failed: {e.stderr.strip()}")
            elif reply != "n":
                status_warning("Stashing local changes (including untracked files)")
                try:
                    stash_result = subprocess.run(["git", "stash", "push", "--include-untracked", "-m", f"Auto-stash {datetime.now()}"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    if is_minimal_mode():
                        print(f"{BLUE}  > {truncate_text('Changes stashed successfully', cols-2)}\033[0m")
                    else:
                        print(f"{BLUE}  ℹ {truncate_text('Changes stashed successfully', cols-3)}\033[0m")
                except subprocess.CalledProcessError as e:
                    status_error(f"Stash failed: {e.stderr.strip()}")
            else:
                status_warning("Skipping Git update due to local changes")
                return 0
        # Get current commit
        try:
            current_commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
            if is_minimal_mode():
                print(f"{BLUE}  > {truncate_text(f'Commit: {current_commit}', cols-2)}\033[0m")
            else:
                print(f"{BLUE}  ℹ {truncate_text(f'Commit: {current_commit}', cols-3)}\033[0m")
        except subprocess.CalledProcessError as e:
            status_error(f"Failed to get commit: {e.stderr.strip()}")
        # Display remote URL
        if is_minimal_mode():
            print(f"{BLUE}  > {truncate_text(f'Remote: {REPO_URL}', cols-2)}\033[0m")
        else:
            print(f"{BLUE}  ℹ {truncate_text(f'Remote: {REPO_URL}', cols-3)}\033[0m")
        # Perform git pull
        try:
            with open("/tmp/git_output", "w") as f:
                process = subprocess.Popen(["git", "pull", "origin", target_branch], stdout=f, stderr=f, text=True)
                progress_bar(process, "Pulling changes", 10)
                process.wait()
                if process.returncode != 0:
                    with open("/tmp/git_output", "r") as f:
                        error_output = f.read().strip()
                    status_error(f"Git update failed: {error_output}")
        except Exception as e:
            status_error(f"Failed to access /tmp/git_output: {str(e)}")
        # Check for new commits
        try:
            new_commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
            if current_commit != new_commit:
                log_result = subprocess.run(["git", "log", "--oneline", f"{current_commit}..{new_commit}"], capture_output=True, text=True).stdout.strip()
                change_count = len(log_result.splitlines())
                if is_minimal_mode():
                    print(f"{BLUE}  > {truncate_text(f'New commit: {new_commit}', cols-2)}\033[0m")
                    print(f"{BLUE}  > {truncate_text(f'Changes: {change_count} commits', cols-2)}\033[0m")
                else:
                    print(f"{BLUE}  ℹ {truncate_text(f'New commit: {new_commit}', cols-3)}\033[0m")
                    print(f"{BLUE}  ℹ {truncate_text(f'Changes: {change_count} commits', cols-3)}\033[0m")
            else:
                if is_minimal_mode():
                    print(f"{BLUE}  > Up to date\033[0m")
                else:
                    print(f"{BLUE}  ℹ Up to date\033[0m")
            status_success("Repository updated")
        except subprocess.CalledProcessError as e:
            status_error(f"Failed to get new commit: {e.stderr.strip()}")
    except subprocess.CalledProcessError as e:
        status_error(f"Git update failed: {e.stderr.strip()}")
    except Exception as e:
        status_error(f"Unexpected Git error: {str(e)}")

# Create backup
def create_backup():
    debug_print("Creating backup")
    render_section("Backup")
    cols, _ = get_term_size()
    if is_minimal_mode():
        print(f"{YELLOW}  > Backup? [{BOLD}Y{RESET}/n]: \033[0m", end="", flush=True)
    else:
        print(f"{YELLOW}  ⚠ Backup? [{BOLD}Y{RESET}/n]: \033[0m", end="", flush=True)
    reply = input("").lower()
    print("\033[0m")
    if reply != "n":
        status_start("Creating backup")
        # Limit to 5 backups
        backup_pattern = os.path.expanduser("~/saturn-backup-*")
        backup_dirs = sorted(glob.glob(backup_pattern), key=os.path.getmtime, reverse=True)
        if len(backup_dirs) > 4:
            for old_backup in backup_dirs[4:]:
                try:
                    shutil.rmtree(old_backup)
                    print(f"{BLUE}  ℹ {truncate_text(f'Deleted old backup: {old_backup}', cols-3)}\033[0m")
                except Exception as e:
                    print(f"{YELLOW}  ⚠ {truncate_text(f'Failed to delete backup {old_backup}: {str(e)}', cols-3)}\033[0m")
        if is_minimal_mode():
            print(f"{BLUE}  > {truncate_text(f'Location: {BACKUP_DIR}', cols-2)}\033[0m")
        else:
            print(f"{BLUE}  ℹ {truncate_text(f'Location: {BACKUP_DIR}', cols-3)}\033[0m")
        try:
            os.makedirs(BACKUP_DIR, exist_ok=True)
        except Exception as e:
            status_error(f"Cannot create backup dir: {str(e)}")
        try:
            with open("/tmp/rsync_output", "w") as f:
                process = subprocess.Popen(["rsync", "-a", f"{SATURN_DIR}/", BACKUP_DIR], stdout=f, stderr=f, text=True)
                progress_bar(process, "Copying files", 10)
                process.wait()
                if process.returncode != 0:
                    with open("/tmp/rsync_output", "r") as f:
                        error_output = f.read().strip()
                    status_error(f"Backup failed: {error_output}")
        except Exception as e:
            status_error(f"Failed to access /tmp/rsync_output: {str(e)}")
        backup_size = subprocess.run(["du", "-sh", BACKUP_DIR], capture_output=True, text=True).stdout.split()[0]
        if is_minimal_mode():
            print(f"{BLUE}  > {truncate_text(f'Size: {backup_size}', cols-2)}\033[0m")
        else:
            print(f"{BLUE}  ℹ {truncate_text(f'Size: {backup_size}', cols-3)}\033[0m")
        status_success("Backup created")
        return True
    else:
        status_warning("Backup skipped")
        return False

# Install libraries
def install_libraries():
    debug_print("Installing libraries")
    render_section("Libraries")
    status_start("Installing libraries")
    install_script = os.path.join(SATURN_DIR, "scripts", "install-libraries.sh")
    if os.path.isfile(install_script):
        try:
            with open("/tmp/library_output", "w") as f:
                process = subprocess.Popen(["bash", install_script], stdout=f, stderr=f, text=True)
                progress_bar(process, "Installing", 10)
                process.wait()
                if process.returncode != 0:
                    with open("/tmp/library_output", "r") as f:
                        error_output = f.read().strip()
                    status_error(f"Library install failed: {error_output}")
            status_success("Libraries installed")
        except Exception as e:
            status_error(f"Failed to access /tmp/library_output: {str(e)}")
    else:
        status_warning("No install script")

# Build p2app
def build_p2app():
    debug_print("Building p2app")
    render_section("p2app Build")
    status_start("Building p2app")
    build_script = os.path.join(SATURN_DIR, "scripts", "update-p2app.sh")
    if os.path.isfile(build_script):
        try:
            with open("/tmp/p2app_output", "w") as f:
                process = subprocess.Popen(["bash", build_script], stdout=f, stderr=f, text=True)
                progress_bar(process, "Building", 10)
                process.wait()
                if process.returncode != 0:
                    with open("/tmp/p2app_output", "r") as f:
                        error_output = f.read().strip()
                    status_error(f"p2app build failed: {error_output}")
            status_success("p2app built")
        except Exception as e:
            status_error(f"Failed to access /tmp/p2app_output: {str(e)}")
    else:
        status_warning("No build script")

# Build desktop apps
def build_desktop_apps():
    debug_print("Building desktop apps")
    render_section("Desktop Apps")
    status_start("Building apps")
    build_script = os.path.join(SATURN_DIR, "scripts", "update-desktop-apps.sh")
    if os.path.isfile(build_script):
        try:
            with open("/tmp/desktop_output", "w") as f:
                process = subprocess.Popen(["bash", build_script], stdout=f, stderr=f, text=True)
                progress_bar(process, "Building", 10)
                process.wait()
                if process.returncode != 0:
                    with open("/tmp/desktop_output", "r") as f:
                        error_output = f.read().strip()
                    status_error(f"App build failed: {error_output}")
            status_success("Apps built")
        except Exception as e:
            status_error(f"Failed to access /tmp/desktop_output: {str(e)}")
    else:
        status_warning("No build script")

# Install udev rules
def install_udev_rules():
    debug_print("Installing udev rules")
    render_section("Udev Rules")
    status_start("Installing rules")
    rules_dir = os.path.join(SATURN_DIR, "rules")
    install_script = os.path.join(rules_dir, "install-rules.sh")
    if os.path.isfile(install_script):
        if not os.access(install_script, os.X_OK):
            status_warning("Setting permissions")
            os.chmod(install_script, 0o755)
        try:
            with open("/tmp/udev_output", "w") as f:
                process = subprocess.Popen(["sudo", "./install-rules.sh"], cwd=rules_dir, stdout=f, stderr=f, text=True)
                progress_bar(process, "Installing", 10)
                process.wait()
                if process.returncode != 0:
                    with open("/tmp/udev_output", "r") as f:
                        error_output = f.read().strip()
                    status_error(f"Udev install failed: {error_output}")
            status_success("Rules installed")
        except Exception as e:
            status_error(f"Failed to access /tmp/udev_output: {str(e)}")
    else:
        status_warning("No install script")

# Install desktop icons
def install_desktop_icons():
    debug_print("Installing desktop icons")
    render_section("Desktop Icons")
    status_start("Installing shortcuts")
    desktop_dir = os.path.join(SATURN_DIR, "desktop")
    home_desktop = os.path.expanduser("~/Desktop")
    if not os.path.isdir(desktop_dir):
        status_warning(f"Desktop directory does not exist: {desktop_dir}")
        return
    if not os.path.isdir(home_desktop):
        status_warning(f"Home Desktop directory does not exist: {home_desktop}")
        return
    desktop_files = glob.glob(os.path.join(desktop_dir, "*.desktop"))
    if not desktop_files:
        status_warning(f"No .desktop files found in {desktop_dir}")
        return
    try:
        for file in desktop_files:
            dest_file = os.path.join(home_desktop, os.path.basename(file))
            shutil.copy2(file, dest_file)
            os.chmod(dest_file, 0o755)
        status_success("Shortcuts installed")
    except Exception as e:
        status_error(f"Shortcut install failed: {str(e)}")

# Check FPGA binary
def check_fpga_binary():
    debug_print("Checking FPGA binary")
    render_section("FPGA Binary")
    status_start("Verifying binary")
    check_script = os.path.join(SATURN_DIR, "scripts", "find-bin.sh")
    if os.path.isfile(check_script):
        try:
            with open("/tmp/fpga_output", "w") as f:
                process = subprocess.Popen(["bash", check_script], stdout=f, stderr=f, text=True)
                progress_bar(process, "Verifying", 10)
                process.wait()
                if process.returncode != 0:
                    with open("/tmp/fpga_output", "r") as f:
                        error_output = f.read().strip()
                    status_error(f"FPGA check failed: {error_output}")
            status_success("Binary verified")
        except Exception as e:
            status_error(f"Failed to access /tmp/fpga_output: {str(e)}")
    else:
        status_warning("No verify script")

# Print summary report
def print_summary_report(start_time, backup_created):
    debug_print("Printing summary report")
    duration = int(time.time() - start_time)
    render_section("Summary")
    cols, _ = get_term_size()
    completed_text = truncate_text(f"Completed: {datetime.now()}", cols-3)
    duration_text = truncate_text(f"Duration: {duration} seconds", cols-3)
    log_text = truncate_text(f"Log: {LOG_FILE}", cols-3)
    backup_text = truncate_text(f"Backup: {BACKUP_DIR}", cols-3)
    if is_minimal_mode():
        print(f"{GREEN}  + {completed_text}\033[0m")
        print(f"{BLUE}  > {duration_text}\033[0m")
        print(f"{BLUE}  > {log_text}\033[0m")
        if backup_created:
            print(f"{GREEN}  + {backup_text}\033[0m")
        else:
            status_warning("No backup created")
    else:
        print(f"{GREEN}  ✔ {completed_text}\033[0m")
        print(f"{BLUE}  ℹ {duration_text}\033[0m")
        print(f"{BLUE}  ℹ {log_text}\033[0m")
        if backup_created:
            print(f"{GREEN}  ✔ {backup_text}\033[0m")
        else:
            status_warning("No backup created")
    print("\033[0m", end="")

# System stats for footer
def get_system_stats():
    debug_print("Getting system stats")
    if is_minimal_mode():
        return
    try:
        cpu = int(subprocess.run(["top", "-bn1"], capture_output=True, text=True).stdout.splitlines()[2].split()[1].split('.')[0])
        mem = subprocess.run(["free", "-m"], capture_output=True, text=True).stdout.splitlines()[1].split()[2] + "/" + subprocess.run(["free", "-m"], capture_output=True, text=True).stdout.splitlines()[1].split()[1] + "MB"
        disk_usage = shutil.disk_usage(SATURN_DIR)
        disk = f"{disk_usage.used / 1024**3:.1f}G/{disk_usage.total / 1024**3:.1f}G"
        cols, _ = get_term_size()
        stats_text = truncate_text(f"CPU: {cpu}% | Mem: {mem} | Disk: {disk}", cols-3)
        print(f"{BLUE}  ℹ {stats_text}\033[0m")
    except Exception as e:
        print(f"{YELLOW}  ⚠ Failed to retrieve system stats: {str(e)}\033[0m")

# Main execution
def main(args):
    start_time = time.time()
    BACKUP_CREATED = False

    debug_print("Starting main execution")
    init_logging()
    parse_args(args)

    render_section("System Info")
    cols, _ = get_term_size()
    host_info = truncate_text(f"Host: {os.uname().nodename}", cols-3)
    try:
        user_info = truncate_text(f"User: {os.getlogin()}", cols-3)
    except OSError:
        user_info = truncate_text(f"User: {os.environ.get('USER', 'unknown')}", cols-3)
    system_info = truncate_text(f"System: {os.uname().sysname} {os.uname().release} {os.uname().machine}", cols-3)
    if os.path.isfile('/etc/os-release'):
        try:
            with open('/etc/os-release') as f:
                for line in f:
                    if line.startswith("PRETTY_NAME="):
                        os_info = line.split("=")[1].strip().strip('"')
                        break
                else:
                    os_info = "Unknown"
        except Exception as e:
            os_info = f"Unknown ({str(e)})"
    else:
        os_info = "Unknown"
    os_info = truncate_text(f"OS: {os_info}", cols-3)
    if is_minimal_mode():
        print(f"{BLUE}  > {host_info}\033[0m")
        print(f"{BLUE}  > {user_info}\033[0m")
        print(f"{BLUE}  > {system_info}\033[0m")
        print(f"{BLUE}  > {os_info}\033[0m")
    else:
        print(f"{BLUE}  ℹ {host_info}\033[0m")
        print(f"{BLUE}  ℹ {user_info}\033[0m")
        print(f"{BLUE}  ℹ {system_info}\033[0m")
        print(f"{BLUE}  ℹ {os_info}\033[0m")
    print("\033[0m", end="")

    check_requirements()
    check_connectivity()

    if not os.path.isdir(SATURN_DIR):
        status_error(f"No Saturn dir: {SATURN_DIR}")

    render_section("Repository")
    cols, _ = get_term_size()
    repo_dir = truncate_text(f"Dir: {SATURN_DIR}", cols-3)
    try:
        repo_size = truncate_text(f"Size: {subprocess.run(['du', '-sh', SATURN_DIR], capture_output=True, text=True).stdout.split()[0]}", cols-3)
        repo_contents = truncate_text(f"Files: {len([f for f in os.walk(SATURN_DIR) if f[2]])}, Dirs: {len([d for d in os.walk(SATURN_DIR) if d[1]])}", cols-3)
        if is_minimal_mode():
            print(f"{BLUE}  > {repo_dir}\033[0m")
            print(f"{BLUE}  > {repo_size}\033[0m")
            print(f"{BLUE}  > {repo_contents}\033[0m")
        else:
            print(f"{BLUE}  ℹ {repo_dir}\033[0m")
            print(f"{BLUE}  ℹ {repo_size}\033[0m")
            print(f"{BLUE}  ℹ {repo_contents}\033[0m")
    except Exception as e:
        status_error(f"Failed to get repository info: {str(e)}")
    print("\033[0m", end="")

    if create_backup():
        BACKUP_CREATED = True
    else:
        BACKUP_CREATED = False

    update_git()
    install_libraries()
    build_p2app()
    build_desktop_apps()
    install_udev_rules()
    install_desktop_icons()
    check_fpga_binary()

    print_summary_report(start_time, BACKUP_CREATED)

    render_section("FPGA Programming")
    cols, _ = get_term_size()
    launch_text = truncate_text("Launch 'flashwriter' from desktop", cols-3)
    navigate_text = truncate_text("Navigate: File > Open > ~/github/Saturn/FPGA", cols-3)
    select_text = truncate_text("Select .BIT file", cols-3)
    verify_text = truncate_text("Verify 'primary' selected", cols-3)
    click_text = truncate_text("Click 'Program'", cols-3)
    if is_minimal_mode():
        print(f"{GREEN}  + {launch_text}\033[0m")
        print(f"{GREEN}  + {navigate_text}\033[0m")
        print(f"{GREEN}  + {select_text}\033[0m")
        print(f"{GREEN}  + {verify_text}\033[0m")
        print(f"{GREEN}  + {click_text}\033[0m")
    else:
        print(f"{GREEN}  ✔ {launch_text}\033[0m")
        print(f"{GREEN}  ✔ {navigate_text}\033[0m")
        print(f"{GREEN}  ✔ {select_text}\033[0m")
        print(f"{GREEN}  ✔ {verify_text}\033[0m")
        print(f"{GREEN}  ✔ {click_text}\033[0m")
    print("\033[0m", end="")

    render_section("Important Notes")
    cols, _ = get_term_size()
    fpga_time_text = truncate_text("FPGA programming takes ~3 minutes", cols-3)
    power_cycle_text = truncate_text("Power cycle required after", cols-3)
    terminal_text = truncate_text("Keep terminal open", cols-3)
    log_text = truncate_text(f"Log: {LOG_FILE}", cols-3)
    if is_minimal_mode():
        print(f"{YELLOW}  ! {fpga_time_text}\033[0m")
        print(f"{YELLOW}  ! {power_cycle_text}\033[0m")
        print(f"{YELLOW}  ! {terminal_text}\033[0m")
        print(f"{YELLOW}  ! {log_text}\033[0m")
    else:
        print(f"{YELLOW}  ⚠ {fpga_time_text}\033[0m")
        print(f"{YELLOW}  ⚠ {power_cycle_text}\033[0m")
        print(f"{YELLOW}  ⚠ {terminal_text}\033[0m")
        print(f"{YELLOW}  ⚠ {log_text}\033[0m")
    print("\033[0m", end="")

    print(f"{CYAN}{BOLD}", end="")
    render_top_section(f"{SCRIPT_NAME} v{SCRIPT_VERSION} Done")
    completion_animation()
    get_system_stats()
    print("\033[0m")

if __name__ == "__main__":
    main(sys.argv[1:])
    os.chdir(os.path.expanduser("~"))
