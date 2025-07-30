#!/bin/bash
# log_cleaner.sh - Script to find *.log files in home directory, report total space used, and optionally delete them
# Version: 3.00
# Written by: Jerry DeLong KD4YAL
# Date: July 26, 2025
# Usage: ./log_cleaner.sh [--delete-all] [--recursive] [--dry-run]

# Flags
DELETE_ALL=false
RECURSIVE=true  # Default to recursive search
DRY_RUN=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --delete-all) DELETE_ALL=true ;;
        --no-recursive) RECURSIVE=false ;;
        --dry-run) DRY_RUN=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

HOME_DIR="$HOME"

# Build find command
FIND_CMD="find $HOME_DIR -maxdepth 1 -type f -name '*.log'"  # Non-recursive by default
if $RECURSIVE; then
    FIND_CMD="find $HOME_DIR -type f -name '*.log'"
fi

# Find all *.log files
LOG_FILES=$($FIND_CMD)

if [ -z "$LOG_FILES" ]; then
    echo "No *.log files found in $HOME_DIR."
    exit 0
fi

# Calculate total size
TOTAL_SIZE=$($FIND_CMD -exec du -b {} + | awk '{total += $1} END {print total}')

# Human-readable size
if command -v numfmt &> /dev/null; then
    HUMAN_SIZE=$(numfmt --to=iec-i --suffix=B --padding=7 $TOTAL_SIZE)
else
    HUMAN_SIZE="$TOTAL_SIZE bytes"
fi

echo "Total space used by *.log files: $HUMAN_SIZE"

# List files with sizes
echo "Log files found:"
while IFS= read -r file; do
    SIZE=$(du -h "$file" | cut -f1)
    echo "- $file ($SIZE)"
done <<< "$LOG_FILES"

# Deletion logic
if $DELETE_ALL; then
    if $DRY_RUN; then
        echo "[Dry run] Would delete all found *.log files."
    else
        while IFS= read -r file; do
            rm -f "$file"
            echo "Deleted: $file"
        done <<< "$LOG_FILES"
        echo "All *.log files deleted."
    fi
else
    read -p "Delete all these files? (y/n): " confirm
    if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
        if $DRY_RUN; then
            echo "[Dry run] Would delete all found *.log files."
        else
            while IFS= read -r file; do
                rm -f "$file"
                echo "Deleted: $file"
            done <<< "$LOG_FILES"
            echo "All *.log files deleted."
        fi
    else
        echo "Deletion cancelled."
    fi
fi
