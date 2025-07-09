
#!/usr/bin/env python3
# saturn_update_manager.py - GUI Update Manager for update-G2.py and update-pihpsdr.py
# Runs from Raspberry Pi desktop, launching scripts in a terminal with selectable flags
# Version: 1.0
# Written by: Jerry DeLong KD4YAL
# Dependencies: tkinter (standard library), subprocess, os, threading, logging, re, shutil, lxterminal
# Usage: python3 ~/github/Saturn/scripts/saturn_update_manager.py

import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox
import subprocess
import os
import threading
from pathlib import Path
import logging
from datetime import datetime
import re
import shutil

class SaturnUpdateManager:
    def __init__(self, root):
        self.root = root
        self.root.title("Saturn Update Manager")
        self.root.geometry("800x600")
        self.root.configure(bg="#F5F5F5")
        self.script_running = False

        # Paths
        self.venv_path = Path.home() / "venv" / "bin" / "activate"
        self.scripts_dir = Path.home() / "github" / "Saturn" / "scripts"
        self.log_dir = Path.home() / "saturn-logs"
        self.scripts = {
            "update-G2.py": ["--skip-git", "-y", "-n", "--dry-run", "--verbose"],
            "update-pihpsdr.py": ["--skip-git", "-y", "-n", "--no-gpio", "--dry-run", "--verbose", "--show-compile"]
        }

        # Setup logging
        self.log_dir.mkdir(parents=True, exist_ok=True)
        log_file = self.log_dir / f"saturn-update-manager-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s [%(levelname)s] %(message)s",
            handlers=[logging.FileHandler(log_file)]
        )
        self.log_file = log_file

        # Colors for Tkinter text widget (matching update-pihpsdr.py)
        self.colors = {
            "header": "#00A3CC",  # Cyan
            "success": "#00FF00",  # Green
            "warning": "#FFFF00",  # Yellow
            "error": "#FF0000",   # Red
            "info": "#0000FF",    # Blue
            "task": "#FF00FF",    # Magenta
            "banner": "#FF0000",  # Red (\033[1;31m)
            "accent": "#00B7EB"   # Blue (\033[38;5;39m)
        }

        # Validate setup
        error_message = self.validate_setup()
        if error_message:
            messagebox.showerror("Setup Error", f"Initialization failed: {error_message}\nCheck log: {self.log_file}")
            logging.error(f"Initialization failed: {error_message}")
            self.root.quit()
            return

        # GUI Elements
        self.create_widgets()
        self.configure_text_tags()

    def validate_setup(self):
        """Validate script paths, virtual environment, and dependencies."""
        try:
            # Check virtual environment
            if not self.venv_path.exists():
                return f"Virtual environment not found at {self.venv_path}"
            # Check script paths
            for script in self.scripts:
                script_path = self.scripts_dir / script
                if not script_path.exists():
                    return f"Script not found: {script_path}"
                if not os.access(script_path, os.X_OK):
                    return f"Script not executable: {script_path}"
            # Check lxterminal
            if not shutil.which("lxterminal"):
                return "lxterminal not found. Install with: sudo apt-get install lxterminal"
            # Check tkinter
            try:
                import tkinter
            except ImportError:
                return "tkinter not installed. Install with: sudo apt-get install python3-tk"
            # Check Python version compatibility
            python_version = subprocess.check_output(["python3", "--version"]).decode().strip()
            logging.info(f"Python version: {python_version}")
            return None
        except Exception as e:
            return f"Setup validation failed: {str(e)}"

    def configure_text_tags(self):
        """Configure text widget tags for colors."""
        for tag, color in self.colors.items():
            self.output_text.tag_configure(tag, foreground=color)

    def create_widgets(self):
        """Create GUI widgets."""
        # Title
        title_label = tk.Label(
            self.root, text="Saturn Update Manager", font=("DejaVu Sans", 16, "bold"),
            fg="#FF0000", bg="#F5F5F5"
        )
        title_label.pack(pady=10)

        # Script Selection
        script_frame = tk.Frame(self.root, bg="#F5F5F5")
        script_frame.pack(pady=5)
        tk.Label(script_frame, text="Select Script:", font=("DejaVu Sans", 12), bg="#F5F5F5").pack(side=tk.LEFT)
        self.script_var = tk.StringVar(value="update-pihpsdr.py")
        script_menu = ttk.Combobox(
            script_frame, textvariable=self.script_var, values=list(self.scripts.keys()),
            state="readonly", font=("DejaVu Sans", 12)
        )
        script_menu.pack(side=tk.LEFT, padx=5)
        script_menu.bind("<<ComboboxSelected>>", self.update_flags)

        # Flags Frame
        self.flags_frame = tk.Frame(self.root, bg="#F5F5F5")
        self.flags_frame.pack(pady=5)
        self.flag_vars = {}
        self.update_flags(None)

        # Output Area
        self.output_text = scrolledtext.ScrolledText(
            self.root, height=20, width=80, font=("DejaVu Sans", 12), wrap=tk.WORD
        )
        self.output_text.pack(pady=10, padx=10, fill=tk.BOTH, expand=True)

        # Status Label
        self.status_var = tk.StringVar(value=f"Ready - Log: {self.log_file}")
        status_label = tk.Label(
            self.root, textvariable=self.status_var, font=("DejaVu Sans", 12), bg="#F5F5F5", fg="#00B7EB"
        )
        status_label.pack(pady=5)

        # Buttons (at bottom)
        button_frame = tk.Frame(self.root, bg="#F5F5F5")
        button_frame.pack(side=tk.BOTTOM, pady=10)
        tk.Button(
            button_frame, text="Run", command=self.run_script, font=("DejaVu Sans", 12),
            bg="#00B7EB", fg="white", width=10
        ).pack(side=tk.LEFT, padx=5)
        tk.Button(
            button_frame, text="Exit", command=self.root.quit, font=("DejaVu Sans", 12),
            bg="#00B7EB", fg="white", width=10
        ).pack(side=tk.LEFT, padx=5)

    def update_flags(self, event):
        """Update flag checkboxes based on selected script."""
        for widget in self.flags_frame.winfo_children():
            widget.destroy()
        script = self.script_var.get()
        for flag in self.scripts[script]:
            var = tk.BooleanVar()
            self.flag_vars[flag] = var
            tk.Checkbutton(
                self.flags_frame, text=flag, variable=var, font=("DejaVu Sans", 12), bg="#F5F5F5"
            ).pack(side=tk.LEFT, padx=5)

    def parse_ansi(self, text):
        """Parse ANSI color codes and return text with Tkinter tags."""
        ansi_patterns = {
            r'\033\[1;31m': 'banner',  # Red
            r'\033\[38;5;39m': 'accent',  # Blue
            r'\[header\]': 'header',  # Cyan
            r'\[success\]': 'success',  # Green
            r'\[warning\]': 'warning',  # Yellow
            r'\[error\]': 'error',  # Red
            r'\[info\]': 'info',  # Blue
            r'\[task\]': 'task'  # Magenta
        }
        segments = []
        last_pos = 0
        for match in re.finditer(r'(\033\[[\d;]+m|\[header\]|\[success\]|\[warning\]|\[error\]|\[info\]|\[task\])', text):
            start, end = match.span()
            if last_pos < start:
                segments.append((text[last_pos:start], None))
            tag = next((tag for pattern, tag in ansi_patterns.items() if match.group(0) == pattern), None)
            if tag:
                segments.append((match.group(0), tag))
            last_pos = end
        if last_pos < len(text):
            segments.append((text[last_pos:], None))
        return segments

    def run_script(self):
        """Run the selected script in a terminal."""
        if self.script_running:
            self.output_text.insert(tk.END, "Script is already running!\n", "error")
            return
        self.script_running = True
        self.status_var.set("Running in terminal...")
        self.output_text.delete(1.0, tk.END)

        script = self.script_var.get()
        script_path = self.scripts_dir / script
        flags = [flag for flag, var in self.flag_vars.items() if var.get()]
        cmd = f"source {self.venv_path}; python3 {script_path} {' '.join(flags)}; deactivate"
        terminal_cmd = f"lxterminal -e 'bash -c \"{cmd}; read -p \\\"Press Enter to close...\\\"\"'"

        logging.info(f"Executing terminal command: {terminal_cmd}")
        threading.Thread(target=self.execute_script, args=(terminal_cmd, script), daemon=True).start()

    def execute_script(self, cmd, script):
        """Execute script in a terminal and capture output."""
        try:
            process = subprocess.Popen(
                cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1, universal_newlines=True
            )
            while process.poll() is None:
                line = process.stdout.readline()
                if line:
                    segments = self.parse_ansi(line)
                    for text, tag in segments:
                        if tag:
                            if text.startswith('\033'):
                                text = ""
                            elif text.startswith('['):
                                text = text.strip('[]') + " "
                        self.output_text.insert(tk.END, text, tag)
                    self.output_text.see(tk.END)
                    self.root.update_idletasks()
            output, _ = process.communicate()
            if output:
                segments = self.parse_ansi(output)
                for text, tag in segments:
                    if tag:
                        if text.startswith('\033'):
                            text = ""
                        elif text.startswith('['):
                            text = text.strip('[]') + " "
                    self.output_text.insert(tk.END, text, tag)
                self.output_text.see(tk.END)
            if process.returncode == 0:
                self.status_var.set(f"Completed: Log at ~/saturn-logs/{script.replace('.py', '')}-*.log")
                logging.info(f"Script {script} completed successfully")
            else:
                self.status_var.set("Failed: Check terminal output for errors")
                logging.error(f"Script {script} failed with return code {process.returncode}")
        except Exception as e:
            error_msg = f"Error: {str(e)}\n"
            self.output_text.insert(tk.END, error_msg, "error")
            self.status_var.set("Failed")
            logging.error(f"Script execution failed: {str(e)}")
        finally:
            self.script_running = False
            self.root.update_idletasks()

    def install_desktop_icons(self):
        """Install desktop shortcut for this GUI."""
        desktop_dir = self.scripts_dir
        home_desktop = Path.home() / "Desktop"
        desktop_file = desktop_dir / "SaturnUpdateManager.desktop"
        dest_file = home_desktop / "SaturnUpdateManager.desktop"

        # Ensure desktop file exists
        if not desktop_file.exists():
            with desktop_file.open("w") as f:
                f.write(f"""[Desktop Entry]
Type=Application
Name=Saturn Update Manager
Comment=GUI to manage updates for update-G2.py and update-pihpsdr.py
Exec=bash -c "source %h/venv/bin/activate; python3 %h/github/Saturn/scripts/saturn_update_manager.py >> %h/saturn-logs/saturn-update-manager.log 2>&1; deactivate"
Icon=system-software-update
Terminal=false
Categories=System;Utility;
""")
            os.chmod(desktop_file, 0o755)
            logging.info(f"Created desktop file: {desktop_file}")

        # Copy to Desktop
        try:
            if not home_desktop.exists():
                logging.warning(f"Home Desktop directory does not exist: {home_desktop}")
                return
            shutil.copy2(desktop_file, dest_file)
            os.chmod(dest_file, 0o755)
            logging.info(f"Installed desktop shortcut: {dest_file}")
            self.output_text.insert(tk.END, f"Installed desktop shortcut: {dest_file}\n")
        except Exception as e:
            logging.error(f"Shortcut install failed: {str(e)}")
            self.output_text.insert(tk.END, f"Error installing shortcut: {str(e)}\n", "error")

if __name__ == "__main__":
    try:
        root = tk.Tk()
        app = SaturnUpdateManager(root)
        app.install_desktop_icons()
        root.mainloop()
    except Exception as e:
        with open(Path.home() / "saturn-logs" / f"saturn-update-manager-error-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log", "w") as f:
            f.write(f"GUI startup error: {str(e)}\n")
        raise
