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
}

# Main execution
main() {
    echo "========================================="
    echo "   Ubuntu Setup - Docker & VS Code"
    echo "========================================="
    echo ""
    
    check_ubuntu
    update_system
    install_git
    install_git_lfs
    install_docker
    install_docker_compose
    install_vscode
    configure_docker_permissions
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
