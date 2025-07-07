#!/usr/bin/env python3
# update-pihpsdr-gui.py - piHPSDR Update Script with Tkinter GUI
# Automates cloning, updating, and building the pihpsdr repository with a desktop GUI
# Version: 1.0 (GUI-based with Enhanced Visuals and Backup Flags)
# Written by: Jerry DeLong KD4YAL
# Dependencies: psutil (version 7.0.0) installed in ~/venv
# Usage: source ~/venv/bin/activate; python3 ~/github/Saturn/scripts/update-pihpsdr-gui.py; deactivate

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
import glob
import tkinter as tk
from tkinter import ttk, scrolledtext
from threading import Thread
import queue

# Script metadata
SCRIPT_NAME = "piHPSDR Update"
SCRIPT_VERSION = "1.0"
PIHPSDR_DIR = Path.home() / "github" / "pihpsdr"
LOG_DIR = Path.home() / "saturn-logs"
BACKUP_DIR = Path.home() / f"pihpsdr-backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
REPO_URL = "https://github.com/dl1ycf/pihpsdr"
DEFAULT_BRANCH = "master"

# Setup logging to file
def setup_logging():
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_file = LOG_DIR / f"pihpsdr-update-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[logging.FileHandler(log_file)],
    )
    return log_file

# GUI Application
class PiHPSDRUpdateApp:
    def __init__(self, root):
        self.root = root
        self.root.title(f"{SCRIPT_NAME} v{SCRIPT_VERSION}")
        self.root.geometry("800x600")
        self.root.resizable(True, True)
        self.queue = queue.Queue()
        self.running = False
        self.log_file = setup_logging()
        self.setup_styles()
        self.create_widgets()
        self.root.protocol("WM_DELETE_WINDOW", self.on_closing)
        self.check_queue()

    def setup_styles(self):
        self.style = ttk.Style()
        self.style.theme_use("clam")
        self.style.configure("TButton", padding=5, font=("Arial", 10))
        self.style.configure("TLabel", font=("Arial", 10))
        self.style.configure("TCheckbutton", font=("Arial", 10))
        self.style.configure("Header.TLabel", font=("Arial", 14, "bold"), foreground="#005f87")
        self.style.configure("Status.TLabel", font=("Arial", 10), foreground="green")

    def create_widgets(self):
        # Main frame
        self.main_frame = ttk.Frame(self.root, padding="10")
        self.main_frame.grid(row=0, column=0, sticky="nsew")
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)

        # Header
        ttk.Label(self.main_frame, text=f"{SCRIPT_NAME} v{SCRIPT_VERSION}", style="Header.TLabel").grid(row=0, column=0, columnspan=2, pady=10)

        # Options frame
        self.options_frame = ttk.LabelFrame(self.main_frame, text="Options", padding="5")
        self.options_frame.grid(row=1, column=0, columnspan=2, sticky="ew", pady=5)

        self.skip_git_var = tk.BooleanVar()
        self.no_gpio_var = tk.BooleanVar()
        self.dry_run_var = tk.BooleanVar()
        self.verbose_var = tk.BooleanVar()
        self.auto_backup_var = tk.BooleanVar()
        self.skip_backup_var = tk.BooleanVar()

        ttk.Checkbutton(self.options_frame, text="Skip Git Update", variable=self.skip_git_var).grid(row=0, column=0, sticky="w", padx=5)
        ttk.Checkbutton(self.options_frame, text="Disable GPIO (Radioberry)", variable=self.no_gpio_var).grid(row=0, column=1, sticky="w", padx=5)
        ttk.Checkbutton(self.options_frame, text="Dry Run", variable=self.dry_run_var).grid(row=1, column=0, sticky="w", padx=5)
        ttk.Checkbutton(self.options_frame, text="Verbose Output", variable=self.verbose_var).grid(row=1, column=1, sticky="w", padx=5)
        ttk.Checkbutton(self.options_frame, text="Auto Backup (-y)", variable=self.auto_backup_var).grid(row=2, column=0, sticky="w", padx=5)
        ttk.Checkbutton(self.options_frame, text="Skip Backup (-n)", variable=self.skip_backup_var).grid(row=2, column=1, sticky="w", padx=5)

        # Action buttons
        self.start_button = ttk.Button(self.main_frame, text="Start Update", command=self.start_update)
        self.start_button.grid(row=2, column=0, pady=10)
        ttk.Button(self.main_frame, text="View Log", command=self.view_log).grid(row=2, column=1, pady=10)

        # Status and progress
        self.status_label = ttk.Label(self.main_frame, text="Ready", style="Status.TLabel")
        self.status_label.grid(row=3, column=0, columnspan=2, pady=5)
        self.progress = ttk.Progressbar(self.main_frame, length=400, mode="determinate")
        self.progress.grid(row=4, column=0, columnspan=2, pady=5)

        # Output text area
        self.output_text = scrolledtext.ScrolledText(self.main_frame, height=15, font=("Arial", 10), wrap=tk.WORD)
        self.output_text.grid(row=5, column=0, columnspan=2, sticky="nsew", pady=5)
        self.main_frame.columnconfigure(0, weight=1)
        self.main_frame.rowconfigure(5, weight=1)

        # System stats
        self.stats_label = ttk.Label(self.main_frame, text="", font=("Arial", 9))
        self.stats_label.grid(row=6, column=0, columnspan=2, pady=5)

    def log_message(self, message, level="info"):
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        self.output_text.insert(tk.END, f"[{timestamp}] {message}\n")
        self.output_text.see(tk.END)
        logging.info(message)

    def update_status(self, message, color="green"):
        self.status_label.configure(text=message, style="Status.TLabel")
        self.style.configure("Status.TLabel", foreground=color)

    def run_command(self, command, description, total_steps=10, timeout=300):
        process = subprocess.Popen(
            command,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        start_time = time.time()
        output_lines = []
        step = 0
        while process.poll() is None:
            if time.time() - start_time > timeout:
                process.terminate()
                self.queue.put(("error", f"{description} timed out after {timeout} seconds"))
                return 1, ""
            step += 1
            self.queue.put(("progress", step / total_steps * 100))
            time.sleep(1.0 if total_steps <= 50 else 1.5)
        self.queue.put(("progress", 100))
        output = process.communicate()[0]
        output_lines.append(output)
        return process.returncode, "\n".join(output_lines)

    def check_requirements(self):
        self.log_message("Verifying requirements")
        required = ["git", "make", "gcc", "sudo", "rsync"]
        missing = [cmd for cmd in required if shutil.which(cmd) is None]
        if missing:
            self.queue.put(("error", f"Missing commands: {', '.join(missing)}"))
            return False
        free_space = psutil.disk_usage(str(Path.home())).free / 1024**2  # MB
        if free_space < 1024:
            self.log_message(f"Low disk space: {free_space:.0f}MB", "warning")
        else:
            self.log_message(f"Disk: {free_space:.0f}MB free")
        self.log_message("Requirements met")
        return True

    def create_backup(self, args):
        self.log_message("Backup")
        do_backup = False
        if args.auto_backup:
            do_backup = True
            self.log_message("Backup enabled via -y flag")
        elif args.skip_backup:
            self.log_message("Backup skipped", "warning")
            return False
        else:
            # In GUI, assume backup unless skipped
            do_backup = True

        if do_backup:
            backup_pattern = str(Path.home() / "pihpsdr-backup-*")
            backup_dirs = sorted(glob.glob(backup_pattern), key=lambda x: os.path.getmtime(x), reverse=True)
            self.log_message(f"Found {len(backup_dirs)} existing backups")
            if not args.dry_run:
                if len(backup_dirs) > 2:
                    for old_backup in backup_dirs[2:]:
                        try:
                            shutil.rmtree(old_backup)
                            self.log_message(f"Deleted old backup: {old_backup}")
                        except Exception as e:
                            self.log_message(f"Failed to delete old backup {old_backup}: {str(e)}", "warning")
            else:
                if len(backup_dirs) > 2:
                    for old_backup in backup_dirs[2:]:
                        self.log_message(f"Dry run: Would delete old backup {old_backup}")

            self.log_message(f"Creating backup at {BACKUP_DIR}")
            if not args.dry_run:
                try:
                    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
                    status, output = self.run_command(
                        f"rsync -a {PIHPSDR_DIR}/ {BACKUP_DIR}/",
                        "Copying files",
                        total_steps=50,
                    )
                    if status != 0:
                        self.queue.put(("error", f"Backup failed: {output}"))
                        return False
                    self.log_message(output)
                    if args.verbose:
                        self.log_message(f"Backup output: {output}")
                    backup_size = sum(f.stat().st_size for f in BACKUP_DIR.rglob('*') if f.is_file()) / 1024**2
                    self.log_message(f"Size: {backup_size:.1f}MB")
                except Exception as e:
                    self.queue.put(("error", f"Backup failed: {str(e)}"))
                    return False
            else:
                self.log_message(f"Dry run: Would back up to {BACKUP_DIR}")
            self.log_message("Backup created")
            return True
        return False

    def update_git(self, args):
        self.log_message("Git Update")
        if args.skip_git:
            self.log_message("Skipping repository update", "warning")
            return

        PIHPSDR_DIR.parent.mkdir(parents=True, exist_ok=True)
        if PIHPSDR_DIR.exists():
            self.log_message("Updating repository")
            try:
                os.chdir(PIHPSDR_DIR)
                current_commit = subprocess.check_output(
                    ["git", "rev-parse", "--short", "HEAD"], text=True
                ).strip()
                self.log_message(f"Commit: {current_commit}")
                if not args.dry_run:
                    if subprocess.run(["git", "diff-index", "--quiet", "HEAD", "--"]).returncode != 0:
                        self.log_message("Stashing changes", "warning")
                        subprocess.run(["git", "stash", "push", "-m", f"Auto-stash {datetime.now()}"], check=True)
                    status, output = self.run_command(
                        f"git pull origin {DEFAULT_BRANCH}",
                        "Pulling changes",
                        total_steps=50,
                    )
                    if status != 0:
                        self.queue.put(("error", f"Git update failed: {output}"))
                        return
                    self.log_message(output)
                    if args.verbose:
                        self.log_message(f"Git output: {output}")
                    new_commit = subprocess.check_output(
                        ["git", "rev-parse", "--short", "HEAD"], text=True
                    ).strip()
                    if current_commit != new_commit:
                        changes = subprocess.check_output(
                            ["git", "log", "--oneline", f"{current_commit}..HEAD"], text=True
                        ).strip().splitlines()
                        self.log_message(f"New commit: {new_commit}")
                        self.log_message(f"Changes: {len(changes)} commits")
                        if args.verbose:
                            self.log_message(f"Log: {changes}")
                    else:
                        self.log_message("Up to date")
                else:
                    self.log_message(f"Dry run: Would update {PIHPSDR_DIR}")
            except subprocess.CalledProcessError as e:
                self.queue.put(("error", f"Git update failed: {str(e)}"))
        else:
            self.log_message("Cloning repository")
            if not args.dry_run:
                try:
                    status, output = self.run_command(
                        f"git clone {REPO_URL} {PIHPSDR_DIR}",
                        "Cloning repository",
                        total_steps=50,
                    )
                    if status != 0:
                        self.queue.put(("error", f"Git clone failed: {output}"))
                        return
                    self.log_message(output)
                    if args.verbose:
                        self.log_message(f"Git output: {output}")
                    os.chdir(PIHPSDR_DIR)
                    new_commit = subprocess.check_output(
                        ["git", "rev-parse", "--short", "HEAD"], text=True
                    ).strip()
                    self.log_message(f"Commit: {new_commit}")
                except subprocess.CalledProcessError as e:
                    self.queue.put(("error", f"Git clone failed: {str(e)}"))
            else:
                self.log_message(f"Dry run: Would clone to {PIHPSDR_DIR}")
        self.log_message("Repository updated")

    def build_pihpsdr(self, args):
        self.log_message("piHPSDR Build")
        try:
            os.chdir(PIHPSDR_DIR)
            self.log_message("Cleaning build")
            if not args.dry_run:
                status, output = self.run_command("make clean", "Cleaning build", total_steps=20)
                if status != 0:
                    self.queue.put(("error", f"make clean failed: {output}"))
                    return
                self.log_message(output)
                if args.verbose:
                    self.log_message(f"Clean output: {output}")
            else:
                self.log_message(f"Dry run: Would run make clean in {PIHPSDR_DIR}")
            self.log_message("Build cleaned")

            self.log_message("Installing dependencies")
            libinstall_script = PIHPSDR_DIR / "LINUX" / "libinstall.sh"
            if libinstall_script.exists():
                if not args.dry_run:
                    status, output = self.run_command(
                        f"bash {libinstall_script}",
                        "Installing dependencies",
                        total_steps=200,
                        timeout=600,
                    )
                    if status != 0:
                        self.queue.put(("error", f"Dependency installation failed: {output}"))
                        return
                    self.log_message(output)
                    if args.verbose:
                        self.log_message(f"Dependency output: {output}")
                else:
                    self.log_message(f"Dry run: Would run {libinstall_script}")
                self.log_message("Dependencies installed")
            else:
                self.queue.put(("error", f"No libinstall.sh script found at {libinstall_script}"))
                return

            self.log_message("Building piHPSDR")
            if args.no_gpio:
                self.log_message("Building with GPIO disabled")
                if not args.dry_run:
                    makefile = PIHPSDR_DIR / "Makefile"
                    with makefile.open("r") as f:
                        content = f.read()
                    content = content.replace("#CONTROLLER=NO_CONTROLLER", "CONTROLLER=NO_CONTROLLER")
                    with makefile.open("w") as f:
                        f.write(content)
                    status, output = self.run_command(
                        "make",
                        "Building piHPSDR",
                        total_steps=200,
                        timeout=600,
                    )
                    if status != 0:
                        self.queue.put(("error", f"piHPSDR build failed: {output}"))
                        return
                    self.log_message(output)
                    if args.verbose:
                        self.log_message(f"Build output: {output}")
                else:
                    self.log_message("Dry run: Would build with GPIO disabled")
            else:
                if not args.dry_run:
                    status, output = self.run_command(
                        "make",
                        "Building piHPSDR",
                        total_steps=200,
                        timeout=600,
                    )
                    if status != 0:
                        self.queue.put(("error", f"piHPSDR build failed: {output}"))
                        return
                    self.log_message(output)
                    if args.verbose:
                        self.log_message(f"Build output: {output}")
                else:
                    self.log_message("Dry run: Would build piHPSDR")
            self.log_message("piHPSDR built")
        except Exception as e:
            self.queue.put(("error", f"Build failed: {str(e)}"))

    def update_stats(self):
        cpu = psutil.cpu_percent(interval=1)
        mem = psutil.virtual_memory()
        disk = psutil.disk_usage(str(Path.home()))
        stats = f"CPU: {cpu:.0f}% | Mem: {mem.used / 1024**2:.0f}/{mem.total / 1024**2:.0f}MB | Disk: {disk.used / 1024**3:.1f}/{disk.total / 1024**3:.1f}GB"
        self.stats_label.configure(text=stats)
        if self.running:
            self.root.after(1000, self.update_stats)

    def start_update(self):
        if self.running:
            return
        self.running = True
        self.start_button.configure(state="disabled")
        self.output_text.delete(1.0, tk.END)
        self.progress["value"] = 0
        self.update_status("Starting update...", "blue")
        args = argparse.Namespace(
            skip_git=self.skip_git_var.get(),
            no_gpio=self.no_gpio_var.get(),
            dry_run=self.dry_run_var.get(),
            verbose=self.verbose_var.get(),
            auto_backup=self.auto_backup_var.get(),
            skip_backup=self.skip_backup_var.get(),
        )
        if args.auto_backup and args.skip_backup:
            self.log_message("Cannot use auto backup and skip backup together", "error")
            self.running = False
            self.start_button.configure(state="normal")
            self.update_status("Error", "red")
            return
        Thread(target=self.run_update, args=(args,)).start()
        self.update_stats()

    def run_update(self, args):
        start_time = time.time()
        backup_created = False
        try:
            if not self.check_requirements():
                return
            if PIHPSDR_DIR.exists():
                backup_created = self.create_backup(args)
            self.update_git(args)
            self.build_pihpsdr(args)
            duration = int(time.time() - start_time)
            self.queue.put(("success", f"Completed in {duration} seconds\nBackup: {BACKUP_DIR if backup_created else 'None'}\nLog: {self.log_file}"))
        except Exception as e:
            self.queue.put(("error", f"Unexpected error: {str(e)}"))
        finally:
            self.queue.put(("done", None))

    def check_queue(self):
        try:
            while True:
                msg_type, msg = self.queue.get_nowait()
                if msg_type == "progress":
                    self.progress["value"] = msg
                elif msg_type == "success":
                    self.update_status("Update completed", "green")
                    self.log_message(msg)
                elif msg_type == "error":
                    self.update_status("Error occurred", "red")
                    self.log_message(msg, "error")
                    self.running = False
                    self.start_button.configure(state="normal")
                elif msg_type == "done":
                    self.running = False
                    self.start_button.configure(state="normal")
        except queue.Empty:
            pass
        self.root.after(100, self.check_queue)

    def view_log(self):
        try:
            with open(self.log_file, "r") as f:
                log_content = f.read()
            log_window = tk.Toplevel(self.root)
            log_window.title("Log Viewer")
            log_window.geometry("600x400")
            log_text = scrolledtext.ScrolledText(log_window, font=("Arial", 10), wrap=tk.WORD)
            log_text.insert(tk.END, log_content)
            log_text.config(state="disabled")
            log_text.pack(fill="both", expand=True, padx=10, pady=10)
        except Exception as e:
            self.log_message(f"Failed to open log: {str(e)}", "error")

    def on_closing(self):
        if self.running:
            self.log_message("Please wait for the update to complete or interrupt the process", "warning")
            return
        self.root.destroy()

if __name__ == "__main__":
    try:
        root = tk.Tk()
        app = PiHPSDRUpdateApp(root)
        root.mainloop()
    except KeyboardInterrupt:
        sys.exit(1)
    except Exception as e:
        logging.error(f"Unexpected error: {str(e)}")
        sys.exit(1)
    finally:
        os.chdir(Path.home())
