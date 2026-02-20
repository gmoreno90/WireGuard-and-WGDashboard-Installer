#!/bin/bash

LOG_FILE="/var/log/wireguard-installer.log"
SCRIPT_VERSION="2.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

init_logging() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    mkdir -p "$log_dir" 2>/dev/null || true
    
    echo "========================================" >> "$LOG_FILE" 2>/dev/null || {
        echo "Warning: Cannot write to $LOG_FILE, logging to stdout only"
        LOG_FILE="/dev/null"
    }
    echo "WireGuard Installer v$SCRIPT_VERSION" >> "$LOG_FILE"
    echo "Started at: $(date)" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        ERROR)
            echo -e "${RED}[$level] $message${NC}" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[$level] $message${NC}"
            ;;
        SUCCESS)
            echo -e "${GREEN}[$level] $message${NC}"
            ;;
        INFO)
            echo -e "${BLUE}[$level] $message${NC}"
            ;;
        DEBUG)
            echo -e "${NC}[$level] $message${NC}"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

log_info() {
    log "INFO" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_debug() {
    log "DEBUG" "$@"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        log_info "Try: sudo $0"
        exit 1
    fi
}

command_exists() {
    command -v "$1" &>/dev/null
}

check_existing_installation() {
    local found=0
    
    if systemctl is-active --quiet wg-quick@wg0 2>/dev/null; then
        log_warn "WireGuard service (wg-quick@wg0) is already running"
        found=1
    fi
    
    if [ -f /etc/wireguard/wg0.conf ]; then
        log_warn "WireGuard configuration exists: /etc/wireguard/wg0.conf"
        found=1
    fi
    
    if systemctl is-active --quiet wgdashboard 2>/dev/null; then
        log_warn "WGDashboard service is already running"
        found=1
    fi
    
    if [ -f /etc/systemd/system/wgdashboard.service ]; then
        log_warn "WGDashboard service file exists"
        found=1
    fi
    
    if [ "$found" -eq 1 ]; then
        log_error "Existing WireGuard/WGDashboard installation detected!"
        log_error "Aborting to prevent data loss."
        echo ""
        echo "If you want to reinstall, please first remove the existing installation:"
        echo "  systemctl stop wg-quick@wg0 wgdashboard"
        echo "  systemctl disable wg-quick@wg0 wgdashboard"
        echo "  rm -rf /etc/wireguard/wg0.conf /opt/WGDashboard /etc/systemd/system/wgdashboard.service"
        echo "  systemctl daemon-reload"
        exit 1
    fi
    
    log_success "No existing installation found, proceeding..."
}

detect_primary_interface() {
    local interface
    interface=$(ip route show default 2>/dev/null | awk '/default/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)
    
    if [ -z "$interface" ]; then
        interface=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n1)
    fi
    
    if [ -z "$interface" ]; then
        log_error "Could not detect primary network interface"
        log_info "Available interfaces:"
        ip link show 2>/dev/null | awk -F: '/^[0-9]/ {print "  - " $2}' | sed 's/ //g'
        exit 1
    fi
    
    PRIMARY_INTERFACE="$interface"
    log_success "Detected primary interface: $PRIMARY_INTERFACE"
}

get_public_ip() {
    local ip
    ip=$(curl -s --max-time 5 http://checkip.amazonaws.com 2>/dev/null)
    
    if [ -z "$ip" ] || [ "$ip" = "unknown" ]; then
        ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
    fi
    
    if [ -z "$ip" ] || [ "$ip" = "unknown" ]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    if [ -z "$ip" ]; then
        ip="YOUR_SERVER_IP"
        log_warn "Could not detect public IP, using placeholder"
    fi
    
    PUBLIC_IP="$ip"
}

rollback() {
    log_error "Installation failed, attempting rollback..."
    
    systemctl stop wgdashboard 2>/dev/null || true
    systemctl stop wg-quick@wg0 2>/dev/null || true
    systemctl disable wgdashboard 2>/dev/null || true
    systemctl disable wg-quick@wg0 2>/dev/null || true
    
    rm -f /etc/systemd/system/wgdashboard.service 2>/dev/null || true
    rm -f /etc/sysctl.d/99-wireguard.conf 2>/dev/null || true
    rm -rf /opt/WGDashboard 2>/dev/null || true
    
    if [ -n "${BACKUP_WG_CONF:-}" ] && [ -f "$BACKUP_WG_CONF" ]; then
        mv "$BACKUP_WG_CONF" /etc/wireguard/wg0.conf 2>/dev/null || true
    fi
    
    systemctl daemon-reload 2>/dev/null || true
    
    log_error "Rollback completed. Check $LOG_FILE for details."
    exit 1
}

create_verification_script() {
    local script_path="/root/check-vpn.sh"
    
    cat > "$script_path" << 'CHECKEOF'
#!/bin/bash
echo "=========================================="
echo "    WireGuard VPN Status Report"
echo "=========================================="

echo ""
echo "=== WireGuard Service ==="
if systemctl is-active --quiet wg-quick@wg0; then
    echo "Status: RUNNING"
    wg show 2>/dev/null || echo "No peers connected"
else
    echo "Status: NOT RUNNING"
    systemctl status wg-quick@wg0 --no-pager -l 2>/dev/null | head -5
fi

echo ""
echo "=== IP Forwarding ==="
IPV4=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)
echo "IPv4 forwarding: $([ "$IPV4" = "1" ] && echo "ENABLED" || echo "DISABLED")"

echo ""
echo "=== WGDashboard ==="
if systemctl is-active --quiet wgdashboard; then
    echo "Status: RUNNING"
    IPADDR=$(curl -s --max-time 3 http://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')
    echo "URL: http://$IPADDR:10086"
else
    echo "Status: NOT RUNNING"
fi

echo ""
echo "=== NAT/MASQUERADE Rules ==="
iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -E "MASQUERADE|Chain" | head -5

echo ""
echo "=== Configuration Files ==="
[ -f /etc/wireguard/wg0.conf ] && echo "WireGuard config: /etc/wireguard/wg0.conf"
[ -f /etc/sysctl.d/99-wireguard.conf ] && echo "Sysctl config: /etc/sysctl.d/99-wireguard.conf"
[ -f /etc/sysctl.conf ] && grep -q "ip_forward" /etc/sysctl.conf 2>/dev/null && echo "Sysctl (legacy): /etc/sysctl.conf"

echo ""
echo "=========================================="
CHECKEOF
    
    chmod +x "$script_path"
    log_success "Created verification script: $script_path"
}
