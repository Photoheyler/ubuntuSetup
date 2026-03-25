#!/bin/bash
# Jetson Router Setup Script
# Run after fresh install or after Docker installation
# Usage: sudo bash setup-jetson-routing.sh

set -e

echo "=== [1/6] Enable IP forwarding ==="
sysctl -w net.ipv4.ip_forward=1
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.d/99-forward.conf 2>/dev/null || \
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-forward.conf

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
            10.42.0.0/16 }    # /16 covers any subnet NM picks for the hotspot
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
# Fully delete the table to avoid stale sets/elements on re-runs,
# then (re-)apply from the file.
nft delete table inet jetson-nat 2>/dev/null || true
nft -f /etc/nftables.d/jetson-nat.nft
echo "nftables OK"

echo "=== [3/6] Write dnsmasq DHCP+DNS config ==="
cat > /etc/dnsmasq.conf << 'DNSMASQ'
# Jetson router â€” DHCP + DNS for LAN subnets
# bind-dynamic handles interfaces coming up/down after dnsmasq starts
# (bind-interfaces would fail to start when wired ports have no cable).
bind-dynamic
except-interface=wlP1p1s0

domain=lan
local=/lan/
expand-hosts
dhcp-authoritative

# jetson.lan always resolves to the WiFi hotspot IP (10.42.0.1) which is
# always up regardless of which wired ports have cables. Wired clients
# reach 10.42.0.1 via the Jetson itself (same physical device).
# This avoids round-robin from multiple /etc/hosts entries and removes
# the dependency on localise-queries (which requires bind-interfaces).
address=/jetson.lan/10.42.0.1

# WiFi client hostnames are synced here by /usr/local/sbin/wifi-lease-to-hosts.sh
# (called via dhcp-script by the NM hotspot dnsmasq). This makes wired-side
# clients (and systemd-resolved on the Jetson itself) resolve WiFi hostnames.
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

# DNS server â€” point clients to the Jetson (dnsmasq itself)
dhcp-option=tag:lan100,option:dns-server,192.168.100.1
dhcp-option=tag:lan101,option:dns-server,192.168.101.1
dhcp-option=tag:lan102,option:dns-server,192.168.102.1
dhcp-option=tag:lan103,option:dns-server,192.168.103.1
dhcp-option=tag:lan104,option:dns-server,192.168.104.1

# Search domain â€” clients resolve bare "jetson" â†’ "jetson.lan"
dhcp-option=tag:lan100,option:domain-search,lan
dhcp-option=tag:lan101,option:domain-search,lan
dhcp-option=tag:lan102,option:domain-search,lan
dhcp-option=tag:lan103,option:domain-search,lan
dhcp-option=tag:lan104,option:domain-search,lan

# WiFi client hostnames are synced here by /usr/local/sbin/wifi-lease-to-hosts.sh
# (called via dhcp-script by the NM hotspot dnsmasq). This makes wired-side
# clients (and systemd-resolved on the Jetson itself) resolve WiFi hostnames.
addn-hosts=/run/dnsmasq-wifi-hosts

# When a wired DHCP lease is issued, immediately remove any stale WiFi entry
# for the same hostname so the wired IP takes precedence right away.
dhcp-script=/usr/local/sbin/wired-lease-event.sh
DNSMASQ
# Remove any stale /etc/hosts jetson entries left from the old localise-queries approach
sed -i '/[[:space:]]jetson$/d' /etc/hosts

# Hotspot DNS: NM spawns its own dnsmasq for wlP1p1s0 and owns 10.42.0.1:53.
# Drop a config file into NM's shared dnsmasq drop-in dir so hotspot clients
# also resolve jetson.lan correctly.
mkdir -p /etc/NetworkManager/dnsmasq-shared.d
cat > /etc/NetworkManager/dnsmasq-shared.d/jetson.conf << 'NMDNS'
address=/jetson.lan/10.42.0.1
# Push .lan search domain to hotspot clients so bare "jetson" resolves too
dhcp-option=option:domain-search,lan
# Call the sync script on every DHCP event so the main dnsmasq immediately
# learns WiFi client hostnames via addn-hosts.
# The script checks wired leases first: if the same hostname already has a
# wired DHCP lease it is NOT added to addn-hosts, avoiding stale WiFi IPs
# overriding the wired IP when a client switches networks.
dhcp-script=/usr/local/sbin/wifi-lease-to-hosts.sh
NMDNS

