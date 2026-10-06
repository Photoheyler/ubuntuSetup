#!/usr/bin/env bash
# Production entrypoint: preflight + logging + execution of setup-jetson-thor.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-jetson-thor.sh"
LOG_FILE="/var/log/jetson-setup.log"

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "[ERROR] Please run as root: sudo bash install.sh"
        exit 1
    fi
}

preflight() {
    echo "[INFO] Running preflight checks..."

    if [[ ! -f /etc/os-release ]]; then
        echo "[ERROR] Cannot detect OS"
        exit 1
    fi

    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        echo "[ERROR] Unsupported OS: ${ID:-unknown}"
        exit 1
    fi

    if [[ ! -f "$SETUP_SCRIPT" ]]; then
        echo "[ERROR] Missing setup script: $SETUP_SCRIPT"
        exit 1
    fi

    chmod +x "$SETUP_SCRIPT"

    for cmd in bash sudo apt-get systemctl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "[ERROR] Missing required command: $cmd"
            exit 1
        fi
    done

    echo "[INFO] Ubuntu ${VERSION_ID:-unknown} detected"
}

enable_logging() {
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE" || true
    echo "[INFO] Logging to: $LOG_FILE"
    exec > >(tee -a "$LOG_FILE") 2>&1
}

main() {
    require_root
    enable_logging
    preflight

    echo "[INFO] Starting Jetson production setup..."
    bash "$SETUP_SCRIPT"
    echo "[INFO] Setup finished successfully"
    echo "[INFO] Next step: run healthcheck with 'bash healthcheck.sh'"
}

main "$@"
