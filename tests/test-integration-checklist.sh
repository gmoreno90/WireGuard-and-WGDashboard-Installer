#!/bin/bash

echo "=========================================="
echo "  WireGuard Installer - Integration Test Checklist"
echo "=========================================="
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "This script provides a checklist for manual integration testing."
echo "Run these tests on actual VMs or containers."
echo ""

print_check() {
    echo -e "${YELLOW}[ ]${NC} $1"
}

section() {
    echo ""
    echo "=== $1 ==="
}

section "Pre-Installation Tests"

print_check "Script runs without errors on Debian 12 (VM/Container)"
print_check "Script runs without errors on Debian 13 (VM/Container)"
print_check "Script runs without errors on Raspberry Pi OS (VM/Hardware)"
print_check "Script detects existing installation and aborts"
print_check "Script fails gracefully when not run as root"

section "OS Detection Tests"

print_check "Correctly detects Debian 12 (bookworm)"
print_check "Correctly detects Debian 13 (trixie)"
print_check "Correctly detects Raspberry Pi OS"
print_check "Correctly identifies primary network interface"
print_check "Correctly detects public IP"

section "Sysctl Tests (Debian 12)"

print_check "Uses /etc/sysctl.conf on Debian 12"
print_check "IP forwarding enabled after installation"
print_check "IP forwarding persists after reboot"

section "Sysctl Tests (Debian 13)"

print_check "Creates /etc/sysctl.d/99-wireguard.conf on Debian 13"
print_check "IP forwarding enabled after installation"
print_check "IP forwarding persists after reboot"

section "WireGuard Tests"

print_check "WireGuard package installed"
print_check "Keys generated in /etc/wireguard/"
print_check "wg0.conf created with correct settings"
print_check "wg-quick@wg0 service starts"
print_check "wg-quick@wg0 service enabled on boot"
print_check "wg show displays interface"

section "WGDashboard Tests"

print_check "WGDashboard cloned to /opt/WGDashboard"
print_check "Python dependencies installed"
print_check "config.json created"
print_check "Systemd service created"
print_check "Service starts successfully"
print_check "Dashboard accessible on port 10086"
print_check "Login works with admin/admin"

section "Firewall Tests"

print_check "Port 51820/UDP open (check with: ss -ulnp)"
print_check "Port 10086/TCP open (check with: ss -tlnp)"
print_check "NAT/MASQUERADE rules present"
print_check "Rules persist after reboot"

section "VPN Connectivity Tests"

print_check "Client can connect to VPN"
print_check "Client can ping VPN server (10.99.99.1)"
print_check "Client can access internet through VPN"
print_check "DNS resolution works through VPN"

section "Rollback Tests"

print_check "Rollback works when installation fails"
print_check "Partial installations are cleaned up"

section "Verification Script Tests"

print_check "/root/check-vpn.sh exists"
print_check "/root/check-vpn.sh runs without errors"
print_check "/root/check-vpn.sh shows correct status"

section "Logging Tests"

print_check "/var/log/wireguard-installer.log created"
print_check "Log contains installation steps"
print_check "Log contains any errors encountered"

echo ""
echo "=========================================="
echo "Test Environments Needed:"
echo "=========================================="
echo ""
echo "1. Debian 12 VM/Container"
echo "   docker run -it --privileged debian:12 bash"
echo ""
echo "2. Debian 13 VM/Container"
echo "   docker run -it --privileged debian:testing bash"
echo ""
echo "3. Raspberry Pi OS (use actual hardware or Pi-specific emulator)"
echo ""
echo "Note: Docker containers need --privileged for systemd"
echo ""

echo "=========================================="
echo "Quick Docker Test Commands:"
echo "=========================================="
echo ""
echo "# Debian 12"
echo "docker run -d --name wg-test-deb12 --privileged debian:12 sleep infinity"
echo "docker exec -it wg-test-deb12 bash"
echo "apt update && apt install -y curl"
echo "curl -O https://raw.githubusercontent.com/.../install.sh"
echo "chmod +x install.sh && ./install.sh"
echo ""
echo "# Debian 13"
echo "docker run -d --name wg-test-deb13 --privileged debian:testing sleep infinity"
echo "docker exec -it wg-test-deb13 bash"
echo ""
