#!/usr/bin/bash
# Script for installing base arch linux

# Disk has to be partitioned prior to execution
# 1. fdisk /dev/sdX:
#    Press `g` to use GPT partition table.
#    Partitions:
#     1. 1GB - UEFI
#     2. rest - x86_64 root
# 2. Format partitions:
#    mkfs.fat -F 32 /dev/sdX1
#    mkfs.ext4 /dev/sdX2

# Sysrq:
# SystemRequest is a mechanism for performing low-level commands.
# It is useful for dealing with frozen/unresponsive system.
# SysRq is either PrintScr or Fn
# To invoke commands use Alt+SysRq+CMD_KEY
#   f - oom_killer
#   b - reboot
#   e - terminate all processes
#   o - shutdown
#   s - sync files

# =========== Config ===========
CPU="intel" # either "intel" or "amd"
BOOT_PARTITION="/dev/sda1"
ROOT_PARTITION="/dev/sda2"
TIME_ZONE="" # file inside /usr/share/timezone
KERNEL_OPTIONS="sysrq_always_enabled=208" # enable system requests
HOSTNAME="Arch"

# Constants
PACKAGES="linux linux-firmware base base-devel vim networkmanager $CPU-ucode git"
ROOT_MOUNT="/mnt"
BOOT_MOUNT="/mnt/boot"

# =========== Checks ===========

# Exit on error
set -e 
set -o pipefail

# Check partitions
if [ ! -e "$BOOT_PARTITION" ] || [ ! -e "$ROOT_PARTITION" ]; then
    echo "Boot or root partition doesn't exist"
    exit 1
fi

# Check file systems
get_fs_type() { echo $(lsblk --output=FSTYPE --noheadings $1); }
if [ $(get_fs_type $BOOT_PARTITION) != "vfat" ] || [ $(get_fs_type $ROOT_PARTITION) != "ext4" ]; then
    echo "Partitions are formatted incorrectly"
    echo "Expected root=ext4 and boot=fat"
    exit 1
fi

# Mount partitions, if necessary
get_mount_point() { echo $(cat /proc/mounts | grep -m 1 $1 | cut -d " " -f 2); }
current_boot_mount=$(get_mount_point $BOOT_PARTITION)
current_root_mount=$(get_mount_point $ROOT_PARTITION)
if [ -z "$current_boot_mount" ] || [ $current_boot_mount != "/mnt/boot" ] || [ -z "$current_root_mount" ] || [ $current_root_mount != "/mnt" ]; then
    echo "Mounting partitions"
    mount $ROOT_PARTITION "/mnt"
    mkdir -p "/mnt/boot"
    mount $BOOT_PARTITION "/mnt/boot"
fi

# Check x86_64
if [ $(uname -m) != "x86_64" ]; then
    echo "Incorrect CPU architecture"
    exit 1
fi

# Check config
if [ $CPU != "intel" ] && [ $CPU != "amd" ]; then
    echo "Invalid value of CPU"
    exit 1
fi
if [ -z "$TIME_ZONE" ]; then
    echo "No TIME_ZONE"
    exit 1
fi
if [ -z "$HOSTNAME" ]; then
    echo "No HOSTNAME"
    exit 1
fi
# ============ Main ============

# Install base system and packages
pacstrap -K /mnt $PACKAGES

# Move other scripts
chmod +x installation/main.sh
mv installation /mnt/var/tmp

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# IMPORTANT: ONLY TABS CHARACTERS ARE ALLOWED FOR INDENTATION
arch-chroot /mnt <<-CHROOT
	ln -sf /usr/share/zoneinfo/$TIME_ZONE /etc/localtime # Setting timezone
	echo $HOSTNAME > /etc/hostname # Setting hostname

	# Generating locale
	echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
	locale-gen
	echo "LANG=en_US.UTF-8" > /etc/locale.conf

	# Installing systemd-boot
	bootctl install
	cat <<-EOF > /boot/loader/loader.conf 
		default arch.conf
		timeout 3
		auto-firmware false
		editor no
	EOF

	# Getting root uuid
	export ROOT_UUID=$(blkid -o value -s UUID $ROOT_PARTITION)

	# Adding boot entries
	cat <<-EOF > /boot/loader/entries/arch.conf 
		title   Arch
		linux   /vmlinuz-linux
		initrd  /$CPU-ucode.img
		initrd  /initramfs-linux.img
		options root=UUID=\$ROOT_UUID rw $KERNEL_OPTIONS
	EOF
	cat <<-EOF > /boot/loader/entries/fallback.conf 
		title   Arch (fallback)
		linux   /vmlinuz-linux
		initrd  /$CPU-ucode.img
		initrd  /initramfs-linux-fallback.img
		options root=UUID=\$ROOT_UUID rw
	EOF

	echo "root:root" | chpasswd # Setting default root password
CHROOT

reboot