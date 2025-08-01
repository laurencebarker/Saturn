# modules/apache_config.py 
import subprocess
import os
import re
import textwrap
from pathlib import Path
import ipaddress

def configure_apache(logger, htpasswd_file, apache_conf, port, user_home, dry_run, username='admin', password='password123'):
    if dry_run:
        logger.info("[Dry Run] Skipping Apache configuration")
        return
    subnet = "127.0.0.1/32"
    interfaces = ["eth0", "wlan0"]
    for iface in interfaces:
        result = subprocess.run(["ip", "a", "show", iface], capture_output=True, text=True)
        match = re.search(r'inet (\d+\.\d+\.\d+\.\d+)/(\d+)', result.stdout)
        if match:
            address = match.group(1) + '/' + match.group(2)
            network = ipaddress.ip_network(address, strict=False)
            subnet = str(network)
            break
    logger.info(f"Using subnet: {subnet}")
    if htpasswd_file.exists():
        htpasswd_file.unlink()
    logger.info("Creating .htpasswd...")
    subprocess.run(["htpasswd", "-cb", str(htpasswd_file), username, password], check=True)
    os.chmod(htpasswd_file, 0o640)
    subprocess.run(["chown", "root:www-data", str(htpasswd_file)], check=True)
    conf_content = textwrap.dedent(f"""
    <VirtualHost *:80>
        ServerName localhost
        ServerAlias 127.0.0.1 ::1 {subnet.split('/')[0]}
        DocumentRoot /var/www/html
        ProxyRequests Off
        ProxyPreserveHost On
        ProxyTimeout 3600
        Timeout 3600
        LogLevel proxy:debug authz_core:debug
        ErrorLog ${{APACHE_LOG_DIR}}/saturn_error.log
        CustomLog ${{APACHE_LOG_DIR}}/saturn_access.log combined
        ProxyPass /saturn/ http://127.0.0.1:{port}/ nocanon
        ProxyPassReverse /saturn/ http://127.0.0.1:{port}/
        ProxyPassReverseCookiePath /saturn/ /
        <Location /saturn/>
            AuthType Basic
            AuthName "Saturn Update Manager - Restricted Access"
            AuthUserFile {htpasswd_file}
            <RequireAny>
                Require ip 127.0.0.1 ::1
                Require ip {subnet}
                Require valid-user
            </RequireAny>
            SetEnv proxy-sendchunked 1
            SetEnv proxy-nokeepalive 1
        </Location>
        <Directory /var/www/html>
            Options -Indexes
            Require all denied
        </Directory>
    </VirtualHost>
    """)
    with open(apache_conf, "w") as f:
        f.write(conf_content)
    subprocess.run(["ln", "-sf", str(apache_conf), "/etc/apache2/sites-enabled/saturn.conf"], check=True)
    # Remove other virtual host configs to avoid conflicts
    subprocess.run(["find", "/etc/apache2/sites-enabled", "-type", "l", "-not", "-name", "saturn.conf", "-delete"], check=True)
    subprocess.run(["a2enmod", "proxy", "proxy_http", "auth_basic", "authn_file", "authz_core"], check=True)
    with open("/etc/apache2/conf-available/servername.conf", "w") as f:
        f.write("ServerName localhost\n")
    subprocess.run(["a2enconf", "servername"], check=True)
    result = subprocess.run(["apache2ctl", "configtest"], capture_output=True, text=True, check=False)
    if "Syntax OK" in result.stdout:
        logger.info("Apache config test - PASS")
    else:
        logger.error("Apache config test - FAIL")
        logger.error(f"Apache config test output: {result.stdout}\n{result.stderr}")
    subprocess.run(["systemctl", "restart", "apache2"], check=True)
    logger.info("Apache configured")

def configure_monitor_vhost(logger, htpasswd_file, monitor_conf, monitor_dir, monitor_html_source, dry_run, username, password, port, ip):
    if dry_run:
        logger.info("[Dry Run] Skipping monitor vhost configuration")
        return
    monitor_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run(["chown", "root:www-data", str(monitor_dir)], check=True)
    os.chmod(monitor_dir, 0o755)
    monitor_dest = monitor_dir / "monitor.html"
    shutil.copy(monitor_html_source, monitor_dest)
    os.chmod(monitor_dest, 0o644)
    logger.info(f"Copied monitor.html to {monitor_dest}")
    conf_content = textwrap.dedent(f"""
    <VirtualHost *:80>
        ServerName monitor.local
        ServerAlias {ip}
        DocumentRoot {monitor_dir}

        <Directory {monitor_dir}>
            Options Indexes FollowSymLinks
            AllowOverride None
            Require all granted
        </Directory>

        ProxyPass /monitor http://127.0.0.1:{port}/monitor
        ProxyPassReverse /monitor http://127.0.0.1:{port}/monitor
        ProxyPass /kill_process http://127.0.0.1:{port}/kill_process
        ProxyPassReverse /kill_process http://127.0.0.1:{port}/kill_process

        ErrorLog ${{APACHE_LOG_DIR}}/monitor_error.log
        CustomLog ${{APACHE_LOG_DIR}}/monitor_access.log combined
    </VirtualHost>
    """)
    with open(monitor_conf, "w") as f:
        f.write(conf_content)
    subprocess.run(["a2ensite", "monitor"], check=True)
    subprocess.run(["systemctl", "reload", "apache2"], check=True)
    logger.info("Monitor vhost configured")
