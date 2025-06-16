#!/bin/bash
# update-G2.sh - Advanced Saturn Update Script
# Original author: Laurence Barker G8NJJ
# Enhanced by: KD4YAL
# Comprehensive system update with parallel processing, robust logging, and advanced error handling

# Exit on error, undefined variables, and pipeline failures
set -euo pipefail

# Enable job control for parallel processing
set -m

# Script metadata
declare -r SCRIPT_VERSION="3.0"
declare -r SCRIPT_NAME="Saturn Update Script"

# Configuration defaults
declare -A CONFIG=(
    [SATURN_DIR]="${HOME}/github/Saturn"
    [SATURN_REPO_URL]="https://github.com/laurencebarker/Saturn.git"
    [SATURN_BRANCH]="main"
    [CREATE_BACKUP]="true"
    [SKIP_CONNECTIVITY_CHECK]="false"
    [VERBOSE]="false"
    [MAX_BACKUPS]="5"
    [MIN_DISK_SPACE]="1048576"  # 1GB in KB
)

# Runtime variables
declare LOG_DIR="${HOME}/saturn-logs"
declare LOG_FILE="${LOG_DIR}/saturn-update-$(date +%Y%m%d-%H%M%S).log"
declare BACKUP_INFO_FILE="${HOME}/.saturn-last-backup"
declare CONFIG_FILE="${HOME}/.saturn-update.conf"
declare -i STEP_COUNT=7
declare -i CURRENT_STEP=0
declare -A STATUS_TRACKER=()

# ANSI color codes for enhanced output
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r YELLOW='\033[1;33m'
declare -r NC='\033[0m'

# Initialize logging
init_logging() {
    mkdir -p "${LOG_DIR}" || {
        printf "${RED}✗ Failed to create log directory${NC}\n" >&2
        exit 1
    }
    exec 1> >(tee -a "${LOG_FILE}")
    exec 2> >(tee -a "${LOG_FILE}" >&2)
    printf "📜 ${SCRIPT_NAME} v${SCRIPT_VERSION} started at %s\n" "$(date)"
}

# Load configuration
load_config() {
    [[ -f "${CONFIG_FILE}" ]] && source "${CONFIG_FILE}"
    # Override defaults with config file values
    for key in "${!CONFIG[@]}"; do
        [[ -n "${!key:-}" ]] && CONFIG[$key]="${!key}"
    done
}

# Print formatted section headers
print_header() {
    local msg="$1"
    printf "\n${YELLOW}%-60s${NC}\n" "##############################################################"
    printf "${YELLOW}%s${NC}\n" "${msg}"
    printf "${YELLOW}%-60s${NC}\n\n" "##############################################################"
}

# Advanced progress display with spinner
show_progress() {
    local -r spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local -i i=0
    ((CURRENT_STEP++))
    while true; do
        printf "\r%s [%d/%d] %s... " "${spinner[$((i++ % 10))]}" "${CURRENT_STEP}" "${STEP_COUNT}" "$1"
        sleep 0.1
        [[ -f "/tmp/saturn-step-${CURRENT_STEP}-done" ]] && break
    done
    rm -f "/tmp/saturn-step-${CURRENT_STEP}-done"
    printf "\r${GREEN}✓ [%d/%d] %s completed${NC}\n" "${CURRENT_STEP}" "${STEP_COUNT}" "$1"
}

# Execute step with error handling and status tracking
execute_step() {
    local desc="$1"
    local cmd="$2"
    local step_key="$3"
    print_header "${desc}"
    show_progress "${desc}" &
    local spinner_pid=$!
    {
        if eval "${cmd}"; then
            STATUS_TRACKER["${step_key}"]="success"
            touch "/tmp/saturn-step-${CURRENT_STEP}-done"
        else
            STATUS_TRACKER["${step_key}"]="failed"
            touch "/tmp/saturn-step-${CURRENT_STEP}-done"
            printf "${RED}✗ %s failed (exit code: %d)${NC}\n" "${desc}" "$?" >&2
            printf "📜 Check log file: %s\n" "${LOG_FILE}" >&2
            attempt_rollback
            exit 1
        fi
    } &
    wait $!
    kill ${spinner_pid} 2>/dev/null || true
}

