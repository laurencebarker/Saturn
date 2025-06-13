#!/bin/bash
# update-G2.sh - Enhanced Version
# Pull repository and build p2app with comprehensive error handling and safety features
# Original script: Laurence Barker G8NJJ
# Substantially rewritten by: KD4YAL
# Enhanced version with logging, backup, and rollback capabilities

# Exit on any error and handle undefined variables
set -euo pipefail

#############################################################################
# CONFIGURATION AND SETUP
#############################################################################

# Version
SCRIPT_VERSION="2.0"

# Load configuration if exists
CONFIG_FILE="$HOME/.saturn-update.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Default configuration (can be overridden by config file)
SATURN_DIR="${SATURN_DIR:-$HOME/github/Saturn}"
SATURN_REPO_URL="${SATURN_REPO_URL:-https://github.com/laurencebarker/Saturn.git}"
SATURN_BRANCH="${SATURN_BRANCH:-main}"
CREATE_BACKUP="${CREATE_BACKUP:-true}"
SKIP_CONNECTIVITY_CHECK="${SKIP_CONNECTIVITY_CHECK:-false}"
VERBOSE="${VERBOSE:-false}"

# Setup logging
LOG_DIR="$HOME/saturn-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/saturn-update-$(date +%Y%m%d-%H%M%S).log"
BACKUP_INFO_FILE="$HOME/.saturn-last-backup"

# Redirect output to both console and log file
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Command line options
SKIP_UPDATE=false
FORCE_UPDATE=false
SKIP_BACKUP=false

#############################################################################
# UTILITY FUNCTIONS
#############################################################################

# Function to print section headers
print_header() {
    echo ""
    echo "##############################################################"
    echo ""
    echo "$1"
    echo ""
    echo "##############################################################"
}

# Enhanced status checking with detailed error reporting
check_status() {
    local exit_code=$?
    local operation="$1"

    if [ $exit_code -eq 0 ]; then
        echo "✓ $operation completed successfully"
        return 0
    else
        echo "✗ Error: $operation failed (exit code: $exit_code)"
        echo "Check log file: $LOG_FILE"

        # Offer rollback if backup exists
        if [ -f "$BACKUP_INFO_FILE" ] && [ "$CREATE_BACKUP" = "true" ]; then
            echo ""
            read -p "Would you like to rollback to the previous version? (y/N): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rollback_changes
                exit 0
            fi
        fi
        exit $exit_code
    fi
}

# Show progress indicator
show_progress() {
    local current=$1
    local total=$2
    local desc=$3
    local percent=$((current * 100 / total))
    printf "\r[%d/%d] %s... %d%%" "$current" "$total" "$desc" "$percent"
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# Check system requirements
check_system_requirements() {
    print_header "Checking System Requirements"

    # Check disk space (need at least 1GB free)
    local free_space=$(df "$HOME" | awk 'NR==2 {print $4}')
    if [ "$free_space" -lt 1048576 ]; then
        echo "⚠ Warning: Low disk space (less than 1GB free)"
        echo "Available: $((free_space / 1024))MB"
    else
        echo "✓ Sufficient disk space available"
    fi

    # Check required commands
    local required_commands=("git" "make" "gcc" "sudo")
    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -gt 0 ]; then
        echo "✗ Error: Missing required commands: ${missing_commands[*]}"
        echo "Please install missing packages and try again"
        exit 1
    else
        echo "✓ All required commands available"
    fi
}

# Check internet connectivity
check_connectivity() {
    if [ "$SKIP_CONNECTIVITY_CHECK" = "true" ]; then
        return 0
    fi

    echo "Checking internet connectivity..."
    if timeout 10 ping -c 1 github.com &> /dev/null; then
        echo "✓ Internet connectivity confirmed"
        return 0
    else
        echo "⚠ Warning: Cannot reach GitHub"
        return 1
    fi
}

