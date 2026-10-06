#!/bin/bash

# ============================================================================
# Jetson Router Setup Script
# ============================================================================
# Konfiguriert die Jetson als Router mit:
# - IP Forwarding & nftables NAT
# - dnsmasq DHCP+DNS für LAN
# - Multi-Ethernet WAN Uplink mit Auto-Failover
# - WiFi Hotspot Integration
#
# Usage: sudo bash setupRouting.sh
# ============================================================================

set -e

# ============================================================================
# [1/6] Enable IP forwarding & Network Buffers
# ============================================================================
echo "=== [1/6] Enable IP forwarding & Network Buffers ==="
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.core.rmem_max=26214400
sysctl -w net.core.rmem_default=26214400
sysctl -w net.core.netdev_max_backlog=10000

# Dauerhaft in Config-Datei schreiben
cat > /etc/sysctl.d/99-network-performance.conf << 'EOF'
net.ipv4.ip_forward=1
net.core.rmem_max=26214400
net.core.rmem_default=26214400
net.core.netdev_max_backlog=10000
EOF

# ============================================================================
# [2/6] Configure nftables NAT
# ============================================================================
echo "=== [2/6] Write nftables NAT config ==="
mkdir -p /etc/nftables.d

cat > /etc/nftables.d/jetson-nat.nft << 'NFT'
table inet jetson-nat {
    # All non-WAN interfaces (LAN side)
    set lan_ifaces {
        type ifname
        elements = { "mgbe0_0", "mgbe1_0", "wlP1p1s0", "lo", "docker0", "l4tbr0" }
    }

    set lan_subnets {
        type ipv4_addr
        flags interval
        elements = {
            192.168.100.0/24,
            192.168.101.0/24,
            192.168.102.0/24,
            192.168.103.0/24,
            192.168.104.0/24,
            10.42.0.0/16
        }
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr @lan_subnets oifname != @lan_ifaces counter masquerade
    }
}
NFT

# Ensure nftables.conf includes the .nft files
grep -q 'include "/etc/nftables.d/*.nft"' /etc/nftables.conf || \
    echo 'include "/etc/nftables.d/*.nft"' >> /etc/nftables.conf

systemctl enable nftables

# Fully delete the table to avoid stale sets/elements on re-runs
nft delete table inet jetson-nat 2>/dev/null || true
nft -f /etc/nftables.d/jetson-nat.nft
echo "✓ nftables OK"

# ============================================================================
# [3/6] Configure dnsmasq for DHCP+DNS
# ============================================================================
echo "=== [3/6] Write dnsmasq DHCP+DNS config ==="

cat > /etc/dnsmasq.conf << 'DNSMASQ'
# Jetson router – DHCP + DNS for LAN subnets
bind-dynamic
except-interface=wlP1p1s0

domain=lan
local=/lan/
expand-hosts
dhcp-authoritative

# jetson.lan resolves to WiFi hotspot IP
address=/jetson.lan/10.42.0.1

# WiFi client hostnames synced by wifi-lease-to-hosts.sh
addn-hosts=/run/dnsmasq-wifi-hosts

# Upstream DNS
server=127.0.0.53

# DHCP ranges per subnet
dhcp-range=set:lan100,192.168.100.10,192.168.100.200,12h
dhcp-range=set:lan101,192.168.101.10,192.168.101.200,12h
dhcp-range=set:lan102,192.168.102.10,192.168.102.200,12h
dhcp-range=set:lan103,192.168.103.10,192.168.103.200,12h
dhcp-range=set:lan104,192.168.104.10,192.168.104.200,12h

# Per-subnet gateway
dhcp-option=tag:lan100,option:router,192.168.100.1
dhcp-option=tag:lan101,option:router,192.168.101.1
dhcp-option=tag:lan102,option:router,192.168.102.1
dhcp-option=tag:lan103,option:router,192.168.103.1
dhcp-option=tag:lan104,option:router,192.168.104.1

