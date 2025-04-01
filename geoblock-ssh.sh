#!/bin/bash
#
# GeoBlock SSH - A script to block SSH connections from specific countries
# 
# Usage: 
#   ./geoblock-ssh.sh install      - Install dependencies and set up the script
#   ./geoblock-ssh.sh block COUNTRY_CODE  - Block a country (e.g., CN for China)
#   ./geoblock-ssh.sh unblock COUNTRY_CODE - Unblock a country
#   ./geoblock-ssh.sh list         - List currently blocked countries
#   ./geoblock-ssh.sh status       - Check if the service is active
#   ./geoblock-ssh.sh help         - Show this help message

# Configuration
GEOIP_DIR="/usr/share/iptables-geoip"
BLOCK_LIST="/etc/geoblock-ssh/blocked-countries.conf"
CHAIN_NAME="GEOBLOCK-SSH"
SSH_PORT="22"  # Default SSH port - change if your SSH runs on a different port

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}" >&2
    exit 1
fi

# Function to display help message
show_help() {
    echo -e "${BLUE}GeoBlock SSH - Block SSH connections from specific countries${NC}"
    echo
    echo "Usage:"
    echo "  $0 install                   - Install dependencies and set up the script"
    echo "  $0 block COUNTRY_CODE        - Block a country (e.g., CN for China)"
    echo "  $0 unblock COUNTRY_CODE      - Unblock a country"
    echo "  $0 list                      - List currently blocked countries"
    echo "  $0 status                    - Check if the service is active"
    echo "  $0 help                      - Show this help message"
    echo
    echo "Examples:"
    echo "  $0 install"
    echo "  $0 block RU                  - Block SSH connections from Russia"
    echo "  $0 block CN KP               - Block China and North Korea"
    echo "  $0 unblock RU                - Allow SSH connections from Russia again"
    echo "  $0 list                      - Show all currently blocked countries"
}

# Function to install dependencies
install_dependencies() {
    echo -e "${BLUE}Installing dependencies...${NC}"
    
    # Create necessary directories
    mkdir -p "$GEOIP_DIR"
    mkdir -p "$(dirname "$BLOCK_LIST")"
    touch "$BLOCK_LIST"
    
    # Install required packages based on distribution
    if [ -f /etc/debian_version ]; then
        apt-get update
        apt-get install -y iptables ipset curl unzip gawk iptables-persistent
    elif [ -f /etc/redhat-release ]; then
        yum install -y iptables ipset curl unzip gawk iptables-services
        systemctl enable iptables
    else
        echo -e "${RED}Unsupported distribution. Please install iptables, ipset, curl, unzip, and gawk manually.${NC}"
        return 1
    fi
    
    # Download GeoIP database
    echo -e "${BLUE}Downloading GeoIP database...${NC}"
    curl -s -o "/tmp/dbip-country-lite.csv.gz" "https://download.db-ip.com/free/dbip-country-lite-$(date +"%Y-%m").csv.gz"
    gunzip -f "/tmp/dbip-country-lite.csv.gz"
    
    # Create country IP lists directory
    mkdir -p "$GEOIP_DIR/lists"
    
    # Create startup service
    create_service
    
    echo -e "${GREEN}Installation complete!${NC}"
    echo -e "${YELLOW}You can now start blocking countries with:${NC}"
    echo -e "${YELLOW}  $0 block COUNTRY_CODE${NC}"
    return 0
}

# Function to create systemd service for persistence
create_service() {
    echo -e "${BLUE}Creating startup service...${NC}"
    
    cat > /etc/systemd/system/geoblock-ssh.service << EOF
[Unit]
Description=GeoBlock SSH - Block SSH connections from specific countries
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash $PWD/$(basename "$0") apply
RemainAfterExit=true
ExecStop=/bin/bash $PWD/$(basename "$0") clear

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable geoblock-ssh.service
    systemctl start geoblock-ssh.service
    
    echo -e "${GREEN}Service created and enabled!${NC}"
}

