#!/bin/bash
# restore-backup.sh - Restore from Saturn or piHPSDR backup directories
# Version: 3.00
# Written by: Jerry DeLong KD4YAL
# Date: July 26, 2025
# Usage: ./restore-backup.sh [--pihpsdr|--saturn] [--latest|--list|--backup-dir <dir>] [--dry-run] [--verbose]
# Assumes backups are directories in ~/ named saturn-backup-YYYYMMDD-HHMMSS or pihpsdr-backup-YYYYMMDD-HHMMSS.

set -e

HOME_DIR="$HOME"
SATURN_DIR="$HOME/github/Saturn"
PIHPSDR_DIR="$HOME/github/pihpsdr"

TYPE=""
LATEST=false
LIST=false
BACKUP_DIR_ARG=""
DRY_RUN=false
VERBOSE=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --pihpsdr) TYPE="pihpsdr" ;;
        --saturn) TYPE="saturn" ;;
        --latest) LATEST=true ;;
        --list) LIST=true ;;
        --backup-dir) BACKUP_DIR_ARG="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        --verbose) VERBOSE=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$TYPE" ]; then
    echo "Error: Must specify --pihpsdr or --saturn"
    exit 1
fi

BACKUP_PATTERN="$HOME_DIR/${TYPE}-backup-*"
TARGET_DIR=$( [ "$TYPE" = "pihpsdr" ] && echo "$PIHPSDR_DIR" || echo "$SATURN_DIR" )
RSYNC_OPTS="-a"
if $VERBOSE; then RSYNC_OPTS="-av"; fi
if $DRY_RUN; then RSYNC_OPTS="$RSYNC_OPTS --dry-run"; fi

if $LIST; then
    echo "Available $TYPE backups:"
    backups=$(ls -dt $BACKUP_PATTERN 2>/dev/null)
    if [ -z "$backups" ]; then
        echo "No backups found."
    else
        echo "$backups" | xargs -n1 basename
    fi
    exit 0
fi

SELECTED_BACKUP=""
if [ -n "$BACKUP_DIR_ARG" ]; then
    if [ -d "$BACKUP_DIR_ARG" ]; then
        SELECTED_BACKUP="$BACKUP_DIR_ARG"
    else
        SELECTED_BACKUP="$HOME_DIR/$BACKUP_DIR_ARG"
        if ! [ -d "$SELECTED_BACKUP" ]; then
            echo "Invalid backup directory: $BACKUP_DIR_ARG"
            exit 1
        fi
    fi
elif $LATEST; then
    SELECTED_BACKUP=$(ls -dt $BACKUP_PATTERN 2>/dev/null | head -1)
    if [ -z "$SELECTED_BACKUP" ]; then
        echo "No $TYPE backup found in $HOME_DIR."
        exit 1
    fi
else
    echo "Usage: Specify --latest or --backup-dir <dir> to restore, --list to list backups."
    exit 1
fi

if $VERBOSE; then
    echo "Restoring from $SELECTED_BACKUP to $TARGET_DIR"
fi
rsync $RSYNC_OPTS "$SELECTED_BACKUP/" "$TARGET_DIR/"
if ! $DRY_RUN; then
    echo "Restore completed. Reboot recommended."
fi
