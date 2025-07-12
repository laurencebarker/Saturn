#!/usr/bin/env python3
# update-pihpsdr.py - piHPSDR Update Script
# Automates cloning, updating, and building the pihpsdr repository from ~/github/Saturn/scripts
# Version: 1.10
# Written by: Jerry DeLong KD4YAL
# Changes: Removed --show-compile flag, merged into --verbose, fixed make process output to display in CLI,
#          changed make output color to white in CLI with --verbose, updated version to 1.10
# Dependencies: psutil (version 7.0.0) in ~/venv, optional pyfiglet, urllib.error
# Usage: source ~/venv/bin/activate; python3 ~/github/Saturn/scripts/update-pihpsdr.py; deactivate

import os
import sys
import time
import subprocess
import shutil
import glob
import argparse
import logging
import re
from datetime import datetime
from pathlib import Path
import psutil
import urllib.error

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
SCRIPT_NAME = "piHPSDR Update"
SCRIPT_VERSION = "1.10"
SCRIPT_START_TIME = datetime.now()
TIMESTAMP = SCRIPT_START_TIME.strftime('%Y%m%d-%H%M%S')
PIHPSDR_DIR = Path.home() / "github" / "pihpsdr"
LOG_DIR = Path.home() / "saturn-logs"
BACKUP_DIR = Path.home() / f"pihpsdr-backup-{TIMESTAMP}"
REPO_URL = "https://github.com/dl1ycf/pihpsdr"
DEFAULT_BRANCH = "master"

# Terminal utilities
def get_term_size():
    try:
        cols = os.get_terminal_size().columns
        lines = os.get_terminal_size().lines
    except OSError:
        cols, lines = 80, 24
    cols = max(40, min(cols, 80))
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

# Initialize logging
def init_logging(verbose=False):
    debug_print("Initializing logging")
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
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
    log_file = LOG_DIR / f"pihpsdr-update-{TIMESTAMP}.log"
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[logging.FileHandler(log_file)]
    )
    try:
        log_handle = open(log_file, 'a')
    except Exception as e:
        print_error(f"Failed to open log file {log_file}: {str(e)}")
    sys.stdout = Tee(sys.__stdout__, log_handle)
    sys.stderr = Tee(sys.__stderr__, log_handle)
    os.system("tput clear")
    cols, _ = get_term_size()
    if Figlet:
        f = Figlet(font='standard', width=cols-2, justify='center')
        pihpsdr_ascii = f.renderText('piHPSDR')
    else:
        pihpsdr_ascii = "piHPSDR\n"
    banner = f"""
{Colors.RED}{pihpsdr_ascii.rstrip()}{Colors.END}
{Colors.BLUE}{'Update Manager v1.10'.center(cols-2)}{Colors.END}\n\n"""
    logging.debug(f"Banner raw output: {repr(banner)}")
    print(banner)
    print_info(f"Started: {SCRIPT_START_TIME}")
    print_info(f"Log: {log_file}")

# Parse command-line arguments
def parse_args():
    parser = argparse.ArgumentParser(description="piHPSDR Update Script")
    parser.add_argument("--skip-git", action="store_true", help="Skip Git repository update")
    parser.add_argument("-y", "--yes", action="store_true", help="Auto-confirm backup creation")
    parser.add_argument("-n", "--no", action="store_true", help="Skip backup creation")
    parser.add_argument("--no-gpio", action="store_true", help="Disable GPIO for Radioberry")
    parser.add_argument("--dry-run", action="store_true", help="Simulate actions without executing")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose output for all commands, including detailed compile output")
    parser.add_argument("--debug", action="store_true", help="Enable debug output")
    args = parser.parse_args()
    if args.yes and args.no:
        print_error("Cannot use -y and -n together")
    return args

