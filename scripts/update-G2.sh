#!/bin/bash
# update-G2.sh - Saturn Update Script
# Original author: Laurence Barker G8NJJ
# Rewritten by: Jerry DeLong KD4YAL
# Simplified update script for Saturn repository on Raspberry Pi
# Version: 2.1 (Scalable CLI with Enhanced Visuals)

# ANSI color codes
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
PURPLE='\033[1;35m'
DIM_CYAN='\033[48;5;24m' # Background cyan for headers
NC='\033[0m'
BOLD='\033[1m'
RESET='\033[0m'

# Script metadata
SCRIPT_NAME="Saturn Update"
SCRIPT_VERSION="2.1"
SATURN_DIR="$HOME/github/Saturn"
LOG_DIR="$HOME/saturn-logs"
LOG_FILE="$LOG_DIR/saturn-update-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="$HOME/saturn-backup-$(date +%Y%m%d-%H%M%S)"

# Flag for skipping Git update
SKIP_GIT="false"

# Terminal utilities
get_term_size() {
    local cols=$(tput cols 2>/dev/null || echo 80)
    local lines=$(tput lines 2>/dev/null || echo 24)
    [ "$cols" -lt 20 ] && cols=20
    [ "$cols" -gt 80 ] && cols=80
    [ "$lines" -lt 8 ] && lines=8
    echo "$cols $lines"
}

is_minimal_mode() {
    local cols=$(get_term_size | cut -d' ' -f1)
    local lines=$(get_term_size | cut -d' ' -f2)
    [ "$cols" -lt 40 ] || [ "$lines" -lt 15 ]
}

