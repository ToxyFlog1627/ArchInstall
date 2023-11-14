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

# Share vim and zsh with root
ln -s /home/$USER/.zsh    /root/.zsh
ln -s /home/$USER/.zshenv /root/.zshenv
ln -s /home/$USER/.vimrc  /root/.vimrc

# TODO: use `chsh -s /usr/bin/zsh` on root user?

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
	cd /home/$USER
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
	cd ..
EOF

# .xinitrc
echo "exec dwm" > /home/$USER/.xinitrc

# .Xresources
install -o $USER -g $USER -m 755 $INSTALLATION_FOLDER/.Xresources /home/$USER

# Disabling getty on TTY1 (to keep boot output)
systemctl mask getty@tty1.service

# Create weekly timer that clears pacman and yay cache
cat <<- EOF > /etc/systemd/system/clear-system.timer
	[Unit]
	Description=Run clear-system every Sunday
	Requires=clear-system.service

	[Timer]
	OnCalendar=Sun
	Persistent=true

	[Install]
	WantedBy=timers.target
EOF
cat <<- EOF > /etc/systemd/system/clear-system.service
	[Unit]
	Description=Remove orphans and clear cache 
	Requires=clear-system.timer

	[Service]
	Type=oneshot
	ExecStart=/usr/local/bin/clear-system

	[Install]
	WantedBy=multi-user.target
EOF
cat <<- EOF > /usr/local/bin/clear-system
	#!/usr/bin/bash
	paccache -qrk1
	yay -Sc --noconfirm
	pacman -Qtdq | ifne pacman -Rns -
EOF
chmod +x /usr/local/bin/clear-system
# TODO: check timer(systemctl list-timers --all)
# TODO: run service and check output

# Setup noise cancellation in Pipewire
# https://github.com/werman/noise-suppression-for-voice#pipewire
sudo -u $USER bash <<- EOF
	mkdir -p ~/.config/pipewire/pipewire.conf.d
	cat <<- EOF > ~/.config/pipewire/pipewire.conf.d/99-noise-cancelling.conf
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
EOF

# TODO: delete this folder