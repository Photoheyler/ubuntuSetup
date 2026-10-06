#!/usr/bin/env bash
# Jetson AGX Thor - Complete Setup Script
# Installs: Git, Git LFS, Docker, Docker Compose, NVIDIA Docker, VS Code,
# Chrome, OpenSSH, TeamViewer, Tailscale, dnsmasq, PCAN driver

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo mode: script located at scripts/jetson/setup-jetson-thor.sh
if [[ "$(basename "$SCRIPT_DIR")" == "jetson" && "$(basename "$(dirname "$SCRIPT_DIR")")" == "scripts" && -f "$SCRIPT_DIR/../../setup.sh" ]]; then
    ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Bundle mode: script located at bundle root
elif [[ -f "$SCRIPT_DIR/setup.sh" ]]; then
    ROOT_DIR="$SCRIPT_DIR"
else
    ROOT_DIR="$SCRIPT_DIR"
fi
THORSETUP_SCRIPT="$ROOT_DIR/envSetup/jetson/thorsetup.sh"
ROUTING_SCRIPT="$ROOT_DIR/envSetup/jetson/setupRouting.sh"
START_APP_SCRIPT="$ROOT_DIR/scripts/jetson/start_app.sh"
APP_START_DESKTOP="$ROOT_DIR/scripts/jetson/APP-Start.desktop"  
APP_UPDATE_DESKTOP="$ROOT_DIR/scripts/jetson/APP-Update.desktop"
LOG_FILE="/var/log/jetson-setup.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        print_error "Please run with sudo/root"
        exit 1
    fi
}

check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Could not determine OS"
        exit 1
    fi

    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        print_error "This script is designed for Ubuntu. Detected: ${ID:-unknown}"
        exit 1
    fi

    print_status "Running on Ubuntu ${VERSION_ID:-unknown}"
}

enable_logging() {
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE" || true
    exec > >(tee -a "$LOG_FILE") 2>&1
    print_status "Logging to $LOG_FILE"
}

update_system() {
    if apt-get update --dry-run 2>/dev/null | grep -q "packages can be upgraded"; then
        print_status "Updating system packages..."
    else
        print_warning "System packages already up to date"
    fi
    sudo apt-get update -qq
    sudo apt-get upgrade -y -qq
}

hold_nvidia_l4t_packages() {
    print_status "Holding NVIDIA L4T packages..."
    sudo apt-mark hold 'nvidia-l4t-*'
    print_status "NVIDIA L4T packages held"
}

install_essentials() {
    if command -v curl &> /dev/null && command -v wget &> /dev/null; then
        print_warning "Essential utilities already installed"
        return
    fi
    print_status "Installing essential utilities (curl, wget, ca-certificates)..."
    sudo apt-get install -y -qq curl wget ca-certificates gnupg lsb-release
    print_status "Essential utilities installed"
}

install_git() {
    if command -v git &> /dev/null; then
        print_warning "Git already installed: $(git --version | cut -d' ' -f3)"
        return
    fi
    print_status "Installing Git..."
    sudo apt-get install -y -qq git
    print_status "Git installed: $(git --version | cut -d' ' -f3)"
}

install_git_lfs() {
    if command -v git-lfs &> /dev/null; then
        print_warning "Git LFS already installed"
        return
    fi
    print_status "Installing Git LFS..."
    curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash >/dev/null 2>&1
    sudo apt-get install -y -qq git-lfs
    git lfs install
    print_status "Git LFS installed"
}

ensure_docker_group_membership() {
    local target_user
    target_user="${SUDO_USER:-$USER}"

    if [[ -z "${target_user}" ]] || [[ "${target_user}" == "root" ]]; then
        print_warning "No non-root user detected for docker group assignment"
        return
    fi

    if id -nG "$target_user" 2>/dev/null | grep -qw docker; then
        print_warning "User $target_user already in docker group"
        return
    fi

    sudo usermod -aG docker "$target_user" 2>/dev/null || true
    print_status "Added user $target_user to docker group"
    print_warning "Run 'newgrp docker' (or log out/in) as $target_user to apply group changes"
}