# Git safety checks and repository validation
check_git_status() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "✗ Error: $SATURN_DIR is not a git repository"
        exit 1
    fi

    # Validate remote repository
    local current_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -z "$current_url" ]; then
        echo "⚠ Warning: No 'origin' remote found"
        echo "Setting up origin remote: $SATURN_REPO_URL"
        git remote add origin "$SATURN_REPO_URL"
    else
        echo "✓ Current repository: $current_url"
        # Optionally validate if it's the expected repository
        if [[ "$current_url" != *"Saturn"* ]] && [[ "$current_url" != "$SATURN_REPO_URL" ]]; then
            echo "⚠ Warning: Repository URL doesn't appear to be the Saturn project"
            echo "Expected: $SATURN_REPO_URL"
            echo "Current: $current_url"

            if [ "$FORCE_UPDATE" = "false" ]; then
                read -p "Continue with current repository? (y/N): " -n 1 -r
                echo ""
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "Update cancelled by user"
                    exit 0
                fi
            fi
        fi
    fi

    # Check current branch
    local current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    echo "✓ Current branch: $current_branch"

    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        echo "⚠ Warning: Uncommitted changes detected"
        if [ "$FORCE_UPDATE" = "false" ]; then
            read -p "Stash changes and continue? (y/N): " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Update cancelled by user"
                exit 0
            fi
        fi
        echo "Stashing changes..."
        git stash push -m "Auto-stash before update $(date)"
        echo "✓ Changes stashed"
    fi

    # Check if we're on the expected branch
    if [ "$current_branch" != "$SATURN_BRANCH" ] && [ "$SATURN_BRANCH" != "current" ]; then
        echo "⚠ Warning: Currently on branch '$current_branch', expected '$SATURN_BRANCH'"
        if [ "$FORCE_UPDATE" = "false" ]; then
            read -p "Switch to branch '$SATURN_BRANCH'? (y/N): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                git checkout "$SATURN_BRANCH" || git checkout -b "$SATURN_BRANCH" "origin/$SATURN_BRANCH"
            fi
        fi
    fi
}

