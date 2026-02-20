#!/bin/bash

WG_DIR="/etc/wireguard"
WG_INTERFACE="wg0"
WG_PORT=51820
WG_NETWORK="10.99.99.0"
WG_SERVER_IP="10.99.99.1"
WG_SERVER_CIDR="10.99.99.1/24"

install_wireguard() {
    log_info "Installing WireGuard..."
    
    $PKG_UPDATE || {
        log_error "Failed to update package lists"
        return 1
    }
    
    local packages="wireguard"
    
    if [ "$PKG_MANAGER" = "apt" ]; then
        packages="$packages iptables-persistent"
    fi
    
    DEBIAN_FRONTEND=noninteractive $PKG_INSTALL $packages 2>/dev/null || {
        log_warn "Some packages may have failed to install, continuing..."
    }
    
    if ! command_exists wg; then
        log_error "WireGuard installation failed - 'wg' command not found"
        return 1
    fi
    
    log_success "WireGuard installed successfully"
    return 0
}

generate_wireguard_keys() {
    log_info "Generating WireGuard keys..."
    
    mkdir -p "$WG_DIR"
    cd "$WG_DIR" || {
        log_error "Cannot access $WG_DIR"
        return 1
    }
    
    if [ -f privatekey ] && [ -f publickey ]; then
        log_warn "Existing keys found, checking validity..."
        if [ -s privatekey ] && [ -s publickey ]; then
            log_info "Reusing existing keys"
            WG_PRIVATE_KEY=$(cat privatekey)
            WG_PUBLIC_KEY=$(cat publickey)
            return 0
        fi
    fi
    
    umask 077
    
    wg genkey 2>/dev/null | tee privatekey | wg pubkey > publickey 2>/dev/null || {
        log_error "Failed to generate WireGuard keys"
        return 1
    }
    
    WG_PRIVATE_KEY=$(cat privatekey)
    WG_PUBLIC_KEY=$(cat publickey)
    
    if [ -z "$WG_PRIVATE_KEY" ] || [ -z "$WG_PUBLIC_KEY" ]; then
        log_error "Generated keys are empty"
        return 1
    fi
    
    chmod 600 privatekey publickey 2>/dev/null || true
    
    log_success "WireGuard keys generated"
    return 0
}

create_wireguard_config() {
    log_info "Creating WireGuard configuration..."
    
    if [ -z "$WG_PRIVATE_KEY" ]; then
        log_error "No private key available"
        return 1
    fi
    
    if [ -z "$PRIMARY_INTERFACE" ]; then
        log_error "Primary interface not detected"
        return 1
    fi
    
    local config_file="$WG_DIR/$WG_INTERFACE.conf"
    
    if [ -f "$config_file" ]; then
        BACKUP_WG_CONF="$config_file.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$config_file" "$BACKUP_WG_CONF"
        log_info "Backed up existing config to $BACKUP_WG_CONF"
    fi
    
    cat > "$config_file" << EOF
[Interface]
Address = $WG_SERVER_CIDR
ListenPort = $WG_PORT
PrivateKey = $WG_PRIVATE_KEY
PostUp = iptables -t nat -A POSTROUTING -s $WG_NETWORK/24 -o $PRIMARY_INTERFACE -j MASQUERADE
PostUp = iptables -A FORWARD -i $WG_INTERFACE -j ACCEPT
PostUp = iptables -A FORWARD -o $WG_INTERFACE -j ACCEPT
PostUp = iptables -A FORWARD -i $WG_INTERFACE -o $PRIMARY_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
PostUp = iptables -A FORWARD -i $PRIMARY_INTERFACE -o $WG_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s $WG_NETWORK/24 -o $PRIMARY_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i $WG_INTERFACE -j ACCEPT
PostDown = iptables -D FORWARD -o $WG_INTERFACE -j ACCEPT
PostDown = iptables -D FORWARD -i $WG_INTERFACE -o $PRIMARY_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
PostDown = iptables -D FORWARD -i $PRIMARY_INTERFACE -o $WG_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
SaveConfig = true
EOF
    
    chmod 600 "$config_file"
    
    log_success "Created $config_file"
    return 0
}

start_wireguard() {
    log_info "Starting WireGuard service..."
    
    systemctl daemon-reload
    
    systemctl enable "wg-quick@$WG_INTERFACE" 2>/dev/null || {
        log_warn "Could not enable WireGuard service"
    }
    
    systemctl start "wg-quick@$WG_INTERFACE" || {
        log_error "Failed to start WireGuard service"
        journalctl -u "wg-quick@$WG_INTERFACE" --no-pager -n 20 2>/dev/null
        return 1
    }
    
    sleep 2
    
    if systemctl is-active --quiet "wg-quick@$WG_INTERFACE"; then
        log_success "WireGuard service started"
        return 0
    else
        log_error "WireGuard service is not running"
        return 1
    fi
}

verify_wireguard() {
    log_info "Verifying WireGuard installation..."
    
    if ! systemctl is-active --quiet "wg-quick@$WG_INTERFACE"; then
        log_error "WireGuard service is not active"
        return 1
    fi
    
    if [ ! -f "$WG_DIR/$WG_INTERFACE.conf" ]; then
        log_error "WireGuard config file not found"
        return 1
    fi
    
    if ! command_exists wg; then
        log_error "wg command not found"
        return 1
    fi
    
    log_success "WireGuard verification passed"
    return 0
}

get_wireguard_status() {
    echo "=== WireGuard Status ==="
    systemctl status "wg-quick@$WG_INTERFACE" --no-pager 2>/dev/null | head -10
    echo ""
    echo "=== WireGuard Peers ==="
    wg show 2>/dev/null || echo "No peers or interface not up"
    echo ""
    echo "=== Configuration ==="
    echo "Interface: $WG_INTERFACE"
    echo "Port: $WG_PORT"
    echo "Network: $WG_NETWORK/24"
    echo "Server IP: $WG_SERVER_IP"
    echo "Public Key: ${WG_PUBLIC_KEY:-not set}"
}

print_client_template() {
    if [ -z "$WG_PUBLIC_KEY" ]; then
        return
    fi
    
    local server_ip="${PUBLIC_IP:-YOUR_SERVER_IP}"
    
    echo ""
    echo "=== Client Configuration Template ==="
    echo "[Interface]"
    echo "PrivateKey = CLIENT_PRIVATE_KEY"
    echo "Address = 10.99.99.X/32"
    echo "DNS = 8.8.8.8, 1.1.1.1"
    echo ""
    echo "[Peer]"
    echo "PublicKey = $WG_PUBLIC_KEY"
    echo "Endpoint = $server_ip:$WG_PORT"
    echo "AllowedIPs = 0.0.0.0/0"
    echo "PersistentKeepalive = 25"
    echo ""
}