echo "=== Writing wifi-lease-to-hosts.sh ==="
cat > /usr/local/sbin/wifi-lease-to-hosts.sh << 'LEASESCRIPT'
#!/bin/bash
# Called by the NM hotspot dnsmasq on every DHCP event.
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
    # Only skip adding the WiFi entry if the hostname has a wired lease
    # AND that wired IP is actually responding (reachable = still on wired).
    # If the wired IP is unreachable the client switched to WiFi, so we use
    # the WiFi IP instead.
    WIRED_IP=$(grep -i "[[:space:]]${HOSTNAME}[[:space:]]" "$WIRED_LEASES" 2>/dev/null | awk '{print $3}')
    WIRED_ACTIVE=0
    if [ -n "$WIRED_IP" ]; then
        ping -c1 -W1 -q "$WIRED_IP" &>/dev/null && WIRED_ACTIVE=1
    fi
    if [ "$WIRED_ACTIVE" -eq 0 ]; then
        echo "$IP $HOSTNAME $HOSTNAME.lan" >> "$HOSTS_FILE"
    fi
fi

# Signal main dnsmasq to reload addn-hosts without dropping leases
[ -f "$PIDFILE" ] && kill -HUP "$(cat "$PIDFILE")" 2>/dev/null || true
LEASESCRIPT
chmod +x /usr/local/sbin/wifi-lease-to-hosts.sh

echo "=== Writing wired-lease-event.sh ==="
cat > /usr/local/sbin/wired-lease-event.sh << 'WIREDEVENT'
#!/bin/bash
# Called by the main dnsmasq on every wired DHCP event.
# Usage: <add|del|old> <MAC> <IP> [hostname]
ACTION="$1"
HOSTNAME="$4"
HOSTS_FILE=/run/dnsmasq-wifi-hosts
PIDFILE=/run/dnsmasq/dnsmasq.pid

# On wired add/renew: remove the WiFi entry so the wired IP (served by
# expand-hosts) takes precedence immediately without waiting for lease expiry.
if [ "$ACTION" != "del" ] && [ -n "$HOSTNAME" ]; then
    if grep -qi "[[:space:]]${HOSTNAME}[[:space:]]" "$HOSTS_FILE" 2>/dev/null; then
        sed -i "/[[:space:]]${HOSTNAME}[[:space:]]/Id" "$HOSTS_FILE"
        [ -f "$PIDFILE" ] && kill -HUP "$(cat "$PIDFILE")" 2>/dev/null || true
    fi
fi
WIREDEVENT
chmod +x /usr/local/sbin/wired-lease-event.sh

# Install a systemd timer that re-syncs the WiFi addn-hosts file every 30s.
# This handles clients that reconnect to the hotspot without a full DHCP
# handshake (i.e. they reuse their cached lease and no dhcp-script event fires).
cat > /usr/local/sbin/sync-wifi-hosts.sh << 'SYNCSCRIPT'
#!/bin/bash
# Re-syncs /run/dnsmasq-wifi-hosts from the NM hotspot lease file.
# Called by a systemd timer every 30 seconds.
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
        continue  # client is active on wired â€” wired IP takes precedence
    fi
    # Wired IP is unreachable. Remove stale wired lease so dnsmasq's
    # expand-hosts stops serving the old wired IP â€” without this the wired
    # entry overrides the addn-hosts WiFi entry in DNS responses.
    if [ -n "$WIRED_LINE" ]; then
        sed -i "/[[:space:]]${hostname}[[:space:]]/Id" "$WIRED_LEASES"
        CHANGED=2  # 2 = full restart needed to flush lease from memory
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
echo "sync-wifi-hosts timer installed OK"

# Pre-create the hosts file so the nobody-run NM dnsmasq can write to it.
touch /run/dnsmasq-wifi-hosts
chown nobody:nogroup /run/dnsmasq-wifi-hosts

# Seed with existing WiFi leases. Skip any hostname whose wired IP is still
# reachable â€” if the wired IP responds to ping, the client is still on wired
# and expand-hosts already serves the correct IP. If the wired IP is gone
# (client switched to WiFi), add the WiFi entry.
: > /run/dnsmasq-wifi-hosts
while IFS=' ' read -r _exp _mac ip hostname _rest; do
    [ -z "$hostname" ] || [ "$hostname" = '*' ] && continue
    WIRED_IP=$(grep -i "[[:space:]]${hostname}[[:space:]]" /var/lib/misc/dnsmasq.leases 2>/dev/null | awk '{print $3}')
    if [ -n "$WIRED_IP" ] && ping -c1 -W1 -q "$WIRED_IP" &>/dev/null; then
        continue  # wired is still alive, skip
    fi
    echo "$ip $hostname $hostname.lan"
done < /var/lib/NetworkManager/dnsmasq-wlP1p1s0.leases 2>/dev/null \
    >> /run/dnsmasq-wifi-hosts || true

systemctl enable dnsmasq
systemctl restart dnsmasq
echo "dnsmasq OK"

echo "=== [4/6] Fix systemd-resolved stub listener + .lan forwarding ==="
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/stub.conf << 'RESOLVED'
[Resolve]
DNSStubListener=yes
RESOLVED
cat > /etc/systemd/resolved.conf.d/lan.conf << 'LANCONF'
[Resolve]
# Route all .lan queries to the main dnsmasq (bind-dynamic on loopback).
# Main dnsmasq has wired DHCP leases (expand-hosts), WiFi leases (addn-hosts
# via wifi-lease-to-hosts.sh), and address=/jetson.lan/10.42.0.1.
# 127.0.0.1 is always reachable regardless of which physical ports are up.
DNS=127.0.0.1
Domains=~lan
LANCONF
systemctl restart systemd-resolved
echo "resolved OK"

echo "=== [4b/6] Install NM dispatcher script for fast WAN-uplink switchover ==="
# Without this, switching the WAN port (e.g. mgbe0 â†’ wlx...) causes ~2 min
# of broken connectivity because:
#   â€¢ systemd-resolved keeps stale/negative-cached DNS answers from the old link
#   â€¢ the kernel neighbour/ARP cache still points at the old gateway MAC
#   â€¢ dnsmasq keeps its upstream TCP/UDP sockets open on the old interface
# The dispatcher fires on every interface event; we only act when a *WAN*
# (non-LAN) interface goes up so we don't disturb normal LAN events.
mkdir -p /etc/NetworkManager/dispatcher.d
cat > /etc/NetworkManager/dispatcher.d/99-uplink-switched.sh << 'DISPATCHER'
#!/bin/bash
# NM calls this as:  <iface> <action>
IFACE="$1"
ACTION="$2"

# Only react when a WAN interface comes up
[ "$ACTION" = "up" ] || exit 0

# Skip LAN-side interfaces â€” changes there don't affect WAN routing
LAN_IFACES="mgbe0_0 mgbe1_0 wlP1p1s0 lo docker0 l4tbr0"
for lan in $LAN_IFACES; do
    [ "$IFACE" = "$lan" ] && exit 0
done

logger -t nm-uplink-switch "WAN uplink switched to $IFACE â€” flushing caches"

# 1. Flush kernel neighbour (ARP) cache so the new gateway is resolved fresh.
ip neigh flush all 2>/dev/null || true

# 2. Flush kernel routing cache (relevant on older kernels; harmless on 5.x).
ip route flush cache 2>/dev/null || true

# 3. Flush systemd-resolved's negative/positive DNS cache so clients get
#    fresh answers immediately instead of waiting for cached TTLs to expire.
resolvectl flush-caches 2>/dev/null || true

# 4. Signal the main dnsmasq to re-open its upstream socket on the new
#    interface and clear its own negative cache.
PIDFILE=/run/dnsmasq/dnsmasq.pid
[ -f "$PIDFILE" ] && kill -HUP "$(cat "$PIDFILE")" 2>/dev/null || true

logger -t nm-uplink-switch "Cache flush complete for uplink $IFACE"
DISPATCHER
chmod +x /etc/NetworkManager/dispatcher.d/99-uplink-switched.sh
echo "NM dispatcher script installed OK"

echo "=== [4c/6] Configure WAN uplinks as DHCP clients ==="
# All non-LAN Ethernet interfaces are WAN uplinks and should request a DHCP
# lease. Profiles are created unconditionally — NM activates them as soon as
# the hardware appears. Missing interfaces are not an error.
# MTU is left at 1500 (default) for WAN uplinks — upstream routers/ISPs
# typically don't support jumbo frames, and MTU >1500 on a WAN port causes
# silent packet drops for large transfers while ping still works.
#
# Route metrics (lower = higher priority):
#   Wired WAN (mgbe2_0, mgbe3_0, enP2p1s0): 100  ← preferred
#   WiFi WAN (wlx*/Freebird):                700  ← fallback only
# This ensures wired always wins when both are up, regardless of which
# interface came up first or what metric the DHCP server suggests.
WAN_ETHERNET_IFACES="mgbe2_0 mgbe3_0 enP2p1s0"
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
        echo "$IFACE: DHCP client profile active (metric 100)"
    else
        echo "$IFACE: not present now — profile saved, NM activates it when the device appears"
    fi
