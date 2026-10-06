#!/usr/bin/env bash
set -euo pipefail

SSH_USER="jetson"
SSH_PASS="1234"
TARGET_KERNEL="6.8.12-1021-tegra"

DESKTOP_CONTENT='[Desktop Entry]
Version=1.0
Type=Application
Name=Update photoheyler
Comment=Pull latest photoheyler Docker images
Exec=bash -lc '\''cd ~ && docker compose pull'\''
Icon=view-refresh
Terminal=true
Categories=Utility;'

# Alle aktiven Linux-Geräte im Tailscale-Netz abrufen
mapfile -t PEERS < <(tailscale status --json | jq -r '
  .Peer[] | 
  select(.OS == "linux" and .Online == true) | 
  .TailscaleIPs[0]
')

echo "Gefundene Linux-Peers: ${#PEERS[@]}"

for ip in "${PEERS[@]}"; do
    echo "Prüfe $ip..."

    # Remote Kernel abfragen
    REMOTE_KERNEL=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=4 "$SSH_USER@$ip" "uname -r" 2>/dev/null || true)

    if [[ "$REMOTE_KERNEL" == "$TARGET_KERNEL" ]]; then
        echo "  -> Treffer ($REMOTE_KERNEL). Schreibe Desktop-Datei..."

        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$ip" bash -c "'
            mkdir -p /home/jetson/Desktop
            cat <<\"EOF\" > /home/jetson/Desktop/APP-Update.desktop
$DESKTOP_CONTENT
EOF
            chmod +x /home/jetson/Desktop/APP-Update.desktop
            gio set /home/jetson/Desktop/APP-Update.desktop metadata::trusted true 2>/dev/null || true
        '"
        echo "  -> Fertig auf $ip."
    else
        echo "  -> Übersprungen (Kernel: ${REMOTE_KERNEL:-Offline/Fehler})"
    fi
done