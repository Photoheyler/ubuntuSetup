#!/bin/bash

# Ubuntu Setup Script - Docker Compose & VS Code Installation
# This script automates the installation of Docker, Docker Compose, and VS Code on Ubuntu

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Source configuration file if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
    source "$SCRIPT_DIR/config.sh"
    print_status "Loaded configuration from config.sh"
fi

# Check if running on Ubuntu
check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Could not determine OS"
        exit 1
    fi
    
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        print_error "This script is designed for Ubuntu. Detected: $ID"
        exit 1
    fi
    
    print_status "Running on Ubuntu $VERSION_ID"
}

# Update system packages
update_system() {
    print_status "Updating system packages..."
    sudo apt-get update
    sudo apt-get upgrade -y
}

# Install Git
install_git() {
    print_status "Installing Git..."
    
    if command -v git &> /dev/null; then
        print_warning "Git is already installed"
        return
    fi
    
    sudo apt-get install -y git
    
    # Configure Git (optional - comment out if not desired)
    if [[ -z $(git config --global user.name) ]]; then
        print_status "Git installed. Configure it with:"
        echo "  git config --global user.name 'Your Name'"
        echo "  git config --global user.email 'your.email@example.com'"
    fi
    
    print_status "Git installed successfully"
}

# Install Git LFS
install_git_lfs() {
    print_status "Installing Git LFS..."
    
    if command -v git-lfs &> /dev/null; then
        print_warning "Git LFS is already installed"
        return
    fi
    
    curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
    sudo apt-get install -y git-lfs
    
    # Initialize Git LFS
    git lfs install
    
    print_status "Git LFS installed successfully"
}

# Install NVIDIA GPU Drivers
install_nvidia_drivers() {
    print_status "Installing NVIDIA GPU Drivers..."
    
    # Check if nvidia-smi exists (NVIDIA drivers already installed)
    if command -v nvidia-smi &> /dev/null; then
        print_warning "NVIDIA drivers are already installed"
        nvidia-smi
        return
    fi
    
    # Check if NVIDIA GPU is present
    if ! lspci | grep -i nvidia &> /dev/null; then
        print_warning "No NVIDIA GPU detected. Skipping NVIDIA driver installation."
        return
    fi
    
    print_status "Detected NVIDIA GPU. Installing drivers..."
    
    # Add NVIDIA repository
    sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys A4B469963BF863CC
    sudo add-apt-repository "deb http://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/ /"
    sudo apt-get update
    
    # Install NVIDIA drivers
    sudo apt-get install -y nvidia-driver-535
    
    print_status "NVIDIA drivers installed successfully"
    print_warning "System reboot may be required for drivers to take effect"
}

# Install CUDA Toolkit
install_cuda() {
    print_status "Installing CUDA Toolkit..."
    
    if command -v nvcc &> /dev/null; then
        print_warning "CUDA Toolkit is already installed"
        nvcc --version
        return
    fi
    
    if ! command -v nvidia-smi &> /dev/null; then
        print_warning "NVIDIA drivers not found. Install drivers first."
        return
    fi
    
    # Download CUDA installer
    CUDA_VERSION="12.3"
    CUDA_INSTALLER="cuda_${CUDA_VERSION}.0_535.104.05_linux.run"
    
    print_status "Downloading CUDA ${CUDA_VERSION}..."
    cd /tmp
    wget -q https://developer.download.nvidia.com/compute/cuda/${CUDA_VERSION}.0/local_installers/${CUDA_INSTALLER}
    
    # Install CUDA (non-interactive)
    sudo sh ${CUDA_INSTALLER} --silent --driver --toolkit --override
    
    # Update PATH
    echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
    source ~/.bashrc
    
    # Cleanup
    rm -f ${CUDA_INSTALLER}
    cd -
    
    print_status "CUDA Toolkit installed successfully"
}

# Install PicoScope
install_picoscope() {
    print_status "Installing PicoScope..."
    
    if command -v picoscope &> /dev/null; then
        print_warning "PicoScope is already installed"
        return
    fi
    
    # Import PicoScope public key
    print_status "Importing PicoScope repository key..."
    sudo bash -c 'wget -O- https://labs.picotech.com/Release.gpg.key | gpg --dearmor > /usr/share/keyrings/picotech-archive-keyring.gpg'
    
    # Configure repository
    print_status "Adding PicoScope repository..."
    sudo bash -c 'echo "deb [signed-by=/usr/share/keyrings/picotech-archive-keyring.gpg] https://labs.picotech.com/picoscope7/debian/ picoscope main" > /etc/apt/sources.list.d/picoscope7.list'
    
    # Update and install
    sudo apt-get update
    sudo apt-get install -y picoscope
    
    print_status "PicoScope installed successfully"
}

