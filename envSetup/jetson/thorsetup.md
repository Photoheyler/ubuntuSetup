sudo loginctl enable-linger stefanheinrich


## general
1. Mgbe0_0 Adapter gets a DHCP Server
2. Mgbe1_0 Adapter gets a DHCP Client

both Jumbo frames enabled.


# set Network setup
# mgbe0
sudo nmcli connection add \
type ethernet \
ifname mgbe0_0 \
con-name mgbe0-dhcp \
ipv4.method manual \
ipv4.addresses 192.168.100.1/24 \
ipv4.never-default yes \
ipv6.method ignore \
802-3-ethernet.mtu 9000


# mgbe1
sudo nmcli connection add \
type ethernet \
ifname mgbe1_0 \
con-name mgbe1-dhcp \
ipv4.method manual \
ipv4.addresses 192.168.101.1/24 \
ipv4.never-default yes \
ipv6.method ignore \
802-3-ethernet.mtu 9000



# mgbe2

sudo nmcli connection add \
type ethernet \
ifname mgbe2_0 \
con-name uplink-mgbe2_0 \
autoconnect yes \
ipv4.method auto \
ipv6.method auto \
802-3-ethernet.mtu 9000



# mgbe3
sudo nmcli connection add \
type ethernet \
ifname mgbe3_0 \
con-name uplink-mgbe3_0 \
autoconnect yes \
ipv4.method auto \
ipv6.method auto \
802-3-ethernet.mtu 9000

# loopback

sudo nmcli connection add \
  type loopback \
  ifname lo \
  con-name loopback-mgmt \
  ipv4.method manual \
  ipv4.addresses 10.255.255.1/32 \
  ipv6.method ignore


# tools ........
nmcli connection show
sudo nmcli connection delete uplink-mgbe1

sudo nmcli connection modify uplink-mgbe3_0 \
autoconnect yes \
ipv4.method auto \
ipv6.method auto \
802-3-ethernet.mtu 9000

# .............
# set loopback ip
sudo ip addr add 10.255.255.1/32 dev lo
ip -br addr show lo

# set up dhcp

sudo apt install dnsmasq
sudo nano /etc/dnsmasq.conf



# disable ipv6 completly
sudo nano /etc/sysctl.conf

net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1

enable it
sudo sysctl -p

# temporary
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1