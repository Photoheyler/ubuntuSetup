# Wichtig: Jetson muss kernel updates bei apt-get upgrade ignorieren!

sudo apt-mark hold 'nvidia-l4t-\*'

# https://www.forecr.io/blogs/bsp-development/how-to-apply-distro-upgrade-apt-upgrade-on-jetson-modules

1. release.sh ausführen, um den dist-Ordner zu erzeugen
2. dist auf jetson übertragen
3. entpacken
4. install.sh ausführen
5. sudo tailscale up