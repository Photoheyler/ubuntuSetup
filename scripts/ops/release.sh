#!/usr/bin/env bash
# Build customer delivery bundle without .git history.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
BUNDLE_ROOT="$DIST_DIR/jetson-setup-bundle"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_NAME="jetson-setup-bundle-$TIMESTAMP.tar.gz"

mkdir -p "$DIST_DIR"
rm -rf "$BUNDLE_ROOT"
mkdir -p "$BUNDLE_ROOT/envSetup/jetson"
mkdir -p "$BUNDLE_ROOT/scripts/jetson"

copy_if_exists() {
    local src="$1"
    local dst="$2"
    if [[ -f "$src" ]]; then
        cp "$src" "$dst"
    else
        echo "[WARN] Missing optional file: $src"
    fi
}

copy_first_existing() {
    local dst="$1"
    shift
    local src

    for src in "$@"; do
        if [[ -f "$src" ]]; then
            cp "$src" "$dst"
            return 0
        fi
    done

    echo "[WARN] Missing optional file for target: $dst"
    return 0
}

normalize_lf_if_script() {
    local file="$1"
    case "$file" in
        *.sh)
            # Strip UTF-8 BOM and normalize CRLF -> LF.
            sed -i '1s/^\xEF\xBB\xBF//' "$file"
            sed -i 's/\r$//' "$file"
            ;;
    esac
}

copy_if_exists "$SCRIPT_DIR/scripts/jetson/install.sh" "$BUNDLE_ROOT/install.sh"
copy_if_exists "$SCRIPT_DIR/scripts/jetson/setup-jetson-thor.sh" "$BUNDLE_ROOT/setup-jetson-thor.sh"
copy_if_exists "$SCRIPT_DIR/scripts/jetson/healthcheck.sh" "$BUNDLE_ROOT/healthcheck.sh"
copy_if_exists "$SCRIPT_DIR/scripts/jetson/start_app.sh" "$BUNDLE_ROOT/scripts/jetson/start_app.sh"
copy_if_exists "$SCRIPT_DIR/scripts/jetson/APP-Start.desktop" "$BUNDLE_ROOT/scripts/jetson/APP-Start.desktop"
copy_if_exists "$SCRIPT_DIR/scripts/jetson/APP-Update.desktop" "$BUNDLE_ROOT/scripts/jetson/APP-Update.desktop"

copy_first_existing "$BUNDLE_ROOT/envSetup/daemon.json" \
    "$SCRIPT_DIR/config/daemon.json"

copy_first_existing "$BUNDLE_ROOT/envSetup/jetson/setupRouting.sh" \
    "$SCRIPT_DIR/envSetup/jetson/setupRouting.sh"

copy_first_existing "$BUNDLE_ROOT/envSetup/jetson/docker-compose.yml" \
    "$SCRIPT_DIR/envSetup/jetson/docker-compose.yml"

copy_first_existing "$BUNDLE_ROOT/envSetup/jetson/thorsetup.sh" \
    "$SCRIPT_DIR/envSetup/jetson/thorsetup.sh"

copy_first_existing "$BUNDLE_ROOT/envSetup/install_pcan_driver.sh" \
    "$SCRIPT_DIR/envSetup/install_pcan_driver.sh"

normalize_lf_if_script "$BUNDLE_ROOT/install.sh"
normalize_lf_if_script "$BUNDLE_ROOT/setup-jetson-thor.sh"
normalize_lf_if_script "$BUNDLE_ROOT/healthcheck.sh"
normalize_lf_if_script "$BUNDLE_ROOT/scripts/jetson/start_app.sh"
normalize_lf_if_script "$BUNDLE_ROOT/scripts/jetson/APP-Start.desktop"
normalize_lf_if_script "$BUNDLE_ROOT/scripts/jetson/APP-Update.desktop"
normalize_lf_if_script "$BUNDLE_ROOT/envSetup/jetson/setupRouting.sh"
normalize_lf_if_script "$BUNDLE_ROOT/envSetup/jetson/thorsetup.sh"
normalize_lf_if_script "$BUNDLE_ROOT/envSetup/install_pcan_driver.sh"

copy_first_existing "$BUNDLE_ROOT/JETSON_THOR_SETUP.md" \
    "$SCRIPT_DIR/envSetup/jetson/thorsetup.md"

cat > "$BUNDLE_ROOT/README_INSTALL.txt" << 'EOF'
Jetson Setup Bundle
===================

1) Copy this folder to the Jetson and enter it.
2) Run: sudo bash install.sh
3) After install: bash healthcheck.sh

Optional application deployment:
  docker compose -f docker-compose.yml pull
  docker compose -f docker-compose.yml up -d
EOF

chmod +x "$BUNDLE_ROOT/install.sh" || true
chmod +x "$BUNDLE_ROOT/setup-jetson-thor.sh" || true
chmod +x "$BUNDLE_ROOT/healthcheck.sh" || true
chmod +x "$BUNDLE_ROOT/scripts/jetson/start_app.sh" || true
chmod +x "$BUNDLE_ROOT/scripts/jetson/APP-Start.desktop" || true
chmod +x "$BUNDLE_ROOT/scripts/jetson/APP-Update.desktop" || true
chmod +x "$BUNDLE_ROOT/envSetup/jetson/setupRouting.sh" || true
chmod +x "$BUNDLE_ROOT/envSetup/install_pcan_driver.sh" || true

(
    cd "$BUNDLE_ROOT"
    sha256sum \
        install.sh \
        setup-jetson-thor.sh \
        healthcheck.sh \
        scripts/jetson/start_app.sh \
        scripts/jetson/APP-Start.desktop \
        scripts/jetson/APP-Update.desktop \
        envSetup/daemon.json \
        envSetup/install_pcan_driver.sh \
        envSetup/jetson/setupRouting.sh \
        envSetup/jetson/docker-compose.yml \
        envSetup/jetson/thorsetup.sh \
        README_INSTALL.txt \
        > SHA256SUMS
)

(
    cd "$DIST_DIR"
    tar -czf "$ARCHIVE_NAME" "$(basename "$BUNDLE_ROOT")"
)

echo "[INFO] Bundle created: $DIST_DIR/$ARCHIVE_NAME"
echo "[INFO] Unpacked folder: $BUNDLE_ROOT"
