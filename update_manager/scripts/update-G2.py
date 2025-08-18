#!/usr/bin/env python3
# update-G2.py - Saturn Update Script (Python drop-in for update-G2.sh)
# Mirrors the original bash orchestrator's behavior while being friendly to
# non-interactive/Go webapp use.
#
# Flags:
#   --skip-git     : skip repository update
#   -y             : auto-create backup (no prompt)
#   -n             : skip backup entirely
#   --dry-run      : simulate actions only
#   --verbose      : stream sub-process output live
#   --debug        : extra debug logs
#
# Repo layout assumed by the original bash script:
#   SATURN_DIR = ~/github/Saturn
#   scripts/               (contains update-p2app.sh, update-desktop-apps.sh, install-libraries.sh, find-bin.sh)
#   rules/install-rules.sh (udev)
#   desktop/               (desktop .desktop shortcuts)

import os
import sys
import time
import shutil
import glob
import json
import argparse
import subprocess
import logging
from datetime import datetime

# -----------------------------
# Config / constants
# -----------------------------
HOME = os.path.expanduser("~")
SATURN_DIR = os.path.join(HOME, "github", "Saturn")
LOG_DIR = os.path.join(HOME, "saturn-logs")
os.makedirs(LOG_DIR, exist_ok=True)
LOG_FILE = os.path.join(LOG_DIR, f"saturn-update-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log")
BACKUP_DIR = os.path.join(HOME, f"saturn-backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}")

# Optional banner dependency; do NOT hard fail if missing
try:
    from pyfiglet import Figlet
except Exception:
    Figlet = None

# ANSI (kept minimal/compatible for logs & web)
class C:
    RED="\033[31m"; GRN="\033[32m"; YEL="\033[33m"; BLU="\033[34m"; CYA="\033[36m"; WHT="\033[37m"; END="\033[0m"

# -----------------------------
# Helpers
# -----------------------------
def term_size():
    cols, lines = shutil.get_terminal_size((80, 24))
    return max(40, min(120, cols)), max(10, lines)

def trunc(s, maxlen):
    s = ''.join(ch for ch in s if ch.isprintable())
    return s if len(s) <= maxlen else s[:maxlen-2] + ".."

def info(msg):   print(f"{C.CYA}ℹ {msg}{C.END}"); logging.info(msg)
def ok(msg):     print(f"{C.GRN}✔ {msg}{C.END}"); logging.info(msg)
def warn(msg):   print(f"{C.YEL}⚠ {msg}{C.END}"); logging.warning(msg)
def err_out(msg, exit_code=1):
    print(f"{C.RED}✗ {msg}{C.END}", file=sys.stderr)
    logging.error(msg)
    sys.exit(exit_code)

def section(title):
    cols, _ = term_size()
    print(f"\n{C.CYA}{'═'*5} {trunc(title, cols-12)} {'═'*5}{C.END}\n")
    logging.info(f"=== {title} ===")

