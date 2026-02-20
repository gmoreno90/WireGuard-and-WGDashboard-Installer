#!/bin/bash

OS_ID=""
OS_VERSION_ID=""
OS_PRETTY_NAME=""
OS_IS_RASPBERRY_PI=false
OS_IS_DEBIAN=false
OS_IS_UBUNTU=false

detect_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot detect OS: /etc/os-release not found"
        exit 1
    fi
    
    . /etc/os-release
    
    OS_ID="${ID:-unknown}"
    OS_VERSION_ID="${VERSION_ID:-unknown}"
    OS_PRETTY_NAME="${PRETTY_NAME:-$OS_ID $OS_VERSION_ID}"
    
    if [ -f /proc/device-tree/model ] && grep -qi "raspberry" /proc/device-tree/model 2>/dev/null; then
        OS_IS_RASPBERRY_PI=true
    fi
    
    case "$OS_ID" in
        debian)
            OS_IS_DEBIAN=true
            ;;
        raspbian)
            OS_IS_DEBIAN=true
            OS_IS_RASPBERRY_PI=true
            ;;
        ubuntu)
            OS_IS_UBUNTU=true
            ;;
        *)
            log_warn "Untested OS: $OS_PRETTY_NAME"
            log_warn "Proceeding with generic installation..."
            ;;
    esac
    
    log_info "Detected OS: $OS_PRETTY_NAME"
    
    if [ "$OS_IS_RASPBERRY_PI" = true ]; then
        log_info "Platform: Raspberry Pi"
    fi
}

validate_os_support() {
    local supported=true
    
    if [ "$OS_IS_DEBIAN" = true ]; then
        local major_version
        major_version=$(echo "$OS_VERSION_ID" | cut -d. -f1)
        
        case "$major_version" in
            11|12|13)
                log_success "Debian $major_version is supported"
                ;;
            *)
                log_warn "Debian $major_version may not be fully tested"
                log_warn "Supported versions: 11, 12, 13"
                ;;
        esac
    fi
    
    if [ "$OS_IS_UBUNTU" = true ]; then
        local major_version
        major_version=$(echo "$OS_VERSION_ID" | cut -d. -f1)
        
        case "$major_version" in
            20|22|24)
                log_success "Ubuntu $major_version is supported"
                ;;
            *)
                log_warn "Ubuntu $major_version may not be fully tested"
                ;;
        esac
    fi
    
    if [ "$supported" = false ]; then
        log_error "Unsupported operating system"
        exit 1
    fi
}

get_package_manager() {
    if command_exists apt-get; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt-get update"
        PKG_INSTALL="apt-get install -y"
        PKG_CHECK="dpkg -l"
    elif command_exists dnf; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf makecache"
        PKG_INSTALL="dnf install -y"
        PKG_CHECK="rpm -q"
    elif command_exists yum; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum makecache"
        PKG_INSTALL="yum install -y"
        PKG_CHECK="rpm -q"
    else
        log_error "No supported package manager found"
        exit 1
    fi
    
    log_debug "Package manager: $PKG_MANAGER"
}

has_sysctl_conf() {
    if [ -f /etc/sysctl.conf ]; then
        return 0
    else
        return 1
    fi
}

get_sysctl_method() {
    if has_sysctl_conf; then
        SYSCTL_METHOD="sysctl.conf"
        SYSCTL_FILE="/etc/sysctl.conf"
        log_debug "Using traditional sysctl.conf"
    else
        SYSCTL_METHOD="sysctl.d"
        SYSCTL_FILE="/etc/sysctl.d/99-wireguard.conf"
        log_debug "Using modern sysctl.d directory"
    fi
}

print_os_info() {
    echo ""
    echo "=== System Information ==="
    echo "OS: $OS_PRETTY_NAME"
    echo "ID: $OS_ID"
    echo "Version: $OS_VERSION_ID"
    echo "Raspberry Pi: $OS_IS_RASPBERRY_PI"
    echo "Package Manager: $PKG_MANAGER"
    echo "Sysctl Method: $SYSCTL_METHOD"
    echo "=========================="
    echo ""
}
