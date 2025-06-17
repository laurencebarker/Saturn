#!/bin/bash
# update-G2.sh - Saturn Update Script
# Original author: Laurence Barker G8NJJ
# Rewritten by: Jerry DeLong KD4YAL
# Simplified update script for Saturn repository on Raspberry Pi
# Version: 2.02 (Colorized)

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Text formatting
BOLD='\033[1m'
RESET='\033[0m'

# Script metadata
SCRIPT_NAME="Saturn Update Manager"
SCRIPT_VERSION="2.1"
SATURN_DIR="$HOME/github/Saturn"
LOG_DIR="$HOME/saturn-logs"
LOG_FILE="$LOG_DIR/saturn-update-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="$HOME/saturn-backup-$(date +%Y%m%d-%H%M%S)"

# Flag for skipping Git update
SKIP_GIT="false"

# Professional status reporting
status_start() {
    echo -e "${BLUE}${BOLD}▶  $1...${NC}${RESET}"
}

status_success() {
    echo -e "${GREEN}✓  SUCCESS: $1${NC}${RESET}"
}

status_warning() {
    echo -e "${YELLOW}⚠  WARNING: $1${NC}${RESET}"
}

status_error() {
    echo -e "${RED}✗  ERROR: $1${NC}${RESET}" >&2
    exit 1
}

# Initialize logging
init_logging() {
    mkdir -p "$LOG_DIR" || {
        echo -e "${RED}✗ ERROR: Failed to create log directory $LOG_DIR${NC}" >&2
        exit 1
    }
    # Redirect stdout and stderr to log file and terminal
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
    
    # Professional header
    echo -e "${BLUE}${BOLD}"
    echo -e "===================================================================="
    echo -e " Saturn Update Manager v$SCRIPT_VERSION"
    echo -e " Started: $(date)"
    echo -e " Log file: $LOG_FILE"
    echo -e "===================================================================="
    echo -e "${NC}${RESET}"
}

# Parse command-line arguments
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --skip-git)
                SKIP_GIT="true"
                status_warning "Skipping Git repository update per user request"
                shift
                ;;
            *)
                status_error "Unknown option: $1\nUsage: $0 [--skip-git]"
                ;;
        esac
    done
}

# Check system requirements
check_requirements() {
    status_start "Verifying system requirements"
    
    # Required commands
    local missing=()
    for cmd in git make gcc sudo rsync; do
        if ! command -v "$cmd" >/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        status_error "Missing required commands: ${missing[*]}"
    fi
    
    # Disk space check
    local free_space
    free_space=$(df --output=avail "$HOME" | tail -1)
    if [ "$free_space" -lt 1048576 ]; then
        status_warning "Low disk space: $((free_space / 1024))MB available (1GB recommended)"
    else
        echo -e "${GREEN}✓  System has sufficient disk space: $((free_space / 1024))MB available${NC}"
    fi
    
    status_success "System meets all requirements"
}

# Check connectivity
check_connectivity() {
    if [ "$SKIP_GIT" = "true" ]; then
        status_warning "Skipping connectivity check (Git update disabled)"
        return 0
    fi
    
    status_start "Checking network connectivity"
    if ping -c 1 -W 2 github.com >/dev/null 2>&1; then
        status_success "Network connection verified"
        return 0
    else
        status_warning "Cannot reach GitHub - network issues may affect update"
        return 1
    fi
}

