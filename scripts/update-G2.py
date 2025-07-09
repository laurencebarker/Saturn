#!/usr/bin/env python3
# update-G2.py- G2 Update Script
# Automates updating the Saturn G2
# Version: 2.1
# Written by: Jerry DeLong KD4YAL
# Dependencies: rich (version 14.0.0) and psutil (version 7.0.0) (pyfiglet 1.0.3) are installed in ~/venv.
# source ~/venv/bin/activate
# python3 ~/github/Saturn/scripts/update-G2.py
# deactivate

import os
import sys
import time
import subprocess
import shutil
import glob
from datetime import datetime

try:
    from pyfiglet import Figlet
except ImportError:
    Figlet = None  # Handle missing pyfiglet

# ANSI color codes
class Colors:
    NEON_BLUE = '\033[1;38;5;51m'  # Neon blue for headers
    CYAN = '\033[1;36m'
    GREEN = '\033[1;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[1;31m'
    BOLD = '\033[1m'
    END = '\033[0m'
    BANNER = '\033[1;31m'  # Red for banner text
    ACCENT = '\033[38;5;39m'  # Blue for banner subtitle
    GRADIENT_GREEN = ['\033[38;5;28m', '\033[38;5;34m', '\033[38;5;40m']  # For progress bar
    NEON_GREEN = '\033[1;38;5;46m'  # For success messages

# Script metadata
SCRIPT_NAME = "SATURN UPDATE"
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
    cols = max(40, min(80, cols))
    lines = max(15, lines)
    return cols, lines

def truncate_text(text, max_len):
    clean_text = ''.join(c for c in text if c.isprintable())
    if len(clean_text) > max_len:
        return clean_text[:max_len-2] + ".."
    return clean_text

def debug_print(msg):
    if DEBUG:
        print(f"{Colors.END}[DEBUG] {msg}{Colors.END}")

# UI functions
def print_header(title):
    cols, _ = get_term_size()
    title = truncate_text(title, cols-12)
    print(f"\n{Colors.NEON_BLUE}═════ {title} ═════{Colors.END}\n")

def print_success(msg):
    print(f"{Colors.NEON_GREEN}✔ {msg}{Colors.END}")

def print_warning(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols-7)
    print(f"{Colors.YELLOW}⚠ {msg}{Colors.END}")

def print_error(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols-7)
    print(f"{Colors.RED}✗ {msg}{Colors.END}", file=sys.stderr)
    sys.exit(1)

def print_info(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols-7)
    print(f"{Colors.CYAN}ℹ {msg}{Colors.END}")

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
        bar = ""
        for i in range(filled):
            bar += f"{Colors.GRADIENT_GREEN[min(2, i//5)]}█"
        bar += f"{Colors.END}{' ' * (bar_width - filled)}"
        print(f"\r{Colors.CYAN}[{bar}] {percent:2d}% {msg}{Colors.END}", end="", flush=True)
        time.sleep(0.5)
    print(f"\r{Colors.CYAN}[{Colors.GRADIENT_GREEN[2]}{'█' * bar_width}{Colors.END}] 100% Complete{Colors.END}", end="", flush=True)
    print(f"\033[2K\r{' ' * cols}\033[0m\033[0G", end="", flush=True)
    os.system("tput cnorm")
    return pid.wait()