install_docker() {
    if command -v docker &> /dev/null; then
        print_warning "Docker already installed: $(docker --version)"
        ensure_docker_group_membership
        return
    fi
    print_status "Installing Docker..."
    sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg >/dev/null 2>&1
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io
    sudo systemctl start docker 2>/dev/null || true
    sudo systemctl enable docker 2>/dev/null || true
    ensure_docker_group_membership
    print_status "Docker installed: $(docker --version)"
}

install_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        print_warning "Docker Compose already installed: $(docker-compose --version)"
        return
    fi
    print_status "Installing Docker Compose..."
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4 | sed 's/^v//')
    sudo curl -L "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose 2>/dev/null
    sudo chmod +x /usr/local/bin/docker-compose
    print_status "Docker Compose installed: $(docker-compose --version)"
}

ensure_nvidia_default_runtime() {
    if ! command -v docker &> /dev/null; then
        print_warning "Docker not available, cannot configure NVIDIA default runtime"
        return 1
    fi

    if command -v nvidia-ctk &> /dev/null; then
        if sudo nvidia-ctk runtime configure --runtime=docker --set-as-default >/dev/null 2>&1; then
            sudo systemctl restart docker 2>/dev/null || true
            if docker info 2>/dev/null | grep -qi 'Default Runtime: nvidia'; then
                print_status "Docker default runtime set to nvidia"
                return 0
            fi
        fi
    fi

    # Fallback for environments without nvidia-ctk.
    if [[ ! -f /etc/docker/daemon.json ]]; then
        sudo mkdir -p /etc/docker
        sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
EOF
      sudo systemctl restart docker 2>/dev/null || true
  fi

    if docker info 2>/dev/null | grep -qi 'Default Runtime: nvidia'; then
        print_status "Docker default runtime set to nvidia"
        return 0
    fi

    print_warning "Docker default runtime is not nvidia"
    print_warning "Please run: sudo nvidia-ctk runtime configure --runtime=docker --set-as-default"
    return 1
}

install_nvidia_docker() {
    if command -v nvidia-docker &> /dev/null || command -v nvidia-container-runtime &> /dev/null || command -v nvidia-ctk &> /dev/null; then
        print_warning "NVIDIA container runtime already installed"
        ensure_nvidia_default_runtime || true
        return
    fi
    print_status "Installing NVIDIA Docker..."
    
    # Jetson devices might not have nvidia-docker2 in standard repos
    # Try to add NVIDIA Docker repository
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    
    # Add GPG key
    if ! curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add - >/dev/null 2>&1; then
        print_warning "Failed to add NVIDIA GPG key, trying alternative method..."
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-docker-keyring.gpg >/dev/null 2>&1 || true
    fi
    
    # Add repository
    if ! curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
        sudo tee /etc/apt/sources.list.d/nvidia-docker.list > /dev/null 2>&1; then
        print_warning "Failed to add NVIDIA Docker repository for $distribution"
        print_warning "nvidia-docker2 may not be available for this system, skipping"
        return
    fi
    
    sudo apt-get update -qq 2>/dev/null || true
    
    # Newer Jetson stacks often provide nvidia-container-toolkit instead of nvidia-docker2.
    if apt-cache show nvidia-docker2 >/dev/null 2>&1; then
        if sudo apt-get install -y -qq nvidia-docker2; then
            ensure_nvidia_default_runtime || true
            sudo systemctl restart docker 2>/dev/null || true
            print_status "NVIDIA Docker installed (nvidia-docker2)"
            return
        fi
        print_warning "Failed to install nvidia-docker2, trying nvidia-container-toolkit..."
    else
        print_warning "nvidia-docker2 package not found in repositories"
    fi

    if apt-cache show nvidia-container-toolkit >/dev/null 2>&1; then
        if sudo apt-get install -y -qq nvidia-container-toolkit; then
            ensure_nvidia_default_runtime || true
            sudo systemctl restart docker 2>/dev/null || true
            print_status "NVIDIA Container Toolkit installed"
            return
        fi
        print_warning "Found nvidia-container-toolkit but installation failed"
    else
        print_warning "nvidia-container-toolkit package not found in repositories"
    fi

    print_warning "NVIDIA GPU Docker runtime not installed automatically"
    print_warning "Please verify Jetson apt sources (L4T/NVIDIA repos)"
}

