#!/usr/bin/env bash
################################################################
# update-desktop-apps.sh
# Build apps and install/repair .desktop launchers (repo + generated).
#
# Key behaviors:
# - If OS codename is "trixie", run patch-trixie-gpiod.sh BEFORE compiling P2App.
# - Recursively copies all *.desktop under $SATURN_ROOT/desktop (follows symlinks)
#   into:
#     - ~/.local/share/applications
#     - Desktop dir (xdg-user-dir DESKTOP or ~/.config/user-dirs.dirs, fallback ~/Desktop)
# - Generates/updates launchers for core apps (BiasCheck/AudioTest/AXI/FlashWriter)
# - Adds a web launcher for Saturn Update Manager (SATURN_URL)
# - IMPORTANT FIX: auto-adds Path= for Saturn binaries so GTK Builder *.ui loads
# - Marks Desktop launchers executable + trusted (gio metadata::trusted) when available
################################################################

set -uo pipefail
IFS=$'\n\t'

# ---------- config ----------
SATURN_ROOT="${SATURN_ROOT:-$HOME/github/Saturn}"
SHORTCUT_SRC="$SATURN_ROOT/desktop"
SATURN_URL="${SATURN_URL:-http://localhost/saturn}"

APP_BIAS_BIN="$SATURN_ROOT/sw_projects/biascheck/biascheck"
APP_AUDIO_BIN="$SATURN_ROOT/sw_projects/audiotest/audiotest"
APP_AXI_BIN="$SATURN_ROOT/sw_tools/axi_rw/axi_rw"
APP_FLASH_BIN="$SATURN_ROOT/sw_tools/flashwriter/flashwriter"

# Candidate locations for P2App (pick the first with a Makefile)
P2APP_CANDIDATES=(
  "$SATURN_ROOT/sw_projects/P2_app"
  "$SATURN_ROOT/sw_projects/P2_App"
  "$SATURN_ROOT/sw_projects/p2_app"
  "$SATURN_ROOT/sw_projects/p2app"
  "$SATURN_ROOT/P2_app"
  "$SATURN_ROOT/P2_App"
  "$SATURN_ROOT/P2app"
  "$SATURN_ROOT/p2app"
)

# ---------- helpers ----------
log() { printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }
hr()  { printf -- '##############################################################\n'; }

get_codename() {
  local codename=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    codename="${VERSION_CODENAME:-${DEBIAN_CODENAME:-}}"
  fi
  printf '%s\n' "$codename"
}

find_patch_script() {
  local exact="$SATURN_ROOT/scripts/patch-trixie-gpiod.sh"
  if [[ -f "$exact" ]]; then
    printf '%s\n' "$exact"; return 0
  fi
  local hit
  hit="$(find "$SATURN_ROOT/scripts" -maxdepth 2 -type f \( -iname 'patch-trixie-gpiod.sh' -o -iname '*gpiod*patch*.sh' \) -print -quit 2>/dev/null || true)"
  [[ -n "$hit" ]] && printf '%s\n' "$hit" || return 1
}

maybe_patch_trixie_for_p2app() {
  local codename; codename="$(get_codename)"
  if [[ "${codename,,}" == "trixie" ]]; then
    hr; echo; log "OS codename '${codename}' detected → applying gpiod v2 patch before building P2App"; echo; hr
    local patch
    if patch="$(find_patch_script)"; then
      log "Found patch script: $patch"
      chmod +x "$patch" 2>/dev/null || true
      ( cd "$(dirname "$patch")" || exit 0; bash "$patch" ) \
        && log "gpiod v2 patch completed" \
        || log "WARN: patch script returned non-zero (continuing)"
    else
      log "WARN: No gpiod patch script found under $SATURN_ROOT/scripts"
    fi
  else
    log "OS codename '${codename:-unknown}' → skipping P2App gpiod patch"
  fi
}

build_dir() {
  local dir="$1" name="$2"
  hr; echo; log "Building ${name}"; echo; hr
  if [[ -d "$dir" ]]; then
    if command -v make >/dev/null 2>&1; then
      ( cd "$dir" && make clean >/dev/null 2>&1 || true
        if make -j"$(nproc 2>/dev/null || echo 1)"; then
          log "OK: ${name} built from $dir"
        else
          log "WARN: make failed in $dir (continuing)"
        fi
      )
    else
      log "WARN: 'make' not found; skipping build for ${name}"
    fi
  else
    log "WARN: Directory not found, skipping: $dir"
  fi
}