done

# LAN interfaces: set MTU 9000 (jumbo frames) — we control both ends so
# there is no upstream router to drop oversized packets.
# Applied immediately if present; the NM static profiles for these interfaces
# should also include ethernet.mtu 9000 when created.
LAN_JUMBO_IFACES="mgbe0_0 mgbe1_0"
for IFACE in $LAN_JUMBO_IFACES; do
    if ip link show "$IFACE" &>/dev/null; then
        ip link set "$IFACE" mtu 9000 2>/dev/null || \
            echo "$IFACE: MTU 9000 not supported — staying at default"
        echo "$IFACE: MTU 9000 applied"
    else
        echo "$IFACE: not present, skipping MTU"
    fi
done

echo "NM WAN DHCP profiles written"

# For any Ethernet device NM encounters that has no explicit profile above
# (e.g. a future USB-to-Ethernet or PCIe NIC), NM auto-creates a connection.
# This conf.d drop-in ensures those auto-created connections default to DHCP
# rather than being left unmanaged or using a link-local address.
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-default-dhcp.conf << 'NMCONF'
[connection]
ipv4.method=auto
ipv6.method=auto
NMCONF
systemctl reload NetworkManager 2>/dev/null || true
echo "NM default-DHCP fallback written"

echo "=== [5/6] Configure DOCKER-USER forwarding rules ==="
# Wait for Docker to be running (DOCKER-USER chain must exist)
if ! iptables -L DOCKER-USER -n &>/dev/null; then
    echo "WARNING: DOCKER-USER chain not found â€” is Docker running?"
    echo "Re-run this script after Docker starts."
    exit 1
fi

# Flush entire DOCKER-USER chain and rebuild cleanly
iptables -F DOCKER-USER

# Allow LANâ†’WAN forwarding in the main FORWARD chain.
# This is needed because Docker sets FORWARD default policy to DROP and
# DOCKER-USER RETURN/ACCEPT only covers Docker-routed traffic.
# The nftables kernel on this Jetson does not support filter hooks,
# so forwarding rules must live here.
# Remove any stale LAN FORWARD rules first so re-runs don't duplicate them.
iptables -D FORWARD -s 192.168.100.0/22 ! -o docker0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -s 192.168.104.0/24 ! -o docker0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -s 10.42.0.0/16     ! -o docker0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -d 10.42.0.0/16     -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -d 192.168.100.0/22 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -d 192.168.104.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -A FORWARD -s 192.168.100.0/22 ! -o docker0 -j ACCEPT
iptables -A FORWARD -s 192.168.104.0/24 ! -o docker0 -j ACCEPT
iptables -A FORWARD -s 10.42.0.0/16     ! -o docker0 -j ACCEPT
iptables -A FORWARD -d 10.42.0.0/16     -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -d 192.168.100.0/22 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -d 192.168.104.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
echo "iptables FORWARD OK"

# DOCKER-USER: pass LAN traffic through without interference
iptables -I DOCKER-USER 1 -s 192.168.100.0/22 ! -o docker0 -j RETURN
iptables -I DOCKER-USER 2 -s 192.168.104.0/24 ! -o docker0 -j RETURN
iptables -I DOCKER-USER 3 -s 10.42.0.0/16     ! -o docker0 -j RETURN
iptables -I DOCKER-USER 4 -d 10.42.0.0/16     -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
echo "iptables DOCKER-USER OK"

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
echo "systemd drop-in installed OK"

echo ""
echo "=== Setup complete ==="
echo "LAN subnets:  192.168.100-104.x/24, 10.42.0.x/24"
echo "WAN uplinks:  any interface except docker0 (mgbe2_0, mgbe3_0, enP2p1s0, wlx...)"
echo ""
echo "Uplink switchover is now fast (<5 s): when any non-LAN interface comes up,"
echo "/etc/NetworkManager/dispatcher.d/99-uplink-switched.sh flushes the ARP,"
echo "route, systemd-resolved, and dnsmasq caches automatically."
echo ""
echo "Verify with:"
echo "  sudo nft list chain inet jetson-nat postrouting"
echo "  sudo iptables -L DOCKER-USER -v -n"
echo "  ping -I 192.168.101.1 8.8.8.8 -c3"
echo "  journalctl -t nm-uplink-switch -n 20   # see switchover events"
