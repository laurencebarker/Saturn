
#!/usr/bin/env bash
################################################################
# update-p2app.sh — robust P2App builder with libgpiod v2 support
# - Detects libgpiod major version (1 vs 2)
# - If v2: runs patch-trixie-gpiod.sh (or any *gpiod*patch*.sh) first
# - Uses Makefile if present; otherwise manual build that selects g2panel_v2.c
################################################################
set -euo pipefail

SATURN_ROOT="${SATURN_ROOT:-$HOME/github/Saturn}"

# Likely locations for the project
P2APP_CANDIDATES=(
  "$SATURN_ROOT/sw_projects/P2_app"
  "$SATURN_ROOT/sw_projects/P2_App"
  "$SATURN_ROOT/P2_app"
  "$SATURN_ROOT/P2_App"
  "$SATURN_ROOT/sw_projects/p2app"
  "$SATURN_ROOT/p2app"
)

hr(){ printf -- '##############################################################\n'; }
log(){ printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }

detect_p2app_dir() {
  local d=""
  for c in "${P2APP_CANDIDATES[@]}"; do
    [[ -d "$c" ]] && { d="$c"; break; }
  done
  [[ -n "$d" ]] || { log "ERROR: P2App directory not found"; exit 1; }
  printf '%s\n' "$d"
}

detect_gpiod_major() {
  local ver=""
  if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libgpiod; then
    ver="$(pkg-config --modversion libgpiod 2>/dev/null || true)"
  fi
  if [[ -z "$ver" ]] && command -v gpiodetect >/dev/null 2>&1; then
    # gpiodetect -V -> "gpiodetect (libgpiod) 2.2.1"
    ver="$(gpiodetect -V 2>&1 | awk '{print $NF}')"
  fi
  [[ -n "$ver" ]] || ver="1.0.0"
  printf '%s\n' "${ver%%.*}"
}

find_patch_script() {
  local exact="$SATURN_ROOT/scripts/patch-trixie-gpiod.sh"
  [[ -f "$exact" ]] && { printf '%s\n' "$exact"; return 0; }
  local hit
  hit="$(find "$SATURN_ROOT/scripts" -maxdepth 2 -type f \( -iname 'patch-trixie-gpiod.sh' -o -iname '*gpiod*patch*.sh' \) -print -quit 2>/dev/null || true)"
  [[ -n "$hit" ]] && printf '%s\n' "$hit" || return 1
}

maybe_run_gpiod_patch() {
  local major="$1"
  if (( major >= 2 )); then
    hr; log "libgpiod v${major} detected → applying v2 patch before build"; hr
    local patch
    if patch="$(find_patch_script)"; then
      log "Found patch script: $patch"
      chmod +x "$patch" 2>/dev/null || true
      ( cd "$(dirname "$patch")" && bash "$patch" ) \
        && log "gpiod v2 patch completed" \
        || log "WARN: patch script returned non-zero (continuing)"
    else
      log "WARN: No gpiod patch script found under $SATURN_ROOT/scripts (continuing)"
    fi
  else
    log "libgpiod v${major} detected → using v1 API path"
  fi
}

manual_build() {
  local dir="$1" major="$2"
  hr; log "Manual build (no Makefile) for P2App"; hr
  local CFLAGS="-Wall -Wextra -Wno-unused-function -g -D_GNU_SOURCE -D GIT_DATE='\"$(date +"%d %b %Y %H:%M:%S")\"'"
  local LDFLAGS="-lm -lpthread -lgpiod -li2c"

  pushd "$dir" >/dev/null
  rm -f p2app *.o || true

  # Choose the correct panel source
  local PANEL_SRC="g2panel.c"
  if (( major >= 2 )) && [[ -f "g2panel_v2.c" ]]; then
    PANEL_SRC="g2panel_v2.c"
    log "Building with ${PANEL_SRC} (libgpiod v${major})"
  else
    log "Building with ${PANEL_SRC} (libgpiod v${major})"
  fi

  local SRCS=(
    p2app.c generalpacket.c IncomingDDCSpecific.c IncomingDUCSpecific.c
    InHighPriority.c InDUCIQ.c InSpkrAudio.c OutMicAudio.c OutDDCIQ.c OutHighPriority.c
    debugaids.c auxadc.c cathandler.c frontpanelhandler.c catmessages.c
    LDGATU.c g2v2panel.c i2cdriver.c andromedacatmessages.c Outwideband.c serialport.c AriesATU.c
    ../common/hwaccess.c ../common/saturnregisters.c ../common/codecwrite.c ../common/saturndrivers.c ../common/version.c
  )

  for src in "${SRCS[@]}"; do
    [[ -f "$src" ]] || { log "INFO: skipping missing $src"; continue; }
    gcc -c $CFLAGS "$src" -o "$(basename "${src%.*}").o"
  done
  [[ -f "$PANEL_SRC" ]] && gcc -c $CFLAGS "$PANEL_SRC" -o g2panel.o

  gcc -o p2app *.o $LDFLAGS
  log "OK: P2App built from $dir"
  popd >/dev/null
}

make_build() {
  local dir="$1"
  hr; log "Using Makefile in $dir"; hr
  make -C "$dir" clean || true
  make -C "$dir" -j"$(nproc 2>/dev/null || echo 1)"
  log "OK: P2App built from $dir"
}

# ---------------- main ----------------
hr; echo; log "making p2app"; log "this will create a lot of warning - please ignore them"; echo; hr

P2DIR="$(detect_p2app_dir)"
GPIOD_MAJOR="$(detect_gpiod_major)"
log "Detected libgpiod major: $GPIOD_MAJOR"

maybe_run_gpiod_patch "$GPIOD_MAJOR"

if [[ -f "$P2DIR/Makefile" || -f "$P2DIR/makefile" ]]; then
  make_build "$P2DIR"
else
  manual_build "$P2DIR" "$GPIOD_MAJOR"
fi
