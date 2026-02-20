#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((TESTS_SKIPPED++))
}

section() {
    echo ""
    echo "=== $1 ==="
}

test_file_exists() {
    local file="$1"
    local desc="${2:-$file}"
    if [ -f "$file" ]; then
        pass "File exists: $desc"
        return 0
    else
        fail "File missing: $desc"
        return 1
    fi
}

test_file_executable() {
    local file="$1"
    local desc="${2:-$file}"
    if [ -x "$file" ]; then
        pass "Executable: $desc"
        return 0
    else
        fail "Not executable: $desc"
        return 1
    fi
}

test_bash_syntax() {
    local file="$1"
    local desc="${2:-$file}"
    if bash -n "$file" 2>/dev/null; then
        pass "Syntax OK: $desc"
        return 0
    else
        fail "Syntax error: $desc"
        bash -n "$file" 2>&1
        return 1
    fi
}

test_shellcheck() {
    local file="$1"
    local desc="${2:-$file}"
    if command -v shellcheck &>/dev/null; then
        if shellcheck -s bash -x "$file" 2>/dev/null; then
            pass "ShellCheck OK: $desc"
            return 0
        else
            fail "ShellCheck issues: $desc"
            shellcheck -s bash -x "$file" 2>&1 | head -20
            return 1
        fi
    else
        skip "ShellCheck not installed"
        return 2
    fi
}

test_function_defined() {
    local file="$1"
    local func="$2"
    local desc="${3:-$func in $(basename $file)}"
    if grep -q "^${func}()" "$file" 2>/dev/null || grep -q "^function ${func}" "$file" 2>/dev/null; then
        pass "Function defined: $desc"
        return 0
    else
        fail "Function missing: $desc"
        return 1
    fi
}

test_no_hardcoded_paths() {
    local file="$1"
    local desc="${2:-$(basename $file)}"
    local issues=0
    
    if grep -E '(^|[^/])/etc/sysctl\.conf[^.]' "$file" | grep -v 'if.*-f' | grep -v 'has_sysctl' | grep -v 'sysctl_method' >/dev/null 2>&1; then
        echo "  Warning: Hardcoded /etc/sysctl.conf usage found"
        ((issues++))
    fi
    
    if [ $issues -eq 0 ]; then
        pass "No problematic hardcoded paths: $desc"
        return 0
    else
        fail "Found $issues hardcoded path issues: $desc"
        return 1
    fi
}

section "File Structure Tests"

test_file_exists "$(dirname "$SCRIPT_DIR")/install.sh" "Main install.sh"
test_file_exists "$LIB_DIR/common.sh" "lib/common.sh"
test_file_exists "$LIB_DIR/detect-os.sh" "lib/detect-os.sh"
test_file_exists "$LIB_DIR/sysctl-config.sh" "lib/sysctl-config.sh"
test_file_exists "$LIB_DIR/firewall.sh" "lib/firewall.sh"
test_file_exists "$LIB_DIR/wireguard.sh" "lib/wireguard.sh"
test_file_exists "$LIB_DIR/dashboard.sh" "lib/dashboard.sh"

section "Executable Tests"

test_file_executable "$(dirname "$SCRIPT_DIR")/install.sh" "install.sh"

section "Syntax Tests"

for file in "$LIB_DIR"/*.sh "$(dirname "$SCRIPT_DIR")/install.sh"; do
    test_bash_syntax "$file"
done

section "ShellCheck Tests"

for file in "$LIB_DIR"/*.sh "$(dirname "$SCRIPT_DIR")/install.sh"; do
    test_shellcheck "$file"
done

section "Function Definition Tests"

test_function_defined "$LIB_DIR/common.sh" "init_logging"
test_function_defined "$LIB_DIR/common.sh" "log"
test_function_defined "$LIB_DIR/common.sh" "check_root"
test_function_defined "$LIB_DIR/common.sh" "check_existing_installation"
test_function_defined "$LIB_DIR/common.sh" "detect_primary_interface"
test_function_defined "$LIB_DIR/common.sh" "rollback"
test_function_defined "$LIB_DIR/common.sh" "create_verification_script"

test_function_defined "$LIB_DIR/detect-os.sh" "detect_os"
test_function_defined "$LIB_DIR/detect-os.sh" "validate_os_support"
test_function_defined "$LIB_DIR/detect-os.sh" "get_package_manager"
test_function_defined "$LIB_DIR/detect-os.sh" "has_sysctl_conf"
test_function_defined "$LIB_DIR/detect-os.sh" "get_sysctl_method"

test_function_defined "$LIB_DIR/sysctl-config.sh" "configure_ip_forwarding"
test_function_defined "$LIB_DIR/sysctl-config.sh" "configure_sysctl_conf"
test_function_defined "$LIB_DIR/sysctl-config.sh" "configure_sysctl_d"
test_function_defined "$LIB_DIR/sysctl-config.sh" "verify_ip_forwarding"

test_function_defined "$LIB_DIR/firewall.sh" "detect_firewall"
test_function_defined "$LIB_DIR/firewall.sh" "configure_firewall"
test_function_defined "$LIB_DIR/firewall.sh" "configure_ufw"
test_function_defined "$LIB_DIR/firewall.sh" "configure_firewalld"
test_function_defined "$LIB_DIR/firewall.sh" "configure_iptables"

test_function_defined "$LIB_DIR/wireguard.sh" "install_wireguard"
test_function_defined "$LIB_DIR/wireguard.sh" "generate_wireguard_keys"
test_function_defined "$LIB_DIR/wireguard.sh" "create_wireguard_config"
test_function_defined "$LIB_DIR/wireguard.sh" "start_wireguard"
test_function_defined "$LIB_DIR/wireguard.sh" "verify_wireguard"

test_function_defined "$LIB_DIR/dashboard.sh" "install_dashboard"
test_function_defined "$LIB_DIR/dashboard.sh" "create_dashboard_config"
test_function_defined "$LIB_DIR/dashboard.sh" "create_dashboard_service"
test_function_defined "$LIB_DIR/dashboard.sh" "verify_dashboard"

section "Code Quality Tests"

for file in "$LIB_DIR"/*.sh; do
    test_no_hardcoded_paths "$file"
done

section "Summary"

echo ""
echo "Results:"
echo "  Passed:  $TESTS_PASSED"
echo "  Failed:  $TESTS_FAILED"
echo "  Skipped: $TESTS_SKIPPED"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