# Check system requirements with parallel validation
check_system_requirements() {
    print_header "Checking System Requirements"
    local -a missing=()
    local -a required=("git" "make" "gcc" "sudo" "rsync")
    
    # Parallel command checking
    for cmd in "${required[@]}"; do
        command -v "${cmd}" &>/dev/null || missing+=("${cmd}") &
    done
    wait
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        printf "${RED}✗ Missing required commands: %s${NC}\n" "${missing[*]}" >&2
        exit 1
    fi
    
    # Check disk space
    local free_space=$(df --output=avail "${HOME}" | tail -1)
    if [[ ${free_space} -lt ${CONFIG[MIN_DISK_SPACE]} ]]; then
        printf "${YELLOW}⚠ Low disk space: %dMB available${NC}\n" "$((free_space / 1024))"
    else
        printf "${GREEN}✓ Sufficient disk space: %dMB available${NC}\n" "$((free_space / 1024))"
    fi
}

# Check connectivity with timeout
check_connectivity() {
    [[ "${CONFIG[SKIP_CONNECTIVITY_CHECK]}" == "true" ]] && return 0
    print_header "Checking Connectivity"
    if timeout 5 ping -c 1 github.com &>/dev/null; then
        printf "${GREEN}✓ Internet connectivity confirmed${NC}\n"
        return 0
    else
        printf "${YELLOW}⚠ Cannot reach GitHub${NC}\n"
        return 1
    fi
}

# Validate and setup git repository
validate_git() {
    print_header "Validating Git Repository"
    cd "${CONFIG[SATURN_DIR]}" || {
        printf "${RED}✗ Cannot access Saturn directory${NC}\n" >&2
        exit 1
    }
    
    # Initialize git if not present
    if ! git rev-parse --git-dir &>/dev/null; then
        git init
        git remote add origin "${CONFIG[SATURN_REPO_URL]}"
    fi
    
    # Validate remote
    local current_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ -z "${current_url}" || "${current_url}" != "${CONFIG[SATURN_REPO_URL]}" ]]; then
        printf "${YELLOW}⚠ Updating remote URL to %s${NC}\n" "${CONFIG[SATURN_REPO_URL]}"
        git remote set-url origin "${CONFIG[SATURN_REPO_URL]}" 2>/dev/null || git remote add origin "${CONFIG[SATURN_REPO_URL]}"
    fi
    
    # Handle branch
    local current_branch=$(git branch --show-current 2>/dev/null || echo "main")
    if [[ "${CONFIG[SATURN_BRANCH]}" != "current" && "${current_branch}" != "${CONFIG[SATURN_BRANCH]}" ]]; then
        git checkout "${CONFIG[SATURN_BRANCH]}" 2>/dev/null || git checkout -b "${CONFIG[SATURN_BRANCH]}" "origin/${CONFIG[SATURN_BRANCH]}"
    fi
    
    # Stash changes if needed
    if ! git diff-index --quiet HEAD --; then
        printf "${YELLOW}⚠ Stashing uncommitted changes${NC}\n"
        git stash push -m "Auto-stash before update $(date)" >/dev/null
    fi
}