install_vscode() {
    if command -v code &> /dev/null; then
        print_warning "VS Code already installed"
        return
    fi
    print_status "Installing VS Code..."
    
    local arch=$(dpkg --print-architecture)
    print_status "Detected architecture: $arch"
    
    sudo apt-get install -y -qq software-properties-common apt-transport-https wget
    wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | sudo apt-key add - >/dev/null 2>&1
    
    # Add repository with detected architecture
    sudo add-apt-repository "deb [arch=$arch] https://packages.microsoft.com/repos/vscode stable main" -y >/dev/null 2>&1
    
    sudo apt-get update -qq 2>/dev/null || true
    sudo apt-get install -y -qq code 2>/dev/null || {
        print_warning "VS Code may not be available for architecture: $arch"
        print_warning "Attempting to install from web..."
        return
    }
    print_status "VS Code installed"
}

install_chrome() {
    if command -v google-chrome &> /dev/null || command -v google-chrome-stable &> /dev/null; then
        print_warning "Google Chrome already installed"
        return
    fi

    print_status "Installing Google Chrome (arm64)..."

    local DEB_PATH="/tmp/google-chrome-stable_current_arm64.deb"

    # Offizielles arm64-Paket herunterladen
    wget -q -O "$DEB_PATH" https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb

    # Installieren und Abhängigkeiten auflösen
    sudo apt-get update -qq
    sudo apt-get install -y -qq "$DEB_PATH"

    # Temporäre Datei aufräumen
    rm -f "$DEB_PATH"

    print_status "Google Chrome installed"
}

install_firefox() {
    # Prüfen, ob Firefox bereits nativ über das Mozilla-PPA/Repo installiert ist
    if command -v firefox &>/dev/null && apt-cache policy firefox 2>/dev/null | grep -q "packages.mozilla.org"; then
        print_warning "Firefox (Native APT) already installed"
        return
    fi

    print_status "Installing Firefox via Mozilla official APT repository..."

    # Falls das Snap-Paket aktiv ist, entfernen
    if command -v snap &>/dev/null && snap list firefox &>/dev/null; then
        print_status "Removing Firefox Snap package..."
        sudo snap remove firefox >/dev/null 2>&1 || true
    fi

    # Eventuellen alten Ubuntu-Dummy-Wrapper via APT entfernen
    if dpkg -l firefox 2>/dev/null | grep -q "^ii"; then
        if ! apt-cache policy firefox 2>/dev/null | grep -q "packages.mozilla.org"; then
            print_status "Removing Ubuntu transitional dummy package..."
            sudo apt-get remove -y -qq firefox >/dev/null 2>&1 || true
        fi
    fi

    # 1. Mozilla Signing-Key sicher hinterlegen
    sudo install -d -m 0755 /etc/apt/keyrings
    wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | \
        sudo gpg --dearmor --yes -o /etc/apt/keyrings/packages.mozilla.org.gpg >/dev/null 2>&1

    # 2. Mozilla APT-Repository anbinden
    echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.gpg] https://packages.mozilla.org/apt mozilla main" | \
        sudo tee /etc/apt/sources.list.d/mozilla.list >/dev/null

    # 3. APT-Pinning einrichten (verhindert Ubuntu-Snap-Wrapper)
    sudo tee /etc/apt/preferences.d/mozilla-firefox >/dev/null <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000

Package: firefox*
Pin: release o=Ubuntu*
Pin-Priority: -1
EOF

    # 4. Paketliste aktualisieren und natives Paket installieren
    sudo apt-get update -qq
    sudo apt-get install -y -qq firefox

    print_status "Firefox (Native APT) installed: $(firefox --version 2>/dev/null | head -n1 || echo 'Done')"
}

