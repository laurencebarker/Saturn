#!/bin/bash
# start_server.sh - Starts Flask server with Gunicorn and verifies endpoints for Saturn Update Manager
# Version: 1.12
# Written by: Jerry DeLong KD4YAL
# Changes: Increased Gunicorn workers to 5 for better concurrency, switched to gevent worker class for async/non-blocking handling (requires gevent installed), updated version to 1.12
# Added robust port release waiting with polling loop after termination to ensure port is fully free before starting Gunicorn.
# Used Gunicorn --pid option for reliable PID capture.
# Updated wait_for_port_free to use netstat polling and fuser -k before start.
# After start, check if port listening, then get PID from lsof if not in file.
# Dependencies: gunicorn, curl, netstat, lsof, ss, gevent (pip install gevent in venv)
# Usage: Called by setup_saturn_webserver.sh

set -e

# Paths
VENV_PATH="/home/pi/venv"
LOG_DIR="/home/pi/saturn-logs"
LOG_FILE="$LOG_DIR/setup_saturn_webserver-$(date +%Y%m%d-%H%M%S).log"
SCRIPTS_DIR="/home/pi/scripts"
SATURN_SCRIPT="$SCRIPTS_DIR/saturn_update_manager.py"
PORT=5000
FALLBACK_PORT=5001
USER="admin"
TEST_PASSWD="password123"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to log and echo output
log_and_echo() {
    echo -e "$1" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Ensure log directory exists with correct permissions
mkdir -p "$LOG_DIR"
chown pi:pi "$LOG_DIR"
chmod 775 "$LOG_DIR"

# Function to stop existing server on port
stop_existing_server() {
    local port=$1
    log_and_echo "${CYAN}Checking for existing server on port $port...${NC}"
    local max_attempts=3 attempt=1
    while [ $attempt -le $max_attempts ]; do
        if netstat -tuln | grep ":$port " >/dev/null; then
            log_and_echo "${YELLOW}Port $port is in use. Attempt $attempt/$max_attempts to terminate process...${NC}"
            PIDS=$(lsof -t -i:$port 2>/dev/null || ss -tuln -p | grep ":$port" | grep -o 'pid=[0-9]\+' | grep -o '[0-9]\+' | sort -u 2>/dev/null)
            if [ -n "$PIDS" ]; then
                for pid in $PIDS; do
                    if kill -0 "$pid" 2>/dev/null; then
                        kill -9 "$pid" 2>/dev/null
                        log_and_echo "${GREEN}Terminated process $pid on port $port${NC}"
                    else
                        log_and_echo "${YELLOW}Process $pid not running, cleaning up stale PID${NC}"
                    fi
                done
                sleep 3
                if ! netstat -tuln | grep ":$port " >/dev/null; then
                    log_and_echo "${GREEN}Port $port is free${NC}"
                    return 0
                fi
            else
                log_and_echo "${YELLOW}No PIDs found for port $port, attempting to free port...${NC}"
                fuser -k -n tcp $port 2>/dev/null || true
                sleep 3
                if ! netstat -tuln | grep ":$port " >/dev/null; then
                    log_and_echo "${GREEN}Port $port is free${NC}"
                    return 0
                fi
            fi
        else
            log_and_echo "${GREEN}Port $port is free${NC}"
            return 0
        fi
        attempt=$((attempt + 1))
    done
    log_and_echo "${RED}Error: Port $port still in use after $max_attempts attempts${NC}"
    exit 1
}

# Function to wait until port is free
wait_for_port_free() {
    local port=$1
    local max_wait=60  # Max wait time in seconds
    local wait_time=0
    log_and_echo "${CYAN}Waiting for port $port to be fully released...${NC}"
    while netstat -tuln | grep ":$port " >/dev/null && [ $wait_time -lt $max_wait ]; do
        fuser -k -n tcp $port 2>/dev/null || true
        sleep 1
        wait_time=$((wait_time + 1))
    done
    if [ $wait_time -ge $max_wait ]; then
        log_and_echo "${RED}Error: Port $port not released after $max_wait seconds${NC}"
        exit 1
    fi
    log_and_echo "${GREEN}Port $port confirmed free${NC}"
}

# Function to verify Flask endpoints
verify_flask_endpoints() {
    local max_attempts=5 attempt=1
    while [ $attempt -le $max_attempts ]; do
        if netstat -tuln | grep ":$PORT " >/dev/null; then
            log_and_echo "${GREEN}Server confirmed listening on port $PORT with PID $SERVER_PID${NC}"
            # /ping endpoint
            local flask_ping_body
            flask_ping_body=$(curl -s --connect-timeout 5 "http://127.0.0.1:$PORT/ping")
            local flask_ping_verbose
            flask_ping_verbose=$(curl -s -v --connect-timeout 5 "http://127.0.0.1:$PORT/ping" 2>&1)
            touch "$LOG_DIR/flask_ping_response.log"
            chown pi:pi "$LOG_DIR/flask_ping_response.log"
            chmod 664 "$LOG_DIR/flask_ping_response.log"
            echo "$flask_ping_verbose" > "$LOG_DIR/flask_ping_response.log"
            if echo "$flask_ping_body" | grep -q "pong"; then
                log_and_echo "${GREEN}Flask /ping endpoint passed${NC}"
            else
                log_and_echo "${RED}Error: Flask /ping endpoint failed${NC}"
                log_and_echo "${YELLOW}Response saved to $LOG_DIR/flask_ping_response.log${NC}"
                cat "$FLASK_LOG" "$FLASK_ERROR_LOG" >> "$LOG_FILE"
                exit 1
            fi
            # /saturn/ endpoint
            local flask_saturn_body
            flask_saturn_body=$(curl -s --connect-timeout 5 "http://127.0.0.1:$PORT/saturn/")
            local flask_saturn_verbose
            flask_saturn_verbose=$(curl -s -v --connect-timeout 5 "http://127.0.0.1:$PORT/saturn/" 2>&1)
            touch "$LOG_DIR/flask_saturn_response.log"
            chown pi:pi "$LOG_DIR/flask_saturn_response.log"
            chmod 664 "$LOG_DIR/flask_saturn_response.log"
            echo "$flask_saturn_verbose" > "$LOG_DIR/flask_saturn_response.log"
            if echo "$flask_saturn_body" | grep -q "Saturn Update Manager" && echo "$flask_saturn_body" | grep -q "script-form"; then
                log_and_echo "${GREEN}Flask /saturn/ endpoint passed${NC}"
            else
                log_and_echo "${RED}Error: Flask /saturn/ endpoint failed - expected content not found${NC}"
                log_and_echo "${YELLOW}Response saved to $LOG_DIR/flask_saturn_response.log${NC}"
                cat "$FLASK_LOG" "$FLASK_ERROR_LOG" >> "$LOG_FILE"
                exit 1
            fi
            # /saturn/get_scripts endpoint
            local flask_scripts_body
            flask_scripts_body=$(curl -s --connect-timeout 5 "http://127.0.0.1:$PORT/saturn/get_scripts")
            local flask_scripts_verbose
            flask_scripts_verbose=$(curl -s -v --connect-timeout 5 "http://127.0.0.1:$PORT/saturn/get_scripts" 2>&1)
            touch "$LOG_DIR/flask_scripts_response.log"
            chown pi:pi "$LOG_DIR/flask_scripts_response.log"
            chmod 664 "$LOG_DIR/flask_scripts_response.log"
            echo "$flask_scripts_verbose" > "$LOG_DIR/flask_scripts_response.log"
            if echo "$flask_scripts_body" | grep -q '"scripts":' && echo "$flask_scripts_body" | grep -q "update-G2.py" && echo "$flask_scripts_body" | grep -q "update-pihpsdr.py"; then
                log_and_echo "${GREEN}Flask /saturn/get_scripts endpoint passed${NC}"
            else
                log_and_echo "${RED}Error: Flask /saturn/get_scripts endpoint failed - expected scripts not found${NC}"
                log_and_echo "${YELLOW}Response saved to $LOG_DIR/flask_scripts_response.log${NC}"
                cat "$FLASK_LOG" "$FLASK_ERROR_LOG" >> "$LOG_FILE"
                exit 1
            fi
            # /saturn/get_versions endpoint
            local flask_versions_body
            flask_versions_body=$(curl -s --connect-timeout 5 "http://127.0.0.1:$PORT/saturn/get_versions")
            local flask_versions_verbose
            flask_versions_verbose=$(curl -s -v --connect-timeout 5 "http://127.0.0.1:$PORT/saturn/get_versions" 2>&1)
            touch "$LOG_DIR/flask_versions_response.log"
            chown pi:pi "$LOG_DIR/flask_versions_response.log"
            chmod 664 "$LOG_DIR/flask_versions_response.log"
            echo "$flask_versions_verbose" > "$LOG_DIR/flask_versions_response.log"
            if echo "$flask_versions_body" | grep -q '"versions":' && echo "$flask_versions_body" | grep -q "saturn_update_manager.py" && echo "$flask_versions_body" | grep -q "update-G2.py" && echo "$flask_versions_body" | grep -q "update-pihpsdr.py"; then
                log_and_echo "${GREEN}Flask /saturn/get_versions endpoint passed${NC}"
            else
                log_and_echo "${RED}Error: Flask /saturn/get_versions endpoint failed - expected versions not found${NC}"
                log_and_echo "${YELLOW}Response saved to $LOG_DIR/flask_versions_response.log${NC}"
                cat "$FLASK_LOG" "$FLASK_ERROR_LOG" >> "$LOG_FILE"
                exit 1
            fi
            local private_ip
            private_ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n1)
            if [ -z "$private_ip" ]; then
                log_and_echo "${RED}Error: Failed to detect private IP address${NC}"
                exit 1
            fi
            local no_auth_response
            no_auth_response=$(curl -s -v -I "http://$private_ip/saturn/" --max-time 5 2>&1)
            local no_auth_status
            no_auth_status=$(curl -s -I "http://$private_ip/saturn/" --max-time 5 2>/dev/null | grep -E '^HTTP/' | awk '{print $2}')
            touch "$LOG_DIR/apache_auth_response.log"
            chown pi:pi "$LOG_DIR/apache_auth_response.log"
            chmod 664 "$LOG_DIR/apache_auth_response.log"
            echo "$no_auth_response" > "$LOG_DIR/apache_auth_response.log"
            if [ "$no_auth_status" = "401" ]; then
                log_and_echo "${GREEN}Authentication prompt test passed (401 Unauthorized without credentials)${NC}"
            else
                log_and_echo "${RED}Error: Authentication prompt test failed - HTTP status: $no_auth_status${NC}"
                log_and_echo "${YELLOW}Response saved to $LOG_DIR/apache_auth_response.log${NC}"
                log_and_echo "${YELLOW}No auth response: $no_auth_response${NC}"
                log_and_echo "${RED}Check Apache error log: /var/log/apache2/saturn_error.log${NC}"
                exit 1
            fi
            local auth_response
            auth_response=$(curl -s -v -u "$USER:$TEST_PASSWD" "http://$private_ip/saturn/" --max-time 5 2>&1)
            local auth_status
            auth_status=$(curl -s -I -u "$USER:$TEST_PASSWD" "http://$private_ip/saturn/" --max-time 5 2>/dev/null | grep -E '^HTTP/' | awk '{print $2}')
            touch "$LOG_DIR/auth_response.log"
            chown pi:pi "$LOG_DIR/auth_response.log"
            chmod 664 "$LOG_DIR/auth_response.log"
            echo "$auth_response" > "$LOG_DIR/auth_response.log"
            if [ "$auth_status" = "200" ]; then
                local auth_content
                auth_content=$(curl -u "$USER:$TEST_PASSWD" -s "http://$private_ip/saturn/" --max-time 5)
                touch "$LOG_DIR/auth_content.log"
                chown pi:pi "$LOG_DIR/auth_content.log"
                chmod 664 "$LOG_DIR/auth_content.log"
                echo "$auth_content" > "$LOG_DIR/auth_content.log"
                if echo "$auth_content" | grep -q "Saturn Update Manager" && echo "$auth_content" | grep -q "script-form"; then
                    log_and_echo "${GREEN}Authentication and Flask proxy test passed${NC}"
                else
                    log_and_echo "${RED}Error: Flask proxy test failed - expected content not found${NC}"
                    log_and_echo "${YELLOW}Response saved to $LOG_DIR/auth_content.log${NC}"
                    log_and_echo "${YELLOW}Authenticated response: $auth_response${NC}"
                    log_and_echo "${RED}Check Apache error log: /var/log/apache2/saturn_error.log${NC}"
                    exit 1
                fi
            else
                log_and_echo "${RED}Error: Authentication test failed - HTTP status: $auth_status${NC}"
                log_and_echo "${YELLOW}Response saved to $LOG_DIR/auth_response.log${NC}"
                log_and_echo "${YELLOW}Authenticated response: $auth_response${NC}"
                log_and_echo "${RED}Check Apache error log: /var/log/apache2/saturn_error.log${NC}"
                exit 1
            fi
            log_and_echo "${GREEN}Flask server and Apache proxy validated successfully${NC}"
            return 0
        fi
        log_and_echo "${YELLOW}Port $PORT not listening, attempt $attempt/$max_attempts${NC}"
        sleep 2
        attempt=$((attempt + 1))
    done
    log_and_echo "${RED}Error: Server failed to start on port $PORT after $max_attempts attempts${NC}"
    log_and_echo "${YELLOW}Gunicorn logs: $FLASK_LOG, $FLASK_ERROR_LOG${NC}"
    cat "$FLASK_LOG" "$FLASK_ERROR_LOG" >> "$LOG_FILE"
    exit 1
}

