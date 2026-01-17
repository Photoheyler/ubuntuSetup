#!/bin/bash

# Ubuntu Setup Script - Extended Version
# Includes Docker, Docker Compose, VS Code + Git, Build Tools, and Node.js

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Check Ubuntu
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

# Update system
update_system() {
    print_status "Updating system packages..."
    sudo apt-get update
    sudo apt-get upgrade -y
}

# Install essentials
install_essentials() {
    print_status "Installing essential build tools..."
    sudo apt-get install -y \
        build-essential \
        curl \
        wget \
        git \
        nano \
        vim \
        htop \
        net-tools \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https
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

# Install Docker
install_docker() {
    print_status "Installing Docker..."
    
    if command -v docker &> /dev/null; then
        print_warning "Docker is already installed"
        return
    fi
    
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    sudo systemctl start docker
    sudo systemctl enable docker
    
    print_status "Docker installed successfully"
}

# Install Docker Compose
install_docker_compose() {
    print_status "Installing Docker Compose..."
    
    if command -v docker-compose &> /dev/null; then
        print_warning "Docker Compose is already installed"
        return
    fi
    
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
    print_status "Installing Docker Compose $DOCKER_COMPOSE_VERSION"
    
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    print_status "Docker Compose installed successfully"
}

# Install VS Code
install_vscode() {
    print_status "Installing VS Code..."
    
    if command -v code &> /dev/null; then
        print_warning "VS Code is already installed"
        return
    fi
    
    wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" -y
    
    sudo apt-get update
    sudo apt-get install -y code
    
    print_status "VS Code installed successfully"
}

# Install Node.js (optional)
install_nodejs() {
    print_status "Installing Node.js..."
    
    if command -v node &> /dev/null; then
        print_warning "Node.js is already installed"
        return
    fi
    
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
    
    print_status "Node.js installed successfully"
}

# Install Python tools (optional)
install_python_tools() {
    print_status "Installing Python tools..."
    
    sudo apt-get install -y \
        python3 \
        python3-pip \
        python3-venv
    
    print_status "Python tools installed successfully"
}

# Configure Docker
configure_docker() {
    print_status "Configuring Docker permissions..."
    
    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER"
        print_warning "Added $USER to docker group. Log out and back in for changes to take effect."
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
    code --version || print_warning "VS Code version check requires graphical session"
    
    echo ""
}

# Show menu
show_menu() {
    echo "========================================="
    echo "   Ubuntu Setup - Extended Edition"
    echo "========================================="
    echo ""
    echo "Select components to install:"
    echo "1) Core (Docker + Docker Compose + VS Code)"
    echo "2) Full (Core + Git + Build Tools + Node.js + Python)"
    echo "3) Custom (choose individual components)"
    echo "4) Exit"
    echo ""
}

# Custom installation
custom_install() {
    echo ""
    echo "Select components (y/n):"
    
    read -p "Install Docker? (y/n) " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] && INSTALL_DOCKER=1
    
    read -p "Install Docker Compose? (y/n) " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] && INSTALL_DOCKER_COMPOSE=1
    
    read -p "Install VS Code? (y/n) " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] && INSTALL_VSCODE=1
    
    read -p "Install Git LFS? (y/n) " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] && INSTALL_GIT_LFS=1
    
    read -p "Install Node.js? (y/n) " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] && INSTALL_NODEJS=1
    
    read -p "Install Python tools? (y/n) " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] && INSTALL_PYTHON=1
    
    echo ""
}

# Main execution
main() {
    check_ubuntu
    update_system
    install_essentials
    
    while true; do
        show_menu
        read -p "Enter choice [1-4]: " choice
        
        case $choice in
            1)
                install_docker
                install_docker_compose
                install_vscode
                install_git_lfs
                configure_docker
                verify_installations
                break
                ;;
            2)
                install_docker
                install_docker_compose
                install_vscode
                install_git_lfs
                install_nodejs
                install_python_tools
                configure_docker
                verify_installations
                break
                ;;
            3)
                INSTALL_DOCKER=0
                INSTALL_DOCKER_COMPOSE=0
                INSTALL_VSCODE=0
                INSTALL_GIT_LFS=0
                INSTALL_NODEJS=0
                INSTALL_PYTHON=0
                
                custom_install
                
                [[ $INSTALL_DOCKER -eq 1 ]] && install_docker
                [[ $INSTALL_DOCKER_COMPOSE -eq 1 ]] && install_docker_compose
                [[ $INSTALL_VSCODE -eq 1 ]] && install_vscode
                [[ $INSTALL_GIT_LFS -eq 1 ]] && install_git_lfs
                [[ $INSTALL_NODEJS -eq 1 ]] && install_nodejs
                [[ $INSTALL_PYTHON -eq 1 ]] && install_python_tools
                
                configure_docker
                verify_installations
                break
                ;;
            4)
                print_status "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                ;;
        esac
    done
    
    echo ""
    print_status "Setup completed successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Log out and log back in for Docker permissions to apply"
    echo "  2. Start using Docker: docker ps"
    echo "  3. Launch VS Code: code"
    echo ""
}

main
