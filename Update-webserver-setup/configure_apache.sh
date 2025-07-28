#!/bin/bash
# configure_apache.sh - Configures Apache as a reverse proxy for Saturn Update Manager
# Version: 1.3
# Written by: Jerry DeLong KD4YAL
# Changes: Moved Timeout directive outside <Location> to VirtualHost context (as it's not allowed in <Location>), kept SetEnv for chunked/no-keepalive, increased timeouts to 3600s, updated version to 1.3
# Dependencies: apache2, apache2-utils
# Usage: Called by setup_saturn_webserver.sh

set -e

# Paths
WEB_DIR="/var/www/html"
HTPASSWD_FILE="/etc/apache2/.htpasswd"
USER="admin"
TEST_PASSWD="password123"
LOG_DIR="/home/pi/saturn-logs"
LOG_FILE="$LOG_DIR/setup_saturn_webserver-$(date +%Y%m%d-%H%M%S).log"
PORT=5000

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

# Function to get subnet
get_subnet() {
    local INTERFACES=("eth0" "wlan0")
    for iface in "${INTERFACES[@]}"; do
        if ip a show "$iface" >/dev/null 2>&1; then
            INET=$(ip a show "$iface" | grep "inet " | grep -v "inet6" | awk '{print $2}')
            if [ -n "$INET" ]; then
                IP=${INET%%/*}
                MASK=${INET##*/}
                if [[ $IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && [ "$IP" != "0.0.0.0" ]; then
                    IFS='.' read -r i1 i2 i3 i4 <<< "$IP"
                    if [ "$i1" -le 255 ] && [ "$i2" -le 255 ] && [ "$i3" -le 255 ] && [ "$i4" -le 255 ]; then
                        NETMASK=$(( 0xffffffff ^ ((1 << (32 - MASK)) - 1) ))
                        N1=$(( i1 & (NETMASK >> 24) ))
                        N2=$(( i2 & (NETMASK >> 16 & 0xff) ))
                        N3=$(( i3 & (NETMASK >> 8 & 0xff) ))
                        N4=$(( i4 & (NETMASK & 0xff) ))
                        SUBNET="${N1}.${N2}.${N3}.${N4}/${MASK}"
                        log_and_echo "${GREEN}Found subnet: $SUBNET on $iface${NC}" >&2
                        echo "$SUBNET"
                        return 0
                    fi
                fi
            fi
        fi
    done
    log_and_echo "${YELLOW}No valid network interface found, falling back to localhost${NC}" >&2
    echo "127.0.0.1/32"
    return 1
}

# Configure Apache
log_and_echo "${CYAN}Configuring Apache as reverse proxy...${NC}"
SUBNET=$(get_subnet)
if ! [[ $SUBNET =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    log_and_echo "${RED}Error: Invalid subnet detected: $SUBNET${NC}"
    exit 1
fi
log_and_echo "${CYAN}Using subnet: $SUBNET${NC}"

# Remove existing .htpasswd
[ -f "$HTPASSWD_FILE" ] && rm -f "$HTPASSWD_FILE"
log_and_echo "${CYAN}Creating .htpasswd file for user $USER with default password...${NC}"
htpasswd -cb "$HTPASSWD_FILE" "$USER" "$TEST_PASSWD"
chown root:www-data "$HTPASSWD_FILE"
chmod 640 "$HTPASSWD_FILE"

if sudo -u www-data test -r "$HTPASSWD_FILE"; then
    log_and_echo "${GREEN}.htpasswd is readable by Apache${NC}"
else
    log_and_echo "${RED}Error: .htpasswd is not readable by Apache user${NC}"
    exit 1
fi

APACHE_CONF="/etc/apache2/sites-available/saturn.conf"
cat > "$APACHE_CONF" << EOF
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot $WEB_DIR
    ProxyRequests Off
    ProxyPreserveHost On
    ProxyTimeout 3600
    Timeout 3600
    LogLevel proxy:debug
    ErrorLog \${APACHE_LOG_DIR}/saturn_error.log
    CustomLog \${APACHE_LOG_DIR}/saturn_access.log combined
    ProxyPass /saturn/ http://127.0.0.1:$PORT/saturn/ nocanon
    ProxyPassReverse /saturn/ http://127.0.0.1:$PORT/saturn/
    ProxyPassReverseCookiePath /saturn/ /saturn/
    <Location /saturn/>
        AuthType Basic
        AuthName "Saturn Update Manager - Restricted Access"
        AuthUserFile $HTPASSWD_FILE
        Allow from 127.0.0.0/8
        <RequireAll>
            Require valid-user
            Require ip $SUBNET
        </RequireAll>
        SetEnv proxy-sendchunked 1
        SetEnv proxy-nokeepalive 1
    </Location>
    <Directory $WEB_DIR>
        Options -Indexes
        Require all denied
    </Directory>
</VirtualHost>
EOF
ln -sf "$APACHE_CONF" /etc/apache2/sites-enabled/saturn.conf
find /etc/apache2/sites-enabled -type l -not -name "saturn.conf" -delete
a2enmod proxy proxy_http auth_basic authn_file authz_core
echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf
a2enconf servername
if apache2ctl configtest; then
    log_and_echo "${GREEN}Apache configuration test passed${NC}"
else
    log_and_echo "${RED}Error: Apache configuration test failed${NC}"
    exit 1
fi
rm -rf /var/cache/apache2/*
systemctl restart apache2
log_and_echo "${GREEN}Apache restarted${NC}"
