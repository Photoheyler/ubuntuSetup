#!/bin/bash
set -e

# PEAK CAN Driver Installation Script with SocketCAN support
# This script downloads, compiles, and installs the PEAK Linux driver

DRIVER_VERSION="9.0"
DOWNLOAD_DIR="$HOME/Documents"
DRIVER_NAME="peak-linux-driver-${DRIVER_VERSION}"
DRIVER_ARCHIVE="${DRIVER_NAME}.tar.gz"
DRIVER_URL="https://www.peak-system.com/fileadmin/media/linux/files/${DRIVER_ARCHIVE}"

echo "========================================"
echo "PEAK CAN Driver Installation"
echo "Version: ${DRIVER_VERSION}"
echo "========================================"

# Install dependencies
echo "Installing build dependencies..."
sudo apt update
sudo apt install -y build-essential dkms git linux-headers-$(uname -r) can-utils

# Navigate to download directory
cd "${DOWNLOAD_DIR}"

# Remove old driver if loaded
echo "Unloading existing PEAK driver (if any)..."
sudo rmmod pcan 2>/dev/null || true

# Download driver
echo "Downloading PEAK driver ${DRIVER_VERSION}..."
if [ -f "${DRIVER_ARCHIVE}" ]; then
    echo "Archive already exists, checking if valid..."
    if ! tar -tzf "${DRIVER_ARCHIVE}" >/dev/null 2>&1; then
        echo "Archive is corrupted, re-downloading..."
        rm -f "${DRIVER_ARCHIVE}"
        wget "${DRIVER_URL}"
    fi
else
    wget "${DRIVER_URL}"
fi

# Extract driver
echo "Extracting driver..."
if [ -d "${DRIVER_NAME}" ]; then
    echo "Removing existing directory..."
    rm -rf "${DRIVER_NAME}"
fi
tar -xzf "${DRIVER_ARCHIVE}"

# Navigate to driver directory
cd "${DRIVER_NAME}"

# Build with SocketCAN support
echo "Building driver with SocketCAN/netdev support..."
make netdev

# Install driver
echo "Installing driver..."
sudo make install

# Load the module
echo "Loading PEAK driver module..."
sudo modprobe pcan

# Display driver info
echo ""
echo "========================================"
echo "Installation complete!"
echo "========================================"
echo ""
echo "Driver loaded successfully:"
lsmod | grep pcan

echo ""
echo "Checking for PEAK devices..."
pcaninfo || echo "No PEAK devices connected"

echo ""
echo "Available CAN interfaces:"
ip link show | grep -E "can[0-9]+" || echo "No CAN interfaces found"

echo ""
echo "========================================"
echo "SocketCAN Usage Examples:"
echo "========================================"
echo ""
echo "# Configure and bring up CAN interface at 500 kbps:"
echo "sudo ip link set can4 type can bitrate 500000"
echo "sudo ip link set can4 up"
echo ""
echo "# Monitor CAN traffic:"
echo "candump can4"
echo ""
echo "# Send test message:"
echo "cansend can4 123#DEADBEEF"
echo ""
echo "# For CAN FD mode:"
echo "sudo ip link set can4 type can bitrate 500000 dbitrate 2000000 fd on"
echo "sudo ip link set can4 up"
echo ""
echo "========================================"
echo "Character Device Usage:"
echo "========================================"
echo ""
echo "# Test receive:"
echo "receivetest -f=/dev/pcanusbfd32 -b=500K"
echo ""
echo "# Test transmit:"
echo "transmitest -f=/dev/pcanusbfd32 -b=500K"
echo ""
