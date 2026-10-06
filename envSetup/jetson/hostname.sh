#!/bin/bash

# ============================================================================
# Jetson Hostname Configuration Script
# ============================================================================
# Setzt den Hostname der Jetson auf "jetson" und konfiguriert mDNS (Avahi)
# damit die Jetson über "jetson.local" erreichbar ist
# ============================================================================

set -e

echo ""
echo "=========================================="
echo "  Jetson Hostname Setup"
echo "=========================================="
echo ""

# ===== 1. Hostname setzen =====
echo "[1/4] Setze Hostname auf 'jetson'..."
sudo hostnamectl set-hostname jetson
echo "✓ Hostname gesetzt"

# ===== 2. systemd-hostnamed neustarten =====
echo "[2/4] Starte systemd-hostnamed neu..."
sudo systemctl restart systemd-hostnamed
echo "✓ systemd-hostnamed neu gestartet"

# ===== 3. System aktualisieren =====
echo "[3/4] Aktualisiere Paketliste..."
sudo apt update
echo "✓ Paketliste aktualisiert"

# ===== 4. Avahi Daemon installieren =====
echo "[4/4] Installiere Avahi Daemon für mDNS..."
sudo apt install -y avahi-daemon
echo "✓ Avahi Daemon installiert"

# ===== 5. Avahi Daemon aktivieren =====
echo "[5/5] Aktiviere und starte Avahi Daemon..."
sudo systemctl enable --now avahi-daemon
echo "✓ Avahi Daemon aktiviert und gestartet"

echo ""
echo "=========================================="
echo "  ✓ Setup abgeschlossen!"
echo "=========================================="
echo ""
echo "Die Jetson ist jetzt über folgende Namen erreichbar:"
echo "  • Hostname:     jetson"
echo "  • mDNS Name:    jetson.local (SSH: ssh jetson@jetson.local)"
echo ""
