#!/bin/bash
# update-G2.sh - Saturn Update Script
# Original author: Laurence Barker G8NJJ
# Rewritten by: Jerry DeLong KD4YAL
# Simplified update script for Saturn repository on Raspberry Pi
# Version: 2.0 (Colorized)

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script metadata
SCRIPT_NAME="Saturn Update Script"
SCRIPT_VERSION="2.0"
SATURN_DIR="$HOME/github/Saturn"
LOG_DIR="$HOME/saturn-logs"
LOG_FILE="$LOG_DIR/saturn-update-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="$HOME/saturn-backup-$(date +%Y%m%d-%H%M%S)"

# Flag for skipping Git update
SKIP_GIT="false"

# Initialize logging
init_logging() {
    mkdir -p "$LOG_DIR" || {
        echo -e "${RED}✗ ERROR: Failed to create log directory $LOG_DIR${NC}" >&2
        exit 1
    }
    # Redirect stdout and stderr to log file and terminal
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
    echo -e "${GREEN}📜 $SCRIPT_NAME v$SCRIPT_VERSION started at $(date)${NC}"
    echo -e "${BLUE}📝 Detailed log: $LOG_FILE${NC}"
}

# Parse command-line arguments
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --skip-git)
                SKIP_GIT="true"
                echo -e "${YELLOW}⚠ INFO: Skipping Git repository update${NC}"
                shift
                ;;
            *)
                echo -e "${RED}✗ ERROR: Unknown option: $1${NC}" >&2
                echo -e "${YELLOW}Usage: $0 [--skip-git]${NC}" >&2
                exit 1
                ;;
        esac
    done
}

# Check system requirements
check_requirements() {
    echo -e "${YELLOW}🔍 Checking system requirements...${NC}"
    for cmd in git make gcc sudo rsync; do
        if ! command -v "$cmd" >/dev/null; then
            echo -e "${RED}✗ ERROR: Required command '$cmd' is missing${NC}" >&2
            exit 1
        fi
    done
    # Check disk space (1GB minimum)
    local free_space
    free_space=$(df --output=avail "$HOME" | tail -1)
    if [ "$free_space" -lt 1048576 ]; then
        echo -e "${YELLOW}⚠ WARNING: Low disk space: $((free_space / 1024))MB available${NC}"
    else
        echo -e "${GREEN}✓ Sufficient disk space: $((free_space / 1024))MB available${NC}"
    fi
    echo -e "${GREEN}✓ System requirements met${NC}"
}