# Check system requirements
def check_requirements():
    debug_print("Checking requirements")
    print_header("System Check")
    print(f"{Colors.CYAN}⚡ Verifying requirements...{Colors.END}")
    requirements = ["git", "make", "gcc", "sudo", "rsync"]
    for item in requirements:
        print(f"{Colors.CYAN}Scanning: {item}...{Colors.END}")
        time.sleep(0.3)
        if shutil.which(item):
            cols, _ = get_term_size()
            print(f"{Colors.GREEN}✓ {item} - OK{' ' * (cols - len(item) - 8)}{Colors.END}")
        else:
            print_error(f"Missing command: {item}")
    print(f"\n{Colors.GREEN}[SCAN COMPLETE]{Colors.END}\n")
    try:
        free_space = psutil.disk_usage(str(Path.home())).free / 1024**3  # Convert to GB
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
    max_attempts = 3
    for attempt in range(1, max_attempts + 1):
        try:
            result = subprocess.run(["ping", "-c", "1", "-W", "2", "github.com"], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            rtt_match = re.search(r"time=([\d.]+)\s*ms", result.stdout)
            rtt = float(rtt_match.group(1)) if rtt_match else None
            if args.verbose:
                print_info(f"RTT: {rtt:.3f} ms")
            print_success("Network verified")
            return 0
        except subprocess.CalledProcessError as e:
            if attempt < max_attempts:
                print_warning(f"Cannot reach GitHub (attempt {attempt}/{max_attempts}): {e.output.strip()}. Retrying...")
                time.sleep(2)
            else:
                print_warning(f"Cannot reach GitHub after {max_attempts} attempts: {e.output.strip()}")
                return 1

# Create backup
def create_backup():
    debug_print("Creating backup")
    print_header("Backup")
    cols, _ = get_term_size()
    do_backup = False
    if args.no:
        print_warning("Backup skipped via -n flag")
        return False
    if args.yes:
        do_backup = True
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
        do_backup = True
    if do_backup:
        print(f"{Colors.CYAN}⚡ Creating backup...{Colors.END}")
        backup_pattern = str(Path.home() / "pihpsdr-backup-*")
        backup_dirs = sorted(glob.glob(backup_pattern), key=os.path.getmtime, reverse=True)
        print_info(f"Found {len(backup_dirs)} existing backups")
        if len(backup_dirs) > 2:
            for old_backup in backup_dirs[2:]:
                try:
                    if not args.dry_run:
                        shutil.rmtree(old_backup)
                    print_info(f"Deleted old backup: {old_backup}")
                except Exception as e:
                    print_warning(f"Failed to delete backup {old_backup}: {str(e)}")
        print_info(f"Location: {BACKUP_DIR}")
        try:
            if not args.dry_run:
                BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        except Exception as e:
            print_error(f"Cannot create backup dir: {str(e)}")
        try:
            with open("/tmp/rsync_output", "w") as f:
                process = subprocess.Popen(["rsync", "-a", f"{PIHPSDR_DIR}/", str(BACKUP_DIR)], stdout=f, stderr=f, text=True)
                return_code = progress_bar(process, "Copying files", 50)
                if return_code != 0:
                    with open("/tmp/rsync_output", "r") as f:
                        error_output = f.read().strip()
                    print_error(f"Backup failed: {error_output}")
                if args.verbose:
                    with open("/tmp/rsync_output", "r") as f:
                        print_info(f"Rsync output: {f.read().strip()}")
        except Exception as e:
            print_error(f"Failed to access /tmp/rsync_output: {str(e)}")
        if args.dry_run:
            print_info("[Dry Run] Backup created")
            return True
        backup_size = sum(f.stat().st_size for f in BACKUP_DIR.rglob('*') if f.is_file()) / 1024**2
        print_info(f"Size: {backup_size:.1f}MB")
        print_success("Backup created")
        return True
    return False

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
    PIHPSDR_DIR.parent.mkdir(parents=True, exist_ok=True)
    if PIHPSDR_DIR.exists():
        try:
            os.chdir(PIHPSDR_DIR)
            current_commit = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], text=True).strip()
            print_info(f"Commit: {current_commit}")
            if subprocess.run(["git", "diff-index", "--quiet", "HEAD", "--"]).returncode != 0:
                print_warning("Stashing changes")
                subprocess.run(["git", "stash", "push", "-m", f"Auto-stash {datetime.now()}"], check=True)
            max_attempts = 3
            for attempt in range(1, max_attempts + 1):
                try:
                    with open("/tmp/git_output", "w") as f:
                        process = subprocess.Popen(["git", "pull", "origin", DEFAULT_BRANCH], stdout=f, stderr=f, text=True)
                        return_code = progress_bar(process, "Pulling changes", 50)
                        if return_code == 0:
                            break
                        with open("/tmp/git_output", "r") as f:
                            error_output = f.read().strip()
                        if attempt < max_attempts:
                            print_warning(f"Git update failed (attempt {attempt}/{max_attempts}): {error_output}. Retrying...")
                            time.sleep(2)
                        else:
                            print_error(f"Git update failed after {max_attempts} attempts: {error_output}")
                    if args.verbose:
                        with open("/tmp/git_output", "r") as f:
                            print_info(f"Git output: {f.read().strip()}")
                    break
                except subprocess.CalledProcessError as e:
                    if attempt < max_attempts:
                        print_warning(f"Git update failed (attempt {attempt}/{max_attempts}): {e.output.strip()}. Retrying...")
                        time.sleep(2)
                    else:
                        print_error(f"Git update failed after {max_attempts} attempts: {e.output.strip()}")
            new_commit = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], text=True).strip()
            if current_commit != new_commit:
                changes = subprocess.check_output(["git", "log", "--oneline", f"{current_commit}..HEAD"], text=True).strip().splitlines()
                print_info(f"New commit: {new_commit}")
                print_info(f"Changes: {len(changes)} commits")
                if args.verbose:
                    print_info(f"Log: {changes}")
            else:
                print_info("Up to date")
            print_success("Repository updated")
        except subprocess.CalledProcessError as e:
            print_error(f"Git update failed: {e.output.strip()}")
    else:
        print(f"{Colors.CYAN}⚡ Cloning repository...{Colors.END}")
        max_attempts = 3
        for attempt in range(1, max_attempts + 1):
            try:
                with open("/tmp/git_output", "w") as f:
                    process = subprocess.Popen(["git", "clone", REPO_URL, str(PIHPSDR_DIR)], stdout=f, stderr=f, text=True)
                    return_code = progress_bar(process, "Cloning repository", 50)
                    if return_code == 0:
                        break
                    with open("/tmp/git_output", "r") as f:
                        error_output = f.read().strip()
                    if attempt < max_attempts:
                        print_warning(f"Git clone failed (attempt {attempt}/{max_attempts}): {error_output}. Retrying...")
                        time.sleep(2)
                    else:
                        print_error(f"Git clone failed after {max_attempts} attempts: {error_output}")
                if args.verbose:
                    with open("/tmp/git_output", "r") as f:
                        print_info(f"Git output: {f.read().strip()}")
                os.chdir(PIHPSDR_DIR)
                new_commit = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], text=True).strip()
                print_info(f"Commit: {new_commit}")
                print_success("Repository cloned")
                break
            except subprocess.CalledProcessError as e:
                if attempt < max_attempts:
                    print_warning(f"Git clone failed (attempt {attempt}/{max_attempts}): {e.output.strip()}. Retrying...")
                    time.sleep(2)
                else:
                    print_error(f"Git clone failed after {max_attempts} attempts: {e.output.strip()}")