def run(cmd, *, live=False, cwd=None, check=True, env=None):
    """Run a command. If live=True, stream output; else capture and return (rc, out)."""
    if args.dry_run:
        info(f"[Dry Run] {' '.join(cmd)}")
        return 0, ""
    if live or args.verbose:
        p = subprocess.Popen(cmd, cwd=cwd, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        for line in p.stdout:
            line = line.rstrip("\n")
            print(line)
            logging.info(line)
        rc = p.wait()
        if check and rc != 0:
            err_out(f"Command failed ({rc}): {' '.join(cmd)}")
        return rc, ""
    else:
        cp = subprocess.run(cmd, cwd=cwd, env=env, text=True, capture_output=True)
        out = (cp.stdout or "") + (cp.stderr or "")
        if out.strip():
            for ln in out.splitlines():
                logging.info(ln)
        if check and cp.returncode != 0:
            err_out(f"Command failed ({cp.returncode}): {' '.join(cmd)}\n{out}")
        return cp.returncode, out

# -----------------------------
# Logging (safe Tee that works in web/pipe)
# -----------------------------
class Tee:
    def __init__(self, *files):
        self.files = files
    def write(self, data):
        for f in self.files:
            try:
                f.write(data)
                f.flush()
            except Exception:
                pass
    def flush(self):
        for f in self.files:
            try: f.flush()
            except Exception: pass
    # fileno guard so os.isatty(...) checks don’t blow up
    def fileno(self):
        raise OSError("No fileno for Tee")

def init_logging():
    logging.basicConfig(level=logging.DEBUG if args.debug else logging.INFO,
                        format="%(asctime)s [%(levelname)s] %(message)s",
                        handlers=[logging.FileHandler(LOG_FILE)])
    logfile = open(LOG_FILE, "a", buffering=1)
    sys.stdout = Tee(sys.__stdout__, logfile)
    sys.stderr = Tee(sys.__stderr__, logfile)

    # Banner (no tput clear; safe for headless)
    cols, _ = term_size()
    if Figlet:
        try:
            f = Figlet(font='standard', width=max(60, cols-2), justify='center')
            banner = f.renderText('G2 Saturn').rstrip()
        except Exception:
            banner = "G2 Saturn"
    else:
        banner = "G2 Saturn"
    print(f"\n{C.RED}{banner}{C.END}\n{C.BLU}{'Update Manager v2.14'.center(cols)}{C.END}\n")

# -----------------------------
# CLI
# -----------------------------
def parse_args():
    p = argparse.ArgumentParser(description="Saturn Update Orchestrator (Python)")
    p.add_argument("--skip-git", action="store_true", help="Skip Git repository update")
    p.add_argument("-y", action="store_true", help="Auto-create backup (no prompt)")
    p.add_argument("-n", action="store_true", help="Skip backup creation")
    p.add_argument("--dry-run", action="store_true", help="Simulate actions only")
    p.add_argument("--verbose", action="store_true", help="Stream subprocess output live")
    p.add_argument("--debug", action="store_true", help="Verbose logging")
    return p.parse_args()

# -----------------------------
# Steps (mirroring the bash)
# -----------------------------
def system_info():
    section("System Info")
    cols, _ = term_size()
    host = os.uname().nodename
    try:
        user = os.getlogin()
    except Exception:
        user = os.environ.get("USER", "unknown")
    sysinfo = f"{os.uname().sysname} {os.uname().release} {os.uname().machine}"
    os_release = "Unknown"
    if os.path.isfile("/etc/os-release"):
        try:
            with open("/etc/os-release") as f:
                for line in f:
                    if line.startswith("PRETTY_NAME="):
                        os_release = line.split("=", 1)[1].strip().strip('"')
                        break
        except Exception:
            pass
    info(trunc(f"Host: {host}", cols-7))
    info(trunc(f"User: {user}", cols-7))
    info(trunc(f"System: {sysinfo}", cols-7))
    info(trunc(f"OS: {os_release}", cols-7))

def check_requirements():
    section("System Check")
    # basic commands expected by the bash version
    needed_cmds = ["git", "make", "gcc", "sudo", "rsync"]
    missing = [c for c in needed_cmds if shutil.which(c) is None]
    if missing:
        err_out(f"Missing commands: {', '.join(missing)}")

    # disk space (MB) in HOME
    try:
        st = shutil.disk_usage(HOME)
        free_mb = int(st.free / 1024 / 1024)
        ok(f"Disk: {free_mb}MB free")
    except Exception as e:
        warn(f"Disk check failed: {e}")

def check_connectivity():
    if args.skip_git:
        warn("Skipping network check (per --skip-git)")
        return
    section("Network Check")
    rc, _ = run(["ping", "-c", "1", "-W", "2", "github.com"], live=bool(args.verbose), check=False)
    if rc == 0:
        ok("Network verified")
    else:
        warn("Cannot reach GitHub (continuing)")

def repository_section():
    section("Repository")
    cols, _ = term_size()
    if not os.path.isdir(SATURN_DIR):
        err_out(f"No Saturn dir: {SATURN_DIR}")
    info(trunc(f"Dir: {SATURN_DIR}", cols-7))
    # size/files/dirs
    try:
        # du may be slow; keep simple
        _rc, out = run(["du", "-sh", SATURN_DIR], check=False)
        size = (out.split()[0] if out.strip() else "?")
        info(trunc(f"Size: {size}", cols-7))
    except Exception:
        pass
    try:
        file_cnt = sum(len(files) for _, _, files in os.walk(SATURN_DIR))
        dir_cnt  = sum(len(dirs)  for _, dirs, _ in os.walk(SATURN_DIR))
        info(trunc(f"Files: {file_cnt}, Dirs: {dir_cnt}", cols-7))
    except Exception:
        pass

def maybe_backup():
    if args.n:
        warn("Backup skipped (-n)")
        return False
    if not args.y:
        # If running under webapp, stdin may not be a TTY — default to "no prompt" behavior.
        if not sys.__stdin__.isatty():
            warn("Non-interactive session: backup skipped (use -y to force)")
            return False
        # interactive prompt
        try:
            ans = input("Create a backup? (y/n): ").strip().lower()
        except Exception:
            ans = "n"
        if ans != "y":
            warn("Backup skipped")
            return False

    if args.dry_run:
        info("[Dry Run] Simulating backup creation")
        return True

    try:
        os.makedirs(BACKUP_DIR, exist_ok=True)
        # keep 4 most recent old backups (like bash)
        old = sorted([p for p in glob.glob(os.path.join(HOME, "saturn-backup-*")) if os.path.isdir(p)], reverse=True)
        for d in old[4:]:
            shutil.rmtree(d, ignore_errors=True)
            info(f"Deleted old backup: {d}")
        info(f"Location: {BACKUP_DIR}")
        # Use rsync if available for speed; else shutil
        if shutil.which("rsync"):
            run(["rsync", "-a", f"{SATURN_DIR}/", f"{BACKUP_DIR}/"], live=True)
        else:
            # fallback (slower)
            shutil.copytree(SATURN_DIR, BACKUP_DIR, dirs_exist_ok=True)
        ok("Backup created")
        return True
    except Exception as e:
        err_out(f"Backup failed: {e}")

def update_git():
    if args.skip_git:
        warn("Skipping repository update")
        return
    section("Git Update")

    # Sanity checks
    if not os.path.isdir(SATURN_DIR):
        err_out(f"Cannot access: {SATURN_DIR}")
    if not os.path.isdir(os.path.join(SATURN_DIR, ".git")):
        err_out("Not a Git repository")

    # Stash local changes if any
    rc, _ = run(["git", "diff-index", "--quiet", "HEAD", "--"], cwd=SATURN_DIR, check=False)
    if rc != 0:
        warn("Stashing changes")
        run(["git", "stash", "push", "-m", f"Auto-stash {datetime.now():%Y-%m-%d %H:%M:%S}"], cwd=SATURN_DIR, live=True)

    # Branch / commit
    _rc, out = run(["git", "branch", "--show-current"], cwd=SATURN_DIR, check=False)
    branch = out.strip() or "HEAD"
    info(f"Branch: {branch}")
    _rc, out = run(["git", "rev-parse", "--short", "HEAD"], cwd=SATURN_DIR, check=False)
    before = out.strip()
    info(f"Commit: {before or '?'}")

    # Pull
    run(["git", "pull", "origin", "main"], cwd=SATURN_DIR, live=True)

    _rc, out = run(["git", "rev-parse", "--short", "HEAD"], cwd=SATURN_DIR, check=False)
    after = out.strip()
    if before and after and before != after:
        _rc, out = run(["git", "log", "--oneline", f"{before}..HEAD"], cwd=SATURN_DIR, check=False)
        nchanges = len([ln for ln in out.splitlines() if ln.strip()])
        info(f"New commit: {after} ({nchanges} changes)")
    else:
        info("Up to date")
    ok("Repository updated")

def install_libraries():
    section("Libraries")
    script = os.path.join(SATURN_DIR, "scripts", "install-libraries.sh")
    if not os.path.isfile(script):
        warn("No install script found: scripts/install-libraries.sh")
        return
    if args.dry_run:
        info(f"[Dry Run] Would run: {script}")
        return
    # sudo may prompt; your original bash script used sudo here as well
    run(["bash", script], live=True, cwd=os.path.dirname(script))
    ok("Libraries installed")

def build_p2app():
    section("p2app Build")
    script = os.path.join(SATURN_DIR, "scripts", "update-p2app.sh")
    if not os.path.isfile(script):
        warn("No build script: scripts/update-p2app.sh")
        return
    if args.dry_run:
        info(f"[Dry Run] Would run: {script}")
        return
    run(["bash", script], live=True, cwd=os.path.dirname(script))
    ok("p2app built")

def build_desktop_apps():
    section("Desktop Apps")
    script = os.path.join(SATURN_DIR, "scripts", "update-desktop-apps.sh")
    if not os.path.isfile(script):
        warn("No build script: scripts/update-desktop-apps.sh")
        return
    if args.dry_run:
        info(f"[Dry Run] Would run: {script}")
        return
    run(["bash", script], live=True, cwd=os.path.dirname(script))
    ok("Apps built")

def install_udev_rules():
    section("Udev Rules")
    rules_dir = os.path.join(SATURN_DIR, "rules")
    script = os.path.join(rules_dir, "install-rules.sh")
    if not os.path.isfile(script):
        warn("No udev install script: rules/install-rules.sh")
        return
    if args.dry_run:
        info(f"[Dry Run] Would run (sudo) {script}")
        return
    # match bash (cd rules && sudo ./install-rules.sh)
    run(["sudo", "./install-rules.sh"], live=True, cwd=rules_dir)
    ok("Rules installed")

def install_desktop_icons():
    section("Desktop Icons")
    desktop_src = os.path.join(SATURN_DIR, "desktop")
    desktop_dst = os.path.join(HOME, "Desktop")
    if not (os.path.isdir(desktop_src) and os.path.isdir(desktop_dst)):
        warn("No desktop dir (need Saturn/desktop and ~/Desktop)")
        return
    if args.dry_run:
        info(f"[Dry Run] Would copy {desktop_src}/*.desktop -> {desktop_dst}/")
        return
    # copy then chmod +x
    copied = 0
    for f in glob.glob(os.path.join(desktop_src, "*.desktop")):
        dst = os.path.join(desktop_dst, os.path.basename(f))
        shutil.copy2(f, dst)
        try:
            os.chmod(dst, os.stat(dst).st_mode | 0o111)
        except Exception:
            pass
        copied += 1
    if copied:
        ok("Shortcuts installed")
    else:
        warn("No .desktop files to copy")

def check_fpga_binary():
    section("FPGA Binary")
    script = os.path.join(SATURN_DIR, "scripts", "find-bin.sh")
    if not os.path.isfile(script):
        warn("No verify script: scripts/find-bin.sh")
        return
    if args.dry_run:
        info(f"[Dry Run] Would run: {script}")
        return
    run(["bash", script], live=True, cwd=os.path.dirname(script))
    ok("Binary verified")

def summary(start_time, backup_created):
    section("Summary")
    info(f"Completed: {datetime.now()}")
    info(f"Duration: {int(time.time() - start_time)} seconds")
    info(f"Log: {LOG_FILE}")
    if backup_created:
        ok(f"Backup: {BACKUP_DIR}")
    else:
        warn("No backup created")

def fpga_instructions():
    section("FPGA Programming")
    ok("Launch 'flashwriter' from desktop (use 'xvfb-run flashwriter' if headless)")
    ok("Navigate: File > Open > ~/github/Saturn/FPGA")
    ok("Select .BIT file")
    ok("Verify 'primary' selected")
    ok("Click 'Program'")

def important_notes():
    section("Important Notes")
    warn("FPGA programming takes ~3 minutes")
    warn("Power cycle required after")
    warn("Keep terminal open")
    warn(f"Log: {LOG_FILE}")

def footer():
    cols, _ = term_size()
    print(f"\n{C.CYA}{'═'*5} {'SATURN UPDATE v2.14 Done'} {'═'*5}{C.END}")
    # Simple system stats (best-effort)
    try:
        # CPU rough — parse top
        cpu = "?"
        top_out = subprocess.run(["top", "-bn1"], capture_output=True, text=True).stdout
        for ln in top_out.splitlines():
            if ln.strip().startswith("%Cpu") or "Cpu(s)" in ln:
                parts = ln.replace(",", " ").split()
                # Typical: Cpu(s):  5.3%us, ...
                for p in parts:
                    if p.endswith("%us") or p.endswith("%us,"):
                        cpu = p.replace("%us", "").replace("%us,", "")
                        break
                break
        mem_out = subprocess.run(["free", "-m"], capture_output=True, text=True).stdout.splitlines()
        mem = mem_out[1].split()
        mem_used = f"{mem[2]}/{mem[1]}MB"
        disk = shutil.disk_usage(HOME)
        disk_text = f"{disk.used/1024**3:.1f}G/{disk.total/1024**3:.1f}G"
        info(trunc(f"CPU: {cpu}% | Mem: {mem_used} | Disk: {disk_text}", cols-7))
    except Exception:
        pass

# -----------------------------
# Main
# -----------------------------
if __name__ == "__main__":
    args = parse_args()
    start = time.time()
    init_logging()
    system_info()
    check_requirements()
    check_connectivity()
    repository_section()
    backup_created = maybe_backup()
    update_git()
    install_libraries()
    build_p2app()
    build_desktop_apps()
    install_udev_rules()
    install_desktop_icons()
    check_fpga_binary()
    summary(start, backup_created)
    fpga_instructions()
    important_notes()
    footer()
    # Return to HOME, like the bash script
    try:
        os.chdir(HOME)
    except Exception:
        pass