truncate_text() {
    local text="$1" max_len=$2
    local clean_text=$(echo "$text" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')
    if [ ${#clean_text} -gt "$max_len" ]; then
        echo "${text:0:$((max_len-2))}.."
    else
        echo "$text"
    fi
}

draw_line() {
    local cols=$(get_term_size | cut -d' ' -f1)
    printf "+%${cols}s+\n" | sed 's/ /-/g;s/+/-/;s/+$/-/'
}

draw_double_line() {
    local cols=$(get_term_size | cut -d' ' -f1)
    if is_minimal_mode; then
        printf "+%${cols}s+\n" | sed 's/ /-/g;s/+/-/;s/+$/-/'
    else
        printf "╔%${cols}s╗\n" | sed 's/ /═/g;s/╔/═/;s/╗/═/'
    fi
}

draw_transition() {
    if is_minimal_mode; then
        return
    fi
    local cols=$(get_term_size | cut -d' ' -f1)
    for i in 1 2 3; do
        printf "\r${CYAN}%*s${NC}" "$cols" "..."
        sleep 0.1
        printf "\r%*s" "$cols" ""
        sleep 0.1
    done
    echo
}

progress_bar() {
    local pid=$1 msg=$2 total_steps=$3
    local cols=$(get_term_size | cut -d' ' -f1)
    local max_width=$(( cols - 20 ))
    msg=$(truncate_text "$msg" "$max_width")
    local bar_width=$(( cols - 20 ))
    local step=0
    tput civis
    while kill -0 "$pid" 2>/dev/null; do
        step=$(( step + 1 ))
        local percent=$(( (step * 100) / total_steps ))
        [ "$percent" -gt 100 ] && percent=100
        local filled=$(( (bar_width * percent) / 100 ))
        local empty=$(( bar_width - filled ))
        local bar=$(printf "%${filled}s" | sed 's/ /█/g')$(printf "%${empty}s" | sed 's/ / /g')
        printf "\r${BLUE}[%s] %2d%% %s${NC}" "$bar" "$percent" "$msg"
        sleep 0.5
    done
    printf "\r%*s\r" "$cols" ""
    sleep 0.1 # Ensure output is fully cleared
    tput cnorm
    wait "$pid"
    return $?
}

render_section() {
    local title="$1" cols=$(get_term_size | cut -d' ' -f1)
    title=$(truncate_text "$title" "$((cols-4))")
    echo -e "${CYAN}${BOLD}${DIM_CYAN}"
    draw_line
    printf "|%*s|\n" $(( (cols + ${#title} - 2) / 2 )) "$title"
    draw_line
    echo -e "${NC}${RESET}"
    draw_transition
}

render_top_section() {
    local title="$1" cols=$(get_term_size | cut -d' ' -f1)
    title=$(truncate_text "$title" "$((cols-4))")
    echo -e "${CYAN}${BOLD}${DIM_CYAN}"
    if is_minimal_mode; then
        echo "$title"
    else
        draw_double_line
        printf "║%*s║\n" $(( (cols + ${#title} - 2) / 2 )) "$title"
        draw_double_line
    fi
    echo -e "${NC}${RESET}"
    draw_transition
}

completion_animation() {
    if is_minimal_mode; then
        return
    fi
    local cols=$(get_term_size | cut -d' ' -f1)
    for i in 1 2 3; do
        printf "\r${GREEN}%*s${NC}" "$cols" "✔"
        sleep 0.1
        printf "\r%*s" "$cols" ""
        sleep 0.1
    done
    echo -e "${GREEN}✔ Complete!${NC}"
}

# Status reporting
status_start() {
    local msg="$1" cols=$(get_term_size | cut -d' ' -f1)
    msg=$(truncate_text "$msg" "$((cols-7))")
    if is_minimal_mode; then
        echo -e "${PURPLE}> $msg${NC}"
    else
        echo -e "${PURPLE}${BOLD}⏳ $msg${NC}${RESET}"
    fi
}

status_success() {
    local msg="$1" cols=$(get_term_size | cut -d' ' -f1)
    msg=$(truncate_text "$msg" "$((cols-7))")
    if is_minimal_mode; then
        echo -e "${GREEN}+ $msg${NC}"
    else
        echo -e "${GREEN}✔ $msg${NC}"
    fi
}

status_warning() {
    local msg="$1" cols=$(get_term_size | cut -d' ' -f1)
    msg=$(truncate_text "$msg" "$((cols-7))")
    if is_minimal_mode; then
        echo -e "${YELLOW}! $msg${NC}"
    else
        echo -e "${YELLOW}⚠ $msg${NC}"
    fi
}

status_error() {
    local msg="$1" cols=$(get_term_size | cut -d' ' -f1)
    msg=$(truncate_text "$msg" "$((cols-7))")
    if is_minimal_mode; then
        echo -e "${RED}x $msg${NC}" >&2
    else
        echo -e "${RED}✗ $msg${NC}" >&2
        draw_line
    fi
    exit 1
}

# Initialize logging
init_logging() {
    mkdir -p "$LOG_DIR" || {
        if is_minimal_mode; then
            echo -e "${RED}x Failed to create log dir${NC}" >&2
        else
            echo -e "${RED}✗ Failed to create log dir${NC}" >&2
        fi
        exit 1
    }
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1

    tput clear
    local cols=$(get_term_size | cut -d' ' -f1)
    render_top_section "$SCRIPT_NAME v$SCRIPT_VERSION"
    if is_minimal_mode; then
        echo -e "${BLUE}> $(truncate_text "Started: $(date)" $((cols-2)))${NC}"
        echo -e "${BLUE}> $(truncate_text "Log: $LOG_FILE" $((cols-2)))${NC}"
    else
        echo -e "${BLUE}ℹ $(truncate_text "Started: $(date)" $((cols-3)))${NC}"
        echo -e "${BLUE}ℹ $(truncate_text "Log: $LOG_FILE" $((cols-3)))${NC}"
    fi
}

# Parse command-line arguments
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --skip-git)
                SKIP_GIT="true"
                status_warning "Skipping Git update"
                shift
                ;;
            *)
                status_error "Unknown option: $1"
                ;;
        esac
    done
}

# Check system requirements
check_requirements() {
    render_section "System Check"
    status_start "Verifying requirements"

    local missing=()
    for cmd in git make gcc sudo rsync; do
        if ! command -v "$cmd" >/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        status_error "Missing commands: ${missing[*]}"
    fi

    local free_space
    free_space=$(df --output=avail "$HOME" | tail -1)
    local cols=$(get_term_size | cut -d' ' -f1)
    if [ "$free_space" -lt 1048576 ]; then
        status_warning "Low disk space: $((free_space / 1024))MB"
    else
        if is_minimal_mode; then
            echo -e "${GREEN}+ $(truncate_text "Disk: $((free_space / 1024))MB free" $((cols-2)))${NC}"
        else
            echo -e "${GREEN}✔ $(truncate_text "Disk: $((free_space / 1024))MB free" $((cols-3)))${NC}"
        fi
    fi

    status_success "Requirements met"
}

# Check connectivity
check_connectivity() {
    if [ "$SKIP_GIT" = "true" ]; then
        status_warning "Skipping network check"
        return 0
    fi

    render_section "Network Check"
    status_start "Checking connectivity"
    if ping -c 1 -W 2 github.com >/dev/null 2>&1; then
        status_success "Network verified"
        return 0
    else
        status_warning "Cannot reach GitHub"
        return 1
    fi
}

# Create backup
create_backup() {
    render_section "Backup"
    local cols=$(get_term_size | cut -d' ' -f1)
    if is_minimal_mode; then
        echo -ne "${YELLOW}> Backup? [${BOLD}Y${RESET}/n]: ${NC}"
    else
        echo -ne "${YELLOW}⚠ Backup? [${BOLD}Y${RESET}/n]: ${NC}"
    fi
    read -r -n 1 -p "" REPLY
    echo
    if [ "$REPLY" != "n" ] && [ "$REPLY" != "N" ]; then
        status_start "Creating backup"
        # Clean up old backups to keep only the 4 most recent (before adding new one)
        local backup_pattern="$HOME/saturn-backup-*"
        local backup_dirs
        backup_dirs=($(ls -dt $backup_pattern 2>/dev/null))
        if is_minimal_mode; then
            echo -e "${BLUE}> $(truncate_text "Found ${#backup_dirs[@]} existing backups" $((cols-2)))${NC}"
        else
            echo -e "${BLUE}ℹ $(truncate_text "Found ${#backup_dirs[@]} existing backups" $((cols-3)))${NC}"
        fi
        if [ ${#backup_dirs[@]} -gt 4 ]; then
            for old_backup in "${backup_dirs[@]:4}"; do
                rm -rf "$old_backup"
                if is_minimal_mode; then
                    echo -e "${BLUE}> $(truncate_text "Deleted old backup: $old_backup" $((cols-2)))${NC}"
                else
                    echo -e "${BLUE}ℹ $(truncate_text "Deleted old backup: $old_backup" $((cols-3)))${NC}"
                fi
            done
        fi

        if is_minimal_mode; then
            echo -e "${BLUE}> $(truncate_text "Location: $BACKUP_DIR" $((cols-2)))${NC}"
        else
            echo -e "${BLUE}ℹ $(truncate_text "Location: $BACKUP_DIR" $((cols-3)))${NC}"
        fi

        if ! mkdir -p "$BACKUP_DIR"; then
            status_error "Cannot create backup dir"
        fi

        {
            rsync -a "$SATURN_DIR/" "$BACKUP_DIR/" > /tmp/rsync_output 2>&1 &
            local rsync_pid=$!
            progress_bar "$rsync_pid" "Copying files" 10
            local rsync_status=$?
            cat /tmp/rsync_output
            sleep 0.1 # Ensure output is fully cleared
            return $rsync_status
        } || {
            status_error "Backup failed"
        }

        local backup_size=$(du -sh "$BACKUP_DIR" | cut -f1)
        if is_minimal_mode; then
            echo -e "${BLUE}> $(truncate_text "Size: $backup_size" $((cols-2)))${NC}"
        else
            echo -e "${BLUE}ℹ $(truncate_text "Size: $backup_size" $((cols-3)))${NC}"
        fi
        status_success "Backup created"
        return 0
    else
        status_warning "Backup skipped"
        return 1
    fi
}

# Update Git repository
update_git() {
    if [ "$SKIP_GIT" = "true" ]; then
        status_warning "Skipping repository update"
        return 0
    fi

    render_section "Git Update"
    status_start "Updating repository"
    cd "$SATURN_DIR" || {
        status_error "Cannot access: $SATURN_DIR"
    }

    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        status_error "Not a Git repository"
    fi

    if ! git diff-index --quiet HEAD --; then
        status_warning "Stashing changes"
        git stash push -m "Auto-stash $(date)" >/dev/null
    fi

    local cols=$(get_term_size | cut -d' ' -f1)
    local current_branch
    if current_branch=$(git branch --show-current 2>/dev/null); then
        if is_minimal_mode; then
            echo -e "${BLUE}> $(truncate_text "Branch: $current_branch" $((cols-2)))${NC}"
        else
            echo -e "${BLUE}ℹ $(truncate_text "Branch: $current_branch" $((cols-3)))${NC}"
        fi
    else
        current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD)
        if is_minimal_mode; then
            echo -e "${BLUE}> $(truncate_text "Ref: $current_branch" $((cols-2)))${NC}"
        else
            echo -e "${BLUE}ℹ $(truncate_text "Ref: $current_branch" $((cols-3)))${NC}"
        fi
    fi

    local current_commit=$(git rev-parse --short HEAD)
    if is_minimal_mode; then
        echo -e "${BLUE}> $(truncate_text "Commit: $current_commit" $((cols-2)))${NC}"
    else
        echo -e "${BLUE}ℹ $(truncate_text "Commit: $current_commit" $((cols-3)))${NC}"
    fi

    {
        git pull origin main > /tmp/git_output 2>&1 &
        progress_bar $! "Pulling changes" 10
        local git_status=$?
        cat /tmp/git_output
        return $git_status
    } || {
        status_error "Git update failed"
    }

    local new_commit=$(git rev-parse --short HEAD)
    if [ "$current_commit" != "$new_commit" ]; then
        if is_minimal_mode; then
            echo -e "${BLUE}> $(truncate_text "New commit: $new_commit" $((cols-2)))${NC}"
            echo -e "${BLUE}> $(truncate_text "Changes: $(git log --oneline "$current_commit..HEAD" 2>/dev/null | wc -l) commits" $((cols-2)))${NC}"
        else
            echo -e "${BLUE}ℹ $(truncate_text "New commit: $new_commit" $((cols-3)))${NC}"
            echo -e "${BLUE}ℹ $(truncate_text "Changes: $(git log --oneline "$current_commit..HEAD" 2>/dev/null | wc -l) commits" $((cols-3)))${NC}"
        fi
    else
        if is_minimal_mode; then
            echo -e "${BLUE}> Up to date${NC}"
        else
            echo -e "${BLUE}ℹ Up to date${NC}"
        fi
    fi
    status_success "Repository updated"
}

# Install libraries
install_libraries() {
    render_section "Libraries"
    status_start "Installing libraries"
    if [ -f "$SATURN_DIR/scripts/install-libraries.sh" ]; then
        {
            bash "$SATURN_DIR/scripts/install-libraries.sh" > /tmp/library_output 2>&1 &
            progress_bar $! "Installing" 10
            local library_status=$?
            cat /tmp/library_output
            return $library_status
        } || {
            status_error "Library install failed"
        }
        status_success "Libraries installed"
    else
        status_warning "No install script"
    fi
}

# Build p2app
build_p2app() {
    render_section "p2app Build"
    status_start "Building p2app"
    if [ -f "$SATURN_DIR/scripts/update-p2app.sh" ]; then
        {
            bash "$SATURN_DIR/scripts/update-p2app.sh" > /tmp/p2app_output 2>&1 &
            progress_bar $! "Building" 10
            local p2app_status=$?
            cat /tmp/p2app_output
            return $p2app_status
        } || {
            status_error "p2app build failed"
        }
        status_success "p2app built"
    else
        status_warning "No build script"
    fi
}

# Build desktop apps
build_desktop_apps() {
    render_section "Desktop Apps"
    status_start "Building apps"
    if [ -f "$SATURN_DIR/scripts/update-desktop-apps.sh" ]; then
        {
            bash "$SATURN_DIR/scripts/update-desktop-apps.sh" > /tmp/desktop_output 2>&1 &
            progress_bar $! "Building" 10
            local desktop_status=$?
            cat /tmp/desktop_output
            return $desktop_status
        } || {
            status_error "App build failed"
        }
        status_success "Apps built"
    else
        status_warning "No build script"
    fi
}

# Install udev rules
install_udev_rules() {
    render_section "Udev Rules"
    status_start "Installing rules"
    local rules_dir="$SATURN_DIR/rules"
    local install_script="$rules_dir/install-rules.sh"

    if [ -f "$install_script" ]; then
        if [ ! -x "$install_script" ]; then
            status_warning "Setting permissions"
            chmod +x "$install_script"
        fi

        {
            (cd "$rules_dir" && sudo ./install-rules.sh) > /tmp/udev_output 2>&1 &
            progress_bar $! "Installing" 10
            local udev_status=$?
            cat /tmp/udev_output
            return $udev_status
        } || {
            status_error "Udev install failed"
        }
        status_success "Rules installed"
    else
        status_warning "No install script"
    fi
}

# Install desktop icons
install_desktop_icons() {
    render_section "Desktop Icons"
    status_start "Installing shortcuts"
    if [ -d "$SATURN_DIR/desktop" ] && [ -d "$HOME/Desktop" ]; then
        {
            cp "$SATURN_DIR/desktop/"* "$HOME/Desktop/" && chmod +x "$HOME/Desktop/"*.desktop > /tmp/icons_output 2>&1 &
            progress_bar $! "Copying" 10
            local icons_status=$?
            cat /tmp/icons_output
            return $icons_status
        } || {
            status_error "Shortcut install failed"
        }
        status_success "Shortcuts installed"
    else
        status_warning "No desktop dir"
    fi
}

# Check FPGA binary
check_fpga_binary() {
    render_section "FPGA Binary"
    status_start "Verifying binary"
    if [ -f "$SATURN_DIR/scripts/find-bin.sh" ]; then
        {
            bash "$SATURN_DIR/scripts/find-bin.sh" > /tmp/fpga_output 2>&1 &
            progress_bar $! "Verifying" 10
            local fpga_status=$?
            cat /tmp/fpga_output
            return $fpga_status
        } || {
            status_error "FPGA check failed"
        }
        status_success "Binary verified"
    else
        status_warning "No verify script"
    fi
}

# Print summary report
print_summary_report() {
    local duration=$(( $(date +%s) - start_time ))
    render_section "Summary"
    local cols=$(get_term_size | cut -d' ' -f1)
    if is_minimal_mode; then
        echo -e "${GREEN}+ $(truncate_text "Completed: $(date)" $((cols-2)))${NC}"
        echo -e "${BLUE}> $(truncate_text "Duration: $duration seconds" $((cols-2)))${NC}"
        echo -e "${BLUE}> $(truncate_text "Log: $LOG_FILE" $((cols-2)))${NC}"
        if [ "$BACKUP_CREATED" = true ]; then
            echo -e "${GREEN}+ $(truncate_text "Backup: $BACKUP_DIR" $((cols-2)))${NC}"
        else
            status_warning "No backup created"
        fi
    else
        echo -e "${GREEN}✔ $(truncate_text "Completed: $(date)" $((cols-3)))${NC}"
        echo -e "${BLUE}ℹ $(truncate_text "Duration: $duration seconds" $((cols-3)))${NC}"
        echo -e "${BLUE}ℹ $(truncate_text "Log: $LOG_FILE" $((cols-3)))${NC}"
        if [ "$BACKUP_CREATED" = true ]; then
            echo -e "${GREEN}✔ $(truncate_text "Backup: $BACKUP_DIR" $((cols-3)))${NC}"
        else
            status_warning "No backup created"
        fi
    fi
}

# System stats for footer
get_system_stats() {
    if is_minimal_mode; then
        return
    fi
    local cpu=$(top -bn1 | head -n3 | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1)
    local mem=$(free -m | awk '/Mem:/ {print $3 "/" $2 "MB"}')
    local disk=$(df -h "$HOME" | tail -1 | awk '{print $3 "/" $2}')
    local cols=$(get_term_size | cut -d' ' -f1)
    echo -e "${BLUE}ℹ $(truncate_text "CPU: $cpu% | Mem: $mem | Disk: $disk" $((cols-3)))${NC}"
}

# Main execution
main() {
    local start_time=$(date +%s)
    local BACKUP_CREATED=false

    init_logging
    parse_args "$@"

    render_section "System Info"
    local cols=$(get_term_size | cut -d' ' -f1)
    local host_info=$(truncate_text "Host: $(hostname)" $((cols-3)))
    local user_info=$(truncate_text "User: $USER" $((cols-3)))
    local system_info=$(truncate_text "System: $(uname -srm)" $((cols-3)))
    local os_info=$(truncate_text "OS: $( [ -f /etc/os-release ] && grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"' || echo "Unknown" )" $((cols-3)))
    if is_minimal_mode; then
        echo -e "${BLUE}> $host_info${NC}"
        echo -e "${BLUE}> $user_info${NC}"
        echo -e "${BLUE}> $system_info${NC}"
        echo -e "${BLUE}> $os_info${NC}"
    else
        echo -e "${BLUE}ℹ $host_info${NC}"
        echo -e "${BLUE}ℹ $user_info${NC}"
        echo -e "${BLUE}ℹ $system_info${NC}"
        echo -e "${BLUE}ℹ $os_info${NC}"
    fi

    check_requirements
    check_connectivity

    [ -d "$SATURN_DIR" ] || {
        status_error "No Saturn dir: $SATURN_DIR"
    }

    render_section "Repository"
    local repo_dir=$(truncate_text "Dir: $SATURN_DIR" $((cols-3)))
    local repo_size=$(truncate_text "Size: $(du -sh "$SATURN_DIR" | cut -f1)" $((cols-3)))
    local repo_contents=$(truncate_text "Files: $(find "$SATURN_DIR" -type f | wc -l), Dirs: $(find "$SATURN_DIR" -type d | wc -l)" $((cols-3)))
    if is_minimal_mode; then
        echo -e "${BLUE}> $repo_dir${NC}"
        echo -e "${BLUE}> $repo_size${NC}"
        echo -e "${BLUE}> $repo_contents${NC}"
    else
        echo -e "${BLUE}ℹ $repo_dir${NC}"
        echo -e "${BLUE}ℹ $repo_size${NC}"
        echo -e "${BLUE}ℹ $repo_contents${NC}"
    fi

    if create_backup; then
        BACKUP_CREATED=true
    else
        BACKUP_CREATED=false
    fi

    update_git
    install_libraries
    build_p2app
    build_desktop_apps
    install_udev_rules
    install_desktop_icons
    check_fpga_binary

    print_summary_report

    render_section "FPGA Programming"
    if is_minimal_mode; then
        echo -e "${GREEN}+ $(truncate_text "Launch 'flashwriter' from desktop" $((cols-2)))${NC}"
        echo -e "${GREEN}+ $(truncate_text "Navigate: File > Open > ~/github/Saturn/FPGA" $((cols-2)))${NC}"
        echo -e "${GREEN}+ $(truncate_text "Select .BIT file" $((cols-2)))${NC}"
        echo -e "${GREEN}+ $(truncate_text "Verify 'primary' selected" $((cols-2)))${NC}"
        echo -e "${GREEN}+ $(truncate_text "Click 'Program'" $((cols-2)))${NC}"
    else
        echo -e "${GREEN}✔ $(truncate_text "Launch 'flashwriter' from desktop" $((cols-3)))${NC}"
        echo -e "${GREEN}✔ $(truncate_text "Navigate: File > Open > ~/github/Saturn/FPGA" $((cols-3)))${NC}"
        echo -e "${GREEN}✔ $(truncate_text "Select .BIT file" $((cols-3)))${NC}"
        echo -e "${GREEN}✔ $(truncate_text "Verify 'primary' selected" $((cols-3)))${NC}"
        echo -e "${GREEN}✔ $(truncate_text "Click 'Program'" $((cols-3)))${NC}"
    fi

    render_section "Important Notes"
    if is_minimal_mode; then
        echo -e "${YELLOW}! $(truncate_text "FPGA programming takes ~3 minutes" $((cols-2)))${NC}"
        echo -e "${YELLOW}! $(truncate_text "Power cycle required after" $((cols-2)))${NC}"
        echo -e "${YELLOW}! $(truncate_text "Keep terminal open" $((cols-2)))${NC}"
        echo -e "${YELLOW}! $(truncate_text "Log: $LOG_FILE" $((cols-2)))${NC}"
    else
        echo -e "${YELLOW}⚠ $(truncate_text "FPGA programming takes ~3 minutes" $((cols-3)))${NC}"
        echo -e "${YELLOW}⚠ $(truncate_text "Power cycle required after" $((cols-3)))${NC}"
        echo -e "${YELLOW}⚠ $(truncate_text "Keep terminal open" $((cols-3)))${NC}"
        echo -e "${YELLOW}⚠ $(truncate_text "Log: $LOG_FILE" $((cols-3)))${NC}"
    fi

    echo -e "${CYAN}${BOLD}"
    render_top_section "$SCRIPT_NAME v$SCRIPT_VERSION Done"
    completion_animation
    get_system_stats
    echo -e "${NC}${RESET}"
}

# Run main
main "$@"
cd "$HOME"
