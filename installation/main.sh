#!/usr/bin/bash
# Script for configuring arch linux

# =========== Config ===========
USER=""
PARALLEL_DOWNLOADS=10

# ============ Utils ===========

uncomment() { echo "s/^# ?\($1\)\$/\1/"; }

# ============ Main ============

# Exit on error
set -e 
set -o pipefail

# Time
systemctl enable systemd-timesyncd
timedatectl set-ntp true

# Internet connection
systemctl disable systemd-networkd
systemctl enable systemd-resolved
systemctl enable NetworkManager

# Configure resolver # TODO
# cat <<-EOF >> /etc/systemd/resolved.conf
# 	[Resolve]
# 	DNS=//TODO:quad9
# 	FallbackDNS=//TODO:cloudflare
# 	DNSSEC=allow-downgrade
# 	DNSOverTLS=opportunistic
# 	Cache=yes
# 	ReadEtcHosts=yes
# EOF

# update
pacman -Syu --noconfirm

# install packages
pacman -S --noconfirm - < PACKAGES

# set root password
echo "set root password"
passwd

# create user
useradd -m -G wheel -s /usr/bin/zsh $USER
# set user password
echo "set user password"
paswd $USER

# allow wheel group to sudo
SUDOERS="%wheel ALL=(ALL:ALL) NOPASSWD: ALL"
sed -i $(uncomment $SUDOERS) /etc/sudoers

# reflector
echo "--save /etc/pacman.d/mirrorlist --protocol https -l 10 -f 5 --sort rate" > /etc/xdg/reflector/reflector.conf # TODO: check
systemctl enable reflector.timer

# pacman
sed -i $(uncomment "Color") \
	"s/^# ?\(ParallelDownloads = \)\d+\$/\1/$PARALLEL_DOWNLOADS" \
	$(uncomment "[multilib]") \
	$(uncomment "Include = /etc/pacman.d/mirrorlist") \
	/etc/pacman.conf # TODO: check

# sync
pacman -Syu --noconfirm

# yay
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si
yay -Y --gendb
yay -Syu --devel
# TODO: config

# TODO: sort PACKAGES? update with real ones
