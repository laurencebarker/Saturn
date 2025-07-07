#!/bin/bash
# update-pihpsdr.sh - piHPSDR Update Script
# Automates cloning, updating, and building the pihpsdr repository from ~/github/Saturn/scripts
# Version: 1.0 (Scalable CLI with Enhanced Visuals and Backup Flags)
# Written by: Jerry DeLong KD4YAL

# ANSI color codes (using \e for portability)
RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
BLUE='\e[1;34m'
CYAN='\e[1;36m'
PURPLE='\e[1;35m'
DIM_CYAN='\e[48;5;24m' # Background cyan for headers
NC='\e[0m'
BOLD='\e[1m'
RESET='\e[0m'

# Script metadata
SCRIPT_NAME="piHPSDR Update"
SCRIPT_VERSION="1.0"
PIHPSDR_DIR="$HOME/github/pihpsdr"
LOG_DIR="$HOME/saturn-logs"
LOG_FILE="$LOG_DIR/pihpsdr-update-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="$HOME/pihpsdr-backup-$(date +%Y%m%d-%H%M%S)"
BACKUP_MODE="prompt" # Default: prompt for backup; options: y, n, prompt
SKIP_GIT="false"
FLAG_MESSAGES=() # Array to store flag-related status messages
USE_COLORS=true # Flag to enable/disable colors based on terminal support
GPIO_ENABLED="true" # Default: enable GPIO; disable for Radioberry

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
        printf "%s.." "${text:0:$((max_len-2))}"
    else
        printf "%s" "$text"
    fi
}

draw_line() {
    local cols=$(get_term_size | cut -d' ' -f1)
    if [ "$USE_COLORS" = true ]; then
        printf "${DIM_CYAN}+%*s+${NC}\n" "$((cols-2))" "" | sed 's/ /-/g'
    else
        printf "+%*s+\n" "$((cols-2))" "" | sed 's/ /-/g'
    fi
}

draw_double_line() {
    local position="$1" # "top" or "bottom"
    local cols=$(get_term_size | cut -d' ' -f1)
    if is_minimal_mode || [ "$USE_COLORS" != true ]; then
        printf "+%*s+\n" "$((cols-2))" "" | sed 's/ /-/g'
    else
        if [ "$position" = "top" ]; then
            printf "${DIM_CYAN}╔%*s╗${NC}\n" "$((cols-2))" "" | sed 's/ /═/g'
        else
            printf "${DIM_CYAN}╚%*s╝${NC}\n" "$((cols-2))" "" | sed 's/ /═/g'
        fi
    fi
}

draw_transition() {
    if is_minimal_mode || [ "$USE_COLORS" != true ]; then
        return
    fi
    local cols=$(get_term_size | cut -d' ' -f1)
    for i in 1 2 3; do
        printf "\r${CYAN}%*s${NC}" "$cols" "..."
        sleep 0.1
        printf "\r%*s${NC}" "$cols" ""
        sleep 0.1
    done
    printf "${NC}\n"
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
        if [ "$USE_COLORS" = true ]; then
            printf "\r${BLUE}[%s] %2d%% %s${NC}" "$bar" "$percent" "$msg"
        else
            printf "\r[%s] %2d%% %s" "$bar" "$percent" "$msg"
        fi
        sleep 0.75
    done
    printf "\r%*s\r${NC}" "$cols" ""
    sleep 0.1 # Ensure output is fully cleared
    tput cnorm
    wait "$pid"
    return $?
}

