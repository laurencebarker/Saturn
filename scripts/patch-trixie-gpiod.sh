#!/usr/bin/env bash
#
# patch-trixie-gpiod.sh
# ---------------------
# Fix Saturn P2_app build issues on Debian/RPi OS "Trixie" (libgpiod v2+).
#
# - Detect libgpiod major version (pkg-config).
# - Ensure g2panel_v2.c exists and matches g2panel.h (bool CheckG2PanelPresent(void)).
# - Patch Makefile to auto-select g2panel_v1.c vs g2panel_v2.c and use pkg-config flags.
# - Ensure link step includes $(LDLIBS).
# - Fix TAB indentation to avoid "missing separator".
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
APP_DIR="${APP_DIR:-${REPO_ROOT}/sw_projects/P2_app}"
PKGCFG="${PKGCFG:-pkg-config}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --app-dir requires a value" >&2; exit 2; }
      APP_DIR="$2"
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: patch-trixie-gpiod.sh [--app-dir PATH]

Environment:
  APP_DIR   P2_app directory to patch (default: <repo>/sw_projects/P2_app)
USAGE
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

[[ -d "${APP_DIR}" ]] || { echo "ERROR: APP_DIR not found: ${APP_DIR}" >&2; exit 1; }
[[ -f "${APP_DIR}/Makefile" ]] || { echo "ERROR: Makefile not found in: ${APP_DIR}" >&2; exit 1; }

command -v "${PKGCFG}" >/dev/null 2>&1 || { echo "ERROR: pkg-config not found." >&2; exit 1; }

GPIOD_VER="$("${PKGCFG}" --modversion libgpiod 2>/dev/null || echo "0.0.0")"
GPIOD_MAJ="${GPIOD_VER%%.*}"

echo "Detected libgpiod version: ${GPIOD_VER}"

if [[ "${GPIOD_MAJ}" -lt 2 ]]; then
  echo "libgpiod is v1 (or unknown). No v2 patch required."
  exit 0
fi

v2file="${APP_DIR}/g2panel_v2.c"

# Rewrite if missing OR wrong signature OR missing stdbool OR missing i2c_fd
need_write_v2=0
if [[ ! -f "$v2file" ]]; then
  need_write_v2=1
else
  grep -qE '^[[:space:]]*bool[[:space:]]+CheckG2PanelPresent[[:space:]]*\([[:space:]]*void[[:space:]]*\)' "$v2file" || need_write_v2=1
  grep -qE '#include[[:space:]]+<stdbool\.h>' "$v2file" || need_write_v2=1
  grep -qE '^[[:space:]]*int[[:space:]]+i2c_fd[[:space:]]*=' "$v2file" || need_write_v2=1
fi

if [[ "$need_write_v2" -eq 1 ]]; then
  cat > "$v2file" <<'G2PANEL_V2_EOF'
//
// g2panel_v2.c
// -------------
// Minimal libgpiod v2-compatible G2 front panel stubs.
// Safe on headless radios: panel-present returns false.
//

#include <stdbool.h>

#include <errno.h>
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <unistd.h>

#include <gpiod.h>

#include "g2panel.h"

/*
 * i2cdriver.c references a global i2c_fd symbol in this codebase.
 * Ensure it exists here so the link succeeds on Trixie builds.
 */
int i2c_fd = -1;

static struct gpiod_chip *chip = NULL;

static int open_i2c(void)
{
  if (i2c_fd >= 0) return 0;

  i2c_fd = open("/dev/i2c-1", O_RDWR);
  if (i2c_fd < 0) return -errno;

  return 0;
}

static void close_i2c(void)
{
  if (i2c_fd >= 0) {
    close(i2c_fd);
    i2c_fd = -1;
  }
}

bool CheckG2PanelPresent(void)
{
  // Safe default: not present. (Harmless probe open/close.)
  if (open_i2c() == 0) close_i2c();
  return false;
}

void InitialiseG2PanelHandler(void)
{
  // Non-fatal no-op on headless radios.
  if (!chip) chip = gpiod_chip_open("/dev/gpiochip0");
}

void ShutdownG2PanelHandler(void)
{
  if (chip) { gpiod_chip_close(chip); chip = NULL; }
  close_i2c();
}
G2PANEL_V2_EOF
  echo "Wrote v2-compatible implementation: $v2file"
else
  echo "g2panel_v2.c already present and matches expected signatures; leaving as-is."
fi

# Preserve original for v1 builds
if [[ ! -f "${APP_DIR}/g2panel_v1.c" ]]; then
  if [[ -f "${APP_DIR}/g2panel.c" ]]; then
    cp -a "${APP_DIR}/g2panel.c" "${APP_DIR}/g2panel_v1.c"
    echo "Created g2panel_v1.c from g2panel.c"
  fi
fi

makefile="${APP_DIR}/Makefile"
bak="${makefile}.bak.gpiodv2.$(date +%Y%m%d-%H%M%S)"
cp -a "$makefile" "$bak"
echo "Backup: $bak"

# Ensure the link step includes $(LDLIBS)
python3 - <<'PY' "$makefile"
import sys
from pathlib import Path
p = Path(sys.argv[1])
lines = p.read_text().splitlines(True)
out = []
patched = False
for line in lines:
    if '$(LD) -o $(TARGET)' in line and '$(LDLIBS)' not in line:
        line = line.rstrip('\n') + ' $(LDLIBS)\n'
        patched = True
    out.append(line)
if patched:
    p.write_text(''.join(out))
PY

# Remove any hard-coded -lgpiod from LIBS to prevent duplicates
perl -i -pe 'if (/^LIBS\s*=\s*/) { s/\s+-lgpiod(\s|$)/$1/g; }' "$makefile"

marker="BEGIN GPIOD AUTO-DETECT (added by patch-trixie-gpiod.sh)"
if grep -q "$marker" "$makefile"; then
  echo "Makefile: gpiod auto-detect block already present."
else
  cat >> "$makefile" <<'MAKE_EOF'

# =============================================================================
# BEGIN GPIOD AUTO-DETECT (added by patch-trixie-gpiod.sh)
# Detect libgpiod major version and select appropriate source for g2panel.o
# =============================================================================
PKGCFG ?= pkg-config
GPIOD_VER := $(shell $(PKGCFG) --modversion libgpiod 2>/dev/null || echo 0.0.0)
GPIOD_MAJ := $(firstword $(subst ., ,$(GPIOD_VER)))
$(info libgpiod detected: $(GPIOD_VER))

CFLAGS  += $(shell $(PKGCFG) --cflags libgpiod)
LDLIBS  += $(shell $(PKGCFG) --libs   libgpiod)

ifeq ($(GPIOD_MAJ),2)
  G2PANEL_SRC := g2panel_v2.c
else
  G2PANEL_SRC := g2panel_v1.c
endif
$(info building with $(G2PANEL_SRC))

g2panel.o: $(G2PANEL_SRC) g2panel.h
	$(CC) $(CFLAGS) -c $< -o $@

# =============================================================================
# END GPIOD AUTO-DETECT (added by patch-trixie-gpiod.sh)
# =============================================================================
MAKE_EOF
  echo "Makefile: added gpiod auto-detect block."
fi

# Fix TABs (spaces in recipes cause "missing separator")
python3 - <<'PY' "$makefile"
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
s2 = re.sub(r'^( {8})(?=\S)', '\t', s, flags=re.M)
if s2 != s:
    p.write_text(s2)
PY

echo "Makefile patch complete."
echo "All set. Build with: make -C \"${APP_DIR}\" clean && make"
