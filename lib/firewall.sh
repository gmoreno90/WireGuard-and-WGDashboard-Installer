#!/bin/bash

FIREWALL_TYPE=""
WIREGUARD_PORT=51820
DASHBOARD_PORT=10086

detect_firewall() {
    FIREWALL_TYPE="none"
    
    if command_exists ufw; then
        if ufw status 2>/dev/null | grep -qi "active\|enabled"; then
            FIREWALL_TYPE="ufw"
            log_info "Detected active firewall: UFW"
            return
        fi
    fi
    
    if command_exists firewall-cmd; then
        if firewall-cmd --state 2>/dev/null | grep -qi "running"; then
            FIREWALL_TYPE="firewalld"
            log_info "Detected active firewall: firewalld"
            return
        fi
    fi
    
    if command_exists iptables; then
        if iptables -L 2>/dev/null | grep -q "Chain"; then
            FIREWALL_TYPE="iptables"
            log_info "Using iptables for firewall rules"
            return
        fi
    fi
    
    log_info "No active firewall detected, will configure iptables"
    FIREWALL_TYPE="iptables"
}

configure_firewall() {
    log_info "Configuring firewall for WireGuard..."
    
    detect_firewall
    
    case "$FIREWALL_TYPE" in
        ufw)
            configure_ufw
            ;;
        firewalld)
            configure_firewalld
            ;;
        iptables|*)
            configure_iptables
            ;;
    esac
}

configure_ufw() {
    log_info "Configuring UFW..."
    
    ufw allow "$WIREGUARD_PORT"/udp comment 'WireGuard VPN' 2>/dev/null || {
        log_warn "Could not add WireGuard rule to UFW"
    }
    
    ufw allow "$DASHBOARD_PORT"/tcp comment 'WGDashboard' 2>/dev/null || {
        log_warn "Could not add WGDashboard rule to UFW"
    }
    
    if command_exists ufw; then
        ufw route allow in on wg0 out on "$PRIMARY_INTERFACE" 2>/dev/null || true
    fi
    
    ufw reload 2>/dev/null || true
    
    log_success "UFW configured: ports $WIREGUARD_PORT/udp and $DASHBOARD_PORT/tcp allowed"
}

configure_firewalld() {
    log_info "Configuring firewalld..."
    
    firewall-cmd --permanent --add-port="$WIREGUARD_PORT"/udp 2>/dev/null || {
        log_warn "Could not add WireGuard port to firewalld"
    }
    
    firewall-cmd --permanent --add-port="$DASHBOARD_PORT"/tcp 2>/dev/null || {
        log_warn "Could not add WGDashboard port to firewalld"
    }
    
    firewall-cmd --permanent --add-masquerade 2>/dev/null || true
    
    firewall-cmd --permanent --add-forward-port=port="$WIREGUARD_PORT":proto=udp:toport="$WIREGUARD_PORT" 2>/dev/null || true
    
    firewall-cmd --reload 2>/dev/null || true
    
    log_success "firewalld configured: ports $WIREGUARD_PORT/udp and $DASHBOARD_PORT/tcp allowed"
}

configure_iptables() {
    log_info "Configuring iptables..."
    
    iptables -A INPUT -p udp --dport "$WIREGUARD_PORT" -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport "$DASHBOARD_PORT" -j ACCEPT 2>/dev/null || true
    
    iptables -t nat -A POSTROUTING -s 10.99.99.0/24 -o "$PRIMARY_INTERFACE" -j MASQUERADE 2>/dev/null || true
    iptables -A FORWARD -i wg0 -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -o wg0 -j ACCEPT 2>/dev/null || true
    
    save_iptables_rules
    
    log_success "iptables configured"
}

save_iptables_rules() {
    if command_exists netfilter-persistent; then
        log_info "Saving iptables rules with netfilter-persistent..."
        netfilter-persistent save 2>/dev/null || {
            log_warn "Could not save rules with netfilter-persistent"
        }
    elif command_exists iptables-save; then
        local rules_dir="/etc/iptables"
        mkdir -p "$rules_dir"
        iptables-save > "$rules_dir/rules.v4" 2>/dev/null || {
            log_warn "Could not save iptables rules"
        }
    fi
}

setup_nat_rules() {
    log_info "Setting up NAT rules..."
    
    iptables -t nat -C POSTROUTING -s 10.99.99.0/24 -o "$PRIMARY_INTERFACE" -j MASQUERADE 2>/dev/null || {
        iptables -t nat -A POSTROUTING -s 10.99.99.0/24 -o "$PRIMARY_INTERFACE" -j MASQUERADE 2>/dev/null || {
            log_warn "Could not add MASQUERADE rule"
        }
    }
    
    iptables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null || {
        iptables -A FORWARD -i wg0 -j ACCEPT 2>/dev/null || true
    }
    
    iptables -C FORWARD -o wg0 -j ACCEPT 2>/dev/null || {
        iptables -A FORWARD -o wg0 -j ACCEPT 2>/dev/null || true
    }
    
    save_iptables_rules
    
    log_success "NAT rules configured"
}

get_firewall_status() {
    echo "=== Firewall Status ==="
    echo "Detected type: $FIREWALL_TYPE"
    
    case "$FIREWALL_TYPE" in
        ufw)
            ufw status 2>/dev/null | head -20
            ;;
        firewalld)
            firewall-cmd --list-all 2>/dev/null
            ;;
        iptables|*)
            echo "NAT rules:"
            iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -E "MASQUERADE|Chain"
            echo ""
            echo "FORWARD rules:"
            iptables -L FORWARD -n 2>/dev/null | head -10
            ;;
    esac
}