# Create backup with progress
create_backup() {
    [[ "${SKIP_BACKUP}" == "true" ]] && {
        printf "${YELLOW}⚠ Skipping backup creation${NC}\n"
        return 0
    }
    
    print_header "Creating Backup"
    local backup_dir="${HOME}/saturn-backup-$(date +%Y%m%d-%H%M%S)"
    printf "📁 Creating backup at: %s\n" "${backup_dir}"
    
    rsync -a --info=progress2 "${CONFIG[SATURN_DIR]}/" "${backup_dir}/" 2>/dev/null || cp -r "${CONFIG[SATURN_DIR]}" "${backup_dir}"
    
    # Store backup metadata
    cat > "${BACKUP_INFO_FILE}" << EOF
BACKUP_DIR=${backup_dir}
BACKUP_DATE=$(date)
BACKUP_SIZE=$(du -sh "${backup_dir}" 2>/dev/null | cut -f1 || echo "Unknown")
EOF
    
    printf "${GREEN}✓ Backup created: %s (%s)${NC}\n" "${backup_dir}" "$(du -sh "${backup_dir}" 2>/dev/null | cut -f1 || echo "Unknown")"
}

# Rollback mechanism
attempt_rollback() {
    [[ ! -f "${BACKUP_INFO_FILE}" ]] && {
        printf "${RED}✗ No backup available for rollback${NC}\n" >&2
        return 1
    }
    
    source "${BACKUP_INFO_FILE}"
    [[ ! -d "${BACKUP_DIR}" ]] && {
        printf "${RED}✗ Backup directory not found: %s${NC}\n" >&2
        return 1
    }
    
    print_header "Performing Rollback"
    rm -rf "${CONFIG[SATURN_DIR]}" && cp -r "${BACKUP_DIR}" "${CONFIG[SATURN_DIR]}"
    printf "${GREEN}✓ Rollback completed from %s${NC}\n" "${BACKUP_DIR}"
}

# Cleanup old backups
cleanup_backups() {
    local -a backups=($(ls -1d "${HOME}/saturn-backup-"* 2>/dev/null | sort -r))
    if [[ ${#backups[@]} -gt ${CONFIG[MAX_BACKUPS]} ]]; then
        print_header "Cleaning Up Old Backups"
        for backup in "${backups[@]:${CONFIG[MAX_BACKUPS]}}"; do
            rm -rf "${backup}"
            printf "${GREEN}✓ Removed old backup: %s${NC}\n" "${backup}"
        done
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-git) SKIP_UPDATE="true"; shift ;;
            --skip-backup) SKIP_BACKUP="true"; shift ;;
            --force) FORCE_UPDATE="true"; SKIP_BACKUP="true"; shift ;;
            --verbose) CONFIG[VERBOSE]="true"; shift ;;
            --repo-url) CONFIG[SATURN_REPO_URL]="$2"; shift 2 ;;
            --branch) CONFIG[SATURN_BRANCH]="$2"; shift 2 ;;
            --rollback) attempt_rollback; exit $? ;;
            --help) show_usage; exit 0 ;;
            *) printf "${RED}✗ Unknown option: %s${NC}\n" "$1" >&2; show_usage; exit 1 ;;
        esac
    done
}

# Show usage information
show_usage() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

Usage: $0 [OPTIONS]

Options:
  --skip-git          Skip repository update
  --skip-backup       Skip backup creation
  --force            Force update without prompts
  --verbose          Enable verbose output
  --repo-url URL     Override repository URL
  --branch BRANCH    Override target branch
  --rollback         Rollback to previous backup
  --help             Show this help message

Configuration: ${CONFIG_FILE}
Log file: ${LOG_FILE}
EOF
}

# Trap for cleanup
cleanup() {
    local exit_code=$?
    [[ ${exit_code} -ne 0 ]] && {
        printf "${RED}✗ Script failed (exit code: %d)${NC}\n" "${exit_code}" >&2
        printf "📜 Log file: %s\n" "${LOG_FILE}" >&2
    }
    rm -f /tmp/saturn-step-* 2>/dev/null
}

trap cleanup EXIT

