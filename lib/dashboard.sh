#!/bin/bash

DASHBOARD_DIR="/opt/WGDashboard"
DASHBOARD_PORT=10086
DASHBOARD_USER="admin"
DASHBOARD_PASS="admin"

install_dashboard() {
    log_info "Installing WGDashboard..."
    
    install_python_deps
    
    clone_dashboard
    
    install_python_requirements
    
    create_dashboard_config
    
    create_dashboard_service
    
    start_dashboard
    
    verify_dashboard
}

install_python_deps() {
    log_info "Installing Python dependencies..."
    
    local packages="python3 python3-pip git"
    
    $PKG_INSTALL $packages 2>/dev/null || {
        log_warn "Some Python packages may have failed to install"
    }
    
    if ! command_exists python3; then
        log_error "Python3 installation failed"
        return 1
    fi
    
    log_success "Python dependencies installed"
}

clone_dashboard() {
    log_info "Cloning WGDashboard repository..."
    
    if [ -d "$DASHBOARD_DIR" ]; then
        log_warn "Existing WGDashboard directory found"
        if [ -d "$DASHBOARD_DIR/.git" ]; then
            log_info "Updating existing repository..."
            cd "$DASHBOARD_DIR" && git pull 2>/dev/null || {
                log_warn "Could not update repository, will reinstall"
                rm -rf "$DASHBOARD_DIR"
            }
        else
            log_info "Backing up and removing non-git directory..."
            mv "$DASHBOARD_DIR" "$DASHBOARD_DIR.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || {
                rm -rf "$DASHBOARD_DIR"
            }
        fi
    fi
    
    if [ ! -d "$DASHBOARD_DIR" ]; then
        git clone https://github.com/donaldzou/WGDashboard.git "$DASHBOARD_DIR" 2>/dev/null || {
            log_error "Failed to clone WGDashboard repository"
            return 1
        }
    fi
    
    log_success "WGDashboard repository ready"
}

install_python_requirements() {
    log_info "Installing Python requirements..."
    
    local requirements_file="$DASHBOARD_DIR/src/requirements.txt"
    
    if [ ! -f "$requirements_file" ]; then
        log_warn "requirements.txt not found at $requirements_file"
        log_info "Searching for requirements.txt..."
        requirements_file=$(find "$DASHBOARD_DIR" -name "requirements.txt" 2>/dev/null | head -1)
        
        if [ -z "$requirements_file" ]; then
            log_warn "No requirements.txt found, attempting to install common dependencies"
            pip3 install --break-system-packages flask bcrypt psutil 2>/dev/null || true
            return 0
        fi
    fi
    
    pip3 install --break-system-packages -r "$requirements_file" 2>&1 | tee /tmp/pip_install.log || {
        if grep -q "Cannot uninstall" /tmp/pip_install.log 2>/dev/null; then
            log_warn "Dependency conflict detected, attempting workaround..."
            pip3 install --break-system-packages --ignore-installed -r "$requirements_file" 2>/dev/null || {
                log_warn "Some packages may not have installed correctly"
            }
        fi
    }
    
    python3 -c "import flask" 2>/dev/null || {
        log_warn "Flask not installed, attempting direct installation..."
        pip3 install --break-system-packages flask 2>/dev/null || true
    }
    
    python3 -c "import bcrypt" 2>/dev/null || {
        pip3 install --break-system-packages bcrypt 2>/dev/null || true
    }
    
    python3 -c "import psutil" 2>/dev/null || {
        pip3 install --break-system-packages psutil 2>/dev/null || true
    }
    
    log_success "Python requirements installed"
}

create_dashboard_config() {
    log_info "Creating WGDashboard configuration..."
    
    local config_dir="$DASHBOARD_DIR/src"
    mkdir -p "$config_dir"
    
    local wg_config_path="/etc/wireguard/${WG_INTERFACE:-wg0}.conf"
    
    cat > "$config_dir/config.json" << EOF
{
  "wg_conf_path": "$wg_config_path",
  "interface": "${WG_INTERFACE:-wg0}",
  "listen_port": $DASHBOARD_PORT,
  "username": "$DASHBOARD_USER",
  "password": "$DASHBOARD_PASS"
}
EOF
    
    chmod 600 "$config_dir/config.json"
    
    log_success "WGDashboard configuration created"
}

