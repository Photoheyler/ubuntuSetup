
sudo hostnamectl set-hostname jetson
sudo systemctl restart systemd-hostnamed
sudo apt update
sudo apt install -y avahi-daemon
sudo systemctl enable --now avahi-daemon
