# Ubuntu Setup Hub

Automated setup script for Ubuntu that installs Docker Compose and VS Code with all dependencies.

## Features

- ✅ Automatic Git installation
- ✅ Git LFS (Large File Storage) installation and configuration
- ✅ NVIDIA GPU Driver installation (auto-detects GPU)
- ✅ CUDA Toolkit installation
- ✅ nvidia-docker integration for GPU containers
- ✅ Automatic Docker installation from official Docker repository
- ✅ Docker Compose standalone installation (latest version)
- ✅ VS Code installation from Microsoft repository
- ✅ System package updates
- ✅ Docker daemon configuration and user permissions
- ✅ Installation verification
- ✅ Error handling and status messages

## Prerequisites

- Ubuntu 20.04 LTS or later
- Sudo access (script requires sudo permissions)
- Internet connection

## Quick Start

### Method 1: Direct Download and Run

```bash
curl -fsSL https://raw.githubusercontent.com/yourusername/ubuntuSetup/main/setup.sh | bash
```

### Method 2: Clone and Run

```bash
git clone https://github.com/yourusername/ubuntuSetup.git
cd ubuntuSetup
chmod +x setup.sh
./setup.sh
```

### Method 3: Run Locally

```bash
chmod +x setup.sh
./setup.sh
```

## What Gets Installed

### Git
- Git version control system
- Git LFS (Large File Storage) for managing large binary files
- Automatically initialized for the current user

### NVIDIA GPU Support (if GPU detected)
- NVIDIA GPU Drivers (version 535)
- CUDA Toolkit (version 12.3)
- nvidia-docker for GPU-accelerated containers

### Docker
- Docker Engine (latest stable)
- Docker CLI
- containerd
- Docker CLI plugin for Compose

### Docker Compose
- Standalone docker-compose binary (latest version)
- Located at `/usr/local/bin/docker-compose`

### VS Code
- Latest stable version from Microsoft repository
- Installed via apt package manager
- Ready to use with extensions

## Post-Installation

After running the script, you may need to:

1. **Reboot (for NVIDIA GPU drivers)** - If NVIDIA drivers were installed:
   ```bash
   sudo reboot
   ```

2. **Log out and log back in** for Docker group permissions to take effect:
   ```bash
   exit
   # Log back in to your user account
   ```
   Or use:
   ```bash
   newgrp docker
   ```

3. **Reload shell configuration** (if CUDA was installed):
   ```bash
   source ~/.bashrc
   ```

2. **Verify installations**:
   ```bash   git --version
   git lfs version   docker --version
   docker-compose --version
   code --version
   ```

3. **Test NVIDIA GPU** (if installed):
   ```bash
   nvidia-smi
   nvcc --version
   docker run --rm --gpus all nvidia/cuda:12.3.0-runtime-ubuntu22.04 nvidia-smi
   ```

4. **Test Docker**:
   ```bash
   docker ps
   ```

5. **Launch VS Code**:
   ```bash
   code
   ```

## Script Details

### Functions

- `check_ubuntu()` - Validates that the script is running on Ubuntu
- `update_system()` - Updates all system packages
- `install_git()` - Installs Git version control
- `install_git_lfs()` - Installs Git LFS and initializes it
- `install_docker()` - Installs Docker from official repository
- `install_docker_compose()` - Installs standalone docker-compose
- `install_vscode()` - Installs VS Code from Microsoft repository
- `configure_docker_permissions()` - Adds user to docker group
- `verify_installations()` - Verifies all installations

### Error Handling

The script exits immediately on any error with a clear error message.

## Supported Ubuntu Versions

- Ubuntu 20.04 LTS (Focal)
- Ubuntu 22.04 LTS (Jammy)
- Ubuntu 24.04 LTS (Noble)
- Other Ubuntu versions may work but are untested

## Troubleshooting

### NVIDIA GPU not detected
Make sure you have an NVIDIA GPU and the drivers are properly connected. Check:
```bash
lspci | grep -i nvidia
```

### nvidia-smi command not found
Log out and log back in, or reboot the system for drivers to take effect:
```bash
nvidia-smi
```

### Docker command not found
Make sure you've logged out and logged back in after running the script.

### Permission denied
Make sure the script is executable:
```bash
chmod +x setup.sh
```

### Network errors
Ensure you have a stable internet connection. The script downloads packages from:
- `apt.ubuntu.com`
- `download.docker.com`
- `packages.microsoft.com`
- `github.com` (for docker-compose releases)

### VS Code won't launch
If running in headless environment, VS Code installation will complete but GUI won't start. This is normal.

## Customization

Edit `setup.sh` to skip specific components:

```bash
# Comment out these lines to skip:
install_git
install_git_lfs
install_docker
install_docker_compose
install_vscode
```

## Security Notes

- The script runs with `set -e` to exit on errors
- Uses official repositories from Docker and Microsoft
- Downloads and verifies GPG keys for package authentication
- Requires sudo for system-level installations

## License

MIT

## Support

For issues or questions, please create an issue on the repository.

## Manual Installation (Alternative)

If you prefer manual installation, here are the equivalent commands:

### Install Git
```bash
sudo apt-get update
sudo apt-get install -y git
```

### Install Git LFS
```bash
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
sudo apt-get install -y git-lfs
git lfs install
```

### Install Docker
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl start docker
sudo systemctl enable docker
```

### Install Docker Compose
```bash
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### Install VS Code
```bash
sudo apt-get install -y software-properties-common apt-transport-https wget
wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" -y
sudo apt-get update
sudo apt-get install -y code
```

### Configure Docker Permissions
```bash
sudo usermod -aG docker $USER
```