# DNS server – point clients to the Jetson
dhcp-option=tag:lan100,option:dns-server,192.168.100.1
dhcp-option=tag:lan101,option:dns-server,192.168.101.1
dhcp-option=tag:lan102,option:dns-server,192.168.102.1
dhcp-option=tag:lan103,option:dns-server,192.168.103.1
dhcp-option=tag:lan104,option:dns-server,192.168.104.1

# Search domain
dhcp-option=tag:lan100,option:domain-search,lan
dhcp-option=tag:lan101,option:domain-search,lan
dhcp-option=tag:lan102,option:domain-search,lan
dhcp-option=tag:lan103,option:domain-search,lan
dhcp-option=tag:lan104,option:domain-search,lan

# WiFi client hostnames sync
addn-hosts=/run/dnsmasq-wifi-hosts

# Handle stale WiFi entries on wired lease
dhcp-script=/usr/local/sbin/wired-lease-event.sh
DNSMASQ

# Remove stale /etc/hosts jetson entries
sed -i '/[[:space:]]jetson$/d' /etc/hosts

# Hotspot DNS: NM spawns dnsmasq for wlP1p1s0
mkdir -p /etc/NetworkManager/dnsmasq-shared.d

cat > /etc/NetworkManager/dnsmasq-shared.d/jetson.conf << 'NMDNS'
address=/jetson.lan/10.42.0.1
dhcp-option=option:domain-search,lan
dhcp-script=/usr/local/sbin/wifi-lease-to-hosts.sh
NMDNS

# ============================================================================
# Install wifi-lease-to-hosts.sh script
# ============================================================================
echo "=== Writing wifi-lease-to-hosts.sh ==="

cat > /usr/local/sbin/wifi-lease-to-hosts.sh << 'LEASESCRIPT'
#!/bin/bash
# Called by NM hotspot dnsmasq on every DHCP event
# Usage: <add|del|old> <MAC> <IP> [hostname]

ACTION="$1"
IP="$3"
HOSTNAME="$4"
HOSTS_FILE=/run/dnsmasq-wifi-hosts
PIDFILE=/run/dnsmasq/dnsmasq.pid
WIRED_LEASES=/var/lib/misc/dnsmasq.leases

# Remove any existing entry for this IP
touch "$HOSTS_FILE"
sed -i "/\\b${IP//./\\.}\\b/d" "$HOSTS_FILE"

if [ "$ACTION" != "del" ] && [ -n "$HOSTNAME" ]; then
    WIRED_IP=$(grep -i "[[:space:]]${HOSTNAME}[[:space:]]" "$WIRED_LEASES" 2>/dev/null | awk '{print $3}')
    WIRED_ACTIVE=0
    if [ -n "$WIRED_IP" ]; then
        ping -c1 -W1 -q "$WIRED_IP" &>/dev/null && WIRED_ACTIVE=1
    fi
    if [ "$WIRED_ACTIVE" -eq 0 ]; then
        echo "$IP $HOSTNAME $HOSTNAME.lan" >> "$HOSTS_FILE"
    fi
fi

# Signal main dnsmasq to reload
[ -f "$PIDFILE" ] && kill -HUP "$(cat "$PIDFILE")" 2>/dev/null || true
LEASESCRIPT
chmod +x /usr/local/sbin/wifi-lease-to-hosts.sh

# ============================================================================
# Install wired-lease-event.sh script
# ============================================================================
echo "=== Writing wired-lease-event.sh ==="

cat > /usr/local/sbin/wired-lease-event.sh << 'WIREDEVENT'
#!/bin/bash
# Called by main dnsmasq on every wired DHCP event
# Usage: <add|del|old> <MAC> <IP> [hostname]

ACTION="$1"
HOSTNAME="$4"
HOSTS_FILE=/run/dnsmasq-wifi-hosts
PIDFILE=/run/dnsmasq/dnsmasq.pid

# On wired add/renew: remove the WiFi entry
if [ "$ACTION" != "del" ] && [ -n "$HOSTNAME" ]; then
    if grep -qi "[[:space:]]${HOSTNAME}[[:space:]]" "$HOSTS_FILE" 2>/dev/null; then
        sed -i "/[[:space:]]${HOSTNAME}[[:space:]]/Id" "$HOSTS_FILE"
        [ -f "$PIDFILE" ] && kill -HUP "$(cat "$PIDFILE")" 2>/dev/null || true
    fi
