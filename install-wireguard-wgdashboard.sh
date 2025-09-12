#!/bin/bash
set -e

echo "🔧 Installing WireGuard and WGDashboard with Domain Support on Debian 12..."
echo "⚠️  This script has been fixed to handle network interface detection and persistent rules"

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

# Step 3: Enable IP forwarding permanently
echo "🔀 Enabling IP forwarding..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p

# Step 4: Setup initial iptables rules
echo "🔥 Setting up firewall rules..."
# Clean any existing conflicting rules
iptables -t nat -F POSTROUTING || true
iptables -F FORWARD || true

# Add the correct rules
iptables -t nat -A POSTROUTING -s 10.99.99.0/24 -o $PRIMARY_INTERFACE -j MASQUERADE
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT
iptables -A FORWARD -i wg0 -o $PRIMARY_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $PRIMARY_INTERFACE -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Save rules for persistence
netfilter-persistent save

# Step 5: Enable and start WireGuard
echo "🚀 Starting WireGuard service..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0 || {
    echo "❌ WireGuard service failed to start. Checking logs..."
    journalctl -u wg-quick@wg0 --no-pager -l
    exit 1
}

# Step 6: Install WGDashboard
echo "🖥️  Installing WGDashboard..."
cd /opt
rm -rf WGDashboard
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
systemctl start wgdashboard

# Step 11: Generate client configuration template
echo "👤 Generating client configuration template..."
cd /etc/wireguard
umask 077
wg genkey | tee client1-private.key | wg pubkey > client1-public.key
CLIENT_PRIVATE_KEY=$(cat client1-private.key)
CLIENT_PUBLIC_KEY=$(cat client1-public.key)

# Add client to server configuration
wg set wg0 peer $CLIENT_PUBLIC_KEY allowed-ips 10.99.99.2/32
wg-quick save wg0

# Create client configuration file
cat > client1.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = 10.99.99.2/32
MTU = 1420
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = $PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = $(curl -s http://checkip.amazonaws.com || echo "YOUR_SERVER_IP"):51820
PersistentKeepalive = 25
EOF

# Step 12: Create verification script
cat > /root/check-vpn.sh <<'EOF'
#!/bin/bash
echo "=== WireGuard Status ==="
systemctl status wg-quick@wg0 --no-pager -l

echo -e "\n=== WireGuard Peers ==="
wg show

echo -e "\n=== NAT Rules ==="
iptables -t nat -L -n -v | grep -E "(MASQUERADE|Chain)"

echo -e "\n=== Forward Rules ==="
iptables -L FORWARD -n -v

echo -e "\n=== IP Forwarding ==="
cat /proc/sys/net/ipv4/ip_forward

echo -e "\n=== Network Interface ==="
ip route show default
EOF

chmod +x /root/check-vpn.sh

# Step 13: Final verification
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

# Get server IP
IPADDR=$(curl -s http://checkip.amazonaws.com || hostname -I | awk '{print $1}')

# Step 14: Output results
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
echo ""
echo "📱 Client Configuration:"
echo "   File location: /etc/wireguard/client1.conf"
echo "   Client IP: 10.99.99.2/32"
echo ""
echo "🔍 Useful Commands:"
echo "   Check VPN status: /root/check-vpn.sh"
echo "   View active peers: wg show"
echo "   View client config: cat /etc/wireguard/client1.conf"
echo ""
echo "⚠️  IMPORTANT NOTES:"
echo "   1. Change the dashboard password after first login"
echo "   2. The client configuration is ready to use in: /etc/wireguard/client1.conf"
echo "   3. For domain setup, create an A record pointing to $IPADDR (disable Cloudflare proxy)"
echo "   4. Firewall rules are automatically saved and will persist after reboot"
echo ""
echo "🧪 To test the installation:"
echo "   1. Copy /etc/wireguard/client1.conf to your client device"
echo "   2. Connect using WireGuard client"
echo "   3. Test with: ping 10.99.99.1 and ping 8.8.8.8"
echo ""
