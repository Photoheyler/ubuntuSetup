#!/bin/bash
set -euo pipefail

# PEAK CAN Driver Installation Script - JETSON AGX THOR EDITION
# Fixes "Invalid Argument / Symbol Version Mismatch" on Ubuntu 24.04

DRIVER_VERSION="9.0"
DRIVER_NAME="peak-linux-driver-${DRIVER_VERSION}"
DRIVER_ARCHIVE="${DRIVER_NAME}.tar.gz"
DRIVER_URL="https://www.peak-system.com/fileadmin/media/linux/files/${DRIVER_ARCHIVE}"

echo "========================================"
echo "PEAK CAN Driver Installation (Jetson AGX)"
echo "Kernel: $(uname -r)"
echo "========================================"

ensure_kernel_headers() {
    local kernel_release
    kernel_release="$(uname -r)"

    if [[ -r "/lib/modules/${kernel_release}/build/Makefile" ]]; then
        echo "[1/6] Using existing kernel build tree for ${kernel_release}..."
        return 0
    fi

    echo "[1/6] Resolving kernel headers for ${kernel_release}..."

    local package_candidates=(
        "linux-headers-${kernel_release}"
        "linux-headers-${kernel_release}-generic"
        "linux-headers-tegra"
    )

    local package_name
    for package_name in "${package_candidates[@]}"; do
        if apt-cache show "$package_name" >/dev/null 2>&1; then
            sudo apt install -y build-essential dkms git can-utils libelf-dev libpopt-dev wget mokutil "$package_name"
            return 0
        fi
    done

    local tegra_headers
    mapfile -t tegra_headers < <(apt-cache search '^linux-headers-.*tegra' | awk '{print $1}' | sort -u)
    for package_name in "${tegra_headers[@]}"; do
        if apt-cache show "$package_name" >/dev/null 2>&1; then
            sudo apt install -y build-essential dkms git can-utils libelf-dev libpopt-dev wget mokutil "$package_name"
            return 0
        fi
    done

    echo ""
    echo "ERROR: No suitable Jetson kernel headers package found for ${kernel_release}."
    echo "       Expected one of: ${package_candidates[*]}"
    echo "       If your kernel headers are installed elsewhere, ensure /lib/modules/${kernel_release}/build exists."
    return 1
}

# 1. Abhängigkeiten installieren
echo "[1/6] Installing build dependencies..."
sudo apt update
sudo apt install -y build-essential g++ g++-13 gcc-13
ensure_kernel_headers

# 2. Secure Boot Check
if mokutil --sb-state 2>/dev/null | grep -q "enabled"; then
    echo "!"
    echo "! WARNING: Secure Boot is ENABLED."
    echo "! The driver might not load unless you sign the module or disable SB in BIOS."
    echo "!"
fi

# 3. Download & Entpacken
DOWNLOAD_DIR="/tmp/pcan-install"
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

echo "[2/6] Downloading driver v${DRIVER_VERSION}..."
wget -N "$DRIVER_URL"
tar -xzf "$DRIVER_ARCHIVE"
cd "$DRIVER_NAME"

# 4. Compiler-Fix für NVIDIAs Cross-Compiled Kernel
echo "[3/6] Setting up compiler symlinks for kernel matching..."
sudo apt install -y gcc-13 g++-13
sudo ln -sf /usr/bin/gcc-13 /usr/bin/aarch64-none-linux-gnu-gcc
sudo ln -sf /usr/bin/g++-13 /usr/bin/aarch64-none-linux-gnu-g++
sudo ln -sf /usr/bin/ld /usr/bin/aarch64-none-linux-gnu-ld

# 5. Kompilieren
echo "[4/6] Building driver..."
sudo make clean

# Wir zwingen make, die neu erstellten Symlinks zu nutzen
sudo make NET=NETDEV_SUPPORT CC=aarch64-none-linux-gnu-gcc LD=aarch64-none-linux-gnu-ld USB_SUPPORT=1 PCI_SUPPORT=1 PCIE_SUPPORT=1 ISA_SUPPORT=0 NO_PCCARD_SUPPORT=1

# 6. Installation
echo "[5/6] Installing driver..."
sudo make install
sudo depmod -a

# 7. Modul laden & Testen
echo "[6/6] Loading module pcan..."
# Vorher altes Modul sicherheitshalber entfernen
sudo rmmod pcan 2>/dev/null || true

if sudo modprobe pcan; then
    echo "----------------------------------------"
    echo "SUCCESS: PCAN module loaded successfully!"
    echo "----------------------------------------"
    lsmod | grep pcan
    
    echo ""
    echo "Detected CAN Interfaces:"
    ip link show | grep can || echo "No CAN interfaces found (Check hardware connection)"
else
    echo "----------------------------------------"
    echo "ERROR: PCAN module still failed to load."
    echo "Check 'dmesg | tail -n 20' for details."
    echo "Trying fallback to mainline drivers..."
    sudo rm -f /etc/modprobe.d/blacklist-peak.conf
    sudo modprobe peak_usb 2>/dev/null || true
    echo "----------------------------------------"
fi