# Check connectivity
check_connectivity() {
    if [ "$SKIP_GIT" = "true" ]; then
        echo -e "${YELLOW}⚠ INFO: Skipping connectivity check due to --skip-git${NC}"
        return 0
    fi
    echo -e "${YELLOW}🌐 Checking connectivity...${NC}"
    if ping -c 1 -W 2 github.com >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Internet connectivity confirmed${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ WARNING: Cannot reach GitHub${NC}"
        return 1
    fi
}

# Update Git repository
update_git() {
    if [ "$SKIP_GIT" = "true" ]; then
        echo -e "${YELLOW}⚠ INFO: Skipping repository update${NC}"
        return 0
    fi
    echo -e "${YELLOW}🔄 Updating Git repository...${NC}"
    cd "$SATURN_DIR" || {
        echo -e "${RED}✗ ERROR: Cannot access Saturn directory $SATURN_DIR${NC}" >&2
        exit 1
    }
    # Check if it's a valid Git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo -e "${RED}✗ ERROR: $SATURN_DIR is not a Git repository${NC}" >&2
        exit 1
    fi
    # Stash any uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        echo -e "${YELLOW}⚠ INFO: Stashing uncommitted changes${NC}"
        git stash push -m "Auto-stash before update $(date)" >/dev/null
    fi
    # Pull latest changes
    if git pull origin main; then
        echo -e "${GREEN}✓ Repository updated${NC}"
    else
        echo -e "${RED}✗ ERROR: Failed to update repository${NC}" >&2
        exit 1
    fi
}

# Create backup
create_backup() {
    echo -e "${YELLOW}💾 Creating backup...${NC}"
    echo -e "${BLUE}📦 Backup directory: $BACKUP_DIR${NC}"
    if rsync -a "$SATURN_DIR/" "$BACKUP_DIR/"; then
        echo -e "${GREEN}✓ Backup created: $BACKUP_DIR ($(du -sh "$BACKUP_DIR" | cut -f1))${NC}"
    else
        echo -e "${RED}✗ ERROR: Failed to create backup${NC}" >&2
        exit 1
    fi
}

# Install libraries
install_libraries() {
    echo -e "${YELLOW}📚 Installing libraries...${NC}"
    if [ -f "$SATURN_DIR/scripts/install-libraries.sh" ]; then
        if bash "$SATURN_DIR/scripts/install-libraries.sh"; then
            echo -e "${GREEN}✓ Libraries installed${NC}"
        else
            echo -e "${RED}✗ ERROR: Failed to install libraries${NC}" >&2
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠ WARNING: install-libraries.sh not found, skipping${NC}"
    fi
}

# Build p2app
build_p2app() {
    echo -e "${YELLOW}🛠️ Building p2app...${NC}"
    if [ -f "$SATURN_DIR/scripts/update-p2app.sh" ]; then
        if bash "$SATURN_DIR/scripts/update-p2app.sh"; then
            echo -e "${GREEN}✓ p2app built${NC}"
        else
            echo -e "${RED}✗ ERROR: Failed to build p2app${NC}" >&2
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠ WARNING: update-p2app.sh not found, skipping${NC}"
    fi
}

# Build desktop apps
build_desktop_apps() {
    echo -e "${YELLOW}💻 Building desktop apps...${NC}"
    if [ -f "$SATURN_DIR/scripts/update-desktop-apps.sh" ]; then
        if bash "$SATURN_DIR/scripts/update-desktop-apps.sh"; then
            echo -e "${GREEN}✓ Desktop apps built${NC}"
        else
            echo -e "${RED}✗ ERROR: Failed to build desktop apps${NC}" >&2
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠ WARNING: update-desktop-apps.sh not found, skipping${NC}"
    fi
}

# Install udev rules
install_udev_rules() {
    echo -e "${YELLOW}⚙️ Installing udev rules...${NC}"
    local rules_dir="$SATURN_DIR/rules"
    local install_script="$rules_dir/install-rules.sh"
    
    if [ -f "$install_script" ]; then
        # Ensure the script is executable
        if [ ! -x "$install_script" ]; then
            echo -e "${YELLOW}⚠ Making script executable: $install_script${NC}"
            chmod +x "$install_script"
        fi
        
        # Execute from the rules directory to ensure proper context
        if (cd "$rules_dir" && sudo ./install-rules.sh); then
            echo -e "${GREEN}✓ Udev rules installed${NC}"
        else
            echo -e "${RED}✗ ERROR: Failed to install udev rules${NC}" >&2
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠ WARNING: install-rules.sh not found, skipping${NC}"
    fi
}

# Install desktop icons
install_desktop_icons() {
    echo -e "${YELLOW}🖥️ Installing desktop icons...${NC}"
    if [ -d "$SATURN_DIR/desktop" ] && [ -d "$HOME/Desktop" ]; then
        if cp "$SATURN_DIR/desktop/"* "$HOME/Desktop/" && chmod +x "$HOME/Desktop/"*.desktop; then
            echo -e "${GREEN}✓ Desktop icons installed${NC}"
        else
            echo -e "${RED}✗ ERROR: Failed to install desktop icons${NC}" >&2
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠ WARNING: Desktop directory not found, skipping${NC}"
    fi
}

# Check FPGA binary
check_fpga_binary() {
    echo -e "${YELLOW}🔍 Checking FPGA binary...${NC}"
    if [ -f "$SATURN_DIR/scripts/find-bin.sh" ]; then
        if bash "$SATURN_DIR/scripts/find-bin.sh"; then
            echo -e "${GREEN}✓ FPGA binary check completed${NC}"
        else
            echo -e "${RED}✗ ERROR: Failed to check FPGA binary${NC}" >&2
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠ WARNING: find-bin.sh not found, skipping${NC}"
    fi
}

# Main execution
main() {
    init_logging
    parse_args "$@"
    check_requirements
    check_connectivity
    
    [ -d "$SATURN_DIR" ] || {
        echo -e "${RED}✗ ERROR: Saturn directory not found: $SATURN_DIR${NC}" >&2
        exit 1
    }
    
    echo -e "${BLUE}📊 Current directory size: $(du -sh "$SATURN_DIR" | cut -f1)${NC}"
    echo -ne "${YELLOW}💾 Create backup before updating? (Y/n): ${NC}"
    read -n 1 -r
    echo
    if [ "$REPLY" != "n" ] && [ "$REPLY" != "N" ]; then
        create_backup
    else
        echo -e "${YELLOW}⚠ INFO: Skipping backup${NC}"
    fi
    
    update_git
    install_libraries
    build_p2app
    build_desktop_apps
    install_udev_rules
    install_desktop_icons
    check_fpga_binary
    
    echo -e "${GREEN}✓ Update completed successfully at $(date)${NC}"
    echo -e "${BLUE}📜 Log file: $LOG_FILE${NC}"
    
    echo -e "\n${GREEN}🔧 FPGA Update Instructions:${NC}"
    echo -e "${GREEN}1. Launch flashwriter desktop app"
    echo -e "2. Navigate: Open file → Home → github → Saturn → FPGA"
    echo -e "3. Select the new .BIT file"
    echo -e "4. Ensure 'primary' is selected"
    echo -e "5. Click 'Program'${NC}"
    
    echo -e "\n${YELLOW}⚠ Important Notes:${NC}"
    echo -e "${YELLOW}- FPGA programming takes ~3 minutes"
    echo -e "- Power cycle after programming"
    echo -e "- Keep terminal open for full log${NC}"
}

# Run main
main "$@"
cd "$HOME"