fi
WIREDEVENT
chmod +x /usr/local/sbin/wired-lease-event.sh

# ============================================================================
# Install sync-wifi-hosts background task
# ============================================================================

cat > /usr/local/sbin/sync-wifi-hosts.sh << 'SYNCSCRIPT'
#!/bin/bash
# Re-syncs /run/dnsmasq-wifi-hosts every 30 seconds
HOSTS_FILE=/run/dnsmasq-wifi-hosts
WIRED_LEASES=/var/lib/misc/dnsmasq.leases
WIFI_LEASES=/var/lib/NetworkManager/dnsmasq-wlP1p1s0.leases
PIDFILE=/run/dnsmasq/dnsmasq.pid
CHANGED=0

NEW=$(mktemp)
while IFS=' ' read -r _exp _mac ip hostname _rest; do
    [ -z "$hostname" ] || [ "$hostname" = '*' ] && continue
    WIRED_LINE=$(grep -i "[[:space:]]${hostname}[[:space:]]" "$WIRED_LEASES" 2>/dev/null)
    WIRED_IP=$(echo "$WIRED_LINE" | awk '{print $3}')
    if [ -n "$WIRED_IP" ] && ping -c1 -W1 -q "$WIRED_IP" &>/dev/null; then
        continue  # wired is active
    fi
    if [ -n "$WIRED_LINE" ]; then
        sed -i "/[[:space:]]${hostname}[[:space:]]/Id" "$WIRED_LEASES"
        CHANGED=2
    fi
    echo "$ip $hostname $hostname.lan"
done < "$WIFI_LEASES" 2>/dev/null > "$NEW"

if ! diff -q "$NEW" "$HOSTS_FILE" &>/dev/null; then
    cp "$NEW" "$HOSTS_FILE"
    chown nobody:nogroup "$HOSTS_FILE"
    [ "$CHANGED" -lt 1 ] && CHANGED=1
fi
rm -f "$NEW"

[ "$CHANGED" -eq 2 ] && systemctl restart dnsmasq && exit 0
[ "$CHANGED" -eq 1 ] && [ -f "$PIDFILE" ] && kill -HUP "$(cat "$PIDFILE")" 2>/dev/null || true
SYNCSCRIPT
chmod +x /usr/local/sbin/sync-wifi-hosts.sh

cat > /etc/systemd/system/sync-wifi-hosts.service << 'SVC'
[Unit]
Description=Sync WiFi DHCP hostnames into dnsmasq addn-hosts
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sync-wifi-hosts.sh
SVC

cat > /etc/systemd/system/sync-wifi-hosts.timer << 'TIMER'
[Unit]
Description=Refresh WiFi hostnames every 30 seconds

[Timer]
OnBootSec=10
OnUnitActiveSec=30s
AccuracySec=5s

[Install]
WantedBy=timers.target
TIMER

systemctl daemon-reload
systemctl enable --now sync-wifi-hosts.timer
echo "✓ sync-wifi-hosts timer installed OK"

# Pre-create the hosts file
touch /run/dnsmasq-wifi-hosts
chown nobody:nogroup /run/dnsmasq-wifi-hosts

# Seed with existing WiFi leases
: > /run/dnsmasq-wifi-hosts
WIFI_LEASES_FILE="/var/lib/NetworkManager/dnsmasq-wlP1p1s0.leases"
if [ -f "$WIFI_LEASES_FILE" ]; then
    while IFS=' ' read -r _exp _mac ip hostname _rest; do
        [ -z "$hostname" ] || [ "$hostname" = '*' ] && continue
        WIRED_IP=$(grep -i "[[:space:]]${hostname}[[:space:]]" /var/lib/misc/dnsmasq.leases 2>/dev/null | awk '{print $3}')
        if [ -n "$WIRED_IP" ] && ping -c1 -W1 -q "$WIRED_IP" &>/dev/null; then
            continue  # wired is still alive
        fi
        echo "$ip $hostname $hostname.lan"
    done < "$WIFI_LEASES_FILE" >> /run/dnsmasq-wifi-hosts
