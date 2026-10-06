#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$BASE_DIR/scripts/jetson/setup-jetson-thor.sh"

if [[ -f "$SCRIPT_PATH" ]]; then
	exec "$SCRIPT_PATH" "$@"
fi

echo "[ERROR] Could not find setup-jetson-thor implementation." >&2
echo "[ERROR] Checked: $SCRIPT_PATH" >&2
exit 1