install_udev_ilitek_mouse_ignore() {
    local rule_file="/etc/udev/rules.d/99-ilitek-ignore-mouse.rules"
    local rule_content='KERNEL=="event*", ENV{ID_VENDOR_ID}=="222a", ENV{ID_MODEL_ID}=="0001", ATTRS{name}=="*Mouse*", ENV{LIBINPUT_IGNORE_DEVICE}="1", ENV{ID_INPUT_MOUSE}="", ENV{ID_INPUT}=""'

    if [[ -f "$rule_file" ]]; then
        if grep -Fxq "$rule_content" "$rule_file" 2>/dev/null; then
            print_warning "Ilitek udev rule already exists"
            sudo udevadm control --reload-rules >/dev/null 2>&1 || true
            sudo udevadm trigger --action=change --subsystem-match=input >/dev/null 2>&1 || true
            return
        fi
    fi

    print_status "Installing udev rule to ignore Ilitek mouse input..."
    sudo mkdir -p /etc/udev/rules.d
    echo "$rule_content" | sudo tee "$rule_file" >/dev/null
    sudo chmod 644 "$rule_file"
    sudo udevadm control --reload-rules >/dev/null 2>&1 || true
    sudo udevadm trigger --action=change --subsystem-match=input >/dev/null 2>&1 || true
    print_status "Ilitek udev rule installed"
}

install_openssh() {
    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        print_warning "OpenSSH Server already running"
        return
    fi
    print_status "Installing OpenSSH Server..."
    sudo apt-get install -y -qq openssh-server
    sudo systemctl start ssh 2>/dev/null || sudo systemctl start sshd 2>/dev/null || true
    sudo systemctl enable ssh 2>/dev/null || sudo systemctl enable sshd 2>/dev/null || true
    print_status "OpenSSH Server installed and enabled"
}

install_teamviewer() {
    if command -v teamviewer &> /dev/null; then
        print_warning "TeamViewer already installed"
        return
    fi
    print_status "Installing TeamViewer..."
    
    local arch=$(dpkg --print-architecture)
    local deb_file="teamviewer_${arch}.deb"
    
    # Map aarch64 to arm64 for TeamViewer
    if [[ "$arch" == "arm64" ]]; then
        deb_file="teamviewer_arm64.deb"
    elif [[ "$arch" == "amd64" ]]; then
        deb_file="teamviewer_amd64.deb"
    else
        print_warning "Support for architecture $arch unknown, attempting generic download"
        deb_file="teamviewer_${arch}.deb"
    fi
    
    print_status "Downloading TeamViewer for $arch..."
    cd /tmp
    
    # Try to download the architecture-specific version
    if ! wget -q "https://download.teamviewer.com/download/linux/$deb_file" 2>/dev/null; then
        print_warning "TeamViewer binary not available for $arch architecture"
        print_warning "TeamViewer is not officially supported on ARM devices"
        print_warning "Consider using SSH (OpenSSH) for remote access instead"
        cd - >/dev/null
        return
    fi
    
    if sudo apt-get install -y -qq ./$deb_file >/dev/null 2>&1; then
        print_status "TeamViewer installed"
    else
        sudo apt-get install -f -y -qq >/dev/null 2>&1 || true
        if sudo apt-get install -y -qq ./$deb_file >/dev/null 2>&1; then
            print_status "TeamViewer installed"
        else
            print_warning "TeamViewer installation failed - likely due to ARM architecture limitations"
            print_warning "ARM support is not officially available for all TeamViewer versions"
        fi
    fi
    
    rm -f $deb_file
    cd - >/dev/null
}

install_tailscale() {
    if command -v tailscale &> /dev/null; then
        print_warning "Tailscale already installed"
        return
    fi
    print_status "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh >/dev/null 2>&1
    print_status "Tailscale installed"
}

install_dnsmasq() {
    if command -v dnsmasq &> /dev/null; then
        print_warning "dnsmasq already installed"
        return
    fi
    print_status "Installing dnsmasq..."
    sudo apt-get install -y -qq dnsmasq
    sudo systemctl enable dnsmasq 2>/dev/null || true
    print_status "dnsmasq installed"
}