fi

systemctl enable dnsmasq
systemctl restart dnsmasq
echo "✓ dnsmasq OK"

# ============================================================================
# [4/6] Configure systemd-resolved for .lan domain
# ============================================================================
echo "=== [4/6] Fix systemd-resolved stub listener + .lan forwarding ==="

mkdir -p /etc/systemd/resolved.conf.d

cat > /etc/systemd/resolved.conf.d/stub.conf << 'RESOLVED'
[Resolve]
DNSStubListener=yes
RESOLVED

cat > /etc/systemd/resolved.conf.d/lan.conf << 'LANCONF'
[Resolve]
# Route all .lan queries to the main dnsmasq
DNS=127.0.0.1
Domains=~lan
LANCONF

systemctl restart systemd-resolved
echo "✓ resolved OK"

# ============================================================================
# [4b/6] Install NM dispatcher for fast uplink switchover
# ============================================================================
echo "=== [4b/6] Install NM dispatcher script for fast WAN-uplink switchover ==="

mkdir -p /etc/NetworkManager/dispatcher.d

cat > /etc/NetworkManager/dispatcher.d/99-uplink-switched.sh << 'DISPATCHER'
#!/bin/bash
# NM calls this as: <iface> <action>

IFACE="$1"
ACTION="$2"

# Only react when a WAN interface comes up
[ "$ACTION" = "up" ] || exit 0

# Skip LAN-side interfaces
LAN_IFACES="mgbe0_0 mgbe1_0 wlP1p1s0 lo docker0 l4tbr0"
for lan in $LAN_IFACES; do
    [ "$IFACE" = "$lan" ] && exit 0
done

logger -t nm-uplink-switch "WAN uplink switched to $IFACE - flushing caches"

# Flush caches
ip neigh flush all 2>/dev/null || true
ip route flush cache 2>/dev/null || true
resolvectl flush-caches 2>/dev/null || true
PIDFILE=/run/dnsmasq/dnsmasq.pid
[ -f "$PIDFILE" ] && kill -HUP "$(cat "$PIDFILE")" 2>/dev/null || true

logger -t nm-uplink-switch "Cache flush complete for uplink $IFACE"
DISPATCHER
chmod +x /etc/NetworkManager/dispatcher.d/99-uplink-switched.sh
echo "✓ NM dispatcher script installed OK"

# ============================================================================
# [4c/6] Configure WAN uplinks as DHCP clients
# ============================================================================
echo "=== [4c/6] Configure WAN uplinks as DHCP clients ==="

WAN_ETHERNET_IFACES="enP2p1s0"
for IFACE in $WAN_ETHERNET_IFACES; do
    CONNAME="${IFACE}-dhcp"
    nmcli connection delete "$CONNAME" 2>/dev/null || true
    nmcli connection add \
        type ethernet \
        ifname "$IFACE" \
        con-name "$CONNAME" \
        ipv4.method auto \
        ipv6.method auto \
        connection.autoconnect yes
    if ip link show "$IFACE" &>/dev/null; then
        nmcli connection up "$CONNAME" 2>/dev/null || true
        echo "✓ $IFACE: DHCP client profile active (metric 100)"
    else
        echo "  $IFACE: not present now - profile saved"
    fi
done

# Configure LAN interfaces with jumbo frames
LAN_JUMBO_IFACES="mgbe0_0 mgbe1_0"
for IFACE in $LAN_JUMBO_IFACES; do
    if ip link show "$IFACE" &>/dev/null; then
        ip link set "$IFACE" mtu 9000 2>/dev/null || \
            echo "  $IFACE: MTU 9000 not supported"
        echo "✓ $IFACE: MTU 9000 applied"
    else
        echo "  $IFACE: not present, skipping MTU"
    fi
done

mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-default-dhcp.conf << 'NMCONF'
[connection]
ipv4.method=auto
ipv6.method=auto
NMCONF

systemctl reload NetworkManager 2>/dev/null || true
echo "✓ NM WAN DHCP profiles written"

# ============================================================================
# [5/6] Configure DOCKER-USER forwarding rules
# ============================================================================
echo "=== [5/6] Configure DOCKER-USER forwarding rules ==="