create_dashboard_service() {
    log_info "Creating WGDashboard systemd service..."
    
    local working_dir="$DASHBOARD_DIR/src"
    local dashboard_script="$working_dir/dashboard.py"
    
    if [ ! -f "$dashboard_script" ]; then
        dashboard_script=$(find "$DASHBOARD_DIR" -name "dashboard.py" 2>/dev/null | head -1)
        if [ -n "$dashboard_script" ]; then
            working_dir=$(dirname "$dashboard_script")
        else
            log_warn "dashboard.py not found, using default path"
        fi
    fi
    
    cat > /etc/systemd/system/wgdashboard.service << EOF
[Unit]
Description=WGDashboard Web UI
After=network.target wg-quick@${WG_INTERFACE:-wg0}.service
Wants=wg-quick@${WG_INTERFACE:-wg0}.service

[Service]
WorkingDirectory=$working_dir
ExecStart=/usr/bin/python3 $dashboard_script
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    
    log_success "WGDashboard service created"
}

start_dashboard() {
    log_info "Starting WGDashboard service..."
    
    systemctl enable wgdashboard 2>/dev/null || {
        log_warn "Could not enable WGDashboard service"
    }
    
    systemctl start wgdashboard || {
        log_error "Failed to start WGDashboard service"
        journalctl -u wgdashboard --no-pager -n 20 2>/dev/null
        return 1
    }
    
    sleep 3
    
    if systemctl is-active --quiet wgdashboard; then
        log_success "WGDashboard service started"
        return 0
    else
        log_error "WGDashboard service is not running"
        journalctl -u wgdashboard --no-pager -n 30 2>/dev/null
        return 1
    fi
}

verify_dashboard() {
    log_info "Verifying WGDashboard installation..."
    
    if [ ! -d "$DASHBOARD_DIR" ]; then
        log_error "WGDashboard directory not found"
        return 1
    fi
    
    if [ ! -f /etc/systemd/system/wgdashboard.service ]; then
        log_error "WGDashboard service file not found"
        return 1
    fi
    
    if ! systemctl is-active --quiet wgdashboard; then
        log_warn "WGDashboard service is not active"
        return 1
    fi
    
    local port_check
    port_check=$(ss -tln 2>/dev/null | grep ":$DASHBOARD_PORT " || netstat -tln 2>/dev/null | grep ":$DASHBOARD_PORT " || true)
    
    if [ -n "$port_check" ]; then
        log_success "WGDashboard is listening on port $DASHBOARD_PORT"
    else
        log_warn "WGDashboard may not be listening on port $DASHBOARD_PORT yet"
    fi
    
    log_success "WGDashboard verification passed"
    return 0
}

get_dashboard_status() {
    echo "=== WGDashboard Status ==="
    systemctl status wgdashboard --no-pager 2>/dev/null | head -10
    echo ""
    echo "=== Access Information ==="
    local ip="${PUBLIC_IP:-$(hostname -I | awk '{print $1}')}"
    echo "URL: http://$ip:$DASHBOARD_PORT"
    echo "Username: $DASHBOARD_USER"
    echo "Password: $DASHBOARD_PASS"
    echo ""
    echo "=== Installation Directory ==="
    echo "Path: $DASHBOARD_DIR"
}

print_dashboard_info() {
    local ip="${PUBLIC_IP:-YOUR_SERVER_IP}"
    
    echo ""
    echo "=== WGDashboard Access ==="
    echo "URL: http://$ip:$DASHBOARD_PORT"
    echo "Username: $DASHBOARD_USER"
    echo "Password: $DASHBOARD_PASS"
    echo ""
    echo "WARNING: Change the default password after first login!"
}
