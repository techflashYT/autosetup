#!/bin/bash -e
ourself="$PWD/$0"

dots() {
	echo -ne "$1"
	sleep 0.25
	echo -n "$2"
	sleep 0.25
	echo -n "$2"
	sleep 0.25
	echo -n "$2"
	sleep 0.25
}
echo "Techflash autosetup script v0.0.3"
echo -e "\e[1;33m======= WARNING!!! =======\e[0m"
echo "This script will set up your PC exactly like I set up mine."
echo "If you're not sure about this, please back out now.  I'll give you 5 seconds."
dots "\e[32m5" "."
dots "4" "."
dots "\e[1;33m3" "."
dots "\e[0;33m2" "."
dots "\e[31m1" "!"


hostname="$(cat /etc/hostname)"
awk '/iwctl/ && /nmcli/ && /utility/ && /Wi-Fi, authenticate to the wireless network using the/' /etc/motd
awkRet=$?

isArchISO=false
if [ "$hostname" = "archiso" ] && [ "$awkRet" = "0" ]; then
	isArchISO=true
fi

toBytes() {
	echo $1 | sed 's/.*/\L\0/;s/t/Xg/;s/g/Xm/;s/m/Xk/;s/k/X/;s/b//;s/X/ *1024/g' | bc
}

###########################################
#                                         #
#   I N - I N S T A L L E R   S E T U P   #
#                                         #
###########################################



partEsp() {
	if [ "$uefi" = "true" ]; then
		until [[ "$esp" == "/dev/"* ]] && [ -b "$esp" ]; do
			echo -n "EFI System Partiton: "; read -r esp
		done

		until [ "$format_esp" = "y" ] || [ "$format_esp" = "n" ]; do
			echo -n "Format? "; read -r format_esp
		done
	fi
}
partRoot() {
	until [[ "$rootfs" == "/dev/"* ]] && [ -b "$rootfs" ]; do
		echo -n "Rootfs: "; read -r rootfs
	done
	until [ "$format_rootfs" = "y" ] || [ "$format_rootfs" = "n" ]; do
		echo -n "Format? "; read -r format_rootfs
	done
}
partSwap() {
	until { [[ "$swap" == "/dev/"* ]] && [ -b "$swap" ]; }; do
		if [ "$swap" = "none" ]; then
			format_swap="N/A"
			break;
		fi

		if [[ "$swap" =~ ^/[-_/a-zA-Z0-9]*$ ]]; then
			case "$swap" in
				/dev* | /sys* | /proc* | /tmp* | /run* | /var/tmp* | /var/run* | /boot* | /usr* | /bin* | /lib* | /etc* | /home* | /opt* | /root* | /sbin* | /srv*)
					echo "This is a reserved directory.  Please choose something else for your swapfile/partition."
					swap=""
					continue ;;
				*)
					swapfile=true
					format_swap="N/A"

					until [ "$validSize" = true ]; do
						read -rp "Enter file size: " input_size
						# Convert input to lowercase and remove 'b' if present
						input_size=${input_size,,}
						input_size=${input_size//b/}

						# Convert input to bytes
						size_in_bytes=$(toBytes $input_size)

						# Check if size is a multiple of 4MB
						if (( $size_in_bytes % (4*1024*1024) == 0 )); then
							swapfileSize4MB=$(( $size_in_bytes / (4*1024*1024) ))
							validSize=true
						else
							echo "Invalid size"
						fi
					done
					unset validSize input_size size_in_bytes

					break;
					;;
			esac
		fi
		echo -n "Swap: "; read -r swap
	done
	until [ "$swapfile" = "true" ] || [ "$swap" = "none" ] || [ "$format_swap" = "y" ] || [ "$format_swap" = "n" ]; do
		echo -n "Format? "; read -r format_swap
	done
}


partToDisk() {
	if [[ "$1" == "/dev/nvme"* ]] || [[ "$1" == "/dev/mmcblk"* ]]; then
		echo "${1//p[0-9]/}"
	elif [[ "$1" = "/dev/sd"* ]]; then
		echo "${1//[0-9]}"
	fi
}

