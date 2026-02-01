#!/bin/bash
set -e

echo "🔧 Installing WireGuard and WGDashboard with Domain Support on Debian 13..."
echo "⚠️  This script has been updated for Debian 13 (Trixie) with proper sysctl.d support"

# Detect the primary network interface automatically
echo "🔍 Detecting primary network interface..."
PRIMARY_INTERFACE=$(ip route show default | awk '/default/ { print $5 }' | head -n1)
if [ -z "$PRIMARY_INTERFACE" ]; then
    echo "❌ ERROR: Could not detect primary network interface. Please run 'ip route show default' and check your network configuration."
    exit 1
fi
echo "✅ Detected primary interface: $PRIMARY_INTERFACE"

# Step 1: Install required packages
echo "📦 Installing required packages..."
apt update
apt install -y wireguard iptables-persistent python3 python3-pip git

# Step 2: Create WireGuard keys and configuration
WG_DIR="/etc/wireguard"
mkdir -p $WG_DIR
cd $WG_DIR

# Check if keys already exist
if [ -f "$WG_DIR/privatekey" ] && [ -f "$WG_DIR/publickey" ]; then
    echo "🔐 WireGuard keys already exist, reusing them..."
    PRIVATE_KEY=$(cat privatekey)
    PUBLIC_KEY=$(cat publickey)
else
    echo "🔐 Generating WireGuard server keys..."
    umask 077
    wg genkey | tee privatekey | wg pubkey > publickey
    PRIVATE_KEY=$(cat privatekey)
    PUBLIC_KEY=$(cat publickey)
fi

SERVER_IP="10.99.99.1"

echo "📝 Creating WireGuard configuration..."
cat > wg0.conf <<EOF
[Interface]
Address = $SERVER_IP/24
ListenPort = 51820
PrivateKey = $PRIVATE_KEY
PostUp = iptables -t nat -A POSTROUTING -s 10.99.99.0/24 -o $PRIMARY_INTERFACE -j MASQUERADE
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j ACCEPT
PostUp = iptables -A FORWARD -i wg0 -o $PRIMARY_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
PostUp = iptables -A FORWARD -i $PRIMARY_INTERFACE -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s 10.99.99.0/24 -o $PRIMARY_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -o $PRIMARY_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
PostDown = iptables -D FORWARD -i $PRIMARY_INTERFACE -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
SaveConfig = true
EOF

echo "🌐 Server public key: $PUBLIC_KEY"

# Step 3: Enable IP forwarding permanently (UPDATED for Debian 13)
echo "🔀 Enabling IP forwarding..."

# Create sysctl configuration file for WireGuard in /etc/sysctl.d/
SYSCTL_FILE="/etc/sysctl.d/99-wireguard.conf"

# Remove file if it exists to avoid duplicates
rm -f "$SYSCTL_FILE"

# Create new configuration
cat > "$SYSCTL_FILE" <<EOF
# IP Forwarding for WireGuard VPN
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

echo "✅ Created sysctl configuration at $SYSCTL_FILE"

# Apply the settings immediately
sysctl --system

# Verify it's enabled
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    echo "✅ IP forwarding is now enabled"
else
    echo "❌ ERROR: IP forwarding could not be enabled"
    exit 1
fi

# Step 4: Setup initial iptables rules
echo "🔥 Setting up firewall rules..."

# Stop WireGuard temporarily if running to clean rules
systemctl stop wg-quick@wg0 2>/dev/null || true

# Clean any existing conflicting rules
iptables -t nat -F POSTROUTING 2>/dev/null || true
iptables -F FORWARD 2>/dev/null || true

# Add the correct rules
iptables -t nat -A POSTROUTING -s 10.99.99.0/24 -o $PRIMARY_INTERFACE -j MASQUERADE
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT
iptables -A FORWARD -i wg0 -o $PRIMARY_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $PRIMARY_INTERFACE -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Save rules for persistence
echo "💾 Saving firewall rules..."
netfilter-persistent save

# Step 5: Enable and start WireGuard
echo "🚀 Starting WireGuard service..."
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0 || {
    echo "❌ WireGuard service failed to start. Checking logs..."
    journalctl -u wg-quick@wg0 --no-pager -l
    exit 1
}

# Step 6: Install WGDashboard
echo "🖥️  Installing WGDashboard..."
cd /opt

# Check if already exists and backup if needed
if [ -d "WGDashboard" ]; then
    echo "⚠️  WGDashboard directory already exists, backing up..."
    mv WGDashboard WGDashboard.backup.$(date +%Y%m%d_%H%M%S)
fi

git clone https://github.com/donaldzou/WGDashboard.git
cd WGDashboard

# Step 7: Install Python requirements with proper handling of Debian packages
REQUIREMENTS_PATH="/opt/WGDashboard/src/requirements.txt"
if [ ! -f "$REQUIREMENTS_PATH" ]; then
    echo "❌ ERROR: requirements.txt not found at $REQUIREMENTS_PATH. Repo may have changed. Aborting."
    exit 1
fi

echo "📦 Installing Python dependencies (handling Debian conflicts)..."

# Try normal installation first
pip3 install --break-system-packages -r "$REQUIREMENTS_PATH" 2>&1 | tee /tmp/pip_install.log

# Check if installation failed due to typing-extensions
if grep -q "Cannot uninstall typing_extensions" /tmp/pip_install.log; then
    echo "⚠️  Detected typing-extensions conflict, retrying with --ignore-installed..."
    pip3 install --break-system-packages --ignore-installed typing-extensions -r "$REQUIREMENTS_PATH"
fi

# Verify critical packages are installed
echo "🔍 Verifying Python dependencies..."
python3 -c "import flask, bcrypt, psutil" 2>/dev/null || {
    echo "❌ Critical Python packages missing. Attempting force reinstall..."
    pip3 install --break-system-packages --force-reinstall -r "$REQUIREMENTS_PATH"
}

# Step 8: Create config.json for WGDashboard
echo "⚙️  Creating WGDashboard configuration..."
mkdir -p /opt/WGDashboard/src
cat > /opt/WGDashboard/src/config.json <<EOF
{
  "wg_conf_path": "/etc/wireguard/wg0.conf",
  "interface": "wg0",
  "listen_port": 10086,
  "username": "admin",
  "password": "admin"
}
EOF

# Step 9: Create systemd service for WGDashboard
echo "🔧 Creating WGDashboard systemd service..."
cat > /etc/systemd/system/wgdashboard.service <<EOF
[Unit]
Description=WGDashboard Web UI
After=network.target wg-quick@wg0.service

[Service]
WorkingDirectory=/opt/WGDashboard/src
ExecStart=/usr/bin/python3 /opt/WGDashboard/src/dashboard.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Step 10: Enable and start the dashboard
echo "🚀 Starting WGDashboard service..."
systemctl daemon-reload
systemctl enable wgdashboard
systemctl restart wgdashboard

# Wait a moment for service to start
sleep 3

# Step 11: Create verification script
echo "📝 Creating verification script..."
cat > /root/check-vpn.sh <<'EOF'
#!/bin/bash
echo "=========================================="
echo "    WireGuard VPN Status Report"
echo "=========================================="

echo ""
echo "=== WireGuard Service Status ==="
if systemctl is-active --quiet wg-quick@wg0; then
    echo "✅ WireGuard is RUNNING"
    systemctl status wg-quick@wg0 --no-pager -l | head -n 10
else
    echo "❌ WireGuard is NOT RUNNING"
    systemctl status wg-quick@wg0 --no-pager -l
fi

echo ""
echo "=== WireGuard Peers ==="
wg show 2>/dev/null || echo "No peers connected"

echo ""
echo "=== IP Forwarding Status ==="
IPV4_FORWARD=$(cat /proc/sys/net/ipv4/ip_forward)
IPV6_FORWARD=$(cat /proc/sys/net/ipv6/conf/all/forwarding)
if [ "$IPV4_FORWARD" = "1" ]; then
    echo "✅ IPv4 forwarding: ENABLED"
else
    echo "❌ IPv4 forwarding: DISABLED"
fi
if [ "$IPV6_FORWARD" = "1" ]; then
    echo "✅ IPv6 forwarding: ENABLED"
else
    echo "⚠️  IPv6 forwarding: DISABLED"
fi

echo ""
echo "=== Sysctl Configuration ==="
if [ -f /etc/sysctl.d/99-wireguard.conf ]; then
    echo "Configuration file: /etc/sysctl.d/99-wireguard.conf"
    cat /etc/sysctl.d/99-wireguard.conf
else
    echo "⚠️  Wireguard sysctl config not found"
fi

echo ""
echo "=== NAT Rules (MASQUERADE) ==="
iptables -t nat -L POSTROUTING -n -v | grep -E "(MASQUERADE|Chain)" | head -n 5

echo ""
echo "=== Forward Rules ==="
iptables -L FORWARD -n -v | head -n 10

echo ""
echo "=== Network Interface ==="
ip route show default

echo ""
echo "=== WGDashboard Service Status ==="
if systemctl is-active --quiet wgdashboard; then
    echo "✅ WGDashboard is RUNNING"
    systemctl status wgdashboard --no-pager -l | head -n 10
