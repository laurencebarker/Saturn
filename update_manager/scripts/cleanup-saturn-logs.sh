#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
DELETE_ALL=false
OLDER_7=false
VERBOSE=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --all) DELETE_ALL=true ;;
    --older-7) OLDER_7=true ;;
    --verbose) VERBOSE=true ;;
    *)
      echo "Unknown flag: $arg"
      exit 1
      ;;
  esac
done

LOG_DIR="${SATURN_LOG_DIR:-$HOME/saturn-logs}"
if [[ ! -d "$LOG_DIR" ]]; then
  echo "No Saturn log directory found at: $LOG_DIR"
  exit 0
fi

DAYS=30
if $OLDER_7; then
  DAYS=7
fi

if $DELETE_ALL; then
  mapfile -t files < <(find "$LOG_DIR" -type f -name "*.log" | sort)
else
  mapfile -t files < <(find "$LOG_DIR" -type f -name "*.log" -mtime +"$DAYS" | sort)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  if $DELETE_ALL; then
    echo "No log files found to delete in $LOG_DIR."
  else
    echo "No log files older than $DAYS days found in $LOG_DIR."
  fi
  exit 0
fi

echo "Matched ${#files[@]} log file(s) in $LOG_DIR."
for file in "${files[@]}"; do
  if $DRY_RUN; then
    echo "[dry-run] would delete: $file"
  else
    rm -f -- "$file"
    echo "deleted: $file"
  fi
done

if $VERBOSE; then
  du -sh "$LOG_DIR" 2>/dev/null || true
fi

echo "Done."
