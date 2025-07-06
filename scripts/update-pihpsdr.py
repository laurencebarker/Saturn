#!/usr/bin/env python3
# update-pihpsdr.py- piHPSDR Update Script
# Automates cloning, updating, and building the pihpsdr repository from ~/github/Saturn/scripts
# Version: 1.0 (Scalable CLI with Enhanced Visuals and Backup Flags)
# Written by: Jerry DeLong KD4YAL
# Dependencies: rich (version 14.0.0) and psutil (version 7.0.0) are installed in ~/venv.
# source ~/venv/bin/activate
# python3 ~/github/Saturn/scripts/update-pihpsdr.py -y
# deactivate
import argparse
import logging
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
import shutil
import psutil
from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TimeRemainingColumn
from rich.status import Status
from rich.theme import Theme

# Initialize console with custom theme
theme = Theme({
    "header": "bold cyan on #005f87",
    "success": "bold green",
    "warning": "bold yellow",
    "error": "bold red",
    "info": "bold blue",
    "task": "bold magenta",
})
console = Console(theme=theme)

# Script metadata
SCRIPT_NAME = "piHPSDR Update"
SCRIPT_VERSION = "1.0"
PIHPSDR_DIR = Path.home() / "github" / "pihpsdr"
LOG_DIR = Path.home() / "saturn-logs"
BACKUP_DIR = Path.home() / f"pihpsdr-backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
REPO_URL = "https://github.com/dl1ycf/pihpsdr"
DEFAULT_BRANCH = "master"

# Setup logging
def setup_logging():
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_file = LOG_DIR / f"pihpsdr-update-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler(sys.stdout),
        ],
    )
    return log_file

# Terminal size detection
def get_term_size():
    try:
        cols = os.get_terminal_size().columns
        lines = os.get_terminal_size().lines
    except OSError:
        cols, lines = 80, 24
    cols = max(20, min(cols, 80))
    lines = max(8, lines)
    return cols, lines

def is_minimal_mode():
    cols, lines = get_term_size()
    return cols < 40 or lines < 15

# Detect terminal resizing
def is_terminal_resizing():
    initial_size = get_term_size()
    time.sleep(0.1)
    current_size = get_term_size()
    return initial_size != current_size

# Truncate text for terminal width
def truncate_text(text, max_len):
    if len(text) > max_len:
        return text[:max_len-2] + ".."
    return text

# Draw a section panel with smaller width
def render_section(title):
    cols, _ = get_term_size()
    panel_width = min(60, int(cols * 0.75))  # 75% of terminal width, max 60
    title = truncate_text(title, panel_width - 4)
    console.print(Panel(title, style="header", border_style="cyan", width=panel_width))

# Draw a top/bottom section panel with smaller width
def render_top_section(title):
    cols, _ = get_term_size()
    panel_width = min(60, int(cols * 0.75))  # 75% of terminal width, max 60
    title = truncate_text(title, panel_width - 4)
    console.print(Panel(title, style="header", border_style="cyan", width=panel_width))

# Transition animation
def draw_transition():
    if is_minimal_mode():
        return
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        transient=True,
    ) as progress:
        task = progress.add_task("Processing...", total=None)
        for _ in range(3):
            progress.update(task, description="...")
            time.sleep(0.1)
            progress.update(task, description="")
            time.sleep(0.1)

# Progress bar for subprocesses with timeout and resizing handling
def run_with_progress(command, description, total_steps=10, timeout=300):
    process = subprocess.Popen(
        command,
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    cols, _ = get_term_size()
    output_lines = []
    start_time = time.time()
    if is_terminal_resizing():
        with console.status(f"[task]{description}...") as status:
            while process.poll() is None:
                if time.time() - start_time > timeout:
                    process.terminate()
                    status_error(f"{description} timed out after {timeout} seconds")
                time.sleep(1.0 if total_steps <= 50 else 1.5)
    else:
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(bar_width=cols-20),
            "[progress.percentage]{task.percentage:>3.0f}%",
            TimeRemainingColumn(),
        ) as progress:
            task = progress.add_task(description, total=total_steps)
            step = 0
            while process.poll() is None:
                if time.time() - start_time > timeout:
                    process.terminate()
                    status_error(f"{description} timed out after {timeout} seconds")
                step += 1
                progress.update(task, advance=1)
                time.sleep(1.0 if total_steps <= 50 else 1.5)  # Slower for long tasks
            progress.update(task, completed=total_steps)
    output = process.communicate()[0]
    output_lines.append(output)
    return process.returncode, "\n".join(output_lines)

