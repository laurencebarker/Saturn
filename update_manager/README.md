# Saturn Go

**Saturn Go** is the Go-powered successor to the original **Saturn Update Manager**.  
It provides a **web-based management interface** for running maintenance scripts, monitoring system resources, and handling backups.  
This version replaces the Python/Flask backend with a **lightweight Go HTTP API server** for better performance and resource usage while keeping the same web UI design.

---

## 📋 Features

- **Web UI** for system updates, monitoring, and backups  
- **Live system metrics**: CPU, memory, disk usage, network I/O, and top processes  
- **Backup & restore management** for multiple systems (`Saturn`, `piHPSDR`)  
- **Script runner** with live output streaming (Server-Sent Events)  
- **Theme support**: light/dark mode  
- **Authentication** via NGINX Basic Auth  
- **Drop-in custom scripts** in `/opt/saturn-go/scripts`  
- **Service-based deployment** via `systemd`

---

## 📂 Directory Structure

```

/opt/saturn-go/           # Main Saturn-Go installation
│
├── bin/                  # Compiled Go binary (`saturn-go`)
├── cmd/server/           # Go source files (main.go and helpers)
├── scripts/              # Custom shell/Python scripts (user editable)
│   ├── hello.sh
│   ├── sysinfo.py
│   └── ...
├── go.mod                # Go module definition
├── go.sum
│
/var/lib/saturn-web/      # Web assets & config files served via NGINX
│   ├── index.html        # Main Update Manager interface
│   ├── monitor.html      # System monitor interface
│   ├── config.json       # Script definitions & flags
│   ├── themes.json       # Theme definitions
│   └── ...

````

---

## 🛠 Installation

1. **Clone the Saturn repo**
   ```bash
   git clone https://github.com/<your-repo>/Saturn ~/github/Saturn
````

2. **Run the installer**

   ```bash
   cd ~/github/Saturn
   sudo bash install_saturn_go_nginx.sh
   ```

3. **Default credentials**

   * Username: `admin`
   * Password: `admin` (change in NGINX Basic Auth)

4. **Access the Web UI**

   * Navigate to: `http://<host>/saturn/`

---

## ⚙️ How It Works

### Architecture

```
+-----------------+
|  Browser (UI)   |
| index.html /    |
| monitor.html    |
+--------+--------+
         |
         v
+--------+--------+      +--------------------+
|   NGINX Reverse | ---> |   Go API Server    |
|     Proxy       |      | (bin/saturn-go)    |
+--------+--------+      +--------+-----------+
         |                        |
         | static HTML/JS         | script exec, metrics
         v                        v
 /var/lib/saturn-web       /opt/saturn-go/scripts
```

* **NGINX** handles authentication & static file serving
* **Go API** handles:

  * `/get_scripts`, `/get_flags` from `config.json`
  * `/run` — executes scripts, streams output
  * `/get_system_data` — sends system metrics
  * `/kill_process/<pid>` — kills processes
* **Scripts** are stored in `/opt/saturn-go/scripts`

---

## 🧩 Adding Custom Scripts

1. **Place your script**

   * Location: `/opt/saturn-go/scripts/`
   * Permissions:

     ```bash
     sudo chmod 755 /opt/saturn-go/scripts/myscript.sh
     sudo chown <user>:<user> /opt/saturn-go/scripts/myscript.sh
     ```

2. **Update config.json**

   * Location: `/var/lib/saturn-web/config.json`
   * Example:

     ```json
     [
       {
         "filename": "myscript.sh",
         "name": "My Custom Script",
         "description": "Does something useful",
         "directory": "/opt/saturn-go/scripts",
         "category": "Custom Tools",
         "flags": ["--option1", "--verbose"],
         "version": "1.0.0"
       }
     ]
     ```

3. **Reload the Web UI**

   * Simply refresh your browser; the script should appear in the UI.

---

## 🛡️ Backup & Restore

### Creating a Backup

Saturn-Go backups are just timestamped directories in `~/`:

```
saturn-backup-YYYYMMDD-HHMMSS/
pihpsdr-backup-YYYYMMDD-HHMMSS/
```

### Restoring

Use the built-in **Restore Backup** UI or run:

```bash
./restore-backup.sh --saturn --latest
./restore-backup.sh --pihpsdr --list
./restore-backup.sh --pihpsdr --backup-dir <dir>
```

**Note:** If both `--pihpsdr` and `--saturn` are selected in the UI, Saturn-Go will attempt to restore both.

---

## 🐞 Troubleshooting

| Problem                                     | Possible Cause                             | Fix                                                                   |
| ------------------------------------------- | ------------------------------------------ | --------------------------------------------------------------------- |
| Web UI loads, but no data in Monitor graphs | Go API not running or NGINX misconfigured  | `systemctl status saturn-go.service` and `systemctl reload nginx`     |
| Scripts not showing in UI                   | Missing in `config.json` or incorrect path | Verify `/var/lib/saturn-web/config.json` and `/opt/saturn-go/scripts` |
| "Script not found" when running             | File missing or permissions wrong          | Ensure `chmod 755` and correct ownership                              |
| CPU usage >100%                             | Multi-core processes report >100% in `ps`  | Normal — values are per core                                          |
| Light/Dark theme toggle doesn't work        | Tailwind CDN limitation in production      | Use locally built Tailwind CSS file                                   |
| Backups not listed                          | No matching directories in `~/`            | Ensure backups follow naming pattern                                  |

---

## 🔧 Developer Notes

* **Building from source**

  ```bash
  cd /opt/saturn-go
  go build -o bin/saturn-go cmd/server
  ```

* **Environment Variables**

  * `SATURN_WEBROOT` – defaults to `/var/lib/saturn-web`
  * `SATURN_CONFIG` – defaults to `$SATURN_WEBROOT/config.json`
  * `SATURN_ADDR` – defaults to `127.0.0.1:8080`

* **Updating**

  * Pull latest repo changes
  * Re-run `install_saturn_go_nginx.sh` or rebuild Go binary

---

## ✨ Credits

* Original Saturn Update Manager by Jerry DeLong, KD4YAL
* Saturn-Go rewrite in Go for improved performance and maintainability

```
