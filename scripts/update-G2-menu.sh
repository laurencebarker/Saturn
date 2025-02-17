#!/bin/bash
# update-G2.sh
# written by KD4YAL - thank you
# this script provides a menu of update operations.
# Pull repository and build p2app with error handling and status checks

#############################################
# Utility Functions
#############################################

# Function to print section headers
print_header() {
    clear
    echo "##############################################################"
    echo ""
    echo "$1"
    echo ""
    echo "##############################################################"
}

# Improved error handling with detailed messages
check_status() {
    local status=$?
    if [ $status -eq 0 ]; then
        echo "✓ $1 completed successfully"
        return 0
    else
        echo "✗ Error: $1 failed (error code: $status)"
        return $status
    fi
}

#############################################
# Base Directory Definitions
#############################################

SATURN_DIR="$HOME/github/Saturn"
PIHPSDR_DIR="$HOME/github/pihpsdr"

#############################################
# Helper Functions
#############################################

# Function to get current Git revision
get_git_revision() {
    (cd "$SATURN_DIR" 2>/dev/null && git rev-parse --short HEAD) || echo "Unknown"
}

# Function to find latest FPGA BIT file
get_fpga_bit_file() {
    (cd "$SATURN_DIR" 2>/dev/null && ./scripts/find-bin.sh) || echo "Not detected"
}

#############################################
# Core Task Functions
#############################################

update_libraries() {
    print_header "Updating System Libraries"
    if [ -f "$SATURN_DIR/scripts/install-libraries.sh" ]; then
        "$SATURN_DIR/scripts/install-libraries.sh"
        check_status "Library installation"
    else
        echo "Error: Library script not found"
        return 1
    fi
}

update_repository() {
    print_header "Updating Git Repository"
    cd "$SATURN_DIR" || return 1
    local current_commit
    current_commit=$(git rev-parse HEAD)
    git pull
    check_status "Git repository update"
    [ "$current_commit" != "$(git rev-parse HEAD)" ] && echo "New updates were fetched"
}

build_p2app() {
    print_header "Building p2app"
    if [ -f "$SATURN_DIR/scripts/update-p2app.sh" ]; then
        "$SATURN_DIR/scripts/update-p2app.sh"
        check_status "p2app build"
    else
        echo "Error: p2app build script not found"
        return 1
    fi
}

build_desktop_apps() {
    print_header "Building Desktop Applications"
    if [ -f "$SATURN_DIR/scripts/update-desktop-apps.sh" ]; then
        "$SATURN_DIR/scripts/update-desktop-apps.sh"
        check_status "Desktop apps build"
    else
        echo "Error: Desktop apps script not found"
        return 1
    fi
}

install_udev_rules() {
    print_header "Installing Udev Rules"
    if [ -f "$SATURN_DIR/rules/install-rules.sh" ]; then
        sudo "$SATURN_DIR/rules/install-rules.sh"
        check_status "Udev rules installation"
    else
        echo "Error: Udev rules script not found"
        return 1
    fi
}

copy_desktop_icons() {
    print_header "Copying Desktop Icons"
    if [ -d "$SATURN_DIR/desktop" ] && [ -d "$HOME/Desktop" ]; then
        cp -v "$SATURN_DIR"/desktop/* "$HOME/Desktop/"
        check_status "Desktop icons copy"
    else
        echo "Error: Desktop directory missing"
        return 1
    fi
}

check_fpga_bit_file() {
    print_header "Verifying FPGA BIT File"
    get_fpga_bit_file
    check_status "FPGA file check"
}

build_pihpsdr() {
    print_header "Building pihpsdr"
    if [ -d "$PIHPSDR_DIR" ]; then
        cd "$PIHPSDR_DIR" || return 1
        make clean
        check_status "Clean build" || return 1
        git pull
        check_status "Repository update" || return 1
        make
        check_status "pihpsdr compilation"
    else
        echo "Error: pihpsdr directory missing"
        return 1
    fi
}

perform_all_tasks() {
    local status=0
    update_libraries || status=$?
    update_repository || status=$?
    build_p2app || status=$?
    build_desktop_apps || status=$?
    install_udev_rules || status=$?
    copy_desktop_icons || status=$?
    check_fpga_bit_file || status=$?
    build_pihpsdr || status=$?
    return $status
}

#############################################
# run_function Wrapper for GUI Feedback
#############################################

run_function() {
    local func=$1
    # Capture the function's output
    local output
    output=$($func 2>&1)
    local status=$?

    # Write output to a temporary file
    local tmpfile
    tmpfile=$(mktemp /tmp/operation_results.XXXXXX)
    {
        echo "Results of '$func':"
        echo "----------------------------------------"
        echo "$output"
        echo "----------------------------------------"
        if [ $status -eq 0 ]; then
            echo "SUCCESS"
        else
            echo "FAILED (code: $status)"
        fi
    } > "$tmpfile"

    # Display the results using whiptail --textbox
    whiptail --title "Operation Results" --scrolltext --textbox "$tmpfile" 20 60
    rm "$tmpfile"
}

#############################################
# GUI Menu System
#############################################

main_menu() {
    while true; do
        local GIT_REVISION FPGA_BIT_FILE
        GIT_REVISION=$(get_git_revision)
        FPGA_BIT_FILE=$(get_fpga_bit_file)

        local choice
        choice=$(whiptail --title "Saturn Update System" \
            --menu "Current Status:\n\nGit Revision: $GIT_REVISION\nFPGA Firmware: $FPGA_BIT_FILE" \
            22 60 12 \
            "1" "Update System Libraries" \
            "2" "Update Software Repository" \
            "3" "Build p2app" \
            "4" "Build Desktop Apps" \
            "5" "Install Device Rules" \
            "6" "Update Desktop Icons" \
            "7" "Verify FPGA Files" \
            "8" "Build pihpsdr" \
            "9" "Complete System Update" \
            "10" "Exit Program" 3>&1 1>&2 2>&3)

        case $choice in
            1) run_function "update_libraries" ;;
            2) run_function "update_repository" ;;
            3) run_function "build_p2app" ;;
            4) run_function "build_desktop_apps" ;;
            5) run_function "install_udev_rules" ;;
            6) run_function "copy_desktop_icons" ;;
            7) run_function "check_fpga_bit_file" ;;
            8) run_function "build_pihpsdr" ;;
            9) run_function "perform_all_tasks" ;;
            10) break ;;
            *) whiptail --msgbox "Invalid selection" 10 60 ;;
        esac
    done
}

#############################################
# Initialization and Start-up
#############################################

# Verify required directory structure
if [ ! -d "$SATURN_DIR" ]; then
    whiptail --title "Critical Error" --msgbox "Saturn directory not found at:\n$SATURN_DIR" 10 60
    exit 1
fi

cd "$SATURN_DIR" || exit 1

# Launch the main GUI menu
main_menu

# Final system message after menu exit
print_header "Update Process Complete"
echo "Recommended actions:"
echo "1. Restart affected services"
echo "2. Check desktop shortcuts"
echo "3. Verify FPGA version if updated"
echo ""
echo "System will return to user prompt..."
cd "$HOME" || exit 1
