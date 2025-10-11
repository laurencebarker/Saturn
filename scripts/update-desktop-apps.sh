#!/usr/bin/env bash
################################################################
# update-desktop-apps.sh
# Build apps and install .desktop launchers (repo + generated).
#
# - If OS codename is "trixie", run patch-trixie-gpiod.sh
#   BEFORE compiling P2App.
# - Recursively copies all *.desktop under $SATURN_ROOT/desktop
#   (follows symlinks) into:
#       ~/.local/share/applications  and  $XDG_DESKTOP_DIR/~/Desktop
# - Auto-generates launchers for key apps if they don't exist.
# - Adds a web launcher for Saturn Update Manager (SATURN_URL).
################################################################

set -uo pipefail

# ---------- config ----------
SATURN_ROOT="${SATURN_ROOT:-$HOME/github/Saturn}"
SHORTCUT_SRC="$SATURN_ROOT/desktop"
SATURN_URL="${SATURN_URL:-http://localhost/saturn}"

APP_BIAS_BIN="$SATURN_ROOT/sw_projects/biascheck/biascheck"
APP_AUDIO_BIN="$SATURN_ROOT/sw_projects/audiotest/audiotest"
APP_AXI_BIN="$SATURN_ROOT/sw_tools/axi_rw/axi_rw"
APP_FLASH_BIN="$SATURN_ROOT/sw_tools/flashwriter/flashwriter"

