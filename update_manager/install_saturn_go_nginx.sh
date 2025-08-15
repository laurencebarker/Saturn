#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config
# =========================
SATURN_ROOT="/opt/saturn-go"
SRC_DIR="$SATURN_ROOT/cmd/server"
BIN_DIR="$SATURN_ROOT/bin"
WEB_ROOT="/var/lib/saturn-web"
NGINX_SITE="/etc/nginx/sites-available/saturn"
NGINX_SITE_LINK="/etc/nginx/sites-enabled/saturn"
BASIC_AUTH_FILE="/etc/nginx/.htpasswd"
SERVICE_FILE="/etc/systemd/system/saturn-go.service"
GO_MODULE="saturn.local/saturn-go"
GO_ADDR="127.0.0.1:8080"
SOURCE_DIR="/home/${SUDO_USER:-$USER}/github/Saturn/update_manager"

bold(){ printf "\e[1m%s\e[0m\n" "$*"; }
ok(){   printf "[OK] %s\n" "$*"; }
info(){ printf "[INFO] %s\n" "$*"; }
warn(){ printf "[WARN] %s\n" "$*"; }
err(){  printf "[ERR] %s\n" "$*" >&2; }

# =========================
# Must be root
# =========================
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  err "Run as root (sudo)."
  exit 1
fi

# =========================
# Deps
# =========================
info "Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive

# Detect Buster
DIST_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
apt-get update -qq

# Base packages we actually need
APT_PKGS="nginx apache2-utils build-essential pkg-config \
          libgtk-3-dev libcurl4-openssl-dev libasound2-dev libusb-1.0-0-dev \
          curl git python3 python3-venv"

# Only add golang from apt on non-Buster systems
if [[ "$DIST_CODENAME" != "buster" ]]; then
  APT_PKGS="$APT_PKGS golang-go"
fi

apt-get install -y -qq $APT_PKGS
ok "Dependencies installed"

# =========================
# Python venv
# =========================
info "Setting up Python venv and dependencies..."
VENV_DIR="/home/${SUDO_USER:-$USER}/venv"
if [[ -d "$VENV_DIR" ]]; then
  warn "Venv already exists at $VENV_DIR; skipping creation."
else
  su - "${SUDO_USER:-$USER}" -c 'python3 -m venv ~/venv'
  ok "Venv created at $VENV_DIR"
fi

# Install pyfiglet with Buster fallback (1.0.3 not on Buster)
# Use single quotes so nothing like $3 is expanded under set -u
su - "${SUDO_USER:-$USER}" -c '
  set -e
  . ~/venv/bin/activate
  if ! pip install --no-input "pyfiglet==1.0.3"; then
    echo "[INFO] Falling back to pyfiglet==1.0.0 for Buster"
    pip install --no-input "pyfiglet==1.0.0"
  fi
  deactivate
'
ok "Python dependencies installed"
# =========================
# Directories
# =========================
info "Preparing directories..."
mkdir -p "$SRC_DIR" "$BIN_DIR" "$WEB_ROOT" "$SATURN_ROOT/scripts"
ok "Directories ready"

# =========================
# Web assets
# =========================
info "Copying web assets (index.html + monitor.html)..."
copy_html () {
  local name="$1"
  local from_template="$SOURCE_DIR/templates/$name"
  local from_repo="$SOURCE_DIR/$name"
  if [[ -f "$from_template" ]]; then
    cp -f "$from_template" "$WEB_ROOT/$name"
  elif [[ -f "$from_repo" ]]; then
    cp -f "$from_repo" "$WEB_ROOT/$name"
  else
    warn "$name not found in repo; seeding placeholder"
    cat >"$WEB_ROOT/$name" <<'HTML'
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Saturn</title></head>
<body style="font-family:sans-serif;padding:20px">
<h1>Saturn</h1><p>Missing web asset <code>INDEX_PLACEHOLDER</code>. Add it to update_manager/ and reinstall.</p>
</body></html>
HTML
    sed -i "s/INDEX_PLACEHOLDER/$name/" "$WEB_ROOT/$name"
  fi
}
copy_html "index.html"
copy_html "monitor.html"
ok "Web assets copied"

# =========================
# config.json + themes.json
# =========================
info "Copying config.json from scripts dir..."
if [[ -f "$SOURCE_DIR/scripts/config.json" ]]; then
  cp -f "$SOURCE_DIR/scripts/config.json" "$WEB_ROOT/config.json"
elif [[ -f "$SOURCE_DIR/config.json" ]]; then
  cp -f "$SOURCE_DIR/config.json" "$WEB_ROOT/config.json"
else
  # sane default (matches what we used last night)
  cat >"$WEB_ROOT/config.json" <<'JSON'
[
  {
    "filename": "update-G2.py",
    "name": "Update G2",
    "description": "Updates Saturn G2",
    "directory": "~/github/Saturn/update_manager/scripts",
    "category": "Update Scripts",
    "flags": ["--skip-git","-y","-n","--dry-run","--verbose"],
    "version": "1.0.0"
  },
  {
    "filename": "update-pihpsdr.py",
    "name": "Update piHPSDR",
    "description": "Updates piHPSDR",
    "directory": "~/github/Saturn/update_manager/scripts",
    "category": "Update Scripts",
    "flags": ["--skip-git","-y","-n","--no-gpio","--dry-run","--verbose"],
    "version": "1.10"
  }
]
JSON
fi
ok "config.json copied"

info "Copying themes.json from scripts dir..."
if [[ -f "$SOURCE_DIR/scripts/themes.json" ]]; then
  cp -f "$SOURCE_DIR/scripts/themes.json" "$WEB_ROOT/themes.json"
elif [[ -f "$SOURCE_DIR/themes.json" ]]; then
  cp -f "$SOURCE_DIR/themes.json" "$WEB_ROOT/themes.json"
else
  cat >"$WEB_ROOT/themes.json" <<'JSON'
[
  {
    "name":"Default",
    "description":"Standard light theme",
    "styles":{"--bg-color":"#f3f4f6","--text-color":"#333333","--primary-color":"#3b82f6","--secondary-color":"#10b981","--card-bg":"#ffffff"}
  },
  {
    "name":"Dark Mode",
    "description":"Dark theme for low-light environments",
    "styles":{"--bg-color":"#1a1a1a","--text-color":"#ffffff","--primary-color":"#60a5fa","--secondary-color":"#34d399","--card-bg":"#333333"}
  }
]
JSON
fi
ok "themes.json copied"

# =========================
# Webroot permissions (safe)
# =========================
info "Setting webroot permissions..."
chown -R root:root "$WEB_ROOT"
# avoid "missing operand" when no files:
find "$WEB_ROOT" -type d -print0 | xargs -0 -r chmod 0755
find "$WEB_ROOT" -type f -print0 | xargs -0 -r chmod 0644
ok "Webroot permissions set (dirs 0755, files 0644)"

# =========================
# Seed scripts + perms (safe)
# =========================
info "Seeding default config and sample scripts..."
shopt -s nullglob
if compgen -G "$SOURCE_DIR/scripts/*" >/dev/null; then
  cp -f "$SOURCE_DIR/scripts/"* "$SATURN_ROOT/scripts/" 2>/dev/null || true
fi
# Demo if empty
if ! compgen -G "$SATURN_ROOT/scripts/*" >/dev/null; then
  cat >"$SATURN_ROOT/scripts/echo-hello.sh" <<'SH'
#!/usr/bin/env bash
echo "Hello from Saturn demo script!"
for p in 30 60 100; do
  echo "Progress: ${p}%"
  sleep 1
done
SH
fi
# perms (no-op if empty lists; -r avoids error)
chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$SATURN_ROOT/scripts"
find "$SATURN_ROOT/scripts" -type d -print0 | xargs -0 -r chmod 0755
find "$SATURN_ROOT/scripts" -type f \( -name '*.sh' -o -name '*.py' \) -print0 | xargs -0 -r chmod 0755
find "$SATURN_ROOT/scripts" -type f ! \( -name '*.sh' -o -name '*.py' \) -print0 | xargs -0 -r chmod 0644 || true
ok "Script permissions set (exec on .sh/.py)"