install_pcan_driver() {
    if lsmod | grep -q pcan; then
        print_warning "PCAN driver already loaded"
        return
    fi
    
    # Check if source files exist
    local pcan_script="$ROOT_DIR/envSetup/install_pcan_driver.sh"
    if [[ ! -f "$pcan_script" ]]; then
        print_warning "PCAN driver script not found: $pcan_script"
        return
    fi
    
    print_status "Installing PCAN driver..."
    if bash "$pcan_script"; then
        print_status "PCAN driver installed"
    else
        print_warning "PCAN driver installation failed - continuing setup"
    fi
}

configure_thorsetup() {
    if [[ -f "$THORSETUP_SCRIPT" ]]; then
        print_status "Running Thor network setup: $THORSETUP_SCRIPT"
        bash "$THORSETUP_SCRIPT"
    else
        print_warning "Thor setup script not found: $THORSETUP_SCRIPT"
    fi
}

configure_routing() {
    if [[ -f "$ROUTING_SCRIPT" ]]; then
        print_status "Running routing setup: $ROUTING_SCRIPT"
        bash "$ROUTING_SCRIPT"
    else
        print_warning "Routing script not found: $ROUTING_SCRIPT"
    fi
}

install_ddcutil_and_extension() {
    print_status "Setting up ddcutil, I2C permissions, and GNOME extension..."

    local target_user="${SUDO_USER:-$USER}"
    if [[ -z "$target_user" || "$target_user" == "root" ]]; then
        print_warning "No non-root user detected for GNOME setup. Skipping extension install."
        return
    fi

    # 1. Install required packages and CLI tools
    sudo apt-get install -y -qq ddcutil gnome-shell-extension-manager gnome-shell-extensions jq unzip curl

    # 2. Load the I2C kernel module and ensure persistence
    sudo modprobe i2c-dev || true
    if ! grep -q "^i2c-dev" /etc/modules 2>/dev/null; then
        echo "i2c-dev" | sudo tee -a /etc/modules >/dev/null
    fi

    # 3. Add user to i2c group and set udev rule (bypasses logout requirement)
    sudo usermod -aG i2c "$target_user" 2>/dev/null || true
    local udev_rule='/etc/udev/rules.d/45-ddcutil-i2c.rules'
    echo 'KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"' | sudo tee "$udev_rule" >/dev/null
    sudo udevadm control --reload-rules >/dev/null 2>&1 || true
    sudo udevadm trigger >/dev/null 2>&1 || true

    # 4. Run ddcutil capabilities check
    print_status "Checking monitor compatibility via ddcutil..."
    ddcutil capabilities || print_warning "ddcutil reported no DDC/CI displays, or I2C bus is currently busy"

    # 5. Fetch and install 'Brightness Control using ddcutil' via GNOME API
    local ext_uuid="display-brightness-ddcutil@themightydeity.github.com"
    local user_home
    user_home="$(getent passwd "$target_user" | cut -d: -f6)"
    local target_ext_dir="$user_home/.local/share/gnome-shell/extensions/$ext_uuid"

    # Detect installed GNOME version (fallback: 42)
    local gnome_ver
    gnome_ver="$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -n1 || echo "42")"

    # Query official extensions.gnome.org API for download URL
    local download_url
    download_url="$(curl -s "https://extensions.gnome.org/extension-query/?search=Brightness%20Control%20using%20ddcutil" \
        | jq -r --arg uuid "$ext_uuid" '.extensions[] | select(.uuid==$uuid).download_url' 2>/dev/null || true)"

    if [[ -n "$download_url" && "$download_url" != "null" ]]; then
        local zip_path="/tmp/ddcutil-ext.zip"
        curl -sL "https://extensions.gnome.org$download_url" -o "$zip_path"

        # Create target directory and extract files as the target user
        sudo -u "$target_user" mkdir -p "$target_ext_dir"
        sudo -u "$target_user" unzip -qo "$zip_path" -d "$target_ext_dir"
        rm -f "$zip_path"

        # Enable extension via gnome-extensions CLI
        sudo -u "$target_user" gnome-extensions enable "$ext_uuid" 2>/dev/null || true
        print_status "GNOME extension ($ext_uuid) installed and enabled"
    else
        print_warning "Failed to resolve download URL for GNOME extension. Install manually via Extension Manager."
    fi
}

