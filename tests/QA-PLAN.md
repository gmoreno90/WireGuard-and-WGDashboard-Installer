# QA Plan - WireGuard + WGDashboard Installer

## Overview

This document describes the Quality Assurance process for the WireGuard + WGDashboard installer.

## Test Categories

### 1. Static Analysis Tests (`test-static.sh`)

Run without installation - validates code quality.

```bash
chmod +x tests/test-static.sh
./tests/test-static.sh
```

Tests:
- [x] File structure completeness
- [x] Bash syntax validation
- [x] ShellCheck linting (if available)
- [x] Required function definitions
- [x] Hardcoded path detection

### 2. OS Simulation Tests (`test-os-simulation.sh`)

Simulates different OS environments without full installation.

```bash
chmod +x tests/test-os-simulation.sh
./tests/test-os-simulation.sh
```

Tests:
- [x] Debian 12 detection
- [x] Debian 13 detection
- [x] Raspbian detection
- [x] sysctl.conf method selection
- [x] sysctl.d method selection

### 3. Integration Tests (`test-integration-checklist.sh`)

Manual checklist for testing on real systems.

```bash
chmod +x tests/test-integration-checklist.sh
./tests/test-integration-checklist.sh
```

## Test Environments

### Minimum Required

| Environment | Method | Priority |
|-------------|--------|----------|
| Debian 12 | Docker/VM | Required |
| Debian 13 | Docker/VM | Required |
| Raspberry Pi OS | Hardware/Pi | Recommended |

### Docker Quick Test

```bash
# Debian 12
docker run -d --name wg-deb12 --privileged \
  -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
  debian:12 sleep infinity

docker exec -it wg-deb12 bash
apt update && apt install -y curl git
curl -O https://raw.githubusercontent.com/.../install.sh
chmod +x install.sh
./install.sh
```

```bash
# Debian 13 (testing)
docker run -d --name wg-deb13 --privileged \
  -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
  debian:testing sleep infinity

docker exec -it wg-deb13 bash
# Same steps as above
```

## Test Matrix

| Test Case | Debian 12 | Debian 13 | RPi OS |
|-----------|:---------:|:---------:|:------:|
| OS Detection | | | |
| Package Installation | | | |
| Key Generation | | | |
| Config Creation | | | |
| sysctl.conf method | N/A | | N/A |
| sysctl.d method | N/A | | N/A |
| IP Forwarding | | | |
| Firewall Config | | | |
| WireGuard Start | | | |
| Dashboard Install | | | |
| Dashboard Start | | | |
| VPN Connectivity | | | |
| Reboot Persistence | | | |

## Automated CI/CD (Future)

```yaml
# .github/workflows/test.yml
name: Test Installer

on: [push, pull_request]

jobs:
  static-analysis:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run ShellCheck
        run: |
          sudo apt install -y shellcheck
          ./tests/test-static.sh

  test-debian12:
    runs-on: ubuntu-latest
    container: debian:12
    steps:
      - uses: actions/checkout@v4
      - name: Test on Debian 12
        run: |
          apt update
          # Run simulation tests only (can't install WireGuard in CI)

  test-debian13:
    runs-on: ubuntu-latest
    container: debian:testing
    steps:
      - uses: actions/checkout@v4
      - name: Test on Debian 13
        run: |
          apt update
          # Run simulation tests only
```

## Known Issues & Edge Cases

1. **Docker containers**: Need `--privileged` flag for systemd
2. **LXC containers**: May need specific configuration for WireGuard
3. **VPNs/proxies**: Public IP detection may fail
4. **Custom interfaces**: Primary interface detection may need manual override

## Rollback Testing

To test rollback functionality:

```bash
# Simulate failure during installation
# Edit a lib/*.sh file to add 'exit 1' at a specific point
# Run installer and verify cleanup happens
```

## Reporting Issues

When reporting test failures, include:

1. OS and version (`cat /etc/os-release`)
2. Installation log (`/var/log/wireguard-installer.log`)
3. Service status (`systemctl status wg-quick@wg0 wgdashboard`)
4. Network info (`ip addr`, `ip route`)
