#!/usr/bin/env bash
###################################################################################################
# update-p2app.sh — robust P2App builder with libgpiod v1/v2 handling
#
# What this script does:
#   1) Locates the P2_app source directory under your Saturn tree (or uses overrides).
#   2) Detects installed libgpiod major version (v1 vs v2).
#   3) If libgpiod v2 is detected, attempts to run the gpiod v2 patch script first
#      (typically patch-trixie-gpiod.sh), because the v1 API will not compile cleanly on v2.
#   4) Builds using the project Makefile when present; otherwise falls back to a manual gcc build.
#
# Overrides (optional):
#   SATURN_ROOT=/path/to/Saturn          # default: $HOME/github/Saturn
#   P2APP_DIR=/path/to/P2_app            # hard override (skips directory search)
#   NO_GPIOD_PATCH=1                     # skip running patch script even if v2 is detected
#
# Notes:
#   - On Debian Trixie / newer, libgpiod is usually v2.x, so the patch step is important.
#   - The manual build path uses bash arrays for CFLAGS so embedded quotes (like GIT_DATE) are safe.
###################################################################################################

set -Eeuo pipefail

# Pretty separators + timestamped logging
hr(){ printf '##############################################################\n'; }
log(){ printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }

# Helpful error context when anything fails (line + command)
trap 'log "ERROR: command failed (line $LINENO): $BASH_COMMAND"' ERR

SATURN_ROOT="${SATURN_ROOT:-$HOME/github/Saturn}"

# Likely locations for the project (only used if P2APP_DIR is not set)
P2APP_CANDIDATES=(
  "$SATURN_ROOT/sw_projects/P2_app"
  "$SATURN_ROOT/sw_projects/P2_App"
  "$SATURN_ROOT/P2_app"
  "$SATURN_ROOT/P2_App"
  "$SATURN_ROOT/sw_projects/p2app"
  "$SATURN_ROOT/p2app"
)

detect_p2app_dir() {
  # If user explicitly set P2APP_DIR, trust it (but validate)
  if [[ -n "${P2APP_DIR:-}" ]]; then
    [[ -d "$P2APP_DIR" ]] || { log "ERROR: P2APP_DIR is set but not a directory: $P2APP_DIR"; exit 1; }
    printf '%s\n' "$P2APP_DIR"
    return 0
  fi

  # Otherwise search candidates and choose the first that looks like P2App
  local c
  for c in "${P2APP_CANDIDATES[@]}"; do
    if [[ -d "$c" ]] && { [[ -f "$c/p2app.c" ]] || [[ -f "$c/Makefile" ]] || [[ -f "$c/makefile" ]]; }; then
      printf '%s\n' "$c"
      return 0
    fi
  done

  log "ERROR: P2App directory not found. Checked:"
  for c in "${P2APP_CANDIDATES[@]}"; do log "  - $c"; done
  log "Tip: set P2APP_DIR=/full/path/to/P2_app and rerun."
  exit 1
}

detect_gpiod_major() {
  # Prefer pkg-config (most reliable)
  local ver=""
  if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libgpiod; then
    ver="$(pkg-config --modversion libgpiod 2>/dev/null || true)"
  fi

  # Fallback: gpiodetect -V prints something like: "gpiodetect (libgpiod) 2.2.1"
  if [[ -z "$ver" ]] && command -v gpiodetect >/dev/null 2>&1; then
    ver="$(gpiodetect -V 2>&1 | awk '{print $NF}' || true)"
  fi

  # If we couldn't detect, assume v1 to avoid blocking (but we will log it)
  [[ -n "$ver" ]] || ver="1.0.0"

  # Return major version only (e.g., "2" from "2.2.1")
  printf '%s\n' "${ver%%.*}"
}

find_patch_script() {
  # Prefer the known name/location first
  local exact="$SATURN_ROOT/scripts/patch-trixie-gpiod.sh"
  [[ -f "$exact" ]] && { printf '%s\n' "$exact"; return 0; }

  # Otherwise search for something that looks like a gpiod patch script
  local hit=""
  hit="$(find "$SATURN_ROOT/scripts" -maxdepth 2 -type f \
    \( -iname 'patch-trixie-gpiod.sh' -o -iname '*gpiod*patch*.sh' \) \
    -print -quit 2>/dev/null || true)"

  [[ -n "$hit" ]] && { printf '%s\n' "$hit"; return 0; }
  return 1
}

