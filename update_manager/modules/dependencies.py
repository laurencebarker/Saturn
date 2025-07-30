# modules/dependencies.py
import subprocess

def install_system_deps(logger, is_buster, dry_run, autoremove=True):
    """
    Installs required system dependencies for Saturn Update Manager.

    Args:
        logger: Logger object for logging messages.
        is_buster: Boolean indicating if OS is Debian Buster.
        dry_run: Boolean indicating if actions should be simulated.
        autoremove: Boolean indicating if orphaned packages should be removed.
    """
    logger.info("Installing system dependencies...")
    if dry_run:
        logger.info("[Dry Run] Skipping system dependency installation")
        return
    packages = [
        "python3",
        "python3-venv",
        "python3-pip",
        "apache2",
        "apache2-utils",
        "libapache2-mod-proxy-uwsgi",
        "lsof",
        "build-essential",
        "python3-dev"
    ]
    if is_buster:
        packages.remove("libapache2-mod-proxy-uwsgi")
        packages.append("libapache2-mod-wsgi-py3")
    cmd = ["apt-get", "update"]
    logger.info(f"Running: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)
    cmd = ["apt-get", "install", "-y"] + packages
    logger.info(f"Running: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)
    
    if autoremove:
        logger.info("Removing orphaned packages...")
        cmd = ["apt-get", "autoremove", "-y"]
        logger.info(f"Running: {' '.join(cmd)}")
        subprocess.run(cmd, check=True)
    else:
        logger.info("Skipping orphaned package removal")
    
    logger.info("System dependencies installed")