# Status reporting
def status_start(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols - 7)
    console.print(f"[task]⏳ {msg}")

def status_success(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols - 7)
    console.print(f"[success]✔ {msg}")

def status_warning(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols - 7)
    console.print(f"[warning]⚠ {msg}")

def status_error(msg):
    cols, _ = get_term_size()
    msg = truncate_text(msg, cols - 7)
    console.print(Panel(f"✗ {msg}", style="error", border_style="red", width=min(60, cols)))
    logging.error(msg)
    sys.exit(1)

# Initialize logging and console
def init_logging():
    log_file = setup_logging()
    console.clear()
    # Check terminal color support
    try:
        colors = int(subprocess.check_output(["tput", "colors"]).decode().strip())
        if colors < 8 or "256color" not in os.environ.get("TERM", ""):
            console.print(f"[warning]⚠ Terminal lacks 256-color support (TERM={os.environ.get('TERM', 'unknown')}, colors={colors}). Some styles may not render.")
    except subprocess.CalledProcessError:
        console.print(f"[warning]⚠ Unable to check terminal color support. Some styles may not render.")
    render_top_section(f"{SCRIPT_NAME} v{SCRIPT_VERSION}")
    cols, _ = get_term_size()
    console.print(f"[info]ℹ {truncate_text(f'Started: {datetime.now()}', cols-3)}")
    console.print(f"[info]ℹ {truncate_text(f'Log: {log_file}', cols-3)}")
    draw_transition()
    return log_file

# Parse command-line arguments
def parse_args():
    parser = argparse.ArgumentParser(description="piHPSDR Update Script")
    parser.add_argument("--skip-git", action="store_true", help="Skip Git update")
    parser.add_argument("-y", action="store_true", help="Auto-enable backup")
    parser.add_argument("-n", action="store_true", help="Skip backup")
    parser.add_argument("--no-gpio", action="store_true", help="Disable GPIO for Radioberry")
    parser.add_argument("--dry-run", action="store_true", help="Simulate operations")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose output")
    args = parser.parse_args()
    if args.y and args.n:
        status_error("Cannot use -y and -n together")
    return args

# Create backup
def create_backup(args):
    render_section("Backup")
    cols, _ = get_term_size()
    do_backup = False

    if args.y:
        do_backup = True
        console.print(f"[success]✔ Backup enabled via -y flag")
    elif args.n:
        status_warning("Backup skipped")
        return False
    else:
        response = console.input(f"[warning]⚠ Backup? [bold]Y[/bold]/n: ")
        if response.lower() not in ["n"]:
            do_backup = True
        else:
            status_warning("Backup skipped")
            return False

    if do_backup:
        status_start("Creating backup")
        console.print(f"[info]ℹ {truncate_text(f'Location: {BACKUP_DIR}', cols-3)}")
        if not args.dry_run:
            try:
                BACKUP_DIR.mkdir(parents=True, exist_ok=True)
                status, output = run_with_progress(
                    f"rsync -a {PIHPSDR_DIR}/ {BACKUP_DIR}/",
                    "Copying files",
                    total_steps=50,
                )
                if status != 0:
                    status_error(f"Backup failed: {output}")
                logging.info(output)
                if args.verbose:
                    console.print(f"[info]ℹ Backup output: {truncate_text(output, cols-3)}")
                # Calculate backup size outside f-string
                backup_size = sum(f.stat().st_size for f in BACKUP_DIR.rglob('*') if f.is_file()) / 1024**2
                size_text = f"Size: {backup_size:.1f}MB"
                console.print(f"[info]ℹ {truncate_text(size_text, cols-3)}")
            except Exception as e:
                status_error(f"Backup failed: {str(e)}")
        else:
            console.print(f"[info]ℹ Dry run: Would back up to {BACKUP_DIR}")
            console.print(f"[info]ℹ Dry run: Would calculate backup size")
        status_success("Backup created")
        return True
    return False

# Check system requirements
def check_requirements(args):
    render_section("System Check")
    status_start("Verifying requirements")
    required = ["git", "make", "gcc", "sudo", "rsync"]
    missing = [cmd for cmd in required if shutil.which(cmd) is None]
    if missing:
        status_error(f"Missing commands: {', '.join(missing)}")
    free_space = psutil.disk_usage(str(Path.home())).free / 1024**2  # MB
    cols, _ = get_term_size()
    if free_space < 1024:
        status_warning(f"Low disk space: {free_space:.0f}MB")
    else:
        console.print(f"[success]✔ {truncate_text(f'Disk: {free_space:.0f}MB free', cols-3)}")
    status_success("Requirements met")

