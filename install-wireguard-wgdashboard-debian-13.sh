#!/bin/bash
set -e
echo "🔧 Installing WireGuard and WGDashboard on Debian 13..."
echo "⚠️  This script installs WireGuard VPN with web dashboard"
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
apt install -y wireguard iptables-persistent python3 python3-pip git python3-venv curl
# Step 2: Create WireGuard keys and configuration
WG_DIR="/etc/wireguard"
mkdir -p $WG_DIR
cd $WG_DIR
echo "🔐 Generating WireGuard server keys..."
umask 077
wg genkey | tee privatekey | wg pubkey > publickey
PRIVATE_KEY=$(cat privatekey)
PUBLIC_KEY=$(cat publickey)
SERVER_IP="10.99.99.1"
echo "📝 Creating WireGuard configuration..."
cat > wg0.conf <<EOF
[Interface]
Address = $SERVER_IP/24
ListenPort = 51820
PrivateKey = $PRIVATE_KEY
PostUp = iptables -t nat -A POSTROUTING -s 10.99.99.0/24 -o $PRIMARY_INTERFACE -j MASQUERADE; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s 10.99.99.0/24 -o $PRIMARY_INTERFACE -j MASQUERADE; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT
SaveConfig = true
EOF
echo "🌐 Server public key: $PUBLIC_KEY"
# Step 3: Enable IP forwarding (modern method for Debian 13)
echo "🔀 Enabling IP forwarding..."
SYSCTL_CONF="/etc/sysctl.d/99-wireguard.conf"
cat > "$SYSCTL_CONF" <<EOF
# WireGuard VPN IP forwarding
net.ipv4.ip_forward=1
EOF
# Apply the setting immediately
sysctl -p "$SYSCTL_CONF"
# Verify it's enabled
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    echo "✅ IP forwarding is now enabled"
else
    echo "❌ ERROR: IP forwarding could not be enabled"
    exit 1
fi
# Step 4: Setup initial iptables rules
echo "🔥 Setting up firewall rules..."
iptables -t nat -F POSTROUTING 2>/dev/null || true
iptables -F FORWARD 2>/dev/null || true
iptables -t nat -A POSTROUTING -s 10.99.99.0/24 -o $PRIMARY_INTERFACE -j MASQUERADE
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT
echo "💾 Saving firewall rules..."
netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4
# Step 5: Enable and start WireGuard
echo "🚀 Starting WireGuard service..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0 || {
    echo "❌ WireGuard service failed to start. Checking logs..."
    journalctl -u wg-quick@wg0 --no-pager -l
    exit 1
}
# Step 6: Install WGDashboard (modern method)
echo "🖥️  Installing WGDashboard..."
cd /opt
rm -rf WGDashboard
git clone https://github.com/donaldzou/WGDashboard.git
cd WGDashboard
# Step 7: Install WGDashboard using official installer
echo "📦 Running WGDashboard installer..."
chmod +x wgd.sh
./wgd.sh install
# Step 8: Configure WGDashboard to use our WireGuard config
echo "📝 Configuring WGDashboard..."
if [ -f "/opt/WGDashboard/src/wg-dashboard.ini" ]; then
    cat > /opt/WGDashboard/src/wg-dashboard.ini <<EOF
[Account]
username = admin
password = admin
[Server]
app_port = 10086
EOF
fi
# Step 9: Create systemd service for WGDashboard
cat > /etc/systemd/system/wgdashboard.service <<EOF
[Unit]
Description=WGDashboard Web UI
After=network.target
[Service]
Type=forking
WorkingDirectory=/opt/WGDashboard
ExecStart=/opt/WGDashboard/wgd.sh start
ExecStop=/opt/WGDashboard/wgd.sh stop
ExecReload=/opt/WGDashboard/wgd.sh restart
PIDFile=/opt/WGDashboard/gunicorn.pid
Restart=on-failure
User=root
[Install]
WantedBy=multi-user.target
EOF
# Step 10: Enable and start the dashboard
systemctl daemon-reload
systemctl enable wgdashboard
./wgd.sh start || systemctl start wgdashboard
# Step 11: Create verification script
cat > /root/check-vpn.sh <<'EOF'
#!/bin/bash
echo "=== WireGuard Status ==="
systemctl status wg-quick@wg0 --no-pager -l
echo -e "\n=== WireGuard Peers ==="
wg show
echo -e "\n=== IP Forwarding Status ==="
echo "Current value: $(cat /proc/sys/net/ipv4/ip_forward)"
echo "Should be: 1"
echo -e "\n=== NAT Rules ==="
iptables -t nat -L -n -v | grep -E "(MASQUERADE|Chain)"
echo -e "\n=== Forward Rules ==="
iptables -L FORWARD -n -v
echo -e "\n=== Network Interface ==="
ip route show default
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
if pgrep -f "gunicorn.*dashboard" > /dev/null || systemctl is-active --quiet wgdashboard 2>/dev/null; then
    echo "✅ WGDashboard is running"
else
    echo "⚠️  WGDashboard may need manual start: cd /opt/WGDashboard && ./wgd.sh start"
fi
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
echo "   Login: Check /opt/WGDashboard/src/wg-dashboard.ini or run: ./wgd.sh update"
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
echo "   WGDashboard: cd /opt/WGDashboard && ./wgd.sh [start|stop|restart]"
echo "   Add new client: Use the WGDashboard web interface"
echo ""
echo "⚠️  IMPORTANT NOTES:"
echo "   1. Set dashboard credentials: cd /opt/WGDashboard && ./wgd.sh update"
echo "   2. Server is ready to accept client connections"
echo "   3. Use the WGDashboard web interface to add clients"
echo "   4. For domain setup, create an A record pointing to $IPADDR"
echo "   5. IP forwarding configured in: /etc/sysctl.d/99-wireguard.conf"
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
