# Installation Guide

## Table of Contents
1. [Quick Start](#quick-start)
2. [Detailed Installation](#detailed-installation)
3. [Script Options](#script-options)
4. [Troubleshooting](#troubleshooting)
5. [Uninstallation](#uninstallation)

## Quick Start

The fastest way to get started:

```bash
cd /home/stefan/Documents/gitRepos/ubuntuSetup
chmod +x setup.sh
./setup.sh
```

This installs:
- Git and Git LFS
- Docker Engine with CLI
- Docker Compose (standalone)
- VS Code
- Configures Docker permissions

## Detailed Installation

### Option 1: Minimal Setup (Recommended)

Use `setup.sh` for the essential components:

```bash
./setup.sh
```

**Installs:**
- Git and Git LFS
- Docker
- Docker Compose
- VS Code

### Option 2: Extended Setup

Use `setup-extended.sh` for more tools:

```bash
chmod +x setup-extended.sh
./setup-extended.sh
```

**Provides a menu to choose:**
- Core components (Git, Docker, Docker Compose, VS Code)
- Full installation (Core + Build Tools + Node.js + Python)
- Custom selection of individual components

### Option 3: Configuration File

1. Edit `config.sh` to customize what gets installed:
```bash
nano config.sh
```

2. Set variables to `true` or `false` for components you want

3. Run the setup script (it will source the config)

## Script Options

### Basic Setup Script (`setup.sh`)

No command-line options. Installs fixed components:
- Validates Ubuntu installation
- Updates system packages
- Installs Git and Git LFS
- Installs Docker from official repository
- Installs Docker Compose (latest version)
- Installs VS Code from Microsoft repository
- Configures Docker user permissions
- Verifies all installations

```bash
./setup.sh
```

### Extended Setup Script (`setup-extended.sh`)

Interactive menu with three options:

```bash
./setup-extended.sh
```

**Menu Options:**
- **Option 1**: Core (Docker, Docker Compose, VS Code)
- **Option 2**: Full (Core + Git + Build Tools + Node.js + Python)
- **Option 3**: Custom (choose individual components)
- **Option 4**: Exit

## Post-Installation Steps

### 1. Apply Docker Group Changes

After running the script, log out and log back in:

```bash
exit
# Log back in to your user account
```

Or use `newgrp`:
```bash
newgrp docker
```

### 2. Verify Installations

Check that everything is installed correctly:

```bash
# Check Git
git --version
git lfs version

# Check Docker
docker --version
docker ps

# Check Docker Compose
docker-compose --version

# Check VS Code
code --version

# List installed packages
apt list --installed | grep -E "git|docker|code"
```

### 3. Test Docker

Create a test container:

```bash
docker run --rm hello-world
```

Expected output:
```
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

### 4. Configure Git

Set your Git identity (if not already configured):

```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Verify configuration
git config --global user.name
git config --global user.email
```

### 5. Create Docker Compose Project

Test Docker Compose with a simple example:

```bash
mkdir test-docker-compose
cd test-docker-compose
```

Create `docker-compose.yml`:
```yaml
version: '3.8'
services:
  hello:
    image: hello-world
```

Run it:
```bash
docker-compose up
```

## Configuration File Details

Edit `config.sh` to customize:

### Core Components
```bash
INSTALL_DOCKER=true              # Install Docker Engine
INSTALL_DOCKER_COMPOSE=true      # Install Docker Compose
INSTALL_VSCODE=true              # Install Visual Studio Code
INSTALL_GIT=true                 # Install Git version control
INSTALL_GIT_LFS=true             # Install Git LFS (Large File Storage)
```

### Development Tools
```bash
INSTALL_BUILD_TOOLS=true         # Build essentials (gcc, make, etc.)
INSTALL_CURL=true                # cURL command-line tool
INSTALL_WGET=true                # Wget download utility
```

### Programming Languages
```bash
INSTALL_NODEJS=false             # Node.js and npm
INSTALL_PYTHON=false             # Python 3 and pip
INSTALL_GOLANG=false             # Go programming language
INSTALL_RUST=false               # Rust programming language
```

### Utilities
```bash
INSTALL_HTOP=true                # Interactive process viewer
INSTALL_NET_TOOLS=true           # Networking utilities
INSTALL_VIM=false                # Vim text editor
INSTALL_NANO=true                # Nano text editor
```

### Services
```bash
DOCKER_ENABLE_DAEMON=true        # Start Docker daemon
DOCKER_ADD_USER_TO_GROUP=true    # Add current user to docker group
UPDATE_SYSTEM=true               # Update system packages first
```

## Troubleshooting

### Docker command not found

**Problem:** `docker: command not found`

**Solution:**
1. Make sure Docker installation completed without errors
2. Log out and log back in
3. Check if Docker is installed: `which docker`
4. Reinstall if necessary

### Permission denied

**Problem:** `docker run hello-world` gives permission error

**Solution:**
```bash
# Verify user is in docker group
groups $USER

# If docker isn't listed, add user to group
sudo usermod -aG docker $USER

# Log out and back in
exit

# Or use newgrp
newgrp docker
```

### Docker daemon not running

**Problem:** `Cannot connect to Docker daemon`

**Solution:**
```bash
# Start Docker daemon
sudo systemctl start docker

# Enable auto-start
sudo systemctl enable docker

# Check status
sudo systemctl status docker
```

### VS Code won't launch

**Problem:** `command not found: code` or GUI doesn't start

**Solution:**
- If in headless environment (SSH), GUI won't display
- VS Code is still installed and can be used with `--no-sandbox`: `code --no-sandbox`
- Or access via Remote SSH extension

### Network issues during installation

**Problem:** Download fails due to network errors

**Solution:**
1. Check internet connection: `ping 8.8.8.8`
2. Check if repositories are accessible:
   - Docker: `curl -I https://download.docker.com`
   - Microsoft: `curl -I https://packages.microsoft.com`
   - GitHub: `curl -I https://github.com`
3. Try again - it might be temporary
4. Update package lists: `sudo apt-get update`

### Docker Compose version mismatch

**Problem:** Both docker-compose (standalone) and docker compose (plugin) installed

**Solution:** This is fine - both can coexist:
```bash
docker-compose --version    # Standalone
docker compose version      # Plugin
```

Use either one - plugin is newer but standalone is more compatible.

### Git LFS not tracking files

**Problem:** Large files aren't being tracked by Git LFS

**Solution:**
1. Make sure Git LFS is installed: `git lfs version`
2. Initialize Git LFS in your repo: `git lfs install`
3. Specify which files to track:
   ```bash
   git lfs track "*.psd"
   git add .gitattributes
   git commit -m "Add LFS tracking for large files"
   ```
4. Add your large files:
   ```bash
   git add yourlargefiles.psd
   git commit -m "Add large files"
   ```

### Git LFS installation failed

**Problem:** `command not found: git-lfs`

**Solution:**
1. Verify the script ran without errors
2. Check if Git LFS is installed: `which git-lfs`
3. Reinstall Git LFS manually:
   ```bash
   curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
   sudo apt-get install -y git-lfs
   git lfs install
   ```

## Uninstallation

### Remove Individual Components

**Remove Git:**
```bash
sudo apt-get remove -y git git-lfs
```

**Remove Docker:**
```bash
sudo apt-get remove -y docker-ce docker-ce-cli containerd.io
sudo rm -rf /var/lib/docker
sudo rm /etc/apt/sources.list.d/docker.list
```

**Remove Docker Compose:**
```bash
sudo rm /usr/local/bin/docker-compose
```

**Remove VS Code:**
```bash
sudo apt-get remove -y code
sudo rm /etc/apt/sources.list.d/vscode.list
```

### Complete Cleanup

Remove everything installed by the script:

```bash
# Remove all installed packages
sudo apt-get remove -y git git-lfs docker-ce docker-ce-cli containerd.io code

# Remove docker-compose standalone
sudo rm -f /usr/local/bin/docker-compose

# Remove repositories
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -f /etc/apt/sources.list.d/vscode.list

# Remove user from docker group
sudo deluser $USER docker

# Clean up
sudo apt-get autoremove -y
sudo apt-get clean
```

## System Information

After installation, you can check your system:

```bash
# Ubuntu version
lsb_release -a

# Kernel version
uname -r

# Installed Docker version
docker version

# System resources
free -h
df -h
htop
```

## Getting Help

### Git Documentation
- Official docs: https://git-scm.com/doc
- Git LFS docs: https://git-lfs.github.com/
- Git Learning: https://git-scm.com/book/en/v2

### Docker Documentation
- Official docs: https://docs.docker.com/
- Compose docs: https://docs.docker.com/compose/
- Community forum: https://forums.docker.com/

### VS Code Documentation
- Official docs: https://code.visualstudio.com/docs
- Extensions marketplace: https://marketplace.visualstudio.com/
- Community discussions: https://github.com/microsoft/vscode/discussions

### Ubuntu Help
- Official docs: https://ubuntu.com/support
- Community help: https://ubuntuforums.org/
- Ask Ubuntu: https://askubuntu.com/

## Next Steps

1. **Explore Docker**
   - Read Docker documentation
   - Practice with containers
   - Learn Docker Compose

2. **Set Up VS Code**
   - Install extensions for your languages
   - Configure settings and keybindings
   - Explore Remote SSH for remote development

3. **Development Workflows**
   - Use Docker for consistent development environments
   - Use Docker Compose for multi-container applications
   - Use VS Code with Docker extension for better integration

---

For issues or improvements, please update the setup scripts or create an issue on the repository.
