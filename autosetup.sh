#!/bin/bash


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
echo "Techflash autosetup script v0.0.2"
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


###########################################
#                                         #
#   I N - I N S T A L L E R   S E T U P   #
#                                         #
###########################################




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
}




if [ "$isArchISO" = "true" ]; then
	installerSetup
	exit 0
fi

mainSetup
exit 0