build_p2app() {
  maybe_patch_trixie_for_p2app
  local dir=""
  for cand in "${P2APP_CANDIDATES[@]}"; do
    if [[ -d "$cand" ]] && { [[ -f "$cand/Makefile" ]] || [[ -f "$cand/makefile" ]] ; }; then
      dir="$cand"; break
    fi
  done
  if [[ -n "$dir" ]]; then
    build_dir "$dir" "P2App"
  else
    log "INFO: No P2App directory with a Makefile found (candidates: ${P2APP_CANDIDATES[*]})"
  fi
}

detect_desktop_dir() {
  local d=""
  if command -v xdg-user-dir >/dev/null 2>&1; then
    d="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
  fi
  if [[ -z "$d" ]]; then
    local cfg="$HOME/.config/user-dirs.dirs"
    if [[ -f "$cfg" ]]; then
      # shellcheck disable=SC1090
      source "$cfg"
      d="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
      d="${d/\$HOME/$HOME}"
    fi
  fi
  d="${d:-$HOME/Desktop}"

  # Safety guard: never allow "/" (or empty) as the desktop dir.
  if [[ -z "$d" || "$d" == "/" ]]; then
    d="$HOME/Desktop"
  fi

  printf '%s\n' "$d"
}

mark_trusted() {
  local f="$1"
  command -v gio >/dev/null 2>&1 || return 0
  gio set "$f" metadata::trusted true 2>/dev/null || true
}

find_icon() {
  local stem="$1" icon=""
  if [[ -d "$SHORTCUT_SRC/icons" ]]; then
    icon="$(find "$SHORTCUT_SRC/icons" -maxdepth 1 -type f \( -iname "${stem}.*" -o -iname "${stem}-icon.*" \) -print | head -n1 || true)"
  fi
  if [[ -n "$icon" ]]; then printf '%s\n' "$icon"; else printf '%s\n' "applications-utilities"; fi
}

browser_cmd() {
  if command -v chromium-browser >/dev/null 2>&1; then
    echo "chromium-browser --app=${SATURN_URL} --user-data-dir=$HOME/.config/chromium-saturn --new-window"
  elif command -v chromium >/dev/null 2>&1; then
    echo "chromium --app=${SATURN_URL} --user-data-dir=$HOME/.config/chromium-saturn --new-window"
  else
    echo "xdg-open ${SATURN_URL}"
  fi
}

# ---- desktop file normalization/repair ----

extract_exec_cmd() {
  # prints the Exec command (value after Exec=), or empty
  local f="$1"
  grep -E '^Exec=' "$f" 2>/dev/null | head -n1 | cut -d= -f2- || true
}

extract_exec_path() {
  # prints just the command path (first token) from an Exec= value
  local exec="$1"
  local cmd="${exec%% *}"
  cmd="${cmd#\"}"; cmd="${cmd%\"}"
  printf '%s\n' "$cmd"
}

should_add_path_for_exec() {
  # $1 exec_cmd_string -> return 0 if we should add Path=
  local exec="$1" cmd
  cmd="$(extract_exec_path "$exec")"
  [[ -n "$cmd" ]] || return 1
  [[ "$cmd" == "$SATURN_ROOT/"* ]] || return 1
  [[ -x "$cmd" ]] || return 1
  return 0
}

add_path_key_if_missing() {
  # $1 input .desktop  $2 output .desktop
  local in="$1" out="$2"

  # Keep as-is if Path already present
  if grep -qE '^[[:space:]]*Path=' "$in"; then
    cp -f "$in" "$out"
    return 0
  fi

  local exec cmd wd
  exec="$(extract_exec_cmd "$in")"
  if ! should_add_path_for_exec "$exec"; then
    cp -f "$in" "$out"
    return 0
  fi

  cmd="$(extract_exec_path "$exec")"
  wd="$(dirname "$cmd")"

  # Insert Path= immediately after Exec= (works for most desktop parsers)
  awk -v wd="$wd" '
    BEGIN{added=0}
    {print}
    /^Exec=/{ if(!added){ print "Path=" wd; added=1 } }
  ' "$in" > "$out"
}

