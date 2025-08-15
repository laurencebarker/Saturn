#!/usr/bin/env python3
# uninstall_update_manager.py - Uninstaller for Saturn Update Manager
# Version: 3.01 (enhanced prompts/compat)
# ... (header unchanged)

class SaturnUninstaller:
    # ... (__init__ unchanged)

    def run(self):
        self.logger.info("Starting Uninstaller v3.01")
        if self.args.dry_run:
            self.logger.info("[Dry Run] Simulating")
        # Service stop (idempotent)
        if subprocess.run(["systemctl", "is-active", "--quiet", "saturn-update-manager"]).returncode == 0:
            if not self.args.dry_run:
                subprocess.run(["systemctl", "stop", "saturn-update-manager"], check=True)
                subprocess.run(["systemctl", "disable", "saturn-update-manager"], check=True)
                subprocess.run(["systemctl", "daemon-reload"], check=True)
            self.logger.info("Service stopped")
        else:
            self.logger.info("No service (skip)")

        if self.systemd_service.exists():
            if not self.args.dry_run:
                self.systemd_service.unlink()
            self.logger.info("Systemd removed")

        # Apache (compat: check mod before remove)
        for conf in [self.apache_enabled, self.apache_conf, self.htpasswd_file]:
            if conf.exists():
                if not self.args.dry_run:
                    conf.unlink()
                self.logger.info(f"Removed {conf}")
        if not self.args.dry_run:
            subprocess.run(["a2dissite", "saturn"], check=False)
            subprocess.run(["systemctl", "restart", "apache2"], check=True)

        # Venv/logs/configs (prompts for stability)
        dirs_to_remove = [self.venv_path, self.config_dir, self.log_dir]
        for d in dirs_to_remove:
            if d.exists():
                if self.args.force or input(f"Remove {d}? (y/n): ").lower() == 'y':
                    if not self.args.dry_run:
                        shutil.rmtree(d)
                    self.logger.info(f"Removed {d}")
                else:
                    self.logger.info(f"Kept {d}")

        # Deps (check if installed, Buster/Bookworm safe)
        if self.args.force or input("Remove deps? (y/n, may affect others): ").lower() == 'y':
            packages = ["python3-venv", "python3-pip", "apache2", "apache2-utils", "libapache2-mod-proxy-uwsgi", "lsof", "build-essential", "python3-dev"]
            for pkg in packages:
                if subprocess.run(["dpkg", "-s", pkg], capture_output=True).returncode == 0:
                    if not self.args.dry_run:
                        subprocess.run(["apt-get", "purge", "-y", pkg], check=True)
            if not self.args.dry_run:
                subprocess.run(["apt-get", "autoremove", "-y"], check=True)
            self.logger.info("Deps removed")

        self.validate_uninstall()
        self.logger.info("Uninstall complete")

    # ... (validate_uninstall unchanged)

# ... (main unchanged)