# Clone or update repository
def update_git(args):
    render_section("Git Update")
    status_start("Checking repository")
    cols, _ = get_term_size()

    if args.skip_git:
        status_warning("Skipping repository update")
        return

    PIHPSDR_DIR.parent.mkdir(parents=True, exist_ok=True)
    if PIHPSDR_DIR.exists():
        status_start("Updating repository")
        try:
            os.chdir(PIHPSDR_DIR)
            current_commit = subprocess.check_output(
                ["git", "rev-parse", "--short", "HEAD"], text=True
            ).strip()
            console.print(f"[info]ℹ {truncate_text(f'Commit: {current_commit}', cols-3)}")
            if not args.dry_run:
                if subprocess.run(["git", "diff-index", "--quiet", "HEAD", "--"]).returncode != 0:
                    status_warning("Stashing changes")
                    subprocess.run(["git", "stash", "push", "-m", f"Auto-stash {datetime.now()}"], check=True)
                status, output = run_with_progress(
                    f"git pull origin {DEFAULT_BRANCH}",
                    "Pulling changes",
                    total_steps=50,
                )
                if status != 0:
                    status_error(f"Git update failed: {output}")
                logging.info(output)
                if args.verbose:
                    console.print(f"[info]ℹ Git output: {truncate_text(output, cols-3)}")
                new_commit = subprocess.check_output(
                    ["git", "rev-parse", "--short", "HEAD"], text=True
                ).strip()
                if current_commit != new_commit:
                    changes = subprocess.check_output(
                        ["git", "log", "--oneline", f"{current_commit}..HEAD"], text=True
                    ).strip().splitlines()
                    console.print(f"[info]ℹ {truncate_text(f'New commit: {new_commit}', cols-3)}")
                    console.print(f"[info]ℹ {truncate_text(f'Changes: {len(changes)} commits', cols-3)}")
                    if args.verbose:
                        console.print(f"[info]ℹ Log: {truncate_text(str(changes), cols-3)}")
                else:
                    console.print(f"[info]ℹ Up to date")
            else:
                console.print(f"[info]ℹ Dry run: Would update {PIHPSDR_DIR}")
        except subprocess.CalledProcessError as e:
            status_error(f"Git update failed: {str(e)}")
    else:
        status_start("Cloning repository")
        if not args.dry_run:
            try:
                status, output = run_with_progress(
                    f"git clone {REPO_URL} {PIHPSDR_DIR}",
                    "Cloning repository",
                    total_steps=50,
                )
                if status != 0:
                    status_error(f"Git clone failed: {output}")
                logging.info(output)
                if args.verbose:
                    console.print(f"[info]ℹ Git output: {truncate_text(output, cols-3)}")
                os.chdir(PIHPSDR_DIR)
                new_commit = subprocess.check_output(
                    ["git", "rev-parse", "--short", "HEAD"], text=True
                ).strip()
                console.print(f"[info]ℹ {truncate_text(f'Commit: {new_commit}', cols-3)}")
            except subprocess.CalledProcessError as e:
                status_error(f"Git clone failed: {str(e)}")
        else:
            console.print(f"[info]ℹ Dry run: Would clone to {PIHPSDR_DIR}")
    status_success("Repository updated")