write_launcher() {
  # $1 out path; $2 Name; $3 Exec; $4 Comment; $5 Icon; $6 Categories; $7 Terminal(true/false)
  local out="$1" name="$2" exec="$3" comment="$4" icon="$5" cats="$6" term="${7:-false}"
  mkdir -p "$(dirname "$out")"
  cat > "$out" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${name}
Comment=${comment}
Exec=${exec}
TryExec=${exec%% *}
Terminal=${term}
StartupNotify=true
Icon=${icon}
Categories=${cats}
EOF
}

install_desktop_file_processed() {
  # $1: source .desktop file (or generated temp)
  # $2: base filename to install as
  # $3: apps_dir
  # $4: desk_dir
  local src="$1" base="$2" apps_dir="$3" desk_dir="$4"

  log "Installing/Updating launcher: $base"

  mkdir -p "$apps_dir" "$desk_dir"

  local tmp; tmp="$(mktemp)"
  add_path_key_if_missing "$src" "$tmp"

  install -Dm644 "$tmp" "$apps_dir/$base"
  install -Dm644 "$tmp" "$desk_dir/$base"
  rm -f "$tmp"

  # Desktop copy: executable + trusted
  chmod +x "$desk_dir/$base" 2>/dev/null || true
  mark_trusted "$desk_dir/$base"

  # Optional validation (non-fatal)
  if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$apps_dir/$base" >/dev/null 2>&1 || log "WARN: desktop-file-validate reported issues for $base"
  fi
}

