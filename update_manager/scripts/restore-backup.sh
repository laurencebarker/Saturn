#!/usr/bin/env bash
# restore-backup.sh - Restore from Saturn and/or piHPSDR backup directories
# Version: 3.10
# Author: Jerry DeLong KD4YAL
# Date: 2025-07-26
#
# Usage:
#   ./restore-backup.sh [--pihpsdr] [--saturn]
#                       [--latest | --list | --backup-dir <dir>]
#                       [--dry-run] [--verbose] [--json]
#
# Notes:
# - Backups are dirs in $HOME named:
#     saturn-backup-YYYYMMDD-HHMMSS
#     pihpsdr-backup-YYYYMMDD-HHMMSS
# - If both --saturn and --pihpsdr are passed:
#     * --list shows both sets
#     * --latest restores each latest to its own target
# - --backup-dir <dir> may be absolute or relative to $HOME; its type is
#   inferred from the directory name prefix (saturn-backup- | pihpsdr-backup-).

set -Eeuo pipefail

HOME_DIR="${HOME}"
SATURN_DIR="$HOME/github/Saturn"
PIHPSDR_DIR="$HOME/github/pihpsdr"

declare -a TYPES=()
LATEST=false
LIST=false
BACKUP_DIR_ARG=""
DRY_RUN=false
VERBOSE=false
JSON=false

log() { echo "$@"; }
err() { echo "Error: $*" >&2; exit 1; }

# Safer globs: empty set yields empty list, not the literal pattern
shopt -s nullglob

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pihpsdr) TYPES+=("pihpsdr") ;;
    --saturn)  TYPES+=("saturn")  ;;
    --latest)  LATEST=true ;;
    --list)    LIST=true ;;
    --backup-dir)
      shift || err "--backup-dir requires a directory argument"
      BACKUP_DIR_ARG="${1:-}";;
    --dry-run) DRY_RUN=true ;;
    --verbose) VERBOSE=true ;;
    --json)    JSON=true ;;
    -*|--*)    err "Unknown parameter: $1" ;;
    *)         err "Unexpected argument: $1" ;;
  esac
  shift
done

# Default behavior: if neither type specified, treat as both (useful for UI lists)
if [[ ${#TYPES[@]} -eq 0 ]]; then
  TYPES=(saturn pihpsdr)
fi

# De-dupe TYPES while preserving order
declare -A seen
declare -a uniq
for t in "${TYPES[@]}"; do
  [[ -n "${seen[$t]:-}" ]] || { uniq+=("$t"); seen[$t]=1; }
done
TYPES=("${uniq[@]}")

# Helpers
target_dir_for_type() {
  local t="$1"
  case "$t" in
    saturn)  echo "$SATURN_DIR" ;;
    pihpsdr) echo "$PIHPSDR_DIR" ;;
    *) err "Unknown type: $t" ;;
  esac
}

find_backups_for_type() {
  local t="$1"
  local pattern="$HOME_DIR/${t}-backup-"*
  # nullglob ensures non-matches yield empty array
  local matches=($pattern)
  # Sort by mtime desc
  if [[ ${#matches[@]} -gt 0 ]]; then
    printf '%s\0' "${matches[@]}" \
      | xargs -0 stat --printf '%Y\t%n\0' \
      | sort -zrn \
      | cut -z -f2-
  fi
}

latest_backup_for_type() {
  local t="$1"
  local latest
  latest="$(find_backups_for_type "$t" | tr -d '\0' | head -n1 || true)"
  echo "$latest"
}

infer_type_from_dirname() {
  local dname="$1"
  local base
  base="$(basename "$dname")"
  case "$base" in
    saturn-backup-*)  echo "saturn" ;;
    pihpsdr-backup-*) echo "pihpsdr" ;;
    *) echo "" ;;
  esac
}

# rsync options
RSYNC_OPTS=(-a)
$VERBOSE && RSYNC_OPTS=(-av)
$DRY_RUN && RSYNC_OPTS+=("--dry-run")

# ---------- LIST MODE ----------
if $LIST; then
  if $JSON; then
    # JSON object keyed by type with array of basenames
    printf '{'
    local firstType=1
    for t in "${TYPES[@]}"; do
      $firstType || printf ','
      firstType=0
      printf '"%s":[' "$t"
      local first=1
      while IFS= read -r -d '' path; do
        $first || printf ','
        first=0
        printf '"%s"' "$(basename "$path")"
      done < <(find_backups_for_type "$t")
      printf ']'
    done
    printf '}\n'
  else
    for t in "${TYPES[@]}"; do
      log "Available $t backups:"
      has_any=false
      while IFS= read -r -d '' path; do
        has_any=true
        echo "  $(basename "$path")"
      done < <(find_backups_for_type "$t")
      $has_any || log "  (none found)"
      echo
    done
  fi
  exit 0
fi

# ---------- RESTORE MODE ----------
declare -a to_restore_types=()
declare -a to_restore_sources=()
declare -a to_restore_targets=()

if [[ -n "$BACKUP_DIR_ARG" ]]; then
  # Normalize path
  if [[ -d "$BACKUP_DIR_ARG" ]]; then
    sel="$BACKUP_DIR_ARG"
  elif [[ -d "$HOME_DIR/$BACKUP_DIR_ARG" ]]; then
    sel="$HOME_DIR/$BACKUP_DIR_ARG"
  else
    err "Invalid backup directory: $BACKUP_DIR_ARG"
  fi
  # Infer type from directory name prefix
  inferred="$(infer_type_from_dirname "$sel")"
  [[ -n "$inferred" ]] || err "Cannot infer backup type from: $(basename "$sel")"
  # If the user passed specific TYPES and this one isn't included, warn out
  in_requested=false
  for t in "${TYPES[@]}"; do [[ "$t" == "$inferred" ]] && in_requested=true; done
  $in_requested || err "Backup dir is '$inferred' but requested types were: ${TYPES[*]}"

  to_restore_types+=("$inferred")
  to_restore_sources+=("$sel")
  to_restore_targets+=("$(target_dir_for_type "$inferred")")

elif $LATEST; then
  for t in "${TYPES[@]}"; do
    latest="$(latest_backup_for_type "$t")"
    if [[ -z "$latest" ]]; then
      log "No $t backups found in $HOME_DIR; skipping $t."
      continue
    fi
    to_restore_types+=("$t")
    to_restore_sources+=("$latest")
    to_restore_targets+=("$(target_dir_for_type "$t")")
  done
  [[ ${#to_restore_sources[@]} -gt 0 ]] || err "No backups found for requested type(s)."

else
  err "Specify --latest or --backup-dir <dir> to restore, or use --list to list backups."
fi

# Perform the restores (one per type)
for i in "${!to_restore_sources[@]}"; do
  src="${to_restore_sources[$i]}"
  tgt="${to_restore_targets[$i]}"
  t="${to_restore_types[$i]}"

  [[ -d "$src" ]] || err "Selected $t backup not a directory: $src"
  [[ -d "$tgt" ]] || err "Target directory for $t not found: $tgt"

  $VERBOSE && log "Restoring $t from: $src -> $tgt"
  rsync "${RSYNC_OPTS[@]}" --delete "$src/" "$tgt/"
done

$DRY_RUN || log "Restore completed. Reboot recommended."
