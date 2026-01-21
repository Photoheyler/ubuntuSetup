# Ubuntu Setup Configuration
# Customize what gets installed by setting these variables

# Core Components (always recommended)
INSTALL_DOCKER=true
INSTALL_DOCKER_COMPOSE=true
INSTALL_VSCODE=true
INSTALL_GIT=true
INSTALL_GIT_LFS=true

# NVIDIA GPU Support
INSTALL_NVIDIA_DRIVERS=false
INSTALL_CUDA=false
INSTALL_NVIDIA_DOCKER=true

# Additional Development Tools
INSTALL_GIT=true
INSTALL_BUILD_TOOLS=true
INSTALL_CURL=true
INSTALL_WGET=true

# Programming Languages & Runtimes
INSTALL_NODEJS=false
INSTALL_PYTHON=false
INSTALL_GOLANG=false
INSTALL_RUST=false

# Utilities
INSTALL_HTOP=true
INSTALL_NET_TOOLS=true
INSTALL_VIM=false
INSTALL_NANO=true

# Applications
INSTALL_PICOSCOPE=true
INSTALL_CHROMIUM=true

# Docker Configuration
DOCKER_ENABLE_DAEMON=true
DOCKER_ADD_USER_TO_GROUP=true

# System Configuration
UPDATE_SYSTEM=true
ENABLE_SYSTEM_SERVICES=true

# Optional VS Code Extensions (space-separated)
# Example: "esbenp.prettier-vscode ms-python.python"
VSCODE_EXTENSIONS=""

# Docker Compose options
INSTALL_DOCKER_COMPOSE_STANDALONE=true
