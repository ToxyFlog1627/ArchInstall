#!/usr/bin/bash
# Script for configuring arch linux

# =========== Config ===========
USER=""
PARALLEL_DOWNLOADS=10

# =========== Checks ===========

if [ -z "$USER" ]; then
    echo "No USER"
    exit 1
fi

# ============ Main ============
# TODO: check every step

INSTALLATION_FOLDER=$(dirname $(realpath "$0"))

# Exit on error
set -e 
set -o pipefail

# Time
systemctl enable --now systemd-timesyncd
timedatectl set-ntp true

# Internet connection
systemctl disable systemd-networkd
systemctl enable --now NetworkManager

# DNS
cat <<-EOF > /etc/systemd/resolved.conf
	[Resolve]
	DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net
	FallbackDNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 2606:4700:4700::1111#cloudflare-dns.com 2606:4700:4700::1001#cloudflare-dns.com 8.8.8.8#dns.google 8.8.4.4#dns.google 2001:4860:4860::8888#dns.google 2001:4860:4860::8844#dns.google
	DNSSEC=allow-downgrade
	DNSOverTLS=opportunistic
	Cache=yes
	ReadEtcHosts=yes
EOF
systemctl enable --now systemd-resolved

# Log
mkdir /etc/systemd/journald.conf.d
echo <<-EOF > /etc/systemd/journald.conf.d/00-config.conf
	Compress=yes
	SystemMaxUse=50MB
EOF

# OOM
systemctl enable systemd-oomd

# Pacman
echo <<-EOF >> /etc/pacman.conf
	[options]
	Color
	ParallelDownloads = $PARALLEL_DOWNLOADS

	[multilib]
	Include = /etc/pacman.d/mirrorlist
EOF

# Packages
pacman -Syu --noconfirm
pacman -S --noconfirm - < PACKAGES

# Users
echo "Change root password"
passwd root
useradd -m -G wheel -s /usr/bin/zsh $USER
echo "Set user password"
paswd $USER

# Allow wheel group to sudo
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

# zsh
cd /home/$USER
git clone https://github.com/ToxyFlog1627/zshDots .zsh
ln -s .zsh/.zshenv .zshenv
 
# vim
mv $INSTALLATION_FOLDER/.vimrc /home/$USER

# Share vim and zsh with root
ln -s /home/$USER/.zsh    /home/root/.zsh
ln -s /home/$USER/.zshenv /home/root/.zshenv
ln -s /home/$USER/.vimrc  /home/root/.vimrc
# TODO: make root use same vim and zsh config, but with PS_1=root

# Reflector
echo "--save /etc/pacman.d/mirrorlist --protocol https -l 10 -f 5 --sort rate" > /etc/xdg/reflector/reflector.conf
systemctl start reflector.service
systemctl enable reflector.timer

# yay
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si
yay -Y --gendb
yay -Syu --devel

# TODO: config

# TODO: sort PACKAGES? update with real ones
# TODO: reorder + tidy up