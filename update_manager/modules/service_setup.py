# modules/service_setup.py
import subprocess
import textwrap
import os
from pathlib import Path
import pwd

def setup_systemd(logger, systemd_service, scripts_dir, venv_path, port, log_dir, dry_run, user_home, username):
    """
    Create/enable/start the systemd unit for the web app, using the invoking user.

    - User/Group = <username>
    - WorkingDirectory = <user_home>/.saturn/runtime/scripts
    - Ensures runtime dir exists & is owned by the user
    """
    if dry_run:
        logger.info("[Dry Run] Skipping systemd setup")
        return

    # Resolve uid/gid
    try:
        pw = pwd.getpwnam(username)
        uid = pw.pw_uid
        gid = pw.pw_gid
    except KeyError:
        logger.error(f"User '{username}' not found; cannot set up service.")
        return

    # User-specific runtime dir
    runtime_scripts = user_home / ".saturn" / "runtime" / "scripts"
    try:
        runtime_scripts.mkdir(parents=True, exist_ok=True)
        os.chown(str(runtime_scripts), uid, gid)
        os.chmod(str(runtime_scripts), 0o755)
        effective_scripts_dir = runtime_scripts
        logger.info(f"Using/created runtime dir for service: {effective_scripts_dir}")
    except OSError as e:
        logger.error(f"Failed to create runtime dir {runtime_scripts}: {str(e)}")
        return  # Exit early on failure

    # Remove/replace any old service variants that pointed at the repo path
    if os.path.exists(systemd_service):
        with open(systemd_service, 'r', encoding='utf-8') as f:
            content = f.read()
            if '/github/Saturn/update_manager/scripts' in content:
                logger.warning("Old service detected with repo path - removing and replacing")
                if not dry_run:
                    try:
                        subprocess.run(["systemctl", "stop", "saturn-update-manager"], check=True)
                        subprocess.run(["systemctl", "disable", "saturn-update-manager"], check=True)
                        os.remove(systemd_service)
                        logger.info("Old service removed")
                    except subprocess.CalledProcessError as e:
                        logger.error(f"Failed to remove old service: {str(e)}")
                        return
                    except OSError as e:
                        logger.error(f"Failed to delete old service file: {str(e)}")
                        return

    service_content = textwrap.dedent(f"""\
[Unit]
Description=Saturn Update Manager Gunicorn Server
After=network.target

[Service]
User={username}
Group={username}
WorkingDirectory={effective_scripts_dir}
Environment="PYTHONPATH={effective_scripts_dir}"
ExecStart={venv_path / 'bin' / 'gunicorn'} --chdir {effective_scripts_dir} -w 5 --worker-class gevent -b 0.0.0.0:{port} -t 600 saturn_update_manager:app
Restart=always
RestartSec=5s
StandardOutput=append:{log_dir / 'saturn-update-manager.log'}
StandardError=append:{log_dir / 'saturn-update-manager-error.log'}

[Install]
WantedBy=multi-user.target
""")

    if dry_run:
        logger.info(f"[Dry Run] Would write service file:\n{service_content}")
        return

    try:
        with open(systemd_service, "w", encoding='utf-8') as f:
            f.write(service_content)
        os.chmod(systemd_service, 0o644)
        subprocess.run(["systemctl", "daemon-reload"], check=True)
        subprocess.run(["systemctl", "enable", "saturn-update-manager"], check=True)
        subprocess.run(["systemctl", "start", "saturn-update-manager"], check=True)
        logger.info("Systemd service set up successfully")
    except (OSError, subprocess.CalledProcessError) as e:
        logger.error(f"Failed to set up service: {str(e)}")
    except Exception as e:
        logger.error(f"Unexpected error during service setup: {str(e)}")
