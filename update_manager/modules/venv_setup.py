# modules/venv_setup.py
import subprocess
import shutil
import os

def setup_venv(logger, is_buster, venv_path, no_clean, dry_run):
    if dry_run:
        logger.info("[Dry Run] Skipping venv setup")
        return
    if not no_clean and os.path.exists(venv_path):
        logger.info("Removing existing venv...")
        shutil.rmtree(venv_path)
    logger.info("Creating virtual environment...")
    subprocess.run(["python3", "-m", "venv", venv_path], check=True)
    pip_path = os.path.join(venv_path, "bin", "pip")
    logger.info("Upgrading pip...")
    subprocess.run([pip_path, "install", "--upgrade", "pip", "setuptools", "wheel"], check=True)
    if is_buster:
        pkgs = ["flask==2.2.5", "ansi2html==1.9.2", "psutil==5.9.8", "gunicorn", "gevent==21.12.0"]
    else:
        pkgs = ["flask", "ansi2html==1.9.2", "psutil==7.0.0", "pyfiglet", "gunicorn", "gevent"]
    logger.info("Installing Python packages...")
    subprocess.run([pip_path, "install", "--timeout", "120", "--extra-index-url", "https://www.piwheels.org/simple"] + pkgs, check=True)
    logger.info("Virtual environment set up")