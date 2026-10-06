#!/usr/bin/env bash
# Jetson Thor - Network Configuration Setup
# Sets up Jetson AGX Thor network interfaces with Jumbo frames, DHCP, and loopback

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        print_error "Please run as root"
        exit 1
    fi
}

# Enable lingering for user sessions
enable_linger() {
    # Get current default user if not jetson
    local user="${SUDO_USER:-jetson}"
    print_status "Enabling systemd lingering for user: $user"
    sudo loginctl enable-linger "$user" 2>/dev/null || print_warning "Lingering already enabled or user not found"
}

# Create network connection for mgbe0 (DHCP Server)
setup_mgbe0() {
    print_status "Configuring mgbe0_0 as DHCP Server (192.168.100.0/24)..."
    
    if nmcli connection show mgbe0-dhcp >/dev/null 2>&1; then
        print_warning "mgbe0-dhcp connection already exists"
        return
    fi
    
    sudo nmcli connection add \
        type ethernet \
        ifname mgbe0_0 \
        con-name mgbe0-dhcp \
        ipv4.method manual \
        ipv4.addresses 192.168.100.1/24 \
        ipv4.never-default yes \
        ipv6.method ignore \
        802-3-ethernet.mtu 9000
    
    print_status "mgbe0_0 connection created"
}

# Create network connection for mgbe1 (DHCP Client)
setup_mgbe1() {
    print_status "Configuring mgbe1_0 as static IP (192.168.101.0/24)..."
    
    if nmcli connection show mgbe1-dhcp >/dev/null 2>&1; then
        print_warning "mgbe1-dhcp connection already exists"
        return
    fi
    
    sudo nmcli connection add \
        type ethernet \
        ifname mgbe1_0 \
        con-name mgbe1-dhcp \
        ipv4.method manual \
        ipv4.addresses 192.168.101.1/24 \
        ipv4.never-default yes \
        ipv6.method ignore \
        802-3-ethernet.mtu 9000
    
    print_status "mgbe1_0 connection created"
}

# Create network connection for mgbe2 (Uplink with auto config)
setup_mgbe2() {
    print_status "Configuring mgbe2_0 as auto-configured uplink..."
    
    if nmcli connection show uplink-mgbe2_0 >/dev/null 2>&1; then
        print_warning "uplink-mgbe2_0 connection already exists"
        return
    fi
    
    sudo nmcli connection add \
        type ethernet \
        ifname mgbe2_0 \
        con-name uplink-mgbe2_0 \
        autoconnect yes \
        ipv4.method auto \
        ipv6.method auto \
        802-3-ethernet.auto-negotiate yes
    
    print_status "mgbe2_0 connection created"
}

# Create network connection for mgbe3 (Uplink with auto config)
setup_mgbe3() {
    print_status "Configuring mgbe3_0 as auto-configured uplink..."
    
    if nmcli connection show uplink-mgbe3_0 >/dev/null 2>&1; then
        print_warning "uplink-mgbe3_0 connection already exists"
        return
    fi
    
    sudo nmcli connection add \
        type ethernet \
        ifname mgbe3_0 \
        con-name uplink-mgbe3_0 \
        autoconnect yes \
        ipv4.method disabled \
        ipv6.method disabled \
        802-3-ethernet.auto-negotiate yes
    
    print_status "mgbe3_0 connection created"
}

# Create loopback interface for management
setup_loopback() {
    print_status "Configuring loopback management interface (10.255.255.1/32)..."
    
    if nmcli connection show loopback-mgmt >/dev/null 2>&1; then
        print_warning "loopback-mgmt connection already exists"
        return
    fi
    
    sudo nmcli connection add \
        type loopback \
        ifname lo \
        con-name loopback-mgmt \
        ipv4.method manual \
        ipv4.addresses 10.255.255.1/32
    
    print_status "Loopback connection created"
    
    # NM weist die IP normalerweise sofort zu; Fallback mit || true absichern
    if ! ip -4 addr show dev lo | grep -Fq "10.255.255.1"; then
        sudo ip addr add 10.255.255.1/32 dev lo 2>/dev/null || true
        print_status "Loopback IP added"
    fi
}

# Disable IPv6 system-wide
disable_ipv6() {
    print_status "Disabling IPv6 system-wide..."
    
    if grep -q "net.ipv6.conf.all.disable_ipv6=1" /etc/sysctl.conf; then
        print_warning "IPv6 already disabled"
        return
    fi
    
    # Add IPv6 disable settings to sysctl.conf
    sudo tee -a /etc/sysctl.conf > /dev/null <<EOF
# Disable IPv6
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
EOF
    
    # Apply settings
    sudo sysctl -p >/dev/null 2>&1 || print_warning "sysctl reload had issues"
    print_status "IPv6 disabled"
}

