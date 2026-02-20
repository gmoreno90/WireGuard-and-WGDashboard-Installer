# WireGuard + WGDashboard Installer

Universal installer for WireGuard VPN and WGDashboard web interface.

## Supported Systems

| System | Version | Status |
|--------|---------|--------|
| Debian | 12 (Bookworm) | Fully Supported |
| Debian | 13 (Trixie) | Fully Supported |
| Raspberry Pi OS | Bookworm | Fully Supported |
| Raspberry Pi OS | Trixie | Fully Supported |
| Ubuntu | 20.04/22.04/24.04 | Experimental |

## Features

- Automatic OS detection (Debian 12/13, Raspberry Pi OS)
- Compatible sysctl configuration (works on systems with or without `/etc/sysctl.conf`)
- Automatic firewall configuration (ufw, firewalld, iptables)
- Automatic network interface detection
- Installation logging to `/var/log/wireguard-installer.log`
- Automatic rollback on failure
- Detection of existing installations (prevents accidental overwrites)

## Requirements

- Fresh system (no existing WireGuard/WGDashboard installation)
- Root access
- Internet connection
- Open ports: `51820/UDP` (WireGuard) and `10086/TCP` (Dashboard)

## Quick Start

```bash
# Clone the repository
git clone https://github.com/gmoreno90/WireGuard-and-WGDashboard-Installer.git

# Enter directory
cd WireGuard-and-WGDashboard-Installer

# Run installer
sudo ./install.sh
```

## After Installation

Access the dashboard at: `http://YOUR_SERVER_IP:10086`

Default credentials:
- Username: `admin`
- Password: `admin`

**Important:** Change the default password immediately after first login!

## Project Structure

```
.
├── install.sh              # Main entry point
├── lib/
│   ├── common.sh           # Logging, colors, utilities
│   ├── detect-os.sh        # OS detection
│   ├── sysctl-config.sh    # IP forwarding config
│   ├── firewall.sh         # Firewall management
│   ├── wireguard.sh        # WireGuard setup
│   └── dashboard.sh        # WGDashboard setup
└── README.md
```

## Configuration

Default settings can be modified in the library files:

| Setting | File | Default |
|---------|------|---------|
| VPN Port | `lib/wireguard.sh` | 51820 |
| VPN Network | `lib/wireguard.sh` | 10.99.99.0/24 |
| Dashboard Port | `lib/dashboard.sh` | 10086 |
| Dashboard User | `lib/dashboard.sh` | admin |
| Dashboard Pass | `lib/dashboard.sh` | admin |

## Troubleshooting

### Check Status
```bash
/root/check-vpn.sh
```

### View Logs
```bash
# Installation log
cat /var/log/wireguard-installer.log

# WireGuard service
journalctl -u wg-quick@wg0 -f

# Dashboard service
journalctl -u wgdashboard -f
```

### Common Issues

**IP Forwarding not working:**
```bash
# Check current value
cat /proc/sys/net/ipv4/ip_forward

# Apply sysctl settings
sysctl --system
```

**Port already in use:**
```bash
# Check what's using the port
ss -tlnp | grep 10086
ss -ulnp | grep 51820
```

**Dashboard not starting:**
```bash
# Check Python dependencies
python3 -c "import flask, bcrypt, psutil"

# Reinstall requirements
pip3 install --break-system-packages -r /opt/WGDashboard/src/requirements.txt
```

## Uninstallation

```bash
systemctl stop wg-quick@wg0 wgdashboard
systemctl disable wg-quick@wg0 wgdashboard
rm -f /etc/systemd/system/wgdashboard.service
rm -rf /etc/wireguard
rm -rf /opt/WGDashboard
rm -f /etc/sysctl.d/99-wireguard.conf
systemctl daemon-reload
```

## Resources

- [WireGuard Documentation](https://www.wireguard.com/quickstart/)
- [WGDashboard GitHub](https://github.com/donaldzou/WGDashboard)

## Disclaimer

This script is provided "as is" with no warranty. Use at your own risk and always review the code before running on production systems.
