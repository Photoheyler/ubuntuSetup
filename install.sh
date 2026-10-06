#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$BASE_DIR/scripts/jetson/install.sh"

if [[ -f "$SCRIPT_PATH" ]]; then
	exec "$SCRIPT_PATH" "$@"
fi

# Bundle fallback: run local setup script directly if scripts/ tree is not present.
if [[ -f "$BASE_DIR/setup-jetson-thor.sh" ]]; then
	exec bash "$BASE_DIR/setup-jetson-thor.sh" "$@"
fi

echo "[ERROR] Could not find installer script." >&2
echo "[ERROR] Checked: $SCRIPT_PATH and $BASE_DIR/setup-jetson-thor.sh" >&2
exit 1