# Main execution
main() {
    init_logging
    load_config
    parse_args "$@"
    
    printf "${GREEN}🚀 Starting %s v%s${NC}\n" "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
    
    check_system_requirements
    [[ ! -d "${CONFIG[SATURN_DIR]}" ]] && {
        printf "${RED}✗ Saturn directory not found: %s${NC}\n" "${CONFIG[SATURN_DIR]}" >&2
        exit 1
    }
    
    [[ "${FORCE_UPDATE}" != "true" ]] && prompt_for_backup
    create_backup
    
    # Execute update steps
    execute_step "Installing libraries" "./scripts/install-libraries.sh" "libraries"
    
    if [[ "${SKIP_UPDATE}" != "true" ]] && check_connectivity; then
        validate_git
        local current_version=$(git rev-parse HEAD)
        execute_step "Updating repository" "git pull origin ${CONFIG[SATURN_BRANCH]}" "repository"
        [[ "${current_version}" == "$(git rev-parse HEAD)" ]] && printf "${GREEN}✓ Repository already up to date${NC}\n"
    else
        printf "${YELLOW}⚠ Skipping repository update${NC}\n"
    fi
    
    execute_step "Building p2app" "./scripts/update-p2app.sh" "p2app"
    execute_step "Building desktop apps" "./scripts/update-desktop-apps.sh" "desktop_apps"
    
    cd "${CONFIG[SATURN_DIR]}/rules" || exit 1
    execute_step "Installing udev rules" "sudo ./install-rules.sh" "udev_rules"
    
    cd "${CONFIG[SATURN_DIR]}" || exit 1
    if [[ -d "desktop" && -d "${HOME}/Desktop" ]]; then
        execute_step "Installing desktop icons" "cp desktop/* ${HOME}/Desktop/ && chmod +x ${HOME}/Desktop/*.desktop" "desktop_icons"
    else
        printf "${YELLOW}⚠ Desktop directory not found${NC}\n"
        STATUS_TRACKER["desktop_icons"]="skipped"
    fi
    
    execute_step "Checking FPGA binary" "./scripts/find-bin.sh" "fpga_check"
    
    cleanup_backups
    
    # Print summary
    print_header "Update Summary"
    for key in "${!STATUS_TRACKER[@]}"; do
        printf "✓ %-20s: %s\n" "${key//_/ }" "${STATUS_TRACKER[$key]}"
    done
    
    printf "\n${GREEN}✓ Update completed successfully at %s${NC}\n" "$(date)"
    printf "📜 Log file: %s\n" "${LOG_FILE}"
    [[ "${CREATE_BACKUP}" == "true" && "${SKIP_BACKUP}" != "true" ]] && printf "💾 Backup available for rollback\n"
    
    cat << EOF

🔧 FPGA Update Instructions:
1. Launch flashwriter desktop app
2. Navigate: Open file → Home → github → Saturn → FPGA
3. Select the new .BIT file
4. Ensure 'primary' is selected
5. Click 'Program'

⚠ Important Notes:
- FPGA programming takes ~3 minutes
- Power cycle after programming
- Keep terminal open for full log
EOF
}

# Prompt for backup
prompt_for_backup() {
    print_header "Backup Confirmation"
    local backup_count=$(ls -1d "${HOME}/saturn-backup-"* 2>/dev/null | wc -l)
    [[ ${backup_count} -gt 0 ]] && printf "📁 Found %d existing backup(s)\n" "${backup_count}"
    printf "📊 Current directory size: %s\n" "$(du -sh "${CONFIG[SATURN_DIR]}" 2>/dev/null | cut -f1 || echo "Unknown")"
    
    if [[ "${FORCE_UPDATE}" != "true" ]]; then
        read -p "Create backup before updating? (Y/n): " -n 1 -r
        echo
        [[ "${REPLY}" =~ ^[Nn]$ ]] && SKIP_BACKUP="true"
    fi
}

# Initialize variables
declare SKIP_UPDATE="false"
declare SKIP_BACKUP="false"
declare FORCE_UPDATE="false"

# Run main
main "$@"
cd "${HOME}"
