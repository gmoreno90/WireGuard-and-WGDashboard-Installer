#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

for lib in common.sh detect-os.sh sysctl-config.sh firewall.sh wireguard.sh dashboard.sh; do
    if [ -f "$LIB_DIR/$lib" ]; then
        source "$LIB_DIR/$lib"
    else
        echo "ERROR: Library not found: $LIB_DIR/$lib"
        echo ""
        echo "Please clone the repository instead of downloading just this file:"
        echo "  git clone https://github.com/gmoreno90/WireGuard-and-WGDashboard-Installer.git"
        echo "  cd WireGuard-and-WGDashboard-Installer"
        echo "  sudo ./install.sh"
        exit 1
    fi
done

trap rollback ERR INT TERM

main() {
    echo ""
    echo "=========================================="
    echo "  WireGuard + WGDashboard Installer"
    echo "  Universal Version"
    echo "=========================================="
    echo ""
    
    check_root
    
    init_logging
    
    log_info "Starting installation..."
    
    check_existing_installation
    
    detect_os
    
    validate_os_support
    
    get_package_manager
    
    print_os_info
    
    detect_primary_interface
    
    get_public_ip
    
    install_wireguard || {
        log_error "WireGuard installation failed"
        exit 1
    }
    
    generate_wireguard_keys || {
        log_error "Key generation failed"
        exit 1
    }
    
    create_wireguard_config || {
        log_error "WireGuard configuration failed"
        exit 1
    }
    
    configure_ip_forwarding || {
        log_error "IP forwarding configuration failed"
        exit 1
    }
    
    configure_firewall
    
    start_wireguard || {
        log_error "WireGuard service failed to start"
        exit 1
    }
    
    install_dashboard || {
        log_error "WGDashboard installation failed"
        exit 1
    }
    
    create_verification_script
    
    print_summary
}

print_summary() {
    local server_ip="${PUBLIC_IP:-YOUR_SERVER_IP}"
    
    echo ""
    echo "=========================================="
    log_success "Installation completed successfully!"
    echo "=========================================="
    echo ""
    echo "=== Access Information ==="
    echo ""
    echo "WGDashboard:"
    echo "  URL: http://$server_ip:$DASHBOARD_PORT"
    echo "  Username: $DASHBOARD_USER"
    echo "  Password: $DASHBOARD_PASS"
    echo ""
    echo "WireGuard:"
    echo "  Public Key: $WG_PUBLIC_KEY"
    echo "  Listen Port: $WG_PORT"
    echo "  VPN Network: $WG_SERVER_CIDR"
    echo "  Endpoint: $server_ip:$WG_PORT"
    echo ""
    echo "=== System Details ==="
    echo "  OS: $OS_PRETTY_NAME"
    echo "  Primary Interface: $PRIMARY_INTERFACE"
    echo "  Server IP: $server_ip"
    echo ""
    echo "=== Useful Commands ==="
    echo "  Check status: /root/check-vpn.sh"
    echo "  View peers: wg show"
    echo "  WireGuard logs: journalctl -u wg-quick@wg0 -f"
    echo "  Dashboard logs: journalctl -u wgdashboard -f"
    echo "  Installation log: $LOG_FILE"
    echo ""
    echo "=== Security Warning ==="
    echo "  CHANGE the default dashboard password immediately!"
    echo "  Login at: http://$server_ip:$DASHBOARD_PORT"
    echo ""
    
    print_client_template
}

main "$@"