# Update Git repository
update_git() {
    if [ "$SKIP_GIT" = "true" ]; then
        status_warning "Skipping repository update per configuration"
        return 0
    fi
    
    status_start "Updating Git repository"
    cd "$SATURN_DIR" || {
        status_error "Cannot access Saturn directory: $SATURN_DIR"
    }
    
    # Validate repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        status_error "Directory is not a valid Git repository: $SATURN_DIR"
    fi
    
    # Stash uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        echo -e "${YELLOW}⚠  Preserving uncommitted changes with git stash${NC}"
        git stash push -m "Auto-stash before update $(date)" >/dev/null
    fi
    
    # Get current status (compatible method)
    local current_branch
    # Try modern method first, fallback to compatible method
    if current_branch=$(git branch --show-current 2>/dev/null); then
        echo -e "${BLUE}ℹ  Current branch: $current_branch${NC}"
    else
        # Compatible method for older Git versions
        current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD)
        echo -e "${BLUE}ℹ  Current reference: $current_branch${NC}"
    fi
    
    local current_commit=$(git rev-parse --short HEAD)
    echo -e "${BLUE}ℹ  Current commit: $current_commit${NC}"
    
    # Pull changes
    if git pull origin main; then
        local new_commit=$(git rev-parse --short HEAD)
        if [ "$current_commit" != "$new_commit" ]; then
            echo -e "${BLUE}ℹ  New commit: $new_commit${NC}"
            echo -e "${BLUE}ℹ  Changes: $(git log --oneline "$current_commit..HEAD" 2>/dev/null | wc -l) commits applied${NC}"
        else
            echo -e "${BLUE}ℹ  Repository already at latest version${NC}"
        fi
        status_success "Repository updated successfully"
    else
        status_error "Failed to update repository - check network connection"
    fi
}

# Create backup
create_backup() {
    status_start "Creating system backup"
    echo -e "${BLUE}ℹ  Backup location: $BACKUP_DIR${NC}"
    
    # Create backup directory
    if ! mkdir -p "$BACKUP_DIR"; then
        status_error "Failed to create backup directory"
    fi
    
    # Perform backup
    if rsync -a "$SATURN_DIR/" "$BACKUP_DIR/"; then
        local backup_size=$(du -sh "$BACKUP_DIR" | cut -f1)
        echo -e "${BLUE}ℹ  Backup size: $backup_size${NC}"
        status_success "Backup created successfully"
    else
        status_error "Backup operation failed"
    fi
}

# Install libraries
install_libraries() {
    status_start "Installing required libraries"
    if [ -f "$SATURN_DIR/scripts/install-libraries.sh" ]; then
        if bash "$SATURN_DIR/scripts/install-libraries.sh"; then
            status_success "Library installation completed"
        else
            status_error "Library installation failed"
        fi
    else
        status_warning "Installation script not found - skipping"
    fi
}

# Build p2app
build_p2app() {
    status_start "Building p2app application"
    if [ -f "$SATURN_DIR/scripts/update-p2app.sh" ]; then
        if bash "$SATURN_DIR/scripts/update-p2app.sh"; then
            status_success "p2app built successfully"
        else
            status_error "p2app build failed"
        fi
    else
        status_warning "Build script not found - skipping"
    fi
}

# Build desktop apps
build_desktop_apps() {
    status_start "Building desktop applications"
    if [ -f "$SATURN_DIR/scripts/update-desktop-apps.sh" ]; then
        if bash "$SATURN_DIR/scripts/update-desktop-apps.sh"; then
            status_success "Desktop applications built successfully"
        else
            status_error "Desktop application build failed"
        fi
    else
        status_warning "Build script not found - skipping"
    fi
}

# Install udev rules
install_udev_rules() {
    status_start "Configuring system udev rules"
    local rules_dir="$SATURN_DIR/rules"
    local install_script="$rules_dir/install-rules.sh"
    
    if [ -f "$install_script" ]; then
        # Ensure the script is executable
        if [ ! -x "$install_script" ]; then
            echo -e "${YELLOW}⚠  Setting execute permission: $install_script${NC}"
            chmod +x "$install_script"
        fi
        
        # Execute from the rules directory
        if (cd "$rules_dir" && sudo ./install-rules.sh); then
            status_success "Udev rules installed successfully"
        else
            status_error "Udev rules installation failed"
        fi
    else
        status_warning "Installation script not found - skipping"
    fi
}

# Install desktop icons
install_desktop_icons() {
    status_start "Installing desktop shortcuts"
    if [ -d "$SATURN_DIR/desktop" ] && [ -d "$HOME/Desktop" ]; then
        if cp "$SATURN_DIR/desktop/"* "$HOME/Desktop/" && chmod +x "$HOME/Desktop/"*.desktop; then
            status_success "Desktop shortcuts installed"
        else
            status_error "Failed to install desktop shortcuts"
        fi
    else
        status_warning "Desktop directory not found - skipping"
    fi
}