# Prompt user for backup preference
prompt_for_backup() {
    if [ "$SKIP_BACKUP" = "true" ] || [ "$FORCE_UPDATE" = "true" ]; then
        return 0
    fi

    echo ""
    echo "🔄 Saturn Update Process Starting"
    echo ""
    echo "It's recommended to create a backup before updating in case you need to rollback."
    echo "This will copy your current Saturn directory to a timestamped backup folder."
    echo ""

    # Check if previous backups exist
    local backup_pattern="$HOME/saturn-backup-*"
    local backup_count=$(ls -1d $backup_pattern 2>/dev/null | wc -l || echo "0")

    if [ "$backup_count" -gt 0 ]; then
        echo "📁 Found $backup_count existing backup(s)"
        echo "💾 Latest backup: $(ls -1dt $backup_pattern 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo "None")"
        echo ""
    fi

    # Estimate backup size
    local saturn_size=$(du -sh "$SATURN_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    echo "📊 Current Saturn directory size: $saturn_size"

    echo ""
    read -p "Would you like to create a backup before updating? (Y/n): " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "⚠ Proceeding without backup"
        SKIP_BACKUP=true
        return 0
    else
        echo "✓ Backup will be created"
        return 0
    fi
}

# Create backup
create_backup() {
    if [ "$SKIP_BACKUP" = "true" ]; then
        echo "Skipping backup creation (user choice or --skip-backup flag)"
        return 0
    fi

    print_header "Creating Backup"
    local backup_dir="$HOME/saturn-backup-$(date +%Y%m%d-%H%M%S)"

    echo "Creating backup at: $backup_dir"
    echo "This may take a few moments depending on the size of your Saturn directory..."

    # Show progress for large directories
    if command -v rsync &> /dev/null; then
        rsync -av --progress "$SATURN_DIR/" "$backup_dir/" 2>/dev/null || cp -r "$SATURN_DIR" "$backup_dir"
    else
        cp -r "$SATURN_DIR" "$backup_dir"
    fi

    # Save backup info for potential rollback
    echo "BACKUP_DIR=$backup_dir" > "$BACKUP_INFO_FILE"
    echo "BACKUP_DATE=$(date)" >> "$BACKUP_INFO_FILE"
    echo "BACKUP_SIZE=$(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "Unknown")" >> "$BACKUP_INFO_FILE"

    echo "✓ Backup created successfully"
    echo "📁 Location: $backup_dir"
    echo "📊 Size: $(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "Unknown")"
}

# Rollback to previous backup
rollback_changes() {
    if [ ! -f "$BACKUP_INFO_FILE" ]; then
        echo "✗ No backup information found"
        return 1
    fi

    source "$BACKUP_INFO_FILE"

    if [ ! -d "$BACKUP_DIR" ]; then
        echo "✗ Backup directory not found: $BACKUP_DIR"
        return 1
    fi

    print_header "Rolling Back Changes"
    echo "Restoring from backup: $BACKUP_DIR"
    echo "Backup date: $BACKUP_DATE"

    rm -rf "$SATURN_DIR"
    cp -r "$BACKUP_DIR" "$SATURN_DIR"

    echo "✓ Rollback completed successfully"
}

# Cleanup old backups (keep last 5)
cleanup_old_backups() {
    local backup_pattern="$HOME/saturn-backup-*"
    local backup_count=$(ls -1d $backup_pattern 2>/dev/null | wc -l)

    if [ "$backup_count" -gt 5 ]; then
        echo "Cleaning up old backups (keeping last 5)..."
        ls -1dt $backup_pattern | tail -n +6 | xargs rm -rf
        echo "✓ Old backups cleaned up"
    fi
}

# Show usage information
show_usage() {
    echo "Saturn Update Script v$SCRIPT_VERSION"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-git          Skip git pull operation"
    echo "  --skip-backup       Skip backup creation (not recommended)"
    echo "  --force            Force update without prompts (includes backup skip)"
    echo "  --verbose          Enable verbose output"
    echo "  --rollback         Rollback to previous backup"
    echo "  --repo-url URL     Override repository URL"
    echo "  --branch BRANCH    Override target branch (default: main)"
    echo "  --help             Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  SATURN_REPO_URL    Repository URL (default: https://github.com/laurencebarker/Saturn.git)"
    echo "  SATURN_BRANCH      Target branch (default: main)"
    echo ""
    echo "Configuration file: $CONFIG_FILE"
    echo "Log file: $LOG_FILE"
}

#############################################################################
# COMMAND LINE PARSING
#############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-git)
            SKIP_UPDATE=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --force)
            FORCE_UPDATE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --repo-url)
            SATURN_REPO_URL="$2"
            shift 2
            ;;
        --branch)
            SATURN_BRANCH="$2"
            shift 2
            ;;
        --rollback)
            rollback_changes
            exit $?
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

#############################################################################
# ERROR HANDLING SETUP
#############################################################################

# Trap for cleanup on script exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "Script failed with exit code: $exit_code"
        echo "Log file available at: $LOG_FILE"
    fi
}

trap cleanup EXIT

#############################################################################
# MAIN SCRIPT EXECUTION
#############################################################################

echo "Starting Saturn Update Script v$SCRIPT_VERSION"
echo "Log file: $LOG_FILE"
echo "$(date): Update started"

# Check system requirements
check_system_requirements

# Check if Saturn directory exists
if [ ! -d "$SATURN_DIR" ]; then
    echo "✗ Error: Saturn directory not found at $SATURN_DIR"
    echo "Please ensure the Saturn repository is cloned at the expected location"
    exit 1
fi

# Navigate to Saturn directory
cd "$SATURN_DIR" || exit 1
echo "✓ Working directory: $(pwd)"

# Prompt user about backup preference
prompt_for_backup

# Create backup before making changes
create_backup

# Step 1: Install libraries
show_progress 1 7 "Installing libraries"
print_header "Installing Libraries if Required"

if [ -f "./scripts/install-libraries.sh" ]; then
    ./scripts/install-libraries.sh
    check_status "Library installation"
else
    echo "✗ Error: install-libraries.sh script not found"
    exit 1
fi

# Step 2: Update repository
show_progress 2 7 "Updating repository"
print_header "Updating Repository"

cd "$SATURN_DIR" || exit 1