# =========================
# Go sources (embedded)
# =========================
info "Writing embedded Go server source..."
mkdir -p "$SRC_DIR"
# =========================
# Go toolchain (upgrade on old distros)
# =========================
ARCH="$(dpkg --print-architecture)"
if [[ "$ARCH" == "armhf" ]]; then
  info "Installing modern Go toolchain (1.20.x) for armhf…"
  TMPGO="$(mktemp -d)"
  trap 'rm -rf "$TMPGO"' EXIT
  curl -fsSL https://go.dev/dl/go1.20.14.linux-armv6l.tar.gz -o "$TMPGO/go.tgz"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$TMPGO/go.tgz"
  echo 'export PATH=/usr/local/go/bin:$PATH' >/etc/profile.d/go.sh
  chmod 644 /etc/profile.d/go.sh
  export PATH=/usr/local/go/bin:$PATH
  hash -r
  ok "Go $(go version) installed"
fi
# go.mod (match installed Go major.minor to avoid tidy/version errors)
cat >"$SATURN_ROOT/go.mod" <<EOF
module saturn.local/saturn-go

go 1.19

require github.com/shirou/gopsutil/v3 v3.24.5
EOF

if command -v go >/dev/null 2>&1; then
  GOV_RAW="$(go version | awk '{print $3}')"
  GOV="${GOV_RAW#go}"               # e.g. 1.21.10
  GOMAJ="${GOV%%.*}"                # 1
  GOMIN="${GOV#*.}"; GOMIN="${GOMIN%%.*}" # 21
  GO_LINE="go ${GOMAJ}.${GOMIN}"
  sed -i -E "s/^go [0-9]+\.[0-9]+/${GO_LINE}/" "$SATURN_ROOT/go.mod" || true
fi

# main.go (powers both Update Manager + Monitor)
cat >"$SRC_DIR/main.go" <<'GO'
package main

import (
  "bufio"
  "context"
  "encoding/json"
  "fmt"
  "log"
  "net/http"
  "os"
  "os/exec"
  "os/signal"
  "path/filepath"
  "strconv"
  "strings"
  "syscall"
  "time"

  "github.com/shirou/gopsutil/v3/disk"
  "github.com/shirou/gopsutil/v3/mem"
  netio "github.com/shirou/gopsutil/v3/net"
)

/*
API shape expected by monitor.html:

{
  "cpu": [perCorePercents...],             // []float64, 0..100
  "memory": { "percent":f, "used":GB, "total":GB },
  "disk":   { "percent":f, "used":GB, "total":GB },
  "network":{ "sent":bytesTotal, "recv":bytesTotal },
  "processes": [ {pid,user,cpu,memory,command}, ... ]
}

The /kill_process/<pid> endpoint exists and returns {"message":"OK"} on success.
*/

type Server struct {
  webroot string
}

func getEnv(k, def string) string { v := os.Getenv(k); if v == "" { return def }; return v }