# Check FPGA binary
check_fpga_binary() {
    status_start "Verifying FPGA binary"
    if [ -f "$SATURN_DIR/scripts/find-bin.sh" ]; then
        if bash "$SATURN_DIR/scripts/find-bin.sh"; then
            status_success "FPGA binary validation complete"
        else
            status_error "FPGA binary verification failed"
        fi
    else
        status_warning "Verification script not found - skipping"
    fi
}

# Print summary report
print_summary_report() {
    local duration=$(( $(date +%s) - start_time ))
    echo -e "\n${BLUE}${BOLD}=========================== UPDATE SUMMARY ===========================${NC}"
    echo -e "${GREEN}✓  Update completed successfully at $(date)${NC}"
    echo -e "${BLUE}ℹ  Total duration: $duration seconds${NC}"
    echo -e "${BLUE}ℹ  Log file: $LOG_FILE${NC}"
    
    if [ "$BACKUP_CREATED" = true ]; then
        echo -e "${GREEN}✓  Backup created: $BACKUP_DIR${NC}"
    else
        echo -e "${YELLOW}⚠  No backup created${NC}"
    fi
    
    echo -e "${BLUE}${BOLD}====================================================================${NC}"
}

# Main execution
main() {
    local start_time=$(date +%s)
    local BACKUP_CREATED=false
    
    init_logging
    parse_args "$@"
    
    # System information header
    echo -e "${BLUE}${BOLD}"
    echo -e "System Information:"
    echo -e "  Hostname: $(hostname)"
    echo -e "  User: $USER"
    echo -e "  System: $(uname -srm)"
    [ -f /etc/os-release ] && echo -e "  OS: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
    echo -e "${NC}${RESET}"
    
    check_requirements
    check_connectivity
    
    [ -d "$SATURN_DIR" ] || {
        status_error "Saturn directory not found: $SATURN_DIR"
    }
    
    # Directory information
    echo -e "${BLUE}ℹ  Saturn directory: $SATURN_DIR${NC}"
    echo -e "${BLUE}ℹ  Directory size: $(du -sh "$SATURN_DIR" | cut -f1)${NC}"
    echo -e "${BLUE}ℹ  Contents: $(find "$SATURN_DIR" -type f | wc -l) files, $(find "$SATURN_DIR" -type d | wc -l) directories${NC}"
    
    # Backup prompt
    echo -ne "${YELLOW}?  Create backup before updating? [Y/n]: ${NC}"
    read -n 1 -r
    echo
    if [ "$REPLY" != "n" ] && [ "$REPLY" != "N" ]; then
        create_backup
        BACKUP_CREATED=true
    else
        status_warning "Backup skipped per user request"
    fi
    
    # Execute update steps
    update_git
    install_libraries
    build_p2app
    build_desktop_apps
    install_udev_rules
    install_desktop_icons
    check_fpga_binary
    
    # Print summary report
    print_summary_report
    
    # FPGA programming instructions
    echo -e "\n${GREEN}${BOLD}FPGA PROGRAMMING INSTRUCTIONS:${NC}${RESET}"
    echo -e "${GREEN}1. Launch the 'flashwriter' application from your desktop"
    echo -e "2. Navigate to: File → Open → Home → github → Saturn → FPGA"
    echo -e "3. Select the appropriate .BIT file"
    echo -e "4. Verify 'primary' is selected"
    echo -e "5. Click 'Program' to initiate FPGA programming${NC}"
    
    # Important notes
    echo -e "\n${YELLOW}${BOLD}IMPORTANT NOTES:${NC}${RESET}"
    echo -e "${YELLOW}- FPGA programming takes approximately 3 minutes to complete"
    echo -e "- A power cycle is REQUIRED after programming completes"
    echo -e "- Keep this terminal open until programming is fully complete"
    echo -e "- Consult log file for detailed operation records: $LOG_FILE${NC}"
    
    # Footer
    echo -e "\n${BLUE}${BOLD}Saturn Update Manager v$SCRIPT_VERSION - Operation Complete${NC}"
    echo -e "${BLUE}${BOLD}====================================================================${NC}"
}

# Run main
main "$@"
cd "$HOME"