# Function to extract IP ranges for a country
extract_country_ips() {
    local country_code="$1"
    local output_file="$GEOIP_DIR/lists/$country_code.zone"
    
    echo -e "${BLUE}Extracting IP ranges for $country_code...${NC}"
    
    # Check if the database exists
    if [ ! -f "/tmp/dbip-country-lite.csv" ]; then
        echo -e "${RED}GeoIP database not found. Please run 'install' first.${NC}"
        return 1
    fi
    
    # Extract IP ranges for the specified country
    awk -F, -v cc="\"$country_code\"" '$3 == cc {print $1 "-" $2}' "/tmp/dbip-country-lite.csv" > "$output_file"
    
    # Check if any IPs were found
    if [ ! -s "$output_file" ]; then
        echo -e "${RED}No IP ranges found for country code $country_code${NC}"
        rm "$output_file"
        return 1
    fi
    
    echo -e "${GREEN}Extracted $(wc -l < "$output_file") IP ranges for $country_code${NC}"
    return 0
}

# Function to block a country
block_country() {
    local country_code
    for country_code in "$@"; do
        country_code=$(echo "$country_code" | tr '[:lower:]' '[:upper:]')
        
        # Check if already blocked
        if grep -q "^$country_code$" "$BLOCK_LIST"; then
            echo -e "${YELLOW}Country $country_code is already blocked${NC}"
            continue
        fi
        
        # Extract IP ranges
        extract_country_ips "$country_code"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to block $country_code${NC}"
            continue
        fi
        
        # Create ipset
        ipset create "geoblock-$country_code" hash:net 2>/dev/null || ipset flush "geoblock-$country_code"
        
        # Add IP ranges to ipset
        while IFS=- read -r start_ip end_ip; do
            # Convert range to CIDR notation (simplified approach)
            ipset add "geoblock-$country_code" "$start_ip" 2>/dev/null
        done < "$GEOIP_DIR/lists/$country_code.zone"
        
        # Add to iptables if not already
        if ! iptables -C "$CHAIN_NAME" -m set --match-set "geoblock-$country_code" src -p tcp --dport "$SSH_PORT" -j DROP 2>/dev/null; then
            iptables -A "$CHAIN_NAME" -m set --match-set "geoblock-$country_code" src -p tcp --dport "$SSH_PORT" -j DROP
        fi
        
        # Add to block list
        echo "$country_code" >> "$BLOCK_LIST"
        echo -e "${GREEN}Blocked SSH connections from $country_code${NC}"
    done
    
    # Save iptables rules
    save_iptables_rules
}

# Function to unblock a country
unblock_country() {
    local country_code
    for country_code in "$@"; do
        country_code=$(echo "$country_code" | tr '[:lower:]' '[:upper:]')
        
        # Check if blocked
        if ! grep -q "^$country_code$" "$BLOCK_LIST"; then
            echo -e "${YELLOW}Country $country_code is not blocked${NC}"
            continue
        fi
        
        # Remove from iptables
        iptables -D "$CHAIN_NAME" -m set --match-set "geoblock-$country_code" src -p tcp --dport "$SSH_PORT" -j DROP 2>/dev/null
        
        # Remove ipset
        ipset destroy "geoblock-$country_code" 2>/dev/null
        
        # Remove from block list
        sed -i "/^$country_code$/d" "$BLOCK_LIST"
        echo -e "${GREEN}Unblocked SSH connections from $country_code${NC}"
    done
    
    # Save iptables rules
    save_iptables_rules
}