func main() {
  addr := getEnv("SATURN_ADDR", "127.0.0.1:8080")
  webroot := getEnv("SATURN_WEBROOT", "/var/lib/saturn-web")
  s := &Server{webroot: webroot}

  mux := http.NewServeMux()

  // Static (fallback — NGINX serves /saturn/, but this keeps local testing easy)
  mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
   if r.URL.Path == "/" || r.URL.Path == "/saturn/" {
     http.ServeFile(w, r, filepath.Join(webroot, "index.html"))
     return
   }
   http.NotFound(w, r)
  })

  // Update Manager APIs (used by index.html)
  mux.HandleFunc("/get_versions", s.handleGetVersions)
  mux.HandleFunc("/get_scripts", s.handleGetScripts)
  mux.HandleFunc("/get_flags", s.handleGetFlags)
  mux.HandleFunc("/run", s.handleRunSSE)
  mux.HandleFunc("/backup_response", s.noContent)
  mux.HandleFunc("/change_password", s.handleChangePassword)
  mux.HandleFunc("/exit", s.handleExit)

  // Monitor APIs (used by monitor.html)
  mux.HandleFunc("/get_system_data", s.handleSystemData)
  mux.HandleFunc("/kill_process/", s.handleKillProcess) // POST /kill_process/<pid>

  srv := &http.Server{
   Addr:         addr,
   Handler:      logRequests(mux),
   ReadTimeout:  30 * time.Second,
   WriteTimeout: 0, // allow SSE
  }

  go func() {
   stop := make(chan os.Signal, 1)
   signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
   <-stop
   ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
   defer cancel()
   _ = srv.Shutdown(ctx)
  }()

  log.Printf("Saturn server listening on %s (webroot=%s)", addr, webroot)
  if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
   log.Fatalf("server error: %v", err)
  }
}

/* -------------------- middleware -------------------- */

func logRequests(next http.Handler) http.Handler {
  return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
   log.Printf("%s %s", r.Method, r.URL.Path)
   next.ServeHTTP(w, r)
  })
}

/* -------------------- Update Manager stubs -------------------- */
/* These keep the Update UI working using the same JSON shape we used before.
   If you already have your config.json in /var/lib/saturn-web, these will populate the UI.
*/

type cfgEntry struct {
  Filename    string   `json:"filename"`
  Name        string   `json:"name"`
  Description string   `json:"description"`
  Directory   string   `json:"directory"`
  Category    string   `json:"category"`
  Flags       []string `json:"flags"`
  Version     string   `json:"version"`
}

func (s *Server) cfgPath() string {
  if p := os.Getenv("SATURN_CONFIG"); p != "" {
   return p
  }
  return filepath.Join(s.webroot, "config.json")
}

func (s *Server) readConfig() ([]cfgEntry, error) {
  b, err := os.ReadFile(s.cfgPath())
  if err != nil {
   return nil, err
  }
  var entries []cfgEntry
  if err := json.Unmarshal(b, &entries); err != nil {
   return nil, err
  }
  return entries, nil
}

func (s *Server) handleGetVersions(w http.ResponseWriter, r *http.Request) {
  entries, _ := s.readConfig()
  versions := map[string]string{}
  for _, e := range entries {
   v := e.Version
   if v == "" {
     v = "1.0.0"
   }
   versions[e.Filename] = v
  }
  _ = json.NewEncoder(w).Encode(map[string]any{"versions": versions})
}

func (s *Server) handleGetScripts(w http.ResponseWriter, r *http.Request) {
  entries, err := s.readConfig()
  if err != nil || len(entries) == 0 {
   _ = json.NewEncoder(w).Encode(map[string]any{
     "scripts": map[string][]map[string]string{
        "System": {{
                "filename":    "echo-hello.sh",
                "name":        "Echo Hello",
                "description": "Demo script",
        }},
     },
     "warnings": []string{"config.json missing or invalid; showing demo"},
   })
   return
  }
  grouped := map[string][]map[string]string{}
  for _, e := range entries {
   c := e.Category
   if c == "" {
     c = "Scripts"
   }
   grouped[c] = append(grouped[c], map[string]string{
     "filename":    e.Filename,
     "name":        e.Name,
     "description": e.Description,
   })
  }
  _ = json.NewEncoder(w).Encode(map[string]any{"scripts": grouped, "warnings": []string{}})
}

func (s *Server) handleGetFlags(w http.ResponseWriter, r *http.Request) {
  _ = r.ParseForm()
  script := r.Form.Get("script")
  entries, err := s.readConfig()
  if err != nil {
   _ = json.NewEncoder(w).Encode(map[string]any{
     "flags":   []string{},
     "error":   "config.json not found or invalid",
     "warning": "Using empty flags",
   })
   return
  }
  for _, e := range entries {
   if e.Filename == script {
     _ = json.NewEncoder(w).Encode(map[string][]string{"flags": e.Flags})
     return
   }
  }
  _ = json.NewEncoder(w).Encode(map[string][]string{"flags": {}})
}

