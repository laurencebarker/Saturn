#!/bin/bash
# start_server_buster.sh - Starts saturn_update_manager.py with Gunicorn and verifies endpoints on Buster
# Version: 1.7
# Written by: Jerry DeLong KD4YAL
# Changes: Increased Gunicorn workers to 5 for better concurrency, switched to gevent worker class for async/non-blocking handling (requires gevent installed), updated version to 1.7
# Dependencies: bash, gunicorn, curl, gevent (pip install gevent in venv)
# Usage: Called by setup_saturn_webserver.sh on Buster systems

set -e

# Paths
VENV_PATH="/home/pi/venv"
SCRIPTS_DIR="/home/pi/scripts"
LOG_DIR="/home/pi/saturn-logs"
LOG_FILE="$LOG_DIR/setup_saturn_webserver-$(date +%Y%m%d-%H%M%S).log"
SERVER_PID_FILE="/home/pi/saturn-logs/saturn-update-manager.pid"
GUNICORN_LOG="$LOG_DIR/saturn-update-manager-$(date +%Y%m%d-%H%M%S).log"
GUNICORN_ERROR_LOG="$LOG_DIR/saturn-update-manager-error-$(date +%Y%m%d-%H%M%S).log"
FLASK_LOG="$LOG_DIR/flask_$(date +%Y%m%d-%H%M%S).log"
AUTH_LOG="$LOG_DIR/auth_$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to log and echo output
log_and_echo() {
    echo -e "$1" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Verify virtual environment and dependencies
log_and_echo "${CYAN}Verifying virtual environment and dependencies...${NC}"
if [ ! -d "$VENV_PATH" ] || ! sudo -u pi $VENV_PATH/bin/gunicorn --version > /dev/null 2>&1; then
  log_and_echo "${RED}Error: Missing Python dependencies or gunicorn not installed${NC}"
  exit 1
fi

ANSI_VERSION=$(sudo -u pi $VENV_PATH/bin/python -c "import ansi2html; print(ansi2html.__version__)" | tail -1 | tr -d '\r\n')
if [ "$ANSI_VERSION" = "1.9.2" ]; then
  log_and_echo "${GREEN}ansi2html version verified: $ANSI_VERSION${NC}"
else
  log_and_echo "${RED}Error: Incorrect ansi2html version. Expected 1.9.2, got $ANSI_VERSION${NC}"
  exit 1
fi

# Check for gevent
GEVENT_VERSION=$(sudo -u pi $VENV_PATH/bin/python -c "import gevent; print(gevent.__version__)" | tail -1 | tr -d '\r\n' 2>/dev/null || echo "not installed")
if [ "$GEVENT_VERSION" != "not installed" ]; then
  log_and_echo "${GREEN}gevent version verified: $GEVENT_VERSION${NC}"
else
  log_and_echo "${RED}Error: gevent not installed in virtual environment${NC}"
  exit 1
fi

log_and_echo "${GREEN}Virtual environment and dependencies verified${NC}"

# Kill existing Gunicorn process if running
log_and_echo "${CYAN}Stopping any existing Flask server...${NC}"
pkill -f gunicorn || true
log_and_echo "${GREEN}Existing server stopped (if running)${NC}"

# Start Flask server with Gunicorn as pi user
log_and_echo "${CYAN}Starting Flask server with Gunicorn...${NC}"
sudo -u pi nohup $VENV_PATH/bin/gunicorn --chdir $SCRIPTS_DIR -w 5 --worker-class gevent -b 0.0.0.0:5000 -t 600 saturn_update_manager:app > "$GUNICORN_LOG" 2> "$GUNICORN_ERROR_LOG" &
SERVER_PID=$!
echo $SERVER_PID > "$SERVER_PID_FILE"
log_and_echo "${GREEN}Flask server started with PID $SERVER_PID. Logs: $GUNICORN_LOG and $GUNICORN_ERROR_LOG${NC}"

# Wait for server to start (increased for gevent/multi-worker startup)
sleep 30

# Verify Flask endpoints
log_and_echo "${CYAN}Verifying Flask endpoints...${NC}"
private_ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n1)
curl -s -u admin:password123 http://$private_ip/saturn/get_versions > "$FLASK_LOG" 2>&1 || { log_and_echo "${RED}Error: Flask /saturn/get_versions endpoint failed. Response: $(cat "$FLASK_LOG")${NC}"; exit 1; }
if grep -q '"saturn_update_manager.py":"2.22"' "$FLASK_LOG"; then
  log_and_echo "${GREEN}/saturn/get_versions endpoint verified${NC}"
else
  log_and_echo "${RED}Error: Flask /saturn/get_versions endpoint failed - expected versions not found. Response: $(cat "$FLASK_LOG")${NC}"
  exit 1
fi

# Verify Apache authentication
curl -s -u admin:password123 http://$private_ip/saturn/ > "$AUTH_LOG" 2>&1 || { log_and_echo "${RED}Error: Apache authentication failed. Response: $(cat "$AUTH_LOG")${NC}"; exit 1; }
if grep -q "Saturn Update Manager" "$AUTH_LOG"; then
  log_and_echo "${GREEN}Apache authentication and endpoint access verified${NC}"
else
  log_and_echo "${RED}Error: Apache authentication failed or index.html not served. Response: $(cat "$AUTH_LOG")${NC}"
  exit 1
fi

log_and_echo "${GREEN}Server started and verified successfully${NC}"
