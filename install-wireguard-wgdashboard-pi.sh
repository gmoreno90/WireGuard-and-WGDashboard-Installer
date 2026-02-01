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

# Step 7: Install Python requirements
REQUIREMENTS_PATH="/opt/WGDashboard/src/requirements.txt"
if [ ! -f "$REQUIREMENTS_PATH" ]; then
    echo "❌ ERROR: requirements.txt not found at $REQUIREMENTS_PATH. Repo may have changed. Aborting."
    exit 1
fi
pip3 install --break-system-packages -r "$REQUIREMENTS_PATH"

# Step 8: Create config.json for WGDashboard
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
cat > /etc/systemd/system/wgdashboard.service <<EOF
[Unit]
Description=WGDashboard Web UI
After=network.target

[Service]
WorkingDirectory=/opt/WGDashboard/src
ExecStart=/usr/bin/python3 /opt/WGDashboard/src/dashboard.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Step 10: Enable and start the dashboard
systemctl daemon-reload
systemctl enable wgdashboard
systemctl restart wgdashboard

# Step 11: Create verification script
cat > /root/check-vpn.sh <<'EOF'
#!/bin/bash
echo "=== WireGuard Status ==="
systemctl status wg-quick@wg0 --no-pager -l

echo -e "\n=== WireGuard Peers ==="
wg show

echo -e "\n=== IP Forwarding Status ==="
echo "Current value: $(cat /proc/sys/net/ipv4/ip_forward)"
echo "IPv6 forwarding: $(cat /proc/sys/net/ipv6/conf/all/forwarding)"
echo "Should be: 1 for both"

echo -e "\n=== NAT Rules ==="
iptables -t nat -L -n -v | grep -E "(MASQUERADE|Chain)"

echo -e "\n=== Forward Rules ==="
iptables -L FORWARD -n -v

echo -e "\n=== Network Interface ==="
ip route show default

echo -e "\n=== Sysctl Configuration ==="
if [ -f /etc/sysctl.d/99-wireguard.conf ]; then
    echo "Configuration file: /etc/sysctl.d/99-wireguard.conf"
    cat /etc/sysctl.d/99-wireguard.conf
else
    echo "⚠️  Wireguard sysctl config not found at /etc/sysctl.d/99-wireguard.conf"
fi
echo "Current IP forward value: $(cat /proc/sys/net/ipv4/ip_forward)"

echo -e "\n=== WGDashboard Status ==="
systemctl status wgdashboard --no-pager -l
EOF

chmod +x /root/check-vpn.sh

# Step 12: Final verification
echo "🔍 Verifying installation..."
sleep 2

if systemctl is-active --quiet wg-quick@wg0; then
    echo "✅ WireGuard is running"
else
    echo "❌ WireGuard is not running"
    exit 1
fi

if systemctl is-active --quiet wgdashboard; then
    echo "✅ WGDashboard is running"
else
    echo "❌ WGDashboard is not running"
    exit 1
fi

# Verify IP forwarding one more time
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    echo "✅ IP forwarding is active"
else
    echo "❌ IP forwarding verification failed"
    exit 1
fi

# Get server IP
IPADDR=$(curl -s http://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')

# Step 13: Output results
echo ""
echo "🎉 WireGuard and WGDashboard have been successfully installed!"
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
echo "   Check VPN status: /root/check-vpn.sh"
echo "   View active peers: wg show"
echo "   Add new client: Use the WGDashboard web interface"
echo "   Save config: wg-quick save wg0"
echo "   Check sysctl config: cat /etc/sysctl.d/99-wireguard.conf"
echo "   Reload sysctl: sysctl --system"
echo ""
echo "⚠️  IMPORTANT NOTES:"
echo "   1. Change the dashboard password after first login"
echo "   2. Server is ready to accept client connections"
echo "   3. Use the WGDashboard web interface to add clients"
echo "   4. For domain setup, create an A record pointing to $IPADDR (disable Cloudflare proxy)"
echo "   5. IP forwarding is now properly enabled via /etc/sysctl.d/99-wireguard.conf"
echo "   6. Firewall rules are automatically saved and will persist after reboot"
echo "   7. Configuration is compatible with Debian 13 (Trixie)"
echo ""
echo "📱 Client Configuration Template (for manual setup if needed):"
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
