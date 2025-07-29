# modules/service_setup.py
import subprocess
import textwrap
import os
from pathlib import Path

def setup_systemd(logger, systemd_service, scripts_dir, venv_path, port, log_dir, dry_run):
    if dry_run:
        logger.info("[Dry Run] Skipping systemd setup")
        return
    service_content = textwrap.dedent(f"""\
[Unit]
Description=Saturn Update Manager Gunicorn Server
After=network.target

[Service]
User=pi
Group=pi
WorkingDirectory={scripts_dir}
Environment="PYTHONPATH={scripts_dir}"
ExecStart={venv_path / 'bin' / 'gunicorn'} --chdir {scripts_dir} -w 5 --worker-class gevent -b 0.0.0.0:{port} -t 600 saturn_update_manager:app
Restart=always
RestartSec=5s
StandardOutput=append:{log_dir / 'saturn-update-manager.log'}
StandardError=append:{log_dir / 'saturn-update-manager-error.log'}

[Install]
WantedBy=multi-user.target
""")
    with open(systemd_service, "w") as f:
        f.write(service_content)
    os.chmod(systemd_service, 0o644)
    subprocess.run(["systemctl", "daemon-reload"], check=True)
    subprocess.run(["systemctl", "enable", "saturn-update-manager"], check=True)
    subprocess.run(["systemctl", "start", "saturn-update-manager"], check=True)
    logger.info("Systemd service set up")