if [ "$SKIP_UPDATE" = "false" ]; then
    if check_connectivity; then
        # Store current version for comparison
        CURRENT_VERSION=$(git rev-parse HEAD)

        # Check git status and handle uncommitted changes
        check_git_status

        # Configure and pull updates
        git config pull.rebase false
        echo "Pulling latest changes from: $(git remote get-url origin)"
        echo "Target branch: $SATURN_BRANCH"

        # Pull from specific branch if specified
        if [ "$SATURN_BRANCH" = "current" ]; then
            git pull
        else
            git pull origin "$SATURN_BRANCH"
        fi
        check_status "Repository update"

        # Check if update actually occurred
        NEW_VERSION=$(git rev-parse HEAD)
        if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
            echo "✓ Repository already up to date"
        else
            echo "✓ Repository updated to: $(git rev-parse --short HEAD)"
        fi
    else
        echo "⚠ Skipping repository update due to connectivity issues"
    fi
else
    echo "⚠ Skipping repository update (--skip-git specified)"
fi

# Step 3: Build p2app
show_progress 3 7 "Building p2app"
print_header "Building p2app"

if [ -f "./scripts/update-p2app.sh" ]; then
    ./scripts/update-p2app.sh
    check_status "p2app build"
else
    echo "✗ Error: update-p2app.sh script not found"
    exit 1
fi

# Step 4: Build desktop apps
show_progress 4 7 "Building desktop apps"
print_header "Building Desktop Applications"

if [ -f "./scripts/update-desktop-apps.sh" ]; then
    ./scripts/update-desktop-apps.sh
    check_status "Desktop apps build"
else
    echo "✗ Error: update-desktop-apps.sh script not found"
    exit 1
fi

# Step 5: Install udev rules
show_progress 5 7 "Installing udev rules"
print_header "Installing udev Rules"

cd "$SATURN_DIR/rules" || exit 1
if [ -f "./install-rules.sh" ]; then
    sudo ./install-rules.sh
    check_status "udev rules installation"
else
    echo "✗ Error: install-rules.sh script not found"
    exit 1
fi

# Step 6: Copy desktop icons
show_progress 6 7 "Copying desktop icons"
print_header "Installing Desktop Icons"

cd "$SATURN_DIR" || exit 1
if [ -d "desktop" ] && [ -d "$HOME/Desktop" ]; then
    cp desktop/* "$HOME/Desktop/"
    chmod +x "$HOME/Desktop"/*.desktop 2>/dev/null || true
    check_status "Desktop icons installation"
else
    echo "⚠ Warning: desktop directory or Desktop folder not found"
    echo "Desktop icons may not be available"
fi

# Step 7: Check FPGA binary
show_progress 7 7 "Checking FPGA binary"
print_header "Checking Latest FPGA Binary File"

if [ -f "./scripts/find-bin.sh" ]; then
    ./scripts/find-bin.sh
    check_status "FPGA binary check"
else
    echo "✗ Error: find-bin.sh script not found"
    exit 1
fi

# Cleanup old backups
cleanup_old_backups

# Final success message
print_header "Update Completed Successfully"

echo "✓ Saturn update completed at $(date)"
echo ""
echo "Summary:"
echo "- Libraries: Updated"
echo "- Repository: $([ "$SKIP_UPDATE" = "true" ] && echo "Skipped" || echo "Updated")"
echo "- Applications: Built and installed"
echo "- Desktop icons: Installed"
echo "- udev rules: Updated"
echo ""
echo "📁 Log file: $LOG_FILE"
if [ "$CREATE_BACKUP" = "true" ] && [ "$SKIP_BACKUP" = "false" ]; then
    echo "💾 Backup available for rollback if needed"
fi
echo ""
echo "🔧 FPGA Update Instructions:"
echo "1. If FPGA needs updating, launch flashwriter desktop app"
echo "2. Navigate: Open file → Home → github → Saturn → FPGA"
echo "3. Select the new .BIT file (eg saturnprimary2024V19.bin)"
echo "4. Ensure 'primary' is selected"
echo "5. Click 'Program'"
echo ""
echo "⚠ Important Notes:"
echo "- FPGA programming takes approximately 3 minutes"
echo "- Power cycle completely after programming"
echo "- Keep this terminal open to view the full log"

# Return to home directory
cd "$HOME"

echo ""
echo "Update script completed successfully!"
