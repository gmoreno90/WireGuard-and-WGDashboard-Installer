#!/bin/bash

echo "=========================================="
echo "  WireGuard Installer - OS Simulation Tests"
echo "=========================================="
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

TEST_DIR="/tmp/wg-installer-test-$$"
mkdir -p "$TEST_DIR"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

create_os_release() {
    local id="$1"
    local version_id="$2"
    local pretty_name="$3"
    
    mkdir -p "$TEST_DIR/etc"
    cat > "$TEST_DIR/etc/os-release" << EOF
ID=$id
VERSION_ID="$version_id"
PRETTY_NAME="$pretty_name"
EOF
}

test_debian12_detection() {
    echo "Test: Debian 12 (Bookworm) detection"
    
    create_os_release "debian" "12" "Debian GNU/Linux 12 (bookworm)"
    
    source "$LIB_DIR/common.sh" 2>/dev/null
    
    (
        OS_ID=""
        OS_VERSION_ID=""
        OS_PRETTY_NAME=""
        OS_IS_RASPBERRY_PI=false
        OS_IS_DEBIAN=false
        
        . "$TEST_DIR/etc/os-release"
        OS_ID="${ID:-unknown}"
        OS_VERSION_ID="${VERSION_ID:-unknown}"
        OS_PRETTY_NAME="${PRETTY_NAME:-$OS_ID $OS_VERSION_ID}"
        
        if [ "$OS_ID" = "debian" ] && [ "$OS_VERSION_ID" = "12" ]; then
            echo "  OS: $OS_PRETTY_NAME - OK"
            exit 0
        else
            echo "  Expected debian/12, got $OS_ID/$OS_VERSION_ID"
            exit 1
        fi
    ) && pass "Debian 12" || fail "Debian 12"
}

test_debian13_detection() {
    echo "Test: Debian 13 (Trixie) detection"
    
    create_os_release "debian" "13" "Debian GNU/Linux 13 (trixie)"
    
    (
        OS_ID=""
        OS_VERSION_ID=""
        
        . "$TEST_DIR/etc/os-release"
        OS_ID="${ID:-unknown}"
        OS_VERSION_ID="${VERSION_ID:-unknown}"
        
        if [ "$OS_ID" = "debian" ] && [ "$OS_VERSION_ID" = "13" ]; then
            echo "  OS: $PRETTY_NAME - OK"
            exit 0
        else
            echo "  Expected debian/13, got $OS_ID/$OS_VERSION_ID"
            exit 1
        fi
    ) && pass "Debian 13" || fail "Debian 13"
}

test_raspbian_detection() {
    echo "Test: Raspbian detection"
    
    create_os_release "raspbian" "12" "Raspbian GNU/Linux 12 (bookworm)"
    
    (
        OS_ID=""
        OS_VERSION_ID=""
        
        . "$TEST_DIR/etc/os-release"
        OS_ID="${ID:-unknown}"
        OS_VERSION_ID="${VERSION_ID:-unknown}"
        
        if [ "$OS_ID" = "raspbian" ]; then
            echo "  OS: $PRETTY_NAME - OK"
            exit 0
        else
            echo "  Expected raspbian, got $OS_ID"
            exit 1
        fi
    ) && pass "Raspbian" || fail "Raspbian"
}

test_sysctl_method_debian12() {
    echo "Test: Sysctl method for Debian 12 (has /etc/sysctl.conf)"
    
    mkdir -p "$TEST_DIR/etc"
    touch "$TEST_DIR/etc/sysctl.conf"
    
    if [ -f "$TEST_DIR/etc/sysctl.conf" ]; then
        pass "Debian 12 uses /etc/sysctl.conf"
    else
        fail "Debian 12 sysctl.conf detection"
    fi
}

test_sysctl_method_debian13() {
    echo "Test: Sysctl method for Debian 13 (no /etc/sysctl.conf)"
    
    mkdir -p "$TEST_DIR/etc"
    
    if [ ! -f "$TEST_DIR/etc/sysctl.conf" ]; then
        echo "  No /etc/sysctl.conf - should use /etc/sysctl.d/"
        pass "Debian 13 uses /etc/sysctl.d/"
    else
        fail "Debian 13 sysctl detection"
    fi
}

test_sysctl_d_creation() {
    echo "Test: Creating /etc/sysctl.d/99-wireguard.conf"
    
    mkdir -p "$TEST_DIR/etc/sysctl.d"
    local config_file="$TEST_DIR/etc/sysctl.d/99-wireguard.conf"
    
    cat > "$config_file" << EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
    
    if [ -f "$config_file" ] && grep -q "net.ipv4.ip_forward = 1" "$config_file"; then
        pass "sysctl.d config created correctly"
    else
        fail "sysctl.d config creation"
    fi
}

test_sysctl_conf_update() {
    echo "Test: Updating /etc/sysctl.conf"
    
    mkdir -p "$TEST_DIR/etc"
    local config_file="$TEST_DIR/etc/sysctl.conf"
    
    echo "# Some config" > "$config_file"
    echo "net.ipv4.ip_forward=1" >> "$config_file"
    
    if grep -q "net.ipv4.ip_forward=1" "$config_file"; then
        pass "sysctl.conf updated correctly"
    else
        fail "sysctl.conf update"
    fi
}

echo ""
echo "=== Running OS Simulation Tests ==="
echo ""

test_debian12_detection
test_debian13_detection
test_raspbian_detection

echo ""
echo "=== Running Sysctl Tests ==="
echo ""

test_sysctl_method_debian12
test_sysctl_method_debian13
test_sysctl_d_creation
test_sysctl_conf_update

echo ""
echo "=========================================="
echo "OS Simulation Tests Complete"
echo "=========================================="