# Function to apply all rules (used at startup)
apply_rules() {
    echo -e "${BLUE}Applying GeoBlock SSH rules...${NC}"
    
    # Create the iptables chain if it doesn't exist
    iptables -N "$CHAIN_NAME" 2>/dev/null || iptables -F "$CHAIN_NAME"
    
    # Add the chain to the INPUT chain if not already
    if ! iptables -C INPUT -j "$CHAIN_NAME" 2>/dev/null; then
        iptables -I INPUT -j "$CHAIN_NAME"
    fi
    
    # Reapply all country blocks
    if [ -f "$BLOCK_LIST" ]; then
        while read -r country_code; do
            if [ -n "$country_code" ]; then
                extract_country_ips "$country_code"
                
                # Create ipset
                ipset create "geoblock-$country_code" hash:net 2>/dev/null || ipset flush "geoblock-$country_code"
                
                # Add IP ranges to ipset
                while IFS=- read -r start_ip end_ip; do
                    ipset add "geoblock-$country_code" "$start_ip" 2>/dev/null
                done < "$GEOIP_DIR/lists/$country_code.zone"
                
                # Add to iptables
                if ! iptables -C "$CHAIN_NAME" -m set --match-set "geoblock-$country_code" src -p tcp --dport "$SSH_PORT" -j DROP 2>/dev/null; then
                    iptables -A "$CHAIN_NAME" -m set --match-set "geoblock-$country_code" src -p tcp --dport "$SSH_PORT" -j DROP
                fi
                
                echo -e "${GREEN}Applied block for $country_code${NC}"
            fi
        done < "$BLOCK_LIST"
    fi
    
    echo -e "${GREEN}All rules applied!${NC}"
}

# Function to clear all rules
clear_rules() {
    echo -e "${BLUE}Clearing GeoBlock SSH rules...${NC}"
    
    # Remove the chain from INPUT
    iptables -D INPUT -j "$CHAIN_NAME" 2>/dev/null
    
    # Flush and delete the chain
    iptables -F "$CHAIN_NAME" 2>/dev/null
    iptables -X "$CHAIN_NAME" 2>/dev/null
    
    # Remove all ipsets
    if [ -f "$BLOCK_LIST" ]; then
        while read -r country_code; do
            if [ -n "$country_code" ]; then
                ipset destroy "geoblock-$country_code" 2>/dev/null
            fi
        done < "$BLOCK_LIST"
    fi
    
    echo -e "${GREEN}All rules cleared!${NC}"
}

# Function to list blocked countries
list_blocked() {
    echo -e "${BLUE}Currently blocked countries:${NC}"
    
    if [ -f "$BLOCK_LIST" ] && [ -s "$BLOCK_LIST" ]; then
        while read -r country_code; do
            if [ -n "$country_code" ]; then
                echo -e "${GREEN}- $country_code${NC}"
            fi
        done < "$BLOCK_LIST"
    else
        echo -e "${YELLOW}No countries are currently blocked${NC}"
    fi
}

# Function to check status
check_status() {
    echo -e "${BLUE}GeoBlock SSH Status:${NC}"
    
    if systemctl is-active --quiet geoblock-ssh.service; then
        echo -e "${GREEN}Service: Running${NC}"
    else
        echo -e "${RED}Service: Not running${NC}"
    fi
    
    if iptables -L "$CHAIN_NAME" &>/dev/null; then
        echo -e "${GREEN}Firewall Chain: Active${NC}"
        echo -e "${YELLOW}Blocked countries:${NC}"
        list_blocked
    else
        echo -e "${RED}Firewall Chain: Not configured${NC}"
    fi
}

# Function to save iptables rules for persistence
save_iptables_rules() {
    if [ -f /etc/debian_version ]; then
        netfilter-persistent save
    elif [ -f /etc/redhat-release ]; then
        service iptables save
    else
        echo -e "${YELLOW}Please save your iptables rules manually for your distribution${NC}"
    fi
}

# Main script logic
case "$1" in
    install)
        install_dependencies
        ;;
    block)
        shift
        if [ $# -eq 0 ]; then
            echo -e "${RED}Error: No country code specified${NC}"
            show_help
            exit 1
        fi
        block_country "$@"
        ;;
    unblock)
        shift
        if [ $# -eq 0 ]; then
            echo -e "${RED}Error: No country code specified${NC}"
            show_help
            exit 1
        fi
        unblock_country "$@"
        ;;
    list)
        list_blocked
        ;;
    apply)
        apply_rules
        ;;
    clear)
        clear_rules
        ;;
    status)
        check_status
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Error: Unknown command '$1'${NC}"
        show_help
        exit 1
        ;;
esac

exit 0