# Install Chromium
install_chromium() {
    print_status "Installing Chromium browser..."
    
    if command -v chromium-browser &> /dev/null || command -v chromium &> /dev/null; then
        print_warning "Chromium is already installed"
        return
    fi
    
    sudo apt-get install -y chromium-browser
    
    print_status "Chromium browser installed successfully"
}

# Install OpenSSH Server
install_openssh_server() {
    print_status "Installing OpenSSH Server..."
    
    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
        print_warning "OpenSSH Server is already installed and running"
        return
    fi
    
    sudo apt-get install -y openssh-server
    
    # Start and enable SSH service
    sudo systemctl start ssh
    sudo systemctl enable ssh
    
    # Display SSH status
    print_status "OpenSSH Server installed successfully"
    print_status "SSH service status:"
    sudo systemctl status ssh --no-pager -l || true
}

# Install TeamViewer
install_teamviewer() {
    print_status "Installing TeamViewer..."
    
    if command -v teamviewer &> /dev/null; then
        print_warning "TeamViewer is already installed"
        return
    fi
    
    # Download TeamViewer .deb package
    print_status "Downloading TeamViewer..."
    cd /tmp
    wget -q https://download.teamviewer.com/download/linux/teamviewer_amd64.deb
    
    # Install TeamViewer
    sudo apt-get install -y ./teamviewer_amd64.deb || {
        # If dependencies are missing, fix them
        sudo apt-get install -f -y
        sudo apt-get install -y ./teamviewer_amd64.deb
    }
    
    # Cleanup
    rm -f teamviewer_amd64.deb
    cd -
    
    print_status "TeamViewer installed successfully"
}

# Install nvidia-docker
install_nvidia_docker() {
    print_status "Installing nvidia-docker..."
    
    if dpkg -l | grep -q nvidia-docker2; then
        print_warning "nvidia-docker is already installed"
        return
    fi
    
    if ! command -v nvidia-smi &> /dev/null; then
        print_warning "NVIDIA drivers not found. Install drivers first."
        return
    fi
    
    # Add NVIDIA Docker repository
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID) \
        && curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
        && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
    
    sudo apt-get update
    sudo apt-get install -y nvidia-docker2
    
    # Restart Docker daemon
    sudo systemctl restart docker
    
    print_status "nvidia-docker installed successfully"
}

# Install Docker
install_docker() {
    print_status "Installing Docker..."
    
    if command -v docker &> /dev/null; then
        print_warning "Docker is already installed"
        return
    fi
    
    # Install dependencies
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
    
    print_status "Docker installed successfully"
}

# Install Docker Compose (standalone)
install_docker_compose() {
    print_status "Installing Docker Compose (standalone)..."
    
    if command -v docker-compose &> /dev/null; then
        print_warning "Docker Compose is already installed"
        return
    fi
    
    # Get latest version
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
    
    print_status "Installing Docker Compose $DOCKER_COMPOSE_VERSION"
    
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    
    sudo chmod +x /usr/local/bin/docker-compose
    
    # Verify installation
    docker-compose --version
    print_status "Docker Compose installed successfully"
}

# Install VS Code
install_vscode() {
    print_status "Installing VS Code..."
    
    if command -v code &> /dev/null; then
        print_warning "VS Code is already installed"
        return
    fi
    
    # Install dependencies
    sudo apt-get install -y software-properties-common apt-transport-https wget
    
    # Add Microsoft key
    wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | sudo apt-key add -
    
    # Add VS Code repository
    sudo add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" -y
    
    # Install VS Code
    sudo apt-get update
    sudo apt-get install -y code
    
    print_status "VS Code installed successfully"
}

# Configure Docker permissions (optional)
configure_docker_permissions() {
    print_status "Configuring Docker permissions..."
    
    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER"
        print_warning "Added $USER to docker group. Please log out and log back in for changes to take effect."
    else
        print_status "Docker permissions already configured"
    fi
}