repair_existing_saturn_launchers_in_dir() {
  # $1 dir
  local d="$1"
  [[ -d "$d" ]] || return 0

  # Avoid literal "*.desktop" when none exist
  local oldnullglob
  shopt -q nullglob && oldnullglob=1 || oldnullglob=0
  shopt -s nullglob

  local f tmp base exec
  for f in "$d"/*.desktop; do
    [[ -f "$f" ]] || continue
    exec="$(extract_exec_cmd "$f")"
    if should_add_path_for_exec "$exec"; then
      if ! grep -qE '^[[:space:]]*Path=' "$f"; then
        base="$(basename "$f")"
        log "Repairing missing Path= in: $d/$base"
        tmp="$(mktemp)"
        add_path_key_if_missing "$f" "$tmp"
        install -Dm644 "$tmp" "$f"
        rm -f "$tmp"
      fi
    fi
  done

  (( oldnullglob == 1 )) || shopt -u nullglob
}

# ---------- build apps ----------
build_p2app
build_dir "$SATURN_ROOT/sw_projects/biascheck"     "bias check app"
build_dir "$SATURN_ROOT/sw_projects/audiotest"     "audio test app"
build_dir "$SATURN_ROOT/sw_tools/axi_rw"           "AXI reader/writer app"
build_dir "$SATURN_ROOT/sw_tools/flashwriter"      "flash writer app"

# ---------- paths ----------
USER_APPS_DIR="$HOME/.local/share/applications"
USER_DESKTOP_DIR="$(detect_desktop_dir)"
mkdir -p "$USER_APPS_DIR" "$USER_DESKTOP_DIR"

if [[ -z "$USER_DESKTOP_DIR" || "$USER_DESKTOP_DIR" == "/" ]]; then
  log "ERROR: Desktop dir resolved to '$USER_DESKTOP_DIR' — refusing to proceed."
  exit 1
fi

# ---------- copy all repo .desktop files (recurse, follow symlinks) ----------
hr; echo; log "Copying Desktop shortcuts from $SHORTCUT_SRC"; echo; hr
readarray -d '' SHORTCUTS < <(find -L "$SHORTCUT_SRC" -type f -iname '*.desktop' -print0 2>/dev/null || true)

if (( ${#SHORTCUTS[@]} == 0 )); then
  log "WARN: No .desktop files found in $SHORTCUT_SRC"
else
  for f in "${SHORTCUTS[@]}"; do
    base="$(basename "$f")"
    install_desktop_file_processed "$f" "$base" "$USER_APPS_DIR" "$USER_DESKTOP_DIR"
  done
fi

# ---------- generate/update core app launchers (ALWAYS update) ----------
hr; echo; log "Ensuring core app launchers are present and fixed"; echo; hr

ensure_core_launcher() {
  # $1 base filename; $2 Name; $3 ExecBin; $4 Comment; $5 icon stem
  local base="$1" name="$2" bin="$3" comment="$4" icon_stem="$5"

  # If repo provides this launcher, prefer it (but still process it so Path= is injected)
  if [[ -f "$SHORTCUT_SRC/$base" ]]; then
    install_desktop_file_processed "$SHORTCUT_SRC/$base" "$base" "$USER_APPS_DIR" "$USER_DESKTOP_DIR"
    return 0
  fi

  # Otherwise, generate our own launcher
  local tmp; tmp="$(mktemp)"
  write_launcher "$tmp" "$name" "$bin" "$comment" "$(find_icon "$icon_stem")" "Utility;Engineering;" "false"
  install_desktop_file_processed "$tmp" "$base" "$USER_APPS_DIR" "$USER_DESKTOP_DIR"
  rm -f "$tmp"
}

ensure_core_launcher "BiasCheck.desktop"       "Bias Check"        "$APP_BIAS_BIN"   "Run the Saturn Bias Check utility"            "biascheck"
ensure_core_launcher "AudioTest.desktop"       "Audio Test"        "$APP_AUDIO_BIN"  "Run the Saturn Audio Test utility"            "audiotest"
ensure_core_launcher "AXIReaderWriter.desktop" "AXI Reader/Writer" "$APP_AXI_BIN"    "Read/write AXI registers on Saturn hardware"  "axi"
ensure_core_launcher "FlashWriter.desktop"     "Flash Writer"      "$APP_FLASH_BIN"  "Program SPI flash for the FPGA/SoC"           "flashwriter"

# ---------- Saturn Update Manager web launcher (ALWAYS update) ----------
hr; echo; log "Ensuring Saturn Update Manager web launcher"; echo; hr
SATURN_DESKTOP_NAME="SaturnUpdateManager.desktop"

# Prefer repo version if it exists; else generate.
if [[ -f "$SHORTCUT_SRC/$SATURN_DESKTOP_NAME" ]]; then
  install_desktop_file_processed "$SHORTCUT_SRC/$SATURN_DESKTOP_NAME" "$SATURN_DESKTOP_NAME" "$USER_APPS_DIR" "$USER_DESKTOP_DIR"
else
  tmp="$(mktemp)"
  write_launcher "$tmp" "Saturn Update Manager" "$(browser_cmd)" "Open the Saturn Update Manager web UI" "$(find_icon saturn)" "Utility;Engineering;" "false"
  install_desktop_file_processed "$tmp" "$SATURN_DESKTOP_NAME" "$USER_APPS_DIR" "$USER_DESKTOP_DIR"
  rm -f "$tmp"
fi

# ---------- repair any previously-installed Saturn launchers ----------
hr; echo; log "Repairing any existing Saturn launchers missing Path="; echo; hr
repair_existing_saturn_launchers_in_dir "$USER_APPS_DIR"
repair_existing_saturn_launchers_in_dir "$USER_DESKTOP_DIR"

# Ensure Desktop launchers are executable + trusted (again, cheap + safe)
chmod +x "$USER_DESKTOP_DIR"/*.desktop 2>/dev/null || true
for f in "$USER_DESKTOP_DIR"/*.desktop; do
  [[ -f "$f" ]] && mark_trusted "$f"
done

# ---------- optional: install repo icons to user theme ----------
if [[ -d "$SHORTCUT_SRC/icons" ]]; then
  ICON_DST="$HOME/.local/share/icons/hicolor/256x256/apps"
  mkdir -p "$ICON_DST"
  find "$SHORTCUT_SRC/icons" -type f \( -iname '*.png' -o -iname '*.svg' -o -iname '*.xpm' \) -print0 \
    | while IFS= read -r -d '' ic; do
        log "Installing icon: $(basename "$ic")"
        install -Dm644 "$ic" "$ICON_DST/$(basename "$ic")"
      done
fi

# ---------- system-wide (root) ----------
if [[ ${EUID:-$UID} -eq 0 ]]; then
  log "Root mode: installing launchers to /usr/share/applications"
  find "$USER_APPS_DIR" -maxdepth 1 -type f -iname '*.desktop' -print0 \
    | xargs -0 -I {} install -Dm644 "{}" "/usr/share/applications/$(basename "{}")"
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications || true
  fi
fi

# ---------- refresh caches ----------
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$USER_APPS_DIR" || true
fi
if command -v xdg-desktop-menu >/dev/null 2>&1; then
  xdg-desktop-menu forceupdate || true
fi

echo
hr
log "Done. Shortcuts installed/repaired in:"
echo "  - $USER_APPS_DIR"
echo "  - $USER_DESKTOP_DIR"
hr
