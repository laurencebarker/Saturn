#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
DELETE_ALL=false
SATURN_ONLY=false
PIHPSDR_ONLY=false
VERBOSE=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --delete-all) DELETE_ALL=true ;;
    --saturn-only) SATURN_ONLY=true ;;
    --pihpsdr-only) PIHPSDR_ONLY=true ;;
    --verbose) VERBOSE=true ;;
    *)
      echo "Unknown flag: $arg"
      exit 1
      ;;
  esac
done

if $SATURN_ONLY && $PIHPSDR_ONLY; then
  SATURN_ONLY=false
  PIHPSDR_ONLY=false
fi

HOME_DIR="${HOME:-/home/pi}"
KEEP_COUNT=2

cleanup_type() {
  local prefix="$1"
  mapfile -t dirs < <(find "$HOME_DIR" -maxdepth 1 -type d -name "${prefix}-backup-*" | sort -r)

  if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "No ${prefix} backups found."
    return
  fi

  echo "Found ${#dirs[@]} ${prefix} backup(s)."

  local start_index=0
  if ! $DELETE_ALL; then
    start_index=$KEEP_COUNT
  fi

  if (( start_index >= ${#dirs[@]} )); then
    echo "Nothing to remove for ${prefix}."
    return
  fi

  for ((i=start_index; i<${#dirs[@]}; i++)); do
    local dir="${dirs[$i]}"
    if $DRY_RUN; then
      echo "[dry-run] would remove: $dir"
    else
      rm -rf -- "$dir"
      echo "removed: $dir"
    fi
  done
}

if ! $SATURN_ONLY && ! $PIHPSDR_ONLY; then
  cleanup_type "saturn"
  cleanup_type "pihpsdr"
elif $SATURN_ONLY; then
  cleanup_type "saturn"
else
  cleanup_type "pihpsdr"
fi

if $VERBOSE; then
  echo "Remaining backups:"
  find "$HOME_DIR" -maxdepth 1 -type d \( -name "saturn-backup-*" -o -name "pihpsdr-backup-*" \) | sort || true
fi

echo "Done."