maybe_run_gpiod_patch() {
  # Arguments:
  #   $1 = libgpiod major version
  #   $2 = P2_app directory (so we can validate patch results)
  local major="$1"
  local p2dir="$2"

  # If v1, no patch needed.
  if (( major < 2 )); then
    log "libgpiod v${major} detected → using v1 API path"
    return 0
  fi

  # Allow user to skip patch step explicitly
  if [[ -n "${NO_GPIOD_PATCH:-}" ]]; then
    log "libgpiod v${major} detected → NO_GPIOD_PATCH set, skipping patch step"
    return 0
  fi

  hr; log "libgpiod v${major} detected → attempting v2 compatibility patch before build"; hr

  local patch=""
  if patch="$(find_patch_script)"; then
    log "Found patch script: $patch"
    chmod +x "$patch" 2>/dev/null || true

    # Run patch from its own directory (some patch scripts rely on relative paths)
    if ( cd "$(dirname "$patch")" && SATURN_ROOT="$SATURN_ROOT" bash "$patch" ); then
      log "gpiod v2 patch completed (script returned success)"
    else
      log "WARN: patch script returned non-zero"
    fi
  else
    log "WARN: No gpiod patch script found under $SATURN_ROOT/scripts"
  fi

  # Sanity check: on v2 systems, we strongly expect g2panel_v2.c to exist after patching.
  # If it doesn't, your build may fail later with libgpiod API errors — so fail early with guidance.
  if [[ ! -f "$p2dir/g2panel_v2.c" ]]; then
    log "ERROR: libgpiod v${major} is installed, but $p2dir/g2panel_v2.c is missing."
    log "       The project likely still uses libgpiod v1 APIs and may not compile."
    log "       Fix: ensure patch-trixie-gpiod.sh exists under $SATURN_ROOT/scripts and run it."
    exit 1
  fi
}

manual_build() {
  # Manual gcc build path for environments where Makefile is missing/unusable.
  # Uses arrays for flags so quoting is correct (especially for GIT_DATE).
  local dir="$1"
  local major="$2"

  hr; log "Manual build (no Makefile) for P2App"; hr

  command -v gcc >/dev/null 2>&1 || { log "ERROR: gcc not found"; exit 1; }

  local git_date
  git_date="$(date +"%d %b %Y %H:%M:%S")"

  # IMPORTANT: Use an array for flags so embedded spaces/quotes are preserved.
  local -a CFLAGS=(
    -Wall -Wextra -Wno-unused-function -g
    -D_GNU_SOURCE
    "-DGIT_DATE=\"${git_date}\""
    -I. -I../common
  )

  # Libraries should appear after objects at link time
  local -a LDLIBS=(-lm -lpthread -lgpiod -li2c)

  pushd "$dir" >/dev/null
  rm -f p2app *.o || true

  # Choose the correct panel source (v2 file should exist after patch on libgpiod v2)
  local PANEL_SRC="g2panel.c"
  if (( major >= 2 )) && [[ -f "g2panel_v2.c" ]]; then
    PANEL_SRC="g2panel_v2.c"
  fi
  log "Building with ${PANEL_SRC} (libgpiod v${major})"

  # Source list is kept close to your current working set.
  # If some files are optional in your tree, we skip missing ones gracefully.
  local SRCS=(
    p2app.c generalpacket.c IncomingDDCSpecific.c IncomingDUCSpecific.c
    InHighPriority.c InDUCIQ.c InSpkrAudio.c OutMicAudio.c OutDDCIQ.c OutHighPriority.c
    debugaids.c auxadc.c cathandler.c frontpanelhandler.c catmessages.c
    LDGATU.c g2v2panel.c i2cdriver.c andromedacatmessages.c Outwideband.c serialport.c AriesATU.c
    ../common/hwaccess.c ../common/saturnregisters.c ../common/codecwrite.c ../common/saturndrivers.c ../common/version.c
  )

  local src obj
  for src in "${SRCS[@]}"; do
    [[ -f "$src" ]] || { log "INFO: skipping missing $src"; continue; }
    obj="$(basename "${src%.*}").o"
    gcc -c "${CFLAGS[@]}" "$src" -o "$obj"
  done

  # Compile the selected panel source into a consistent object name
  if [[ -f "$PANEL_SRC" ]]; then
    gcc -c "${CFLAGS[@]}" "$PANEL_SRC" -o g2panel.o
  else
    log "ERROR: panel source not found: $PANEL_SRC"
    exit 1
  fi

  gcc -o p2app ./*.o "${LDLIBS[@]}"
  log "OK: P2App built from $dir"
  popd >/dev/null
}

make_build() {
  # Build using the project Makefile (preferred path).
  local dir="$1"
  hr; log "Using Makefile in $dir"; hr

  command -v make >/dev/null 2>&1 || { log "ERROR: make not found"; exit 1; }

  # Clean first to avoid stale objects from older compiler flags / libgpiod changes
  make -C "$dir" clean || true
  make -C "$dir" -j"$(nproc 2>/dev/null || echo 1)"

  log "OK: P2App built from $dir"
}

# ---------------- main ----------------
hr; echo
log "Making p2app"
log "Note: you may see many warnings; errors will stop the build."
echo; hr

P2DIR="$(detect_p2app_dir)"
GPIOD_MAJOR="$(detect_gpiod_major)"

log "P2App directory: $P2DIR"
log "Detected libgpiod major: $GPIOD_MAJOR"

maybe_run_gpiod_patch "$GPIOD_MAJOR" "$P2DIR"

if [[ -f "$P2DIR/Makefile" || -f "$P2DIR/makefile" ]]; then
  make_build "$P2DIR"
else
  manual_build "$P2DIR" "$GPIOD_MAJOR"
fi