def system_scan_effect(items):
    cols, _ = get_term_size()
    print(f"{Colors.NEON_GREEN}[SYSTEM SCAN INITIATED]{Colors.END}")
    for item in items:
        print(f"\r{Colors.CYAN}Scanning: {item}...{Colors.END}", end="", flush=True)
        time.sleep(0.3)
        print(f"\r{Colors.NEON_GREEN}✓ {item} - OK{' ' * (cols - len(item) - 8)}{Colors.END}")
    print(f"\n{Colors.NEON_GREEN}[SCAN COMPLETE]{Colors.END}\n")

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
{Colors.BANNER}{g2_saturn_ascii.rstrip()}{Colors.END}
{Colors.ACCENT}{'Update Manager v2.1'.center(cols-2)}{Colors.END}\n\n"""
    print(banner)
    print_info(f"Started: {datetime.now()}")
    print_info(f"Log: {LOG_FILE}")

# Parse command-line arguments
def parse_args(args):
    global SKIP_GIT, DEBUG
    debug_print("Parsing arguments")
    for arg in args:
        if arg == "--skip-git":
            SKIP_GIT = True
            print_warning("Skipping Git update")
        if arg == "--debug":
            DEBUG = True
            debug_print("Debug mode enabled")

# Check system requirements
def check_requirements():
    debug_print("Checking requirements")
    print_header("System Check")
    print(f"{Colors.NEON_BLUE}⚡ Verifying requirements...{Colors.END}")
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
    if SKIP_GIT:
        print_warning("Skipping network check")
        return 0
    print_header("Network Check")
    print(f"{Colors.NEON_BLUE}⚡ Checking connectivity...{Colors.END}")
    try:
        subprocess.run(["ping", "-c", "1", "-W", "2", "github.com"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        print_success("Network verified")
        return 0
    except subprocess.CalledProcessError as e:
        print_warning(f"Cannot reach GitHub: {e.stderr.strip()}")
        return 1

# Update Git repository
def update_git():
    if SKIP_GIT:
        print_warning("Skipping repository update")
        return 0
    debug_print("Updating Git repository")
    print_header("Git Update")
    print(f"{Colors.NEON_BLUE}⚡ Updating repository...{Colors.END}")
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
        untracked_files = [line.strip().split()[1] for line in diff_result.stdout.splitlines() if line.startswith("??")]
        if diff_result.stdout:
            print_warning("Local changes detected")
            if untracked_files:
                print_warning(f"Untracked files: {', '.join(untracked_files)}")
            print(f"{Colors.YELLOW}⚠ Stash changes or reset to remote? [S/r/n]: {Colors.END}", end="", flush=True)
            reply = input("").lower()
            print(Colors.END)
            if reply == "r":
                print_warning("Resetting to remote state (discards local changes)")
                try:
                    subprocess.run(["git", "reset", "--hard", f"origin/{target_branch}"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    subprocess.run(["git", "clean", "-fd"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    print_info(f"Reset to origin/{target_branch}")
                except subprocess.CalledProcessError as e:
                    print_error(f"Reset failed: {e.stderr.strip()}")
            elif reply != "n":
                print_warning("Stashing local changes (including untracked files)")
                try:
                    subprocess.run(["git", "stash", "push", "--include-untracked", "-m", f"Auto-stash {datetime.now()}"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    print_info("Changes stashed successfully")
                except subprocess.CalledProcessError as e:
                    print_error(f"Stash failed: {e.stderr.strip()}")
            else:
                print_warning("Skipping Git update due to local changes")
                return 0
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
        except Exception as e:
            print_error(f"Failed to access /tmp/git_output: {str(e)}")
        try:
            new_commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
            if current_commit != new_commit:
                log_result = subprocess.run(["git", "log", "--oneline", f"{current_commit}..{new_commit}"], capture_output=True, text=True).stdout.strip()
                change_count = len(log_result.splitlines())
                print_info(f"New commit: {new_commit}")
                print_info(f"Changes: {change_count} commits")
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
    cols, _ = get_term_size()
    print(f"{Colors.YELLOW}⚠ Backup? [{Colors.BOLD}Y{Colors.END}/n]: ", end="", flush=True)
    reply = input("").lower()
    print(Colors.END)
    if reply != "n":
        print(f"{Colors.NEON_BLUE}⚡ Creating backup...{Colors.END}")
        backup_pattern = os.path.expanduser("~/saturn-backup-*")
        backup_dirs = sorted(glob.glob(backup_pattern), key=os.path.getmtime, reverse=True)
        if len(backup_dirs) > 4:
            for old_backup in backup_dirs[4:]:
                try:
                    shutil.rmtree(old_backup)
                    print_info(f"Deleted old backup: {old_backup}")
                except Exception as e:
                    print_warning(f"Failed to delete backup {old_backup}: {str(e)}")
        print_info(f"Location: {BACKUP_DIR}")
        try:
            os.makedirs(BACKUP_DIR, exist_ok=True)
        except Exception as e:
            print_error(f"Cannot create backup dir: {str(e)}")
        try:
            with open("/tmp/rsync_output", "w") as f:
                process = subprocess.Popen(["rsync", "-a", f"{SATURN_DIR}/", BACKUP_DIR], stdout=f, stderr=f, text=True)
                progress_bar(process, "Copying files", 10)
                if process.returncode != 0:
                    with open("/tmp/rsync_output", "r") as f:
                        error_output = f.read().strip()
                    print_error(f"Backup failed: {error_output}")
        except Exception as e:
            print_error(f"Failed to access /tmp/rsync_output: {str(e)}")
        backup_size = subprocess.run(["du", "-sh", BACKUP_DIR], capture_output=True, text=True).stdout.split()[0]
        print_info(f"Size: {backup_size}")
        print_success("Backup created")
        return True
    else:
        print_warning("Backup skipped")
        return False

# Install libraries
def install_libraries():
    debug_print("Installing libraries")
    print_header("Libraries")
    print(f"{Colors.NEON_BLUE}⚡ Installing libraries...{Colors.END}")
    install_script = os.path.join(SATURN_DIR, "scripts", "install-libraries.sh")
    if os.path.isfile(install_script):
        try:
            with open("/tmp/library_output", "w") as f:
                process = subprocess.Popen(["bash", install_script], stdout=f, stderr=f, text=True)
                progress_bar(process, "Installing", 10)
                if process.returncode != 0:
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
    print(f"{Colors.NEON_BLUE}⚡ Building p2app...{Colors.END}")
    build_script = os.path.join(SATURN_DIR, "scripts", "update-p2app.sh")
    if os.path.isfile(build_script):
        try:
            with open("/tmp/p2app_output", "w") as f:
                process = subprocess.Popen(["bash", build_script], stdout=f, stderr=f, text=True)
                progress_bar(process, "Building", 10)
                if process.returncode != 0:
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
    print(f"{Colors.NEON_BLUE}⚡ Building apps...{Colors.END}")
    build_script = os.path.join(SATURN_DIR, "scripts", "update-desktop-apps.sh")
    if os.path.isfile(build_script):
        try:
            with open("/tmp/desktop_output", "w") as f:
                process = subprocess.Popen(["bash", build_script], stdout=f, stderr=f, text=True)
                progress_bar(process, "Building", 10)
                if process.returncode != 0:
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
    print(f"{Colors.NEON_BLUE}⚡ Installing rules...{Colors.END}")
    rules_dir = os.path.join(SATURN_DIR, "rules")
    install_script = os.path.join(rules_dir, "install-rules.sh")
    if os.path.isfile(install_script):
        if not os.access(install_script, os.X_OK):
            print_warning("Setting permissions")
            os.chmod(install_script, 0o755)
        try:
            with open("/tmp/udev_output", "w") as f:
                process = subprocess.Popen(["sudo", "./install-rules.sh"], cwd=rules_dir, stdout=f, stderr=f, text=True)
                progress_bar(process, "Installing", 10)
                if process.returncode != 0:
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
    print(f"{Colors.NEON_BLUE}⚡ Installing shortcuts...{Colors.END}")
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
    print(f"{Colors.NEON_BLUE}⚡ Verifying binary...{Colors.END}")
    check_script = os.path.join(SATURN_DIR, "scripts", "find-bin.sh")
    if os.path.isfile(check_script):
        try:
            with open("/tmp/fpga_output", "w") as f:
                process = subprocess.Popen(["bash", check_script], stdout=f, stderr=f, text=True)
                progress_bar(process, "Verifying", 10)
                if process.returncode != 0:
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
        # Parse 'top' output more robustly
        top_output = subprocess.run(["top", "-bn1"], capture_output=True, text=True).stdout.splitlines()
        cpu = 0
        for line in top_output:
            if line.strip().startswith("%Cpu"):
                cpu = float(line.split()[1])  # Get %CPU from %Cpu(s) line
                break
        mem = subprocess.run(["free", "-m"], capture_output=True, text=True).stdout.splitlines()[1].split()
        mem_used = mem[2] + "/" + mem[1] + "MB"
        disk_usage = shutil.disk_usage(SATURN_DIR)
        disk = f"{disk_usage.used / 1024**3:.1f}G/{disk_usage.total / 1024**3:.1f}G"
        cols, _ = get_term_size()
        stats_text = truncate_text(f"CPU: {cpu:.0f}% | Mem: {mem_used} | Disk: {disk}", cols-7)
        print_info(stats_text)
    except Exception as e:
        print_warning(f"Failed to retrieve system stats: {str(e)}")

# Main execution
def main(args):
    start_time = time.time()
    BACKUP_CREATED = False

    debug_print("Starting main execution")
    init_logging()
    parse_args(args)

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
    main(sys.argv[1:])
    os.chdir(os.path.expanduser("~"))