render_section() {
    local title="$1" cols=$(get_term_size | cut -d' ' -f1)
    title=$(truncate_text "$title" "$((cols-4))")
    if [ "$USE_COLORS" = true ]; then
        printf "${CYAN}${BOLD}${DIM_CYAN}"
        draw_line
        printf "${DIM_CYAN}|%*s|${NC}\n" $(( (cols - ${#title} - 2) / 2 + ${#title} )) "$title"
        draw_line
        printf "${NC}${RESET}\n"
    else
        draw_line
        printf "|%*s|\n" $(( (cols - ${#title} - 2) / 2 + ${#title} )) "$title"
        draw_line
    fi
    draw_transition
}

render_top_section() {
    local title="$1" cols=$(get_term_size | cut -d' ' -f1)
    title=$(truncate_text "$title" "$((cols-4))")
    if [ "$USE_COLORS" = true ]; then
        printf "${CYAN}${BOLD}${DIM_CYAN}"
        if is_minimal_mode; then
            printf "%s${NC}\n" "$title"
        else
            draw_double_line "top"
            printf "${DIM_CYAN}║%*s║${NC}\n" $(( (cols - ${#title} - 2) / 2 + ${#title} )) "$title"
            draw_double_line "bottom"
        fi
        printf "${NC}${RESET}\n"
    else
        if is_minimal_mode; then
            printf "%s\n" "$title"
        else
            draw_line
            printf "|%*s|\n" $(( (cols - ${#title} - 2) / 2 + ${#title} )) "$title"
            draw_line
        fi
    fi
    draw_transition
}

completion_animation() {
    if is_minimal_mode || [ "$USE_COLORS" != true ]; then
        printf "Complete!\n"
        return
    fi
    for i in 1 2 3; do
        printf "\r${GREEN}✔${NC}"
        sleep 0.1
        printf "\r%*s" 2 ""
        sleep 0.1
    done
    printf "\r${GREEN}✔ Complete!${NC}\n"
}

# Status reporting
status_start() {
    local msg="$1" cols=$(get_term_size | cut -d' ' -f1)
    msg=$(truncate_text "$msg" "$((cols-7))")
    if is_minimal_mode || [ "$USE_COLORS" != true ]; then
        printf "> %s\n" "$msg"
    else
        printf "${PURPLE}${BOLD}⏳ %s${NC}${RESET}\n" "$msg"
    fi
}

status_success() {
    local msg="$1" cols=$(get_term_size | cut -d' ' -f1)
    msg=$(truncate_text "$msg" "$((cols-7))")
    if is_minimal_mode || [ "$USE_COLORS" != true ]; then
        printf "+ %s\n" "$msg"
    else
        printf "${GREEN}✔ %s${NC}\n" "$msg"
    fi
}

status_warning() {
    local msg="$1" cols=$(get_term_size | cut -d' ' -f1)
    msg=$(truncate_text "$msg" "$((cols-7))")
    if is_minimal_mode || [ "$USE_COLORS" != true ]; then
        printf "! %s\n" "$msg"
    else
        printf "${YELLOW}⚠ %s${NC}\n" "$msg"
    fi
}

status_error() {
    local msg="$1" cols=$(get_term_size | cut -d' ' -f1)
    msg=$(truncate_text "$msg" "$((cols-7))")
    if is_minimal_mode || [ "$USE_COLORS" != true ]; then
        printf "x %s\n" "$msg" >&2
    else
        printf "${RED}✗ %s${NC}\n" "$msg" >&2
        draw_line
    fi
    exit 1
}

# Initialize logging
init_logging() {
    mkdir -p "$LOG_DIR" || {
        if is_minimal_mode || [ "$USE_COLORS" != true ]; then
            printf "x Failed to create log dir\n" >&2
        else
            printf "${RED}✗ Failed to create log dir${NC}\n" >&2
        fi
        exit 1
    }
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1

    # Check terminal color support
    if ! tput colors >/dev/null 2>&1 || [ "$(tput colors)" -lt 8 ] || [[ "$TERM" != *256color* ]]; then
        USE_COLORS=false
        printf "! Terminal lacks 256-color support (TERM=%s, colors=%s). Colors disabled.\n" "$TERM" "$(tput colors 2>/dev/null || echo unknown)"
    fi

    tput clear
    local cols=$(get_term_size | cut -d' ' -f1)
    render_top_section "$SCRIPT_NAME v$SCRIPT_VERSION"
    if is_minimal_mode || [ "$USE_COLORS" != true ]; then
        printf "> %s\n" "$(truncate_text "Started: $(date)" $((cols-2)))"
        printf "> %s\n" "$(truncate_text "Log: $LOG_FILE" $((cols-2)))"
    else
        printf "${BLUE}ℹ %s${NC}\n" "$(truncate_text "Started: $(date)" $((cols-3)))"
        printf "${BLUE}ℹ %s${NC}\n" "$(truncate_text "Log: $LOG_FILE" $((cols-3)))"
    fi
}

# Parse command-line arguments
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --skip-git)
                SKIP_GIT="true"
                FLAG_MESSAGES+=("Skipping Git update")
                shift
                ;;
            -y)
                if [ "$BACKUP_MODE" = "n" ]; then
                    status_error "Cannot use -y and -n together"
                fi
                BACKUP_MODE="y"
                FLAG_MESSAGES+=("Backup enabled via -y flag")
                shift
                ;;
            -n)
                if [ "$BACKUP_MODE" = "y" ]; then
                    status_error "Cannot use -y and -n together"
                fi
                BACKUP_MODE="n"
                FLAG_MESSAGES+=("Backup disabled via -n flag")
                shift
                ;;
            --no-gpio)
                GPIO_ENABLED="false"
                FLAG_MESSAGES+=("GPIO disabled for Radioberry compatibility")
                shift
                ;;
            *)
                status_error "Unknown option: $1"
                ;;
        esac
    done
}

# Create backup
create_backup() {
    render_section "Backup"
    local cols=$(get_term_size | cut -d' ' -f1)
    local do_backup=false

    if [ "$BACKUP_MODE" = "y" ]; then
        do_backup=true
    elif [ "$BACKUP_MODE" = "n" ]; then
        status_warning "Backup skipped"
        return 1
    else
        if is_minimal_mode || [ "$USE_COLORS" != true ]; then
            printf "> Backup? [Y/n]: "
        else
            printf "${YELLOW}⚠ Backup? [${BOLD}Y${RESET}/n]: ${NC}"
        fi
        read -r -n 1 -p "" REPLY
        printf "${NC}\n"
        if [ "$REPLY" != "n" ] && [ "$REPLY" != "N" ]; then
            do_backup=true
        else
            status_warning "Backup skipped"
            return 1
        fi
    fi

    if [ "$do_backup" = true ]; then
        status_start "Creating backup"
        if is_minimal_mode || [ "$USE_COLORS" != true ]; then
            printf "> %s\n" "$(truncate_text "Location: $BACKUP_DIR" $((cols-2)))"
        else
            printf "${BLUE}ℹ %s${NC}\n" "$(truncate_text "Location: $BACKUP_DIR" $((cols-3)))"
        fi

        if ! mkdir -p "$BACKUP_DIR"; then
            status_error "Cannot create backup dir"
        fi

        {
            rsync -a "$PIHPSDR_DIR/" "$BACKUP_DIR/" > /tmp/rsync_output 2>&1 &
            local rsync_pid=$!
            progress_bar "$rsync_pid" "Copying files" 20
            local rsync_status=$?
            cat /tmp/rsync_output
            if [ $rsync_status -ne 0 ]; then
                status_error "Backup failed"
            fi
            return $rsync_status
        }

        local backup_size=$(du -sh "$BACKUP_DIR" | cut -f1)
        if is_minimal_mode || [ "$USE_COLORS" != true ]; then
            printf "> %s\n" "$(truncate_text "Size: $backup_size" $((cols-2)))"
        else
            printf "${BLUE}ℹ %s${NC}\n" "$(truncate_text "Size: $backup_size" $((cols-3)))"
        fi
        status_success "Backup created"
        return 0
    fi
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
        if is_minimal_mode || [ "$USE_COLORS" != true ]; then
            printf "+ %s\n" "$(truncate_text "Disk: $((free_space / 1024))MB free" $((cols-2)))"
        else
            printf "${GREEN}✔ %s${NC}\n" "$(truncate_text "Disk: $((free_space / 1024))MB free" $((cols-3)))"
        fi
    fi
    status_success "Requirements met"
}

# Clone or update repository
update_git() {
    render_section "Git Update"
    status_start "Checking repository"
    local cols=$(get_term_size | cut -d' ' -f1)

    if [ "$SKIP_GIT" = "true" ]; then
        status_warning "Skipping repository update"
        return 0
    fi

    mkdir -p "$HOME/github" || status_error "Cannot create ~/github directory"

    if [ -d "$PIHPSDR_DIR" ]; then
        status_start "Updating repository"
        cd "$PIHPSDR_DIR" || status_error "Cannot access: $PIHPSDR_DIR"
        if ! git rev-parse --git-dir >/dev/null 2>&1; then
            status_error "Not a Git repository"
        fi

        if ! git diff-index --quiet HEAD --; then
            status_warning "Stashing changes"
            git stash push -m "Auto-stash $(date)" >/dev/null || status_error "Git stash failed"
        fi

        local current_commit=$(git rev-parse --short HEAD)
        if is_minimal_mode || [ "$USE_COLORS" != true ]; then
            printf "> %s\n" "$(truncate_text "Commit: $current_commit" $((cols-2)))"
        else
            printf "${BLUE}ℹ %s${NC}\n" "$(truncate_text "Commit: $current_commit" $((cols-3)))"
        fi

        {
            git pull origin master > /tmp/git_output 2>&1 &
            local git_pid=$!
            progress_bar "$git_pid" "Pulling changes" 20
            local git_status=$?
            cat /tmp/git_output
            if [ $git_status -ne 0 ]; then
                status_error "Git update failed"
            fi
            return $git_status
        }
        local new_commit=$(git rev-parse --short HEAD)
        if [ "$current_commit" != "$new_commit" ]; then
            if is_minimal_mode || [ "$USE_COLORS" != true ]; then
                printf "> %s\n" "$(truncate_text "New commit: $new_commit" $((cols-2)))"
                printf "> %s\n" "$(truncate_text "Changes: $(git log --oneline "$current_commit..HEAD" 2>/dev/null | wc -l) commits" $((cols-2)))"
            else
                printf "${BLUE}ℹ %s${NC}\n" "$(truncate_text "New commit: $new_commit" $((cols-3)))"
                printf "${BLUE}ℹ %s${NC}\n" "$(truncate_text "Changes: $(git log --oneline "$current_commit..HEAD" 2>/dev/null | wc -l) commits" $((cols-3)))"
            fi
        else
            if is_minimal_mode || [ "$USE_COLORS" != true ]; then
                printf "> Up to date\n"
            else
                printf "${BLUE}ℹ Up to date${NC}\n"
            fi
        fi
    else
        status_start "Cloning repository"
        {
            git clone https://github.com/dl1ycf/pihpsdr "$PIHPSDR_DIR" > /tmp/git_output 2>&1 &
            local git_pid=$!
            progress_bar "$git_pid" "Cloning repository" 20
            local git_status=$?
            cat /tmp/git_output
            if [ $git_status -ne 0 ]; then
                status_error "Git clone failed"
            fi
            return $git_status
        }
        cd "$PIHPSDR_DIR" || status_error "Cannot access: $PIHPSDR_DIR"
        local new_commit=$(git rev-parse --short HEAD)
        if is_minimal_mode || [ "$USE_COLORS" != true ]; then
            printf "> %s\n" "$(truncate_text "Commit: $new_commit" $((cols-2)))"
        else
            printf "${BLUE}ℹ %s${NC}\n" "$(truncate_text "Commit: $new_commit" $((cols-3)))"
        fi
    fi
    status_success "Repository updated"
}

# Build pihpsdr
build_pihpsdr() {
    render_section "piHPSDR Build"
    status_start "Cleaning build"
    cd "$PIHPSDR_DIR" || status_error "Cannot access: $PIHPSDR_DIR"

    {
        make clean > /tmp/clean_output 2>&1 &
        local clean_pid=$!
        progress_bar "$clean_pid" "Cleaning build" 10
        local clean_status=$?
        cat /tmp/clean_output
        if [ $clean_status -ne 0 ]; then
            status_error "make clean failed"
        fi
    }
    status_success "Build cleaned"

    status_start "Installing dependencies"
    if [ -f "$PIHPSDR_DIR/LINUX/libinstall.sh" ]; then
        if is_minimal_mode || [ "$USE_COLORS" != true ]; then
            printf "! %s\n" "$(truncate_text "Dependency installation may take several minutes" $((cols-2)))"
        else
            printf "${YELLOW}⚠ %s${NC}\n" "$(truncate_text "Dependency installation may take several minutes" $((cols-3)))"
        fi
        {
            bash "$PIHPSDR_DIR/LINUX/libinstall.sh" > /tmp/libinstall_output 2>&1 &
            local libinstall_pid=$!
            progress_bar "$libinstall_pid" "Installing dependencies" 400
            local libinstall_status=$?
            cat /tmp/libinstall_output
            if [ $libinstall_status -ne 0 ]; then
                status_error "Dependency installation failed"
            fi
        }
        status_success "Dependencies installed"
    else
        status_error "No libinstall.sh script found at $PIHPSDR_DIR/LINUX/libinstall.sh"
    fi

    status_start "Building piHPSDR"
    if [ "$GPIO_ENABLED" = "false" ]; then
        if is_minimal_mode || [ "$USE_COLORS" != true ]; then
            printf "> %s\n" "$(truncate_text "Building with GPIO disabled" $((cols-2)))"
        else
            printf "${BLUE}ℹ %s${NC}\n" "$(truncate_text "Building with GPIO disabled" $((cols-3)))"
        fi
        {
            sed -i 's/#CONTROLLER=NO_CONTROLLER/CONTROLLER=NO_CONTROLLER/' "$PIHPSDR_DIR/Makefile"
            make > /tmp/build_output 2>&1 &
            local build_pid=$!
            progress_bar "$build_pid" "Building piHPSDR" 200
            local build_status=$?
            cat /tmp/build_output
            if [ $build_status -ne 0 ]; then
                status_error "piHPSDR build failed"
            fi
        }
    else
        {
            make > /tmp/build_output 2>&1 &
            local build_pid=$!
            progress_bar "$build_pid" "Building piHPSDR" 200
            local build_status=$?
            cat /tmp/build_output
            if [ $build_status -ne 0 ]; then
                status_error "piHPSDR build failed"
            fi
        }
    fi
    status_success "piHPSDR built"
}

# Print summary report
print_summary_report() {
    local duration=$(( $(date +%s) - start_time ))
    render_section "Summary"
    local cols=$(get_term_size | cut -d' ' -f1)
    if is_minimal_mode || [ "$USE_COLORS" != true ]; then
        printf "+ %s\n" "$(truncate_text "Completed: $(date)" $((cols-2)))"
        printf "> %s\n" "$(truncate_text "Duration: $duration seconds" $((cols-2)))"
        printf "> %s\n" "$(truncate_text "Log: $LOG_FILE" $((cols-2)))"
        if [ "$BACKUP_CREATED" = true ]; then
            printf "+ %s\n" "$(truncate_text "Backup: $BACKUP_DIR" $((cols-2)))"
        else
            status_warning "No backup created"
        fi
    else
        printf "${GREEN}✔ %s${NC}\n" "$(truncate_text "Completed: $(date)" $((cols-3)))"
        printf "${BLUE}ℹ %s${NC}\n" "$(truncate_text "Duration: $duration seconds" $((cols-3)))"
        printf "${BLUE}ℹ %s${NC}\n" "$(truncate_text "Log: $LOG_FILE" $((cols-3)))"
        if [ "$BACKUP_CREATED" = true ]; then
            printf "${GREEN}✔ %s${NC}\n" "$(truncate_text "Backup: $BACKUP_DIR" $((cols-3)))"
        else
            status_warning "No backup created"
        fi
    fi
}

# System stats for footer
get_system_stats() {
    if is_minimal_mode || [ "$USE_COLORS" != true ]; then
        return
    fi
    local cpu=$(top -bn1 | head -n3 | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1)
    local mem=$(free -m | awk '/Mem:/ {print $3 "/" $2 "MB"}')
    local disk=$(df -h "$HOME" | tail -1 | awk '{print $3 "/" $2}')
    local cols=$(get_term_size | cut -d' ' -f1)
    printf "${BLUE}ℹ %s${NC}\n" "$(truncate_text "CPU: $cpu%% | Mem: $mem | Disk: $disk" $((cols-3)))"
}

# Main execution
main() {
    local start_time=$(date +%s)
    local BACKUP_CREATED=false

    init_logging

    # Parse arguments and print flag messages
    parse_args "$@"
    for msg in "${FLAG_MESSAGES[@]}"; do
        if [ "$USE_COLORS" = true ]; then
            case "$msg" in
                "Skipping Git update")
                    printf "${YELLOW}⚠ %s${NC}\n" "$msg"
                    ;;
                "Backup enabled via -y flag")
                    printf "${GREEN}✔ %s${NC}\n" "$msg"
                    ;;
                "Backup disabled via -n flag")
                    printf "${YELLOW}⚠ %s${NC}\n" "$msg"
                    ;;
                "GPIO disabled for Radioberry compatibility")
                    printf "${YELLOW}⚠ %s${NC}\n" "$msg"
                    ;;
            esac
        else
            case "$msg" in
                "Skipping Git update")
                    printf "! %s\n" "$msg"
                    ;;
                "Backup enabled via -y flag")
                    printf "+ %s\n" "$msg"
                    ;;
                "Backup disabled via -n flag")
                    printf "! %s\n" "$msg"
                    ;;
                "GPIO disabled for Radioberry compatibility")
                    printf "! %s\n" "$msg"
                    ;;
            esac
        fi
    done

    render_section "System Info"
    local cols=$(get_term_size | cut -d' ' -f1)
    local host_info=$(truncate_text "Host: $(hostname)" $((cols-3)))
    local user_info=$(truncate_text "User: $USER" $((cols-3)))
    local system_info=$(truncate_text "System: $(uname -srm)" $((cols-3)))
    local os_info=$(truncate_text "OS: $( [ -f /etc/os-release ] && grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"' || echo "Unknown" )" $((cols-3)))
    if is_minimal_mode || [ "$USE_COLORS" != true ]; then
        printf "> %s\n" "$host_info"
        printf "> %s\n" "$user_info"
        printf "> %s\n" "$system_info"
        printf "> %s\n" "$os_info"
    else
        printf "${BLUE}ℹ %s${NC}\n" "$host_info"
        printf "${BLUE}ℹ %s${NC}\n" "$user_info"
        printf "${BLUE}ℹ %s${NC}\n" "$system_info"
        printf "${BLUE}ℹ %s${NC}\n" "$os_info"
    fi

    check_requirements

    if [ -d "$PIHPSDR_DIR" ]; then
        if create_backup; then
            BACKUP_CREATED=true
        else
            BACKUP_CREATED=false
        fi
    fi

    update_git
    build_pihpsdr
    print_summary_report

    if [ "$USE_COLORS" = true ]; then
        printf "${CYAN}${BOLD}"
    fi
    render_top_section "$SCRIPT_NAME v$SCRIPT_VERSION Done"
    get_system_stats
    completion_animation
    printf "${NC}${RESET}\n"
}

# Run main
main "$@"
cd "$HOME"