/* -------------------- /run (SSE) -------------------- */

func (s *Server) handleRunSSE(w http.ResponseWriter, r *http.Request) {
  flusher, ok := w.(http.Flusher)
  if !ok {
   http.Error(w, "stream unsupported", http.StatusInternalServerError)
   return
  }
  if err := r.ParseMultipartForm(32 << 20); err != nil {
   _ = r.ParseForm()
  }
  script := firstForm(r, "script")
  flags := r.Form["flags"]

  scriptPath := filepath.Join("/opt/saturn-go/scripts", script)
  if strings.Contains(script, "..") {
   http.Error(w, "invalid script", http.StatusBadRequest)
   return
  }
  if _, err := os.Stat(scriptPath); err != nil {
   http.Error(w, "script not found", http.StatusNotFound)
   return
  }

  // SSE headers
  w.Header().Set("Content-Type", "text/event-stream")
  w.Header().Set("Cache-Control", "no-cache")
  w.Header().Set("Connection", "keep-alive")
  w.Header().Set("X-Accel-Buffering", "no")

  send := func(line string) {
   fmt.Fprintf(w, "data: %s\n\n", line)
   flusher.Flush()
  }

  send(fmt.Sprintf("Running %s %s", script, strings.Join(flags, " ")))

  var cmd *exec.Cmd
  if strings.HasSuffix(script, ".py") {
   args := append([]string{"-u", scriptPath}, flags...)
   cmd = exec.Command("python3", args...)
   cmd.Env = append(os.Environ(),
     "PYTHONUNBUFFERED=1",
     "PYTHONIOENCODING=UTF-8",
   )
  } else {
   cmd = exec.Command(scriptPath, flags...)
  }
  stdout, _ := cmd.StdoutPipe()
  stderr, _ := cmd.StderrPipe()
  if err := cmd.Start(); err != nil {
   http.Error(w, err.Error(), http.StatusInternalServerError)
   return
  }

  go func() {
   sc := bufio.NewScanner(stderr)
   buf := make([]byte, 0, 256*1024)
   sc.Buffer(buf, 1024*1024)
   for sc.Scan() {
     send("ERR: " + sc.Text())
   }
  }()

  sc := bufio.NewScanner(stdout)
  buf := make([]byte, 0, 256*1024)
  sc.Buffer(buf, 1024*1024)
  for sc.Scan() {
   send(sc.Text())
  }
  if err := cmd.Wait(); err != nil {
   send(fmt.Sprintf("Error: %v", err))
  } else {
   send("Done")
  }
}

func firstForm(r *http.Request, key string) string {
  if v := r.FormValue(key); v != "" {
   return v
  }
  if r.MultipartForm != nil {
   if vs := r.MultipartForm.Value[key]; len(vs) > 0 {
     return vs[0]
   }
  }
  return ""
}

func (s *Server) noContent(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusNoContent) }

func (s *Server) handleChangePassword(w http.ResponseWriter, r *http.Request) {
  _ = r.ParseForm()
  newPwd := r.Form.Get("new_password")
  if len(newPwd) < 8 {
   _ = json.NewEncoder(w).Encode(map[string]any{"status": "error", "message": "min length 8"})
   return
  }
  hc := exec.Command("htpasswd", "-b", "/etc/nginx/.htpasswd", "admin", newPwd)
  if err := hc.Run(); err != nil {
   _ = json.NewEncoder(w).Encode(map[string]any{"status": "error", "message": err.Error()})
   return
  }
  _ = json.NewEncoder(w).Encode(map[string]any{"status": "success"})
}

func (s *Server) handleExit(w http.ResponseWriter, r *http.Request) {
  _ = json.NewEncoder(w).Encode(map[string]string{"status": "shutting down"})
  go func() {
   time.Sleep(200 * time.Millisecond)
   p, _ := os.FindProcess(os.Getpid())
   _ = p.Signal(syscall.SIGTERM)
  }()
}