# Build pihpsdr
def build_pihpsdr(args):
    render_section("piHPSDR Build")
    status_start("Cleaning build")
    try:
        os.chdir(PIHPSDR_DIR)
        if not args.dry_run:
            status, output = run_with_progress("make clean", "Cleaning build", total_steps=20)
            if status != 0:
                status_error(f"make clean failed: {output}")
            logging.info(output)
            if args.verbose:
                console.print(f"[info]ℹ Clean output: {truncate_text(output, cols-3)}")
        else:
            console.print(f"[info]ℹ Dry run: Would run make clean in {PIHPSDR_DIR}")
        status_success("Build cleaned")

        status_start("Installing dependencies")
        libinstall_script = PIHPSDR_DIR / "LINUX" / "libinstall.sh"
        if libinstall_script.exists():
            if not args.dry_run:
                status, output = run_with_progress(
                    f"bash {libinstall_script}",
                    "Installing dependencies",
                    total_steps=200,
                    timeout=600,
                )
                if status != 0:
                    status_error(f"Dependency installation failed: {output}")
                logging.info(output)
                if args.verbose:
                    console.print(f"[info]ℹ Dependency output: {truncate_text(output, cols-3)}")
            else:
                console.print(f"[info]ℹ Dry run: Would run {libinstall_script}")
            status_success("Dependencies installed")
        else:
            status_error(f"No libinstall.sh script found at {libinstall_script}")

        status_start("Building piHPSDR")
        if args.no_gpio:
            console.print(f"[info]ℹ {truncate_text('Building with GPIO disabled', cols-3)}")
            if not args.dry_run:
                makefile = PIHPSDR_DIR / "Makefile"
                with makefile.open("r") as f:
                    content = f.read()
                content = content.replace("#CONTROLLER=NO_CONTROLLER", "CONTROLLER=NO_CONTROLLER")
                with makefile.open("w") as f:
                    f.write(content)
                status, output = run_with_progress(
                    "make",
                    "Building piHPSDR",
                    total_steps=200,
                    timeout=600,
                )
                if status != 0:
                    status_error(f"piHPSDR build failed: {output}")
                logging.info(output)
                if args.verbose:
                    console.print(f"[info]ℹ Build output: {truncate_text(output, cols-3)}")
            else:
                console.print(f"[info]ℹ Dry run: Would build with GPIO disabled")
        else:
            if not args.dry_run:
                status, output = run_with_progress(
                    "make",
                    "Building piHPSDR",
                    total_steps=200,
                    timeout=600,
                )
                if status != 0:
                    status_error(f"piHPSDR build failed: {output}")
                logging.info(output)
                if args.verbose:
                    console.print(f"[info]ℹ Build output: {truncate_text(output, cols-3)}")
            else:
                console.print(f"[info]ℹ Dry run: Would build piHPSDR")
        status_success("piHPSDR built")
    except Exception as e:
        status_error(f"Build failed: {str(e)}")

# System stats
def get_system_stats():
    if is_minimal_mode():
        return
    global cols
    cols, _ = get_term_size()
    cpu = psutil.cpu_percent(interval=1)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage(str(Path.home()))
    stats = f"CPU: {cpu:.0f}% | Mem: {mem.used / 1024**2:.0f}/{mem.total / 1024**2:.0f}MB | Disk: {disk.used / 1024**3:.1f}/{disk.total / 1024**3:.1f}G"
    console.print(f"[info]ℹ {truncate_text(stats, cols-3)}")

# Summary report
def print_summary_report(backup_created, start_time):
    render_section("Summary")
    cols, _ = get_term_size()
    duration = int(time.time() - start_time)
    console.print(f"[success]✔ {truncate_text(f'Completed: {datetime.now()}', cols-3)}")
    console.print(f"[info]ℹ {truncate_text(f'Duration: {duration} seconds', cols-3)}")
    console.print(f"[info]ℹ {truncate_text(f'Log: {log_file}', cols-3)}")
    if backup_created:
        console.print(f"[success]✔ {truncate_text(f'Backup: {BACKUP_DIR}', cols-3)}")
    else:
        status_warning("No backup created")

# Main execution
def main():
    global log_file
    start_time = time.time()
    backup_created = False
    args = parse_args()

    log_file = init_logging()

    # Print flag messages
    if args.skip_git:
        console.print(f"[warning]⚠ Skipping Git update")
    if args.y:
        console.print(f"[success]✔ Backup enabled via -y flag")
    if args.n:
        console.print(f"[warning]⚠ Backup disabled via -n flag")
    if args.no_gpio:
        console.print(f"[warning]⚠ GPIO disabled for Radioberry compatibility")
    if args.dry_run:
        console.print(f"[warning]⚠ Dry run enabled")
    if args.verbose:
        console.print(f"[info]ℹ Verbose output enabled")
    draw_transition()

    check_requirements(args)
    if PIHPSDR_DIR.exists():
        backup_created = create_backup(args)
    update_git(args)
    build_pihpsdr(args)
    print_summary_report(backup_created, start_time)
    render_top_section(f"{SCRIPT_NAME} v{SCRIPT_VERSION} Done")
    get_system_stats()
    console.print(f"[success]✔ Complete!")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        console.print(Panel("Script interrupted by user", style="error", border_style="red", width=min(60, get_term_size()[0])))
        sys.exit(1)
    except Exception as e:
        status_error(f"Unexpected error: {str(e)}")
    finally:
        os.chdir(Path.home())