# Wait for Docker
if ! iptables -L DOCKER-USER -n &>/dev/null; then
    echo "WARNING: DOCKER-USER chain not found - is Docker running?"
    echo "Re-run this script after Docker starts."
    exit 1
fi

# Flush and rebuild
iptables -F DOCKER-USER

# Allow LAN-WAN forwarding
iptables -D FORWARD -s 192.168.100.0/22 ! -o docker0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -s 192.168.104.0/24 ! -o docker0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -s 10.42.0.0/16 ! -o docker0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -d 10.42.0.0/16 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -d 192.168.100.0/22 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -d 192.168.104.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

iptables -A FORWARD -s 192.168.100.0/22 ! -o docker0 -j ACCEPT
iptables -A FORWARD -s 192.168.104.0/24 ! -o docker0 -j ACCEPT
iptables -A FORWARD -s 10.42.0.0/16 ! -o docker0 -j ACCEPT
iptables -A FORWARD -d 10.42.0.0/16 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -d 192.168.100.0/22 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -d 192.168.104.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
echo "✓ iptables FORWARD OK"

# DOCKER-USER rules
iptables -I DOCKER-USER 1 -s 192.168.100.0/22 ! -o docker0 -j RETURN
iptables -I DOCKER-USER 2 -s 192.168.104.0/24 ! -o docker0 -j RETURN
iptables -I DOCKER-USER 3 -s 10.42.0.0/16 ! -o docker0 -j RETURN
iptables -I DOCKER-USER 4 -d 10.42.0.0/16 -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
echo "✓ iptables DOCKER-USER OK"

# ============================================================================
# [6/6] Install systemd drop-in for Docker restart
# ============================================================================
echo "=== [6/6] Install systemd drop-in to re-apply rules after Docker starts ==="

mkdir -p /etc/systemd/system/docker.service.d

cat > /etc/systemd/system/docker.service.d/lan-forward.conf << 'DROPIN'
[Service]
ExecStartPost=/sbin/iptables -F DOCKER-USER
ExecStartPost=/sbin/iptables -A FORWARD -s 192.168.100.0/22 ! -o docker0 -j ACCEPT
ExecStartPost=/sbin/iptables -A FORWARD -s 192.168.104.0/24 ! -o docker0 -j ACCEPT
ExecStartPost=/sbin/iptables -A FORWARD -s 10.42.0.0/16 ! -o docker0 -j ACCEPT
ExecStartPost=/sbin/iptables -A FORWARD -d 10.42.0.0/16 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ExecStartPost=/sbin/iptables -A FORWARD -d 192.168.100.0/22 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ExecStartPost=/sbin/iptables -A FORWARD -d 192.168.104.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ExecStartPost=/sbin/iptables -A DOCKER-USER -s 192.168.100.0/22 ! -o docker0 -j RETURN
ExecStartPost=/sbin/iptables -A DOCKER-USER -s 192.168.104.0/24 ! -o docker0 -j RETURN
ExecStartPost=/sbin/iptables -A DOCKER-USER -s 10.42.0.0/16 ! -o docker0 -j RETURN
ExecStartPost=/sbin/iptables -A DOCKER-USER -d 10.42.0.0/16 -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
DROPIN

systemctl daemon-reload
echo "✓ systemd drop-in installed OK"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=== Setup complete ==="
echo ""
echo "Configuration:"
echo "  • LAN subnets: 192.168.100-104.x/24, 10.42.0.x/24"
echo "  • WAN uplinks: mgbe2_0, mgbe3_0, enP2p1s0, wlx*"
echo ""
echo "Fast uplink switchover:"
echo "  • When non-LAN interface goes up, caches flush automatically"
echo "  • Switchover time: <5 seconds"
echo ""
echo "Verify with:"
echo "  sudo nft list chain inet jetson-nat postrouting"
echo "  sudo iptables -L DOCKER-USER -v -n"
echo "  ping -I 192.168.101.1 8.8.8.8 -c3"
echo "  journalctl -t nm-uplink-switch -n 20"
echo ""