/* -------------------- Monitor endpoints -------------------- */

var lastNetSent, lastNetRecv uint64 // not required by UI, but retained if we want rates later

func (s *Server) handleSystemData(w http.ResponseWriter, r *http.Request) {
  // CPU per-core: read /proc/stat twice quickly to compute a fresh percentage snapshot.
  perCore := readPerCoreCPU()

  // Memory
  vm, _ := mem.VirtualMemory()
  mTotalGB := float64(vm.Total) / (1024 * 1024 * 1024)
  mUsedGB := float64(vm.Total-vm.Available) / (1024 * 1024 * 1024)
  mPercent := 0.0
  if vm.Total > 0 {
   mPercent = (mUsedGB / mTotalGB) * 100.0
  }

  // Disk
  du, _ := disk.Usage("/")
  dTotalGB := float64(du.Total) / (1024 * 1024 * 1024)
  dUsedGB := float64(du.Used) / (1024 * 1024 * 1024)
  dPercent := du.UsedPercent

  // Network totals (all interfaces)
  var sent, recv uint64
  if ios, err := netio.IOCounters(false); err == nil && len(ios) > 0 {
   sent = ios[0].BytesSent
   recv = ios[0].BytesRecv
  }
  lastNetSent, lastNetRecv = sent, recv

  // Top processes (simple & fast)
  procs := listProcs()

  resp := map[string]any{
   "cpu": perCore, // []float64, one entry per core
   "memory": map[string]any{
     "percent": mPercent,
     "used":    mUsedGB,
     "total":   mTotalGB,
   },
   "disk": map[string]any{
     "percent": dPercent,
     "used":    dUsedGB,
     "total":   dTotalGB,
   },
   "network": map[string]any{
     "sent": sent,
     "recv": recv,
   },
   "processes": procs,
  }
  _ = json.NewEncoder(w).Encode(resp)
}

func (s *Server) handleKillProcess(w http.ResponseWriter, r *http.Request) {
  if r.Method != http.MethodPost {
   http.Error(w, "POST only", http.StatusMethodNotAllowed)
   return
  }
  pidStr := strings.TrimPrefix(r.URL.Path, "/kill_process/")
  pid, err := strconv.Atoi(strings.TrimSpace(pidStr))
  if err != nil || pid <= 0 {
   http.Error(w, "bad pid", http.StatusBadRequest)
   return
  }
  if err := syscall.Kill(pid, syscall.SIGKILL); err != nil {
   _ = json.NewEncoder(w).Encode(map[string]string{"message": fmt.Sprintf("Failed: %v", err)})
   return
  }
  _ = json.NewEncoder(w).Encode(map[string]string{"message": "OK"})
}

/* -------------------- Helpers -------------------- */

// readPerCoreCPU computes a single-shot per-core CPU percentage using /proc/stat deltas over ~120ms.
func readPerCoreCPU() []float64 {
  type snap struct{ idle, total uint64 }
  read := func() []snap {
   b, err := os.ReadFile("/proc/stat")
   if err != nil {
     return nil
   }
   var res []snap
   sc := bufio.NewScanner(strings.NewReader(string(b)))
   for sc.Scan() {
     ln := sc.Text()
     if !strings.HasPrefix(ln, "cpu") || ln == "" || strings.HasPrefix(ln, "cpu ") {
        continue // skip aggregate "cpu "
     }
     fields := strings.Fields(ln)
     // fields[0] is "cpuN"
     var vals []uint64
     for _, f := range fields[1:] {
        v, _ := strconv.ParseUint(f, 10, 64)
        vals = append(vals, v)
     }
     if len(vals) < 5 {
        continue
     }
     idle := vals[3] + vals[4] // idle + iowait
     var total uint64
     for _, v := range vals {
        total += v
     }
     res = append(res, snap{idle: idle, total: total})
   }
   return res
  }

  a := read()
  time.Sleep(120 * time.Millisecond)
  b := read()
  if len(a) == 0 || len(a) != len(b) {
   return []float64{0}
  }
  out := make([]float64, len(a))
  for i := range a {
   dIdle := float64(b[i].idle - a[i].idle)
   dTot := float64(b[i].total - a[i].total)
   p := 0.0
   if dTot > 0 {
     p = (1.0 - dIdle/dTot) * 100.0
     if p < 0 {
        p = 0
     }
     if p > 100 {
        p = 100
     }
   }
   out[i] = p
  }
  return out
}