# Verify virtual environment and dependencies
log_and_echo "${CYAN}Verifying virtual environment and dependencies...${NC}"
if [ ! -d "$VENV_PATH" ]; then
    log_and_echo "${RED}Error: Virtual environment not found at $VENV_PATH${NC}"
    exit 1
fi
if ! sudo -u pi bash -c ". $VENV_PATH/bin/activate && python3 -c 'import flask, ansi2html, psutil, pyfiglet, gunicorn, urllib.error, gevent' && which gunicorn" 2>/dev/null; then
    log_and_echo "${RED}Error: Missing Python dependencies or gunicorn/gevent not installed${NC}"
    exit 1
fi
log_and_echo "${GREEN}Virtual environment and dependencies verified${NC}"

# Verify saturn_update_manager.py exists
log_and_echo "${CYAN}Verifying saturn_update_manager.py exists...${NC}"
if [ ! -f "$SATURN_SCRIPT" ]; then
    log_and_echo "${RED}Error: saturn_update_manager.py not found at $SATURN_SCRIPT${NC}"
    exit 1
fi
log_and_echo "${GREEN}saturn_update_manager.py verified${NC}"

# Start web server
log_and_echo "${CYAN}Starting web server on port $PORT...${NC}"
stop_existing_server $PORT
wait_for_port_free $PORT  # Add this call to wait robustly
stop_existing_server $FALLBACK_PORT
FLASK_LOG="$LOG_DIR/saturn-update-manager-$(date +%Y%m%d-%H%M%S).log"
FLASK_ERROR_LOG="$LOG_DIR/saturn-update-manager-error-$(date +%Y%m%d-%H%M%S).log"
touch "$FLASK_LOG" "$FLASK_ERROR_LOG"
chown pi:pi "$FLASK_LOG" "$FLASK_ERROR_LOG"
chmod 664 "$FLASK_LOG" "$FLASK_ERROR_LOG"