# Enable Wayland and select it as the default GDM session
enable_wayland() {
    print_status "Enabling Wayland for GDM..."

    local gdm_conf="/etc/gdm3/custom.conf"
    local wayland_session=""

    if [[ -f "/usr/share/wayland-sessions/ubuntu-wayland.desktop" ]]; then
        wayland_session="ubuntu-wayland"
    elif [[ -f "/usr/share/wayland-sessions/gnome-wayland.desktop" ]]; then
        wayland_session="gnome-wayland"
    fi

    sudo mkdir -p /etc/gdm3

    if [[ ! -f "$gdm_conf" ]]; then
        sudo tee "$gdm_conf" >/dev/null <<'EOF'
[daemon]
WaylandEnable=true
EOF
    elif ! grep -qE '^\[daemon\][[:space:]]*$' "$gdm_conf"; then
        sudo tee -a "$gdm_conf" >/dev/null <<'EOF'

[daemon]
EOF
    fi

    if grep -qE '^[[:space:]]*WaylandEnable[[:space:]]*=[[:space:]]*false[[:space:]]*$' "$gdm_conf"; then
        sudo sed -i 's/^[[:space:]]*WaylandEnable[[:space:]]*=[[:space:]]*false[[:space:]]*$/WaylandEnable=true/' "$gdm_conf"
    elif ! grep -qE '^[[:space:]]*WaylandEnable[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$gdm_conf"; then
        sudo sed -i '/^\[daemon\][[:space:]]*$/a WaylandEnable=true' "$gdm_conf"
    fi

    if [[ -n "$wayland_session" ]]; then
        if grep -qE '^[[:space:]]*DefaultSession[[:space:]]*=' "$gdm_conf"; then
            sudo sed -i "s|^[[:space:]]*DefaultSession[[:space:]]*=.*$|DefaultSession=$wayland_session|" "$gdm_conf"
        else
            sudo sed -i "/^\[daemon\][[:space:]]*$/a DefaultSession=$wayland_session" "$gdm_conf"
        fi
        print_status "GDM default session set to $wayland_session"
    else
        print_warning "No supported Wayland session found; Wayland was enabled but must be selected manually"
    fi

    print_status "Wayland enabled in GDM config"
}

# Move GNOME window buttons to the left side
set_window_buttons_left() {
    print_status "Setting GNOME window buttons to the left..."

    local target_user="${SUDO_USER:-jetson}"
    local button_layout="close,minimize,maximize:"
    local dconf_profile="/etc/dconf/profile/user"
    local dconf_override="/etc/dconf/db/local.d/00-jetson-window-buttons"
    local target_uid
    local target_runtime_dir

    target_uid="$(id -u "$target_user" 2>/dev/null || true)"
    target_runtime_dir="/run/user/${target_uid}"

    sudo mkdir -p /etc/dconf/db/local.d /etc/dconf/profile

    if [[ ! -f "$dconf_profile" ]]; then
        sudo tee "$dconf_profile" >/dev/null <<'EOF'
user-db:user
system-db:local
EOF
    fi

    sudo tee "$dconf_override" >/dev/null <<EOF
[org/gnome/desktop/wm/preferences]
button-layout='$button_layout'
EOF

    if command -v dconf >/dev/null 2>&1; then
        sudo dconf update >/dev/null 2>&1 || true
    fi

    if command -v gsettings >/dev/null 2>&1; then
        if [[ -n "$target_uid" ]] && [[ -S "$target_runtime_dir/bus" ]]; then
            if sudo -u "$target_user" env HOME="/home/$target_user" XDG_RUNTIME_DIR="$target_runtime_dir" DBUS_SESSION_BUS_ADDRESS="unix:path=$target_runtime_dir/bus" gsettings set org.gnome.desktop.wm.preferences button-layout "$button_layout" >/dev/null 2>&1; then
                print_status "GNOME button layout applied for user: $target_user"
                return
            fi
        fi

        if sudo -u "$target_user" gsettings set org.gnome.desktop.wm.preferences button-layout "$button_layout" >/dev/null 2>&1; then
            print_status "GNOME button layout applied for user: $target_user"
            return
        fi
    fi

    print_warning "Could not apply GNOME button layout automatically"
    print_warning "Set org.gnome.desktop.wm.preferences button-layout to '$button_layout' manually if needed"
}

# Activate all network connections
activate_connections() {
    print_status "Activating network connections..."
    
    for conn in mgbe0-dhcp mgbe1-dhcp uplink-mgbe2_0 uplink-mgbe3_0 loopback-mgmt; do
        if nmcli connection show "$conn" >/dev/null 2>&1; then
            sudo nmcli connection up "$conn" 2>/dev/null || print_warning "Connection $conn already up"
        fi
    done
    
    print_status "Network connections activated"
}

# Show current network status
show_status() {
    print_status "Current network configuration:"
    echo ""
    echo "Network Connections:"
    nmcli connection show --active
    echo ""
    echo "Network Interfaces:"
    ip -br addr show
    echo ""
}

main() {
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║  Jetson AGX Thor - Network Setup     ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    
    require_root
    
    print_status "Setting up Jetson AGX Thor network configuration..."
    echo ""
    
    enable_linger
    setup_mgbe0
    setup_mgbe1
    setup_mgbe2
    setup_mgbe3
    setup_loopback
    disable_ipv6
    enable_wayland
    set_window_buttons_left
    activate_connections
    
    echo ""
    show_status
    
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║   ✓ Thor network setup complete      ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
}

main "$@"