func listProcs() []map[string]any {
  out, err := exec.Command("bash", "-lc", "ps -eo pid,user,%cpu,%mem,cmd --sort=-%cpu | head -n 20").Output()
  if err != nil {
   return nil
  }
  lines := strings.Split(strings.TrimSpace(string(out)), "\n")
  var res []map[string]any
  for i, ln := range lines {
   if i == 0 || strings.TrimSpace(ln) == "" {
     continue
   }
   fs := fieldsN(ln, 5)
   if len(fs) < 5 {
     continue
   }
   pid, _ := strconv.Atoi(fs[0])
   cpu, _ := strconv.ParseFloat(fs[2], 64)
   mem, _ := strconv.ParseFloat(fs[3], 64)
   res = append(res, map[string]any{
     "pid":     pid,
     "user":    fs[1],
     "cpu":     cpu,
     "memory":  mem,
     "command": fs[4],
   })
  }
  return res
}

func fieldsN(s string, n int) []string {
  fs := strings.Fields(s)
  if len(fs) <= n {
   return fs
  }
  head := fs[:n-1]
  tail := strings.Join(fs[n-1:], " ")
  return append(head, tail)
}
GO
ok "Go sources written"

# =========================
# Build Go
# =========================
info "Building Go binary..."
pushd "$SATURN_ROOT" >/dev/null

GO_BIN="/usr/local/go/bin/go"
command -v "$GO_BIN" >/dev/null 2>&1 || GO_BIN="go"  # fallback if not armhf

# keep the go directive current
$GO_BIN mod tidy || warn "go mod tidy warning (ignored)"

mkdir -p "$BIN_DIR"

# Map Debian arch to Go arch
DEB_ARCH="$(dpkg --print-architecture)"
case "$DEB_ARCH" in
  armhf) GOARCH="arm" ;;
  arm64) GOARCH="arm64" ;;
  amd64) GOARCH="amd64" ;;
  *)     GOARCH="" ;; # let Go pick
esac

env GOOS=linux ${GOARCH:+GOARCH=$GOARCH} "$GO_BIN" build -o "$BIN_DIR/saturn-go" "$SRC_DIR"
popd >/dev/null
ok "Go binary built -> $BIN_DIR/saturn-go"

# =========================
# NGINX (SSE + static + API)
# =========================
info "Configuring NGINX site..."

# Helper map (http{} scope). Safe to re-create.
cat >/etc/nginx/conf.d/saturn_sse_map.conf <<'NGINX'
map $http_accept $is_sse {
  default               0;
  "~*text/event-stream" 1;
}
NGINX