# candidate locations for P2App (we'll pick the first with a Makefile)
P2APP_CANDIDATES=(
  "$SATURN_ROOT/P2_App"
  "$SATURN_ROOT/sw_projects/P2_App"
  "$SATURN_ROOT/sw_projects/p2app"
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

maybe_patch_trixie_for_p2app() {
  local codename; codename="$(get_codename)"
  if [[ "${codename,,}" == "trixie" ]]; then
    local patch="$SATURN_ROOT/scripts/patch-trixie-gpiod.sh"
    hr; echo; log "OS codename '${codename}' detected → running gpiod v2 patch before building P2App"; echo; hr
    if [[ -x "$patch" ]]; then
      ( cd "$SATURN_ROOT/scripts" && "$patch" ) \
        && log "gpiod v2 patch completed" \
        || log "WARN: patch script returned non-zero (continuing)"
    else
      log "WARN: Expected patch not found or not executable: $patch"
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
  # run the trixie patch first (if applicable)
  maybe_patch_trixie_for_p2app

  # find a p2app directory that has a Makefile
  local dir=""
  for cand in "${P2APP_CANDIDATES[@]}"; do
    if [[ -d "$cand" ]] && { [[ -f "$cand/Makefile" ]] || [[ -f "$cand/makefile" ]]; }; then
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
  printf '%s\n' "${d:-$HOME/Desktop}"
}

find_icon() {
  # $1: stem (e.g., "biascheck" or "saturn")
  local stem="$1" icon=""
  if [[ -d "$SHORTCUT_SRC/icons" ]]; then
    icon="$(find "$SHORTCUT_SRC/icons" -maxdepth 1 -type f \( -iname "${stem}.*" -o -iname "${stem}-icon.*" \) -print | head -n1 || true)"
  fi
  if [[ -n "$icon" ]]; then printf '%s\n' "$icon"; else printf '%s\n' "applications-utilities"; fi
}

write_launcher() {
  # $1 out path; $2 Name; $3 Exec; $4 Comment; $5 Icon
  local out="$1" name="$2" exec="$3" comment="$4" icon="$5"
  mkdir -p "$(dirname "$out")"
  cat > "$out" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${name}
Comment=${comment}
Exec=${exec}
TryExec=${exec%% *}
Terminal=false
StartupNotify=true
Icon=${icon}
Categories=Utility;Engineering;
EOF
}

install_desktop_file() {
  # $1: source path to .desktop
  local src="$1"
  local apps_dir="$2"
  local desk_dir="$3"
  local base; base="$(basename "$src")"
  log "Installing launcher: $base"
  install -Dm644 "$src" "$apps_dir/$base"
  install -Dm644 "$src" "$desk_dir/$base"
  chmod +x "$desk_dir/$base" 2>/dev/null || true
}

# ---------- build apps ----------
# P2App (with trixie patch pre-step if needed)
build_p2app

build_dir "$SATURN_ROOT/sw_projects/biascheck"    "bias check app"
build_dir "$SATURN_ROOT/sw_projects/audiotest"     "audio test app"
build_dir "$SATURN_ROOT/sw_tools/axi_rw"           "AXI reader/writer app"
build_dir "$SATURN_ROOT/sw_tools/flashwriter"      "flash writer app"

# ---------- paths ----------
USER_APPS_DIR="$HOME/.local/share/applications"
USER_DESKTOP_DIR="$(detect_desktop_dir)"
mkdir -p "$USER_APPS_DIR" "$USER_DESKTOP_DIR"

# ---------- copy all repo .desktop files (recurse, follow symlinks) ----------
hr; echo; log "Copying Desktop shortcuts from $SHORTCUT_SRC"; echo; hr
readarray -d '' SHORTCUTS < <(find -L "$SHORTCUT_SRC" -type f -iname '*.desktop' -print0 2>/dev/null || true)

if (( ${#SHORTCUTS[@]} == 0 )); then
  log "WARN: No .desktop files found in $SHORTCUT_SRC"
else
  for f in "${SHORTCUTS[@]}"; do
    install_desktop_file "$f" "$USER_APPS_DIR" "$USER_DESKTOP_DIR"
  done
fi

# ---------- auto-generate app launchers if missing ----------
hr; echo; log "Ensuring core app launchers exist"; echo; hr

ensure_generated() {
  # $1 base filename; $2 Name; $3 Exec; $4 Comment; $5 icon stem
  local base="$1" name="$2" exec="$3" comment="$4" icon_stem="$5"
  local target="$USER_APPS_DIR/$base"
  local src_repo="$SHORTCUT_SRC/$base"
  if [[ ! -f "$src_repo" && ! -f "$target" ]]; then
    local tmp
    tmp="$(mktemp)"
    write_launcher "$tmp" "$name" "$exec" "$comment" "$(find_icon "$icon_stem")"
    install_desktop_file "$tmp" "$USER_APPS_DIR" "$USER_DESKTOP_DIR"
    mv -f "$USER_APPS_DIR/$(basename "$tmp")" "$target" 2>/dev/null || true
    mv -f "$USER_DESKTOP_DIR/$(basename "$tmp")" "$USER_DESKTOP_DIR/$base" 2>/dev/null || true
    rm -f "$tmp"
  else
    log "Launcher already present (repo or installed): $base"
  fi
}

ensure_generated "BiasCheck.desktop"        "Bias Check"        "$APP_BIAS_BIN"  "Run the Saturn Bias Check utility"            "biascheck"
ensure_generated "AudioTest.desktop"        "Audio Test"        "$APP_AUDIO_BIN" "Run the Saturn Audio Test utility"            "audiotest"
ensure_generated "AXIReaderWriter.desktop"  "AXI Reader/Writer" "$APP_AXI_BIN"   "Read/write AXI registers on Saturn hardware"  "axi"
ensure_generated "FlashWriter.desktop"      "Flash Writer"      "$APP_FLASH_BIN" "Program SPI flash for the FPGA/SoC"           "flashwriter"

# ---------- Saturn Go Update Manager web launcher ----------
hr; echo; log "Ensuring Saturn Go Update Manager web launcher"; echo; hr
SATURN_DESKTOP_NAME="SaturnUpdateManager.desktop"
if [[ ! -f "$SHORTCUT_SRC/$SATURN_DESKTOP_NAME" && ! -f "$USER_APPS_DIR/$SATURN_DESKTOP_NAME" ]]; then
  tmp="$(mktemp)"
  write_launcher "$tmp" "Saturn Update Manager" "xdg-open ${SATURN_URL}" "Open the Saturn Go Update Manager web UI" "$(find_icon saturn)"
  install_desktop_file "$tmp" "$USER_APPS_DIR" "$USER_DESKTOP_DIR"
  mv -f "$USER_APPS_DIR/$(basename "$tmp")" "$USER_APPS_DIR/$SATURN_DESKTOP_NAME" 2>/dev/null || true
  mv -f "$USER_DESKTOP_DIR/$(basename "$tmp")" "$USER_DESKTOP_DIR/$SATURN_DESKTOP_NAME" 2>/dev/null || true
  rm -f "$tmp"
else
  log "Launcher already present (repo or installed): $SATURN_DESKTOP_NAME"
fi

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
log "Done. Shortcuts installed to:"
echo "  - $USER_APPS_DIR"
echo "  - $USER_DESKTOP_DIR"
hr
