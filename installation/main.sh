#!/usr/bin/bash
# Script for configuring arch linux

# =========== Config ===========
USER=""
PARALLEL_DOWNLOADS=20

# =========== Checks ===========

if [ -z "$USER" ]; then
    echo "No USER"
    exit 1
fi

# ============ Main ============

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
sleep 5s

# Log
mkdir /etc/systemd/journald.conf.d
cat <<-EOF > /etc/systemd/journald.conf.d/00-config.conf
	Compress=yes
	SystemMaxUse=50MB
EOF

# OOM
systemctl enable systemd-oomd

# Pacman
cat <<-EOF >> /etc/pacman.conf
	[options]
	Color
	ParallelDownloads = $PARALLEL_DOWNLOADS

	[multilib]
	Include = /etc/pacman.d/mirrorlist
EOF

# Packages
pacman -Syu --noconfirm
pacman -S --noconfirm - < PACKAGES

# Reflector
echo "--save /etc/pacman.d/mirrorlist --protocol https -l 10 -f 5 --sort rate" > /etc/xdg/reflector/reflector.conf
systemctl start reflector.service
systemctl enable reflector.timer

# Allow wheel group to sudo
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

# Users
echo "Change root password"
passwd root
useradd -m -G wheel -s /usr/bin/zsh $USER
echo "Set user password"
passwd $USER

# .zshrc
sudo -u $USER bash <<- EOF
	cd /home/$USER
	git clone https://github.com/ToxyFlog1627/zshDots .zsh
	ln -s .zsh/.zshenv .zshenv
EOF

# .vimrc
install -o $USER -g $USER -m 755 $INSTALLATION_FOLDER/.vimrc /home/$USER

# git config
cat <<- EOF > /home/$USER/.gitconfig
	[init]
	defaultBranch = main
	[core]
	editor = vim
EOF
chown $USER:$USER /home/$USER/.gitconfig

# Use same vim and zsh config for root
cp -r /home/$USER/.zsh    /root/.zsh
cp -r /home/$USER/.zshenv /root/.zshenv
cp -r /home/$USER/.vimrc  /root/.vimrc
chsh -s /usr/bin/zsh

# yay
cd $INSTALLATION_FOLDER
git clone https://aur.archlinux.org/yay-bin.git yay
chown -R $USER:$USER yay
sudo -u $USER bash <<- EOF
	cd yay
	makepkg -si --noconfirm
	yay -Y --gendb
	yay -Y --devel --save
EOF
yay -S --noconfirm - < AUR_PACKAGES

# Suckless
sudo -u $USER bash <<- EOF
	mkdir ~/srcs
	cd ~/srcs
	git clone https://github.com/ToxyFlog1627/Suckless
	cd Suckless

	cd dwm
	sudo make install
	cd ..

	cd dmenu
	sudo make install
	cd ..

	cd st
	sudo make install
EOF

# ssdm
sudo -u $USER bash <<- EOF
	cd ~/srcs
	git clone https://github.com/ToxyFlog1627/ssdm
	cd ssdm
	sudo make install
EOF
systemctl enable ssdm

# .xinitrc
cat <<- EOF > /home/$USER/.xinitrc
	#!/bin/bash
	xrdb -merge $HOME/.Xresources
	exec dwm
EOF
chown $USER:$USER /home/$USER/.xinitrc
chmod +x /home/$USER/.xinitrc

# .Xresources
install -o $USER -g $USER -m 755 $INSTALLATION_FOLDER/.Xresources /home/$USER

# Disabling getty on TTY1 (to keep boot output)
systemctl mask getty@tty1.service

# Create weekly timer that clears pacman and yay caches
cat <<- EOF > /etc/systemd/system/clean-system.timer
	[Unit]
	Description=Run clean-system every Sunday
	Requires=clean-system.service

	[Timer]
	OnCalendar=Sun
	Persistent=true

	[Install]
	WantedBy=timers.target
EOF
cat <<- EOF > /etc/systemd/system/clean-system.service
	[Unit]
	Description=Remove orphans and clean cache 
	Requires=clean-system.timer

	[Service]
	Type=oneshot
	ExecStart=/usr/local/bin/clean-system

	[Install]
	WantedBy=multi-user.target
EOF
cat <<- EOF > /usr/local/bin/clean-system
	#!/usr/bin/bash
	paccache -qrk1
	yay -Sc --noconfirm
	pacman -Qtdq | ifne pacman -Rns -
EOF
chmod +x /usr/local/bin/clean-system
systemctl enable clean-system.timer

# Setup noise cancellation in Pipewire
# https://github.com/werman/noise-suppression-for-voice#pipewire
sudo -u $USER bash <<- EOF
	mkdir -p /home/$USER/.config/pipewire/pipewire.conf.d
	touch /home/$USER/.config/pipewire/pipewire.conf.d/99-noise-cancelling.conf
EOF
cat <<- EOF > /home/$USER/.config/pipewire/pipewire.conf.d/99-noise-cancelling.conf
	context.modules = [
		{   name = libpipewire-module-filter-chain
			args = {
				node.description =  "Noise Cancelling source"
				media.name =  "Noise Cancelling source"
				filter.graph = {
					nodes = [
						{
							type = ladspa
							name = rnnoise
							plugin = librnnoise_ladspa
							label = noise_suppressor_mono
							control = {
								"VAD Threshold (%)" = 75.0
								"VAD Grace Period (ms)" = 250
								"Retroactive VAD Grace (ms)" = 0
							}
						}
					]
				}
				capture.props = {
					node.name =  "capture.rnnoise_source"
					node.passive = true
					audio.rate = 48000
				}
				playback.props = {
					node.name =  "rnnoise_source"
					media.class = Audio/Source
					audio.rate = 48000
				}
			}
		}
	]
EOF

rm -r $INSTALLATION_FOLDER
reboot