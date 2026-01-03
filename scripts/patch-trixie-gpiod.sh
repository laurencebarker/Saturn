#!/usr/bin/env bash
#
# patch-trixie-gpiod.sh
# ---------------------
# Fix Saturn P2_app build issues on Debian/RPi OS "Trixie" (libgpiod v2+).
#
# What it does:
#   1) Detect libgpiod version (via pkg-config).
#   2) Ensure a v2-compatible g2panel implementation exists (g2panel_v2.c).
#   3) Patch the P2_app Makefile to:
#        - add pkg-config based gpiod cflags/libs (LDLIBS)
#        - auto-select g2panel_v1.c vs g2panel_v2.c based on libgpiod major version
#        - ensure the link step includes $(LDLIBS)
#        - fix Makefile recipe indentation (TAB vs spaces) to avoid "missing separator"
#
# You can point it at a different P2_app dir by setting APP_DIR:
#   APP_DIR=/path/to/P2_app ./scripts/patch-trixie-gpiod.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

APP_DIR="${APP_DIR:-${REPO_ROOT}/sw_projects/P2_app}"

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

PKGCFG="${PKGCFG:-pkg-config}"

if ! command -v "${PKGCFG}" >/dev/null 2>&1; then
  echo "ERROR: pkg-config not found; cannot detect libgpiod version." >&2
  exit 1
fi

GPIOD_VER="$("${PKGCFG}" --modversion libgpiod 2>/dev/null || echo "0.0.0")"
GPIOD_MAJ="${GPIOD_VER%%.*}"

echo "Detected libgpiod version: ${GPIOD_VER}"

if [[ "${GPIOD_MAJ}" -lt 2 ]]; then
  echo "libgpiod is v1 (or unknown). No v2 patch required."
  exit 0
fi

need_write_v2=0
v2file="${APP_DIR}/g2panel_v2.c"

if [[ ! -f "$v2file" ]]; then
  need_write_v2=1
else
  grep -q "CheckG2PanelPresent" "$v2file" || need_write_v2=1
  grep -q "int[[:space:]]\+i2c_fd" "$v2file" || need_write_v2=1
fi

if [[ "$need_write_v2" -eq 1 ]]; then
  cat > "$v2file" <<'G2PANEL_V2_EOF'
//
// g2panel_v2.c
// -------------
// libgpiod v2 compatible G2 front panel support.
// Safe on radios with no front panel: the "panel present" check will fail cleanly.
//

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <gpiod.h>

#include "g2panel.h"

int i2c_fd = -1;

static struct gpiod_chip *chip = NULL;
static struct gpiod_line_request *req_outputs = NULL;
static struct gpiod_line_request *req_inputs  = NULL;

static int gpio_ok = 0;

static int open_i2c(void)
{
  if (i2c_fd >= 0) return 0;

  const char *dev = "/dev/i2c-1";
  i2c_fd = open(dev, O_RDWR);
  if (i2c_fd < 0) {
    return -errno;
  }
  return 0;
}

static void close_i2c(void)
{
  if (i2c_fd >= 0) {
    close(i2c_fd);
    i2c_fd = -1;
  }
}

static int gpio_init(void)
{
  if (gpio_ok) return 0;

  chip = gpiod_chip_open("/dev/gpiochip0");
  if (!chip) return -errno;

  // NOTE: This code intentionally keeps the request minimal.
  // If your build uses additional panel GPIOs, add them here.

  gpio_ok = 1;
  return 0;
}

static void gpio_shutdown(void)
{
  if (req_outputs) { gpiod_line_request_release(req_outputs); req_outputs = NULL; }
  if (req_inputs)  { gpiod_line_request_release(req_inputs);  req_inputs  = NULL; }
  if (chip)        { gpiod_chip_close(chip); chip = NULL; }
  gpio_ok = 0;
}

int CheckG2PanelPresent(void)
{
  // Radios without a front panel should return "not present" (0) cleanly.
  // A real implementation could probe an I2C address or known GPIO state.
  // We do a lightweight I2C open attempt and immediately close.
  if (open_i2c() == 0) {
    close_i2c();
  }
  return 0;
}

void InitialiseG2PanelHandler(void)
{
  // Non-fatal on headless radios
  gpio_init();
}

void ShutdownG2PanelHandler(void)
{
  gpio_shutdown();
  close_i2c();
}
G2PANEL_V2_EOF
  echo "Wrote v2-compatible implementation: $v2file"
else
  echo "g2panel_v2.c already present and looks sane; leaving as-is."
fi

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
if grep -qE '^\s*\$\(LD\)\s+-o\s+\$\(TARGET\).*\$\(LDLIBS\)' "$makefile"; then
  echo "Makefile: link rule already references \$(LDLIBS)"
else
  perl -0777 -i -pe 's/(^\s*\$\(LD\)\s+-o\s+\$\(TARGET\)\s+\$\(OBJS\)\s+\$\(LDFLAGS\)\s+\$\(LIBS\)\s*)$/\1\$\(\LDLIBS\)\n/m' "$makefile"
  echo "Makefile: attempted to append \$(LDLIBS) to link rule"
fi

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