log_and_echo "${CYAN}Starting Flask server with gunicorn...${NC}"
pkill -u pi -f "gunicorn.*saturn_update_manager:app" 2>/dev/null || true
sleep 2
fuser -k -n tcp $PORT 2>/dev/null || true  # Final fuser before start
# Set PYTHONPATH to include SCRIPTS_DIR
log_and_echo "${CYAN}Setting PYTHONPATH to $SCRIPTS_DIR${NC}"
sudo -u pi bash -c "export PYTHONPATH=$SCRIPTS_DIR:\$PYTHONPATH && . $VENV_PATH/bin/activate && gunicorn -w 5 --worker-class gevent -b 0.0.0.0:$PORT -t 600 saturn_update_manager:app >> $FLASK_LOG 2>> $FLASK_ERROR_LOG & echo \$! > /tmp/saturn-flask.pid"
sleep 15  # Increased delay to ensure Gunicorn starts and writes PID
SERVER_PID=""
if [ -f "/tmp/saturn-flask.pid" ]; then
    TEMP_PID=$(cat /tmp/saturn-flask.pid)
    rm -f /tmp/saturn-flask.pid
    if ps -p "$TEMP_PID" >/dev/null 2>&1; then
        SERVER_PID=$TEMP_PID
    fi
fi
if [ -z "$SERVER_PID" ]; then
    # Fallback to lsof if PID file failed
    sleep 5  # Additional wait for listening
    SERVER_PID=$(lsof -ti :$PORT -sTCP:LISTEN 2>/dev/null | sort | head -n1)
fi
if [ -z "$SERVER_PID" ] || ! ps -p "$SERVER_PID" >/dev/null 2>&1 || ! netstat -tuln | grep ":$PORT " >/dev/null; then
    log_and_echo "${RED}Error: Failed to start Gunicorn or obtain valid SERVER_PID${NC}"
    log_and_echo "${YELLOW}Gunicorn logs: $FLASK_LOG, $FLASK_ERROR_LOG${NC}"
    cat "$FLASK_LOG" "$FLASK_ERROR_LOG" >> "$LOG_FILE"
    exit 1
fi
log_and_echo "${GREEN}Gunicorn started with PID $SERVER_PID${NC}"

# Verify Flask server
log_and_echo "${CYAN}Validating Flask server...${NC}"
if ! [ -f "$SCRIPTS_DIR/update-G2.py" ] || ! [ -f "$SCRIPTS_DIR/update-pihpsdr.py" ]; then
    log_and_echo "${RED}Error: Missing update-G2.py or update-pihpsdr.py in $SCRIPTS_DIR${NC}"
    exit 1
fi

# Call endpoint verification function
verify_flask_endpoints