deploy_application_assets() {
    local target_user="${SUDO_USER:-jetson}"
    local target_home
    target_home="$(getent passwd "$target_user" | cut -d: -f6)"
    [[ -z "$target_home" ]] && target_home="/home/$target_user"

    local target_compose="$target_home/docker-compose.yml"
    local target_start_app="$target_home/start_app.sh"
    local target_desktop_dir="$target_home/Desktop"
    local target_desktop_file="$target_desktop_dir/APP-Start.desktop"
    local target_update_desktop_file="$target_desktop_dir/APP-Update.desktop"

    print_status "Deploying application assets to $target_home..."
    mkdir -p "$target_home"
    mkdir -p "$target_desktop_dir"

    if [[ -f "$ROOT_DIR/envSetup/jetson/docker-compose.yml" ]]; then
        cp "$ROOT_DIR/envSetup/jetson/docker-compose.yml" "$target_compose"
        chown "$target_user:$target_user" "$target_compose"
        print_status "Copied docker-compose.yml to $target_compose"
    else
        print_warning "docker-compose.yml not found: $ROOT_DIR/envSetup/jetson/docker-compose.yml"
    fi

    if [[ -f "$START_APP_SCRIPT" ]]; then
        cp "$START_APP_SCRIPT" "$target_start_app"
        chmod +x "$target_start_app"
        chown "$target_user:$target_user" "$target_start_app"
        print_status "Copied start_app.sh to $target_start_app"
    else
        print_warning "start_app.sh not found: $START_APP_SCRIPT"
    fi

    if [[ -f "$APP_START_DESKTOP" ]]; then
        cp "$APP_START_DESKTOP" "$target_desktop_file"
        print_status "Copied APP-Start.desktop to $target_desktop_file"
    else
        print_warning "APP-Start.desktop not found: $APP_START_DESKTOP"
    fi

    if [[ -f "$APP_UPDATE_DESKTOP" ]]; then
        cp "$APP_UPDATE_DESKTOP" "$target_update_desktop_file"
        print_status "Copied APP-Update.desktop to $target_update_desktop_file"
    else
        print_warning "APP-Update.desktop not found: $APP_UPDATE_DESKTOP"
    fi

    for dfile in "$target_desktop_file" "$target_update_desktop_file"; do
        if [[ -f "$dfile" ]]; then
            chown "$target_user:$target_user" "$dfile"
            
            chmod +x "$dfile"

            sudo -u "$target_user" gio set "$dfile" metadata::trusted true 2>/dev/null || true
            sudo -u "$target_user" gio set "$dfile" metadata::trusted yes 2>/dev/null || true
        fi
    done
    print_status "Desktop shortcuts marked as trusted (Allow Launching enabled)"
}

main() {
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║  Jetson AGX Thor - Complete Setup    ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""

    require_root
    check_ubuntu
    enable_logging

    echo ""
    echo "Installing core development tools..."
    hold_nvidia_l4t_packages
    update_system
    install_essentials
    install_git
    install_git_lfs
    
    echo ""
    echo "Installing containerization & virtualization..."
    install_docker
    install_docker_compose
    install_nvidia_docker
    
    echo ""
    echo "Installing productivity tools..."
    install_vscode
    install_chrome
    install_firefox
    
    echo ""
    echo "Installing system tools..."
    install_udev_ilitek_mouse_ignore
    install_ddcutil_and_extension
    install_openssh
    install_teamviewer
    install_tailscale
    install_dnsmasq
    
    echo ""
    echo "Installing hardware drivers..."
    install_pcan_driver
    
    echo ""
    echo "Running specialized configurations..."
    configure_thorsetup
    configure_routing
    deploy_application_assets

    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║   ✓ Setup completed successfully     ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    echo "Next steps:"
    echo "  1. Run healthcheck: bash healthcheck.sh"
    echo "  2. Configure Tailscale: sudo tailscale up"
    echo "  3. For Docker use: newgrp docker"
    echo ""
}

main "$@"