cat >"$NGINX_SITE" <<'NGINX'
server {
  listen 80 default_server;
  server_name _;

  # Exact API routes
  location = /saturn/get_versions    { auth_basic "Restricted"; auth_basic_user_file /etc/nginx/.htpasswd; include /etc/nginx/proxy_params; proxy_pass http://127.0.0.1:8080/get_versions; }
  location = /saturn/get_scripts     { auth_basic "Restricted"; auth_basic_user_file /etc/nginx/.htpasswd; include /etc/nginx/proxy_params; proxy_pass http://127.0.0.1:8080/get_scripts; }
  location = /saturn/get_flags       { auth_basic "Restricted"; auth_basic_user_file /etc/nginx/.htpasswd; include /etc/nginx/proxy_params; proxy_pass http://127.0.0.1:8080/get_flags; }
  location = /saturn/backup_response { auth_basic "Restricted"; auth_basic_user_file /etc/nginx/.htpasswd; include /etc/nginx/proxy_params; proxy_pass http://127.0.0.1:8080/backup_response; }
  location = /saturn/change_password { auth_basic "Restricted"; auth_basic_user_file /etc/nginx/.htpasswd; include /etc/nginx/proxy_params; proxy_pass http://127.0.0.1:8080/change_password; }
  location = /saturn/exit            { auth_basic "Restricted"; auth_basic_user_file /etc/nginx/.htpasswd; include /etc/nginx/proxy_params; proxy_pass http://127.0.0.1:8080/exit; }
  location = /saturn/get_system_data { auth_basic "Restricted"; auth_basic_user_file /etc/nginx/.htpasswd; include /etc/nginx/proxy_params; proxy_pass http://127.0.0.1:8080/get_system_data; }

  # SSE runner
  location = /saturn/run {
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;

    include /etc/nginx/proxy_params;
    proxy_pass http://127.0.0.1:8080/run;

    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_read_timeout 1d;
    proxy_send_timeout 1d;
    proxy_buffering off;
    proxy_cache off;
    gzip off;
    add_header X-Accel-Buffering no;
  }

  # Kill process (prefix)
  location ^~ /saturn/kill_process/ {
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
    include /etc/nginx/proxy_params;
    proxy_pass http://127.0.0.1:8080$request_uri;
    proxy_redirect off;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
  }

  # Static UI
  location /saturn/ {
    alias /var/lib/saturn-web/;
    index index.html;
    try_files $uri $uri.html $uri/ =404;

    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
  }

  # Convenience
  location = / { return 302 /saturn/; }
}
NGINX

# Basic auth default (admin/admin) if missing
if [[ ! -s "$BASIC_AUTH_FILE" ]]; then
  htpasswd -b -c "$BASIC_AUTH_FILE" admin admin >/dev/null 2>&1 || true
  chmod 640 "$BASIC_AUTH_FILE"
  chown www-data:www-data "$BASIC_AUTH_FILE"
fi

# Ensure only our site is enabled; disable Debian default if present
rm -f /etc/nginx/sites-enabled/default || true
ln -sf "$NGINX_SITE" "$NGINX_SITE_LINK" || true

# If Apache is holding port 80, stop/disable it
if ss -ltnp | grep -q ':80 ' && ss -ltnp | grep -qi apache2; then
  systemctl stop apache2 || true
  systemctl disable apache2 || true
fi

nginx -t

# Start or reload nginx intelligently
if systemctl is-active --quiet nginx; then
  systemctl reload nginx || true
else
  systemctl enable --now nginx || true
fi

ok "NGINX configured"
# =========================
# systemd
# =========================
info "Writing systemd unit..."
cat >"$SERVICE_FILE" <<SERVICE
[Unit]
Description=Saturn Go API server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=SATURN_WEBROOT=$WEB_ROOT
Environment=SATURN_CONFIG=$WEB_ROOT/config.json
Environment=SATURN_ADDR=$GO_ADDR
Environment=PYTHONUNBUFFERED=1
ExecStart=$BIN_DIR/saturn-go
WorkingDirectory=$SATURN_ROOT
Restart=on-failure
User=${SUDO_USER:-$USER}
Group=${SUDO_USER:-$USER}
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now saturn-go.service
ok "Service enabled and started"

# =========================
# Health check
# =========================
info "Waiting for server to listen on $GO_ADDR..."
for i in {1..20}; do
  if (echo >/dev/tcp/127.0.0.1/8080) >/dev/null 2>&1; then
    ok "Go API is listening"
    break
  fi
  sleep 0.25
done

# =========================
# Summary
# =========================
bold "[SUMMARY]"
echo " Web UI:  http://<your-host>/saturn/  (user: admin, pass: admin)"
echo " API:     http://<your-host>/saturn/get_system_data"
echo " Static:  $WEB_ROOT"
echo " Binary:  $BIN_DIR/saturn-go"
echo " Service: saturn-go.service"
echo " NGINX:   $NGINX_SITE"
ok "Install complete."