# Verify installations
verify_installations() {
    print_status "Verifying installations..."
    
    echo ""
    echo "Git version:"
    git --version
    
    echo ""
    echo "Git LFS version:"
    git lfs version || print_warning "Git LFS version check failed"
    
    echo ""
    echo "Docker version:"
    docker --version
    
    echo ""
    echo "Docker Compose version:"
    docker-compose --version
    
    echo ""
    echo "VS Code version:"
    code --version || print_warning "VS Code version check failed (may require graphical session)"
    
    echo ""
    
    # Check PicoScope
    if command -v picoscope &> /dev/null; then
        echo "PicoScope: Installed"
    fi
    
    echo ""
    
    # Check Chromium
    if command -v chromium-browser &> /dev/null || command -v chromium &> /dev/null; then
        echo "Chromium: Installed"
        chromium-browser --version 2>/dev/null || chromium --version 2>/dev/null
    fi
    
    echo ""
    
    # Check OpenSSH Server
    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
        echo "OpenSSH Server: Installed and running"
        ssh -V 2>&1 | head -n1
    fi
    
    echo ""
    
    # Check TeamViewer
    if command -v teamviewer &> /dev/null; then
        echo "TeamViewer: Installed"
        teamviewer --version 2>/dev/null || echo "TeamViewer version: $(teamviewer -v 2>&1 | head -n1)"
    fi
    
    echo ""
    
    # Check NVIDIA installation if available
    if command -v nvidia-smi &> /dev/null; then
        echo ""
        echo "NVIDIA GPU status:"
        nvidia-smi --query-gpu=name --format=csv,noheader
    fi
    
    echo ""
}

# Main execution
main() {
    echo "========================================="
    echo "   Ubuntu Setup - Docker & VS Code"
    echo "========================================="
    echo ""
    
    check_ubuntu
    
    # Update system if configured
    if [[ "${UPDATE_SYSTEM:-true}" == "true" ]]; then
        update_system
    fi
    
    # Install Git if configured
    if [[ "${INSTALL_GIT:-true}" == "true" ]]; then
        install_git
    fi
    
    # Install Git LFS if configured
    if [[ "${INSTALL_GIT_LFS:-true}" == "true" ]]; then
        install_git_lfs
    fi
    
    # Install NVIDIA drivers if configured
    if [[ "${INSTALL_NVIDIA_DRIVERS:-false}" == "true" ]]; then
        install_nvidia_drivers
    fi
    
    # Install CUDA if configured
    if [[ "${INSTALL_CUDA:-false}" == "true" ]]; then
        install_cuda
    fi
    
    # Install nvidia-docker if configured
    if [[ "${INSTALL_NVIDIA_DOCKER:-true}" == "true" ]]; then
        install_nvidia_docker
    fi
    
    # Install Docker if configured
    if [[ "${INSTALL_DOCKER:-true}" == "true" ]]; then
        install_docker
    fi
    
    # Install Docker Compose if configured
    if [[ "${INSTALL_DOCKER_COMPOSE:-true}" == "true" ]]; then
        install_docker_compose
    fi
    
    # Install VS Code if configured
    if [[ "${INSTALL_VSCODE:-true}" == "true" ]]; then
        install_vscode
    fi
    
    # Install PicoScope if configured
    if [[ "${INSTALL_PICOSCOPE:-true}" == "true" ]]; then
        install_picoscope
    fi
    
    # Install Chromium if configured
    if [[ "${INSTALL_CHROMIUM:-true}" == "true" ]]; then
        install_chromium
    fi
    
    # Install OpenSSH Server if configured
    if [[ "${INSTALL_OPENSSH_SERVER:-true}" == "true" ]]; then
        install_openssh_server
    fi
    
    # Install TeamViewer if configured
    if [[ "${INSTALL_TEAMVIEWER:-true}" == "true" ]]; then
        install_teamviewer
    fi
    
    # Configure Docker permissions if configured
    if [[ "${DOCKER_ADD_USER_TO_GROUP:-true}" == "true" ]]; then
        configure_docker_permissions
    fi
    
    verify_installations
    
    echo ""
    print_status "Setup completed successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Log out and log back in for Docker group changes to take effect"
    echo "  2. Start using Docker: docker ps"
    echo "  3. Launch VS Code: code"
    echo ""
}

# Run main function
main