installerSetup() {
	echo "In the Arch Linux installer.  Autoinstalling."
	if [ -d /sys/firmware/efi ] && [ -f /sys/firmware/efi/runtime ] && [ -f /sys/firmware/efi/systab ]; then
		echo "Detected UEFI machine."
		uefi=true
	fi

	echo "Please input your partitions.  I trust you've already created & sized them to your liking."

	partEsp
	partRoot
	partSwap

	until [ "$goodParts" = "true" ]; do
		echo "To review:"
		if [ "$uefi" = "true" ]; then
			echo "ESP: $esp; Format=$format_esp"
		fi
		echo "RootFS: $rootfs; Format=$format_rootfs"
		echo -n "Swap: $swap; Format=$format_swap"
		if [ "$swapfile" = "true" ]; then
			echo -n "; Size=$(($swapfileSize4MB * 4))MB"
		fi
		echo

		echo "Would you like to change any of these?"
		cat << EOF
1. EFI System Partition
2. RootFS
3. Swap
4. Drop to a shell to examine the situation
5. Looks Good!

EOF
		echo -n "Pick one: "; read -r choice
		case "$choice" in
			"1")
				if [ "$uefi" != "true" ]; then
					echo "Not a UEFI system."
					continue
				fi
				unset esp format_esp
				partEsp
				;;
			"2")
				unset rootfs format_rootfs
				partRoot
				;;
			"3")
				unset swap swapfile swapfileSize4MB format_swap
				partSwap
				;;
			"4")
				echo "Ctrl+D or \"exit\" to get back to the script!"
				zsh
				;;
			"5")
				goodParts=true
		esac
	done
	echo "Alright, installer commencing now!"
	# Unmount any disks that may be mounted
	 
	# swapoff the swap partition
	if [[ "$swap" = "/dev/"* ]]; then
		if swapon | grep "$swap"; then
			swapoff "$swap"
		fi
	fi

	# unmount rootfs
	if mount | grep "$rootfs"; then
		umount "$rootfs"
	fi

	# unmount ESP
	if [ "$uefi" = "true" ] && mount | grep "$esp"; then
		umount "$esp"
	fi


	# All disk are unmounted, format any necessary.
	if [ "$format_swap" = "y" ]; then
		wipefs -a "$swap"
		mkswap "$swap"
	fi

	if [ "$format_rootfs" = "y" ]; then
		wipefs -a "$rootfs"
		mkfs.ext4 "$rootfs"
	fi

	if [ "$format_esp" = "y" ]; then
		wipefs -a "$esp"
		mkfs.vfat -F32 "$esp"
	fi

	# All disks are formatted.  Mount them.

	# Clear out any old data in /mnt
	# shellcheck disable=SC2115
	rm -rf /mnt/*

	mount "$rootfs" /mnt

	if [ "$uefi" = "true" ]; then
		mount "$esp" /mnt/boot --mkdir
	fi

	if [ "$swapfile" = "true" ] && [ "$swap" != "none" ]; then
		# make swapfile
		echo "Making swapfile..."
		dd if=/dev/zero of=/mnt/"$swap" bs=4M count="$swapfileSize4MB" status=progress
		mkswap /mnt/"$swap"
	fi

	if [ "$swap" != "none" ]; then
		if [ "$swapfile" != "true" ]; then
			swapon "$swap"
		else
			swapon "/mnt/$swap"
		fi
	fi

	echo "Setting up base system."
	# enable color & parallel downloads in pacman.conf
	sed 's/#Color/Color/' -i /etc/pacman.conf
	sed 's/#ParallelDownloads = 5/ParallelDownloads = 25/' -i /etc/pacman.conf

	until [ "$useCache" = "y" ] || [ "$useCache" = "n" ]; do
		echo -n "Are you on the LAN and would like to use the package caching server? (y/n)"; read -r useCache
	done
	
	until [ "$useTesting" = "y" ] || [ "$useTesting" = "n" ]; do
		echo -n "Would you like to use the testing repos? (y/n)"; read -r useTesting
	done

	if [ "$useCache" = "y" ]; then
		cat << EOF > /etc/resolv.conf
search shack.techflash.wtf
nameserver 172.16.5.254
EOF
	fi

	# FAST PATH!  If both are no, don't modify the file at all!
	if [ "$useCache" = "y" ] || [ "$useTesting" = "y" ]; then
		# remove all lines after and including the line that maches '[core-testing]'.
		if [ "$useCache" = "y" ]; then
			# If the user wanted testing repos, we modify it after this.
			sed -n '/\[core-testing\]/q;p' -i /etc/pacman.conf
			cat << EOF >> /etc/pacman.conf
#[core-testing]
#Server = http://arch:9129/repo/archlinux/$repo/os/$arch

[core]
Server = http://arch:9129/repo/archlinux/$repo/os/$arch

#[extra-testing]
#Server = http://arch:9129/repo/archlinux/$repo/os/$arch

[extra]
Server = http://arch:9129/repo/archlinux/$repo/os/$arch
EOF
		fi

		if [ "$useTesting" = "y" ]; then
			# It's ugly, but it works
			cp /etc/pacman.conf file.txt
			perl -p -e 's/#\[core-testing\]\n/[core-testing]\n/' file.txt > file2.txt
			sed 's/#Server/Server/' -i file2.txt
			sed 's/#Include/Include/' -i file2.txt
			mv file2.txt file.txt

			perl -p -e 's/#\[extra-testing\]\n/[extra-testing]\n/' file.txt > file2.txt
			sed 's/#Server/Server/' -i file2.txt
			sed 's/#Include/Include/' -i file2.txt
			# Move it into the original
			rm file.txt
			mv file2.txt /etc/pacman.conf
		fi


		if [ "$useCache" = "y" ]; then
			# add the original footer back, we deleted it before.
			cat << EOF >> /etc/pacman.conf

# If you want to run 32 bit applications on your x86_64 system,
# enable the multilib repositories as required here.

#[multilib-testing]
#Include = /etc/pacman.d/mirrorlist

#[multilib]
#Include = /etc/pacman.d/mirrorlist

# An example of a custom package repository.  See the pacman manpage for
# tips on creating your own repositories.
#[custom]
#SigLevel = Optional TrustAll
#Server = file:///home/custompkgs
EOF
		fi
	fi

	echo "pacman.conf set up.  running \`pacstrap'."

	# install core packages
	pacstrap -K /mnt base linux linux-firmware

	# copy our pacman config over
	cp /etc/pacman.conf /mnt/etc/pacman.conf

	# make an fstab
	genfstab /mnt >> /mnt/etc/fstab


	# set the timezone
	ln -sf /usr/share/zoneinfo/Region/City /mnt/etc/localtime
	
	# set the clock
	arch-chroot /mnt "hwclock --systohc"

	# set up locale.gen
	sed 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' -i /mnt/etc/locale.gen
	sed 's/#en_US ISO-8859-1/en_US ISO-8859-1/' -i /mnt/etc/locale.gen

	# generate the locales
	arch-chroot /mnt locale-gen

	# set up the locale config
	echo 'LANG=en_US.UTF-8' > /mnt/etc/locale.conf


	# set the system hostname
	echo -n "Please enter the system hostname: "; read -r hostname
	echo "$hostname" > /mnt/etc/hostname

	# disable fallback initramfs
	sed "s/PRESETS=\('default' 'fallback'\)'/PRESETS='default'/" -i /mnt/etc/mkinitcpio.d/linux.preset

	# remove the fallback-related lines
	head -n -5 /mnt/etc/mkinitcpio.d/linux.preset > tmp
	mv tmp /mnt/etc/mkinitcpio.d/linux.preset

	# remove old initramfs's
	rm /mnt/boot/init*

	# rebuild the new, only default initramfs
	arch-chroot /mnt "mkinitcpio -P"

	echo "Please set the root password"
	arch-chroot /mnt "passwd"

	echo "Installing GRUB to the disk of the RootFS."
	if [ "$uefi" = "true" ]; then
		arch-chroot /mnt "grub-install --efi-directory=/boot"
	else
		arch-chroot /mnt "grub-install $(partToDisk "$rootfs")"
	fi

	echo "Installing NetworkManager for networking after bootup."
	arch-chroot /mnt "pacman -S networkmanager --noconfirm --neeeded"

	echo "Enabling NetworkManager and disabling systemd-networkd and resolved."
	arch-chroot /mnt "systemctl disable systemd-networkd"
	arch-chroot /mnt "systemctl disable systemd-resolved"
	arch-chroot /mnt "systemctl enable NetworkManager"

	echo "Installing ourselves into the installed system so that we can run through a little bit more setup after a reboot."
	cp "$ourself" /mnt/autosetup.sh

	# just in case
	chmod +x /mnt/autosetup.sh

	cat << EOF > /etc/systemd/system/autosetup.service
[Service]
User=root
ExecStart=/autosetup.sh --rm

[Install]
WantedBy=default.target
EOF
	until [ "$autostart" = "y" ] || [ "$autostart" = "n" ]; do
		echo -n "If you will not have networking by default on boot (Wi-Fi), it would be unwise to start the remainder of the setup automatically.  Would you like it to start automatically after reboot?  (y/n)"
		read -r autostart
	done
	
	if [ "$autostart" = "y" ]; then
		arch-chroot /mnt "systemctl enable autosetup"
	fi

	echo "Rebooting.  See ya on the other side!"
	sleep 5
	reboot
}



###########################################
#                                         #
#   I N S T A L L E D   O S   S E T U P   #
#                                         #
###########################################
mainSetup() {
	echo -e "\n\e[0mInstalling..."
	if [ "$(id -u)" != "0" ]; then
		echo -e "\e[31mERROR: You must be root to run this script"
		exit 1
	fi
	echo "Installing packages..."
	pacman -S --noconfirm --needed sudo git base-devel rsync \
	pipewire pipewire-pulse pavucontrol 


	echo "Adding user and sudo setup"
	groupadd -r sudo
	sed -i 's/# %sudo	ALL=(ALL:ALL) ALL/%sudo	ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
	useradd -m techflash -c Techflash -G users,sudo,plugdev,video,render
	echo "Please enter the password for the new user"
	passwd techflash

	echo "Running dotfiles setup"

	echo "Adding autologin to getty config"
	mkdir /etc/systemd/system/getty@tty1.service.d
	cat << EOF > /etc/systemd/system/getty@tty1.service.d/autologin.config
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin techflash %I \$TERM
EOF


	if [ "$1" = "--rm" ]; then
		rm "$ourself"
	fi
}




if [ "$isArchISO" = "true" ]; then
	installerSetup $1
	exit 0
fi

mainSetup $1
exit 0