else
    echo "❌ WGDashboard is NOT RUNNING"
    systemctl status wgdashboard --no-pager -l
fi

echo ""
echo "=== Dashboard Access ==="
IPADDR=$(curl -s http://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')
echo "URL: http://$IPADDR:10086"
echo "Default credentials: admin/admin"

echo ""
echo "=========================================="
EOF

chmod +x /root/check-vpn.sh

# Step 12: Final verification
echo ""
echo "🔍 Running final verification checks..."
sleep 2

VERIFICATION_FAILED=0

# Check WireGuard
if systemctl is-active --quiet wg-quick@wg0; then
    echo "✅ WireGuard is running"
else
    echo "❌ WireGuard is not running"
    VERIFICATION_FAILED=1
fi

# Check WGDashboard
if systemctl is-active --quiet wgdashboard; then
    echo "✅ WGDashboard is running"
else
    echo "⚠️  WGDashboard is not running - checking logs..."
    journalctl -u wgdashboard --no-pager -n 20
    VERIFICATION_FAILED=1
fi

# Verify IP forwarding
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    echo "✅ IP forwarding is active"
else
    echo "❌ IP forwarding verification failed"
    VERIFICATION_FAILED=1
fi

# Verify sysctl file exists
if [ -f /etc/sysctl.d/99-wireguard.conf ]; then
    echo "✅ Sysctl configuration file exists"
else
    echo "❌ Sysctl configuration file missing"
    VERIFICATION_FAILED=1
fi

# Get server IP
IPADDR=$(curl -s http://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')

# Step 13: Output results
echo ""
echo "=========================================="
if [ $VERIFICATION_FAILED -eq 0 ]; then
    echo "🎉 Installation completed successfully!"
else
    echo "⚠️  Installation completed with warnings"
    echo "Run /root/check-vpn.sh for detailed diagnostics"
fi
echo "=========================================="
echo ""
echo "📊 Dashboard Access:"
echo "   URL: http://$IPADDR:10086"
echo "   Login: admin / admin"
echo ""
echo "🔧 Server Details:"
echo "   Interface: $PRIMARY_INTERFACE"
echo "   Server IP: $IPADDR"
echo "   WireGuard Port: 51820"
echo "   Server VPN IP: 10.99.99.1/24"
echo "   Server Public Key: $PUBLIC_KEY"
echo ""
echo "🔍 Useful Commands:"
echo "   Full status check: /root/check-vpn.sh"
echo "   View active peers: wg show"
echo "   WireGuard status: systemctl status wg-quick@wg0"
echo "   Dashboard status: systemctl status wgdashboard"
echo "   Dashboard logs: journalctl -u wgdashboard -f"
echo "   Check sysctl: cat /etc/sysctl.d/99-wireguard.conf"
echo "   Reload sysctl: sysctl --system"
echo ""
echo "⚠️  IMPORTANT SECURITY NOTES:"
echo "   1. ⚠️  CHANGE THE DASHBOARD PASSWORD IMMEDIATELY after first login!"
echo "   2. Server is ready to accept client connections"
echo "   3. Use the WGDashboard web interface to add clients"
echo "   4. For domain setup, create an A record pointing to $IPADDR"
echo "   5. Disable Cloudflare proxy (orange cloud) for WireGuard domain"
echo "   6. IP forwarding is persistent via /etc/sysctl.d/99-wireguard.conf"
echo "   7. Firewall rules persist after reboot via iptables-persistent"
echo ""
echo "📱 Client Configuration Template:"
echo "   [Interface]"
echo "   PrivateKey = CLIENT_PRIVATE_KEY"
echo "   Address = 10.99.99.X/32"
echo "   DNS = 8.8.8.8, 1.1.1.1"
echo "   "
echo "   [Peer]"
echo "   PublicKey = $PUBLIC_KEY"
echo "   Endpoint = $IPADDR:51820"
echo "   AllowedIPs = 0.0.0.0/0"
echo "   PersistentKeepalive = 25"
echo ""
echo "🔧 Troubleshooting:"
echo "   If WGDashboard fails to start:"
echo "     journalctl -u wgdashboard --no-pager -n 50"
echo "     systemctl restart wgdashboard"
echo ""
echo "   If WireGuard fails to start:"
echo "     journalctl -u wg-quick@wg0 --no-pager -n 50"
echo "     wg-quick down wg0 && wg-quick up wg0"
echo ""

# Run the verification script for immediate feedback
echo "=========================================="
echo "Running detailed verification check..."
echo "=========================================="
/root/check-vpn.sh

exit 0