# Build piHPSDR
def build_pihpsdr():
    debug_print("Building piHPSDR")
    print_header("piHPSDR Build")
    try:
        os.chdir(PIHPSDR_DIR)
        print(f"{Colors.CYAN}⚡ Cleaning build...{Colors.END}")
        if not args.dry_run:
            if args.verbose:
                process = subprocess.Popen(["make", "clean"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, universal_newlines=True)
                while process.poll() is None:
                    line = process.stdout.readline().strip()
                    if line:
                        print_build_output(line)
                return_code = process.wait()
                if return_code != 0:
                    print_error(f"make clean failed: Check log for details")
            else:
                with open("/tmp/make_clean_output", "w") as f:
                    process = subprocess.Popen(["make", "clean"], stdout=f, stderr=f, text=True)
                    return_code = progress_bar(process, "Cleaning build", 50)
                    if return_code != 0:
                        with open("/tmp/make_clean_output", "r") as f:
                            error_output = f.read().strip()
                        print_error(f"make clean failed: {error_output}")
        else:
            print_info("[Dry Run] Simulating make clean")
        print_success("Build cleaned")

        print(f"{Colors.CYAN}⚡ Installing dependencies...{Colors.END}")
        libinstall_script = PIHPSDR_DIR / "LINUX" / "libinstall.sh"
        if libinstall_script.exists():
            max_attempts = 3
            for attempt in range(1, max_attempts + 1):
                try:
                    if not args.dry_run:
                        if args.verbose:
                            process = subprocess.Popen(["bash", str(libinstall_script)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, universal_newlines=True)
                            while process.poll() is None:
                                line = process.stdout.readline().strip()
                                if line:
                                    print_build_output(line)
                            return_code = process.wait()
                            if return_code != 0:
                                print_error(f"Dependency installation failed: Check log for details")
                        else:
                            with open("/tmp/libinstall_output", "w") as f:
                                process = subprocess.Popen(["bash", str(libinstall_script)], stdout=f, stderr=f, text=True)
                                return_code = progress_bar(process, "Installing dependencies", 50)
                                if return_code != 0:
                                    with open("/tmp/libinstall_output", "r") as f:
                                        error_output = f.read().strip()
                                    print_error(f"Dependency installation failed: {error_output}")
                    else:
                        print_info(f"[Dry Run] Simulating {libinstall_script}")
                    print_success("Dependencies installed")
                    break
                except (subprocess.CalledProcessError, urllib.error.URLError) as e:
                    if attempt < max_attempts:
                        print_warning(f"Dependency installation failed (attempt {attempt}/{max_attempts}): {str(e)}. Retrying...")
                        time.sleep(2)
                    else:
                        print_error(f"Dependency installation failed after {max_attempts} attempts: {str(e)}")
        else:
            print_error(f"No libinstall.sh script found at {libinstall_script}")

        print(f"{Colors.CYAN}⚡ Building piHPSDR...{Colors.END}")
        if args.no_gpio:
            print_info("Building with GPIO disabled")
            if not args.dry_run:
                makefile = PIHPSDR_DIR / "Makefile"
                try:
                    with makefile.open("r") as f:
                        content = f.read()
                    content = content.replace("#CONTROLLER=NO_CONTROLLER", "CONTROLLER=NO_CONTROLLER")
                    with makefile.open("w") as f:
                        f.write(content)
                except Exception as e:
                    print_error(f"Failed to modify Makefile for no-gpio: {str(e)}")
                if args.verbose:
                    process = subprocess.Popen(["make"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, universal_newlines=True)
                    while process.poll() is None:
                        line = process.stdout.readline().strip()
                        if line:
                            print_build_output(line)
                    return_code = process.wait()
                    if return_code != 0:
                        print_error(f"piHPSDR build failed: Check log for details")
                else:
                    with open("/tmp/make_output", "w") as f:
                        process = subprocess.Popen(["make"], stdout=f, stderr=f, text=True)
                        return_code = progress_bar(process, "Building piHPSDR", 50)
                        if return_code != 0:
                            with open("/tmp/make_output", "r") as f:
                                error_output = f.read().strip()
                            print_error(f"piHPSDR build failed: {error_output}")
            else:
                print_info("[Dry Run] Simulating build with GPIO disabled")
        else:
            if not args.dry_run:
                if args.verbose:
                    process = subprocess.Popen(["make"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, universal_newlines=True)
                    while process.poll() is None:
                        line = process.stdout.readline().strip()
                        if line:
                            print_build_output(line)
                    return_code = process.wait()
                    if return_code != 0:
                        print_error(f"piHPSDR build failed: Check log for details")
                else:
                    with open("/tmp/make_output", "w") as f:
                        process = subprocess.Popen(["make"], stdout=f, stderr=f, text=True)
                        return_code = progress_bar(process, "Building piHPSDR", 50)
                        if return_code != 0:
                            with open("/tmp/make_output", "r") as f:
                                error_output = f.read().strip()
                            print_error(f"piHPSDR build failed: {error_output}")
            else:
                print_info("[Dry Run] Simulating piHPSDR build")
        print_success("piHPSDR built")
    except Exception as e:
        print_error(f"Build failed: {str(e)}")

# System stats
def get_system_stats():
    debug_print("Getting system stats")
    try:
        cpu = psutil.cpu_percent(interval=1)
        mem = psutil.virtual_memory()
        disk = psutil.disk_usage(str(Path.home()))
        cols, _ = get_term_size()
        stats_text = truncate_text(f"CPU: {cpu:.0f}% | Mem: {mem.used / 1024**2:.0f}/{mem.total / 1024**2:.0f}MB | Disk: {disk.used / 1024**3:.1f}/{disk.total / 1024**3:.1f}G", cols-7)
        print_info(stats_text)
    except Exception as e:
        print_warning(f"Failed to retrieve system stats: {str(e)}")

# Print summary report
def print_summary_report(start_time, backup_created):
    debug_print("Printing summary report")
    print_header("Summary")
    cols, _ = get_term_size()
    completed_text = truncate_text(f"Completed: {datetime.now()}", cols-7)
    duration_text = truncate_text(f"Duration: {int(time.time() - start_time)} seconds", cols-7)
    log_filename = f"pihpsdr-update-{TIMESTAMP}.log"
    log_text = truncate_text(f"Log: {LOG_DIR / log_filename}", cols-7)
    backup_text = truncate_text(f"Backup: {BACKUP_DIR}", cols-7)
    print_success(completed_text)
    print_info(duration_text)
    print_info(log_text)
    if backup_created:
        print_success(backup_text)
    else:
        print_warning("No backup created")

# Main execution
def main():
    global args
    args = parse_args()
    start_time = time.time()
    BACKUP_CREATED = False

    debug_print("Starting main execution")
    init_logging(args.verbose)

    if args.skip_git:
        print_warning("Skipping Git update")
    if args.yes:
        print_success("Backup enabled via -y flag")
    if args.no:
        print_warning("Backup disabled via -n flag")
    if args.no_gpio:
        print_warning("GPIO disabled for Radioberry compatibility")
    if args.dry_run:
        print_warning("Dry run enabled")
    if args.verbose:
        print_info("Verbose output enabled for all commands, including detailed compile output")
    if args.debug:
        print_info("Debug output enabled")

    check_requirements()
    check_connectivity()
    if PIHPSDR_DIR.exists():
        BACKUP_CREATED = create_backup()
    update_git()
    build_pihpsdr()
    print_summary_report(start_time, BACKUP_CREATED)
    print_header(f"{SCRIPT_NAME} v{SCRIPT_VERSION} Done")
    get_system_stats()
    print_success("Complete!")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print_error("Script interrupted by user")
    except Exception as e:
        print_error(f"Unexpected error: {str(e)}")
    finally:
        os.chdir(Path.home())
