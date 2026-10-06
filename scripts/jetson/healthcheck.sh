#!/usr/bin/env bash
# Post-install validation script for Jetson setup.

set -euo pipefail

PASS=0
FAIL=0

ok() {
    echo "[PASS] $1"
    PASS=$((PASS + 1))
}

bad() {
    echo "[FAIL] $1"
    FAIL=$((FAIL + 1))
}

check_cmd() {
    local name="$1"
    local cmd="$2"

    if eval "$cmd" >/dev/null 2>&1; then
        ok "$name"
    else
        bad "$name"
    fi
}

has_peak_hardware() {
    if command -v lsusb >/dev/null 2>&1 && lsusb | grep -qi "0c72\|peak-system\|pcan"; then
        return 0
    fi

    if command -v lspci >/dev/null 2>&1 && lspci | grep -qi "peak\|pcan"; then
        return 0
    fi

    return 1
}

has_peak_module_loaded() {
    lsmod | grep -Eq '^(pcan|peak_usb|peak_pci|peak_pciefd)\b'
}

check_ilitek_mouse_rule() {
    local dev_name
    local vendor
    local model
    local device_name

    shopt -s nullglob
    for dev_path in /sys/class/input/event*; do
        dev_name="${dev_path##*/}"
        if [[ -f "$dev_path/device/id/vendor" ]] && [[ -f "$dev_path/device/id/model" ]]; then
            vendor="$(tr -d '\n' < "$dev_path/device/id/vendor" 2>/dev/null || true)"
            model="$(tr -d '\n' < "$dev_path/device/id/model" 2>/dev/null || true)"
            if [[ "$vendor" == "222a" && "$model" == "0001" ]]; then
                device_name="$(cat "$dev_path/device/name" 2>/dev/null || true)"
                if [[ "$device_name" == *Mouse* ]]; then
                    if udevadm info --query=property --name="/dev/input/$dev_name" 2>/dev/null | grep -q '^LIBINPUT_IGNORE_DEVICE=1$'; then
                        ok "Ilitek mouse ignored by libinput"
                        return 0
                    fi
                    bad "Ilitek mouse ignored by libinput"
                    return 0
                fi
            fi
        fi
    done

    ok "Ilitek mouse ignore check not applicable (device not present)"
}

check_ilitek_rule_file() {
    local rule_file="/etc/udev/rules.d/99-ilitek-ignore-mouse.rules"
    local expected='KERNEL=="event*", ENV{ID_VENDOR_ID}=="222a", ENV{ID_MODEL_ID}=="0001", ATTRS{name}=="*Mouse*", ENV{LIBINPUT_IGNORE_DEVICE}="1", ENV{ID_INPUT_MOUSE}="", ENV{ID_INPUT}=""'

    if [[ -f "$rule_file" ]] && grep -Fxq "$expected" "$rule_file" 2>/dev/null; then
        ok "Ilitek udev rule file present and correct"
    else
        bad "Ilitek udev rule file present and correct"
    fi
}

echo "=== Jetson Healthcheck ==="

check_cmd "Hostname is jetson" "[[ \"$(hostname)\" == \"jetson\" ]]"
check_cmd "Git installed" "command -v git"
check_cmd "Git LFS installed" "command -v git-lfs"
check_cmd "Docker installed" "command -v docker"
check_cmd "Docker service active" "systemctl is-active --quiet docker"
check_cmd "Docker Compose installed" "command -v docker-compose"
check_cmd "VS Code installed" "command -v code"
check_cmd "Google Chrome installed" "command -v google-chrome || command -v google-chrome-stable"
check_cmd "Firefox (Snap) installed" "snap list firefox || command -v firefox"
check_cmd "OpenSSH active" "systemctl is-active --quiet ssh || systemctl is-active --quiet sshd"
check_cmd "TeamViewer installed" "command -v teamviewer"
check_cmd "Tailscale installed" "command -v tailscale"
check_cmd "dnsmasq installed" "command -v dnsmasq"
check_cmd "dnsmasq active" "systemctl is-active --quiet dnsmasq"
check_cmd "Avahi active" "systemctl is-active --quiet avahi-daemon"
check_ilitek_rule_file
check_ilitek_mouse_rule

if has_peak_hardware; then
    if has_peak_module_loaded; then
        ok "PEAK/PCAN module loaded"
    else
        bad "PEAK/PCAN module loaded"
    fi
else
    ok "PEAK hardware not detected (PCAN optional)"
fi

check_cmd "Routing script exists" "test -f 'envSetup/jetson/setupRouting.sh'"
check_cmd "Thor profile mgbe0-dhcp exists" "nmcli -t -f NAME connection show | grep -Fxq 'mgbe0-dhcp'"
check_cmd "Thor profile mgbe1-dhcp exists" "nmcli -t -f NAME connection show | grep -Fxq 'mgbe1-dhcp'"
check_cmd "Thor profile uplink-mgbe2_0 exists" "nmcli -t -f NAME connection show | grep -Fxq 'uplink-mgbe2_0'"
check_cmd "Thor profile uplink-mgbe3_0 exists" "nmcli -t -f NAME connection show | grep -Fxq 'uplink-mgbe3_0'"

if command -v nvidia-smi >/dev/null 2>&1; then
    ok "NVIDIA driver available"
else
    bad "NVIDIA driver available"
fi

if docker info 2>/dev/null | grep -qi 'Default Runtime: nvidia'; then
    ok "Docker default runtime is nvidia"
else
    bad "Docker default runtime is nvidia"
fi

echo ""
echo "Summary: PASS=$PASS FAIL=$FAIL"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi