#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
#
# This is the image customization script

# NOTE: It is copied to /tmp directory inside the image
# and executed there inside chroot environment
# so don't reference any files that are not already installed

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot
# The sd card's root path is accessible via $SDCARD variable.

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

Main() {
	case $RELEASE in
		stretch)
			# your code here
			# InstallOpenMediaVault # uncomment to get an OMV 4 image
			;;
		buster)
			# your code here
			;;
		bullseye)
			# your code here
			;;
		bionic)
			# your code here
			;;
		bookworm)
			InstallForHubV3
			;;

		jammy)
			InstallForHubV3
			;;
		focal)
			# your code here
			;;
	esac
} # Main

# Function to install Docker from .deb files
#   153456 Mar 18 21:48 ca-certificates_20230311_all.deb
# 22130236 Mar 18 21:48 containerd.io_1.7.25-1_arm64.deb
# 32694884 Mar 18 21:48 docker-buildx-plugin_0.21.1-1~debian.12~bookworm_arm64.deb
# 16611728 Mar 18 21:48 docker-ce_5%3a28.0.1-1~debian.12~bookworm_arm64.deb
# 14273604 Mar 18 21:48 docker-ce-cli_5%3a28.0.1-1~debian.12~bookworm_arm64.deb
#  5490454 Mar 18 21:48 docker-ce-rootless-extras_5%3a28.0.1-1~debian.12~bookworm_arm64.deb
# 12064876 Mar 18 21:48 docker-compose-plugin_2.33.1-1~debian.12~bookworm_arm64.deb
install_docker_debs() {
	echo "install docker debs ... "
	# Do not modify the order, remark by liuguoping.
    debs=(
        "ca-certificates_"
        "docker-ce-cli_"
		"containerd.io_"
        "docker-ce-rootless-extras_"
		"docker-ce_"
        "docker-buildx-plugin_"
        "docker-compose-plugin_"
    )

    for deb_prefix in "${debs[@]}"; do
        file=$(find /tmp/overlay/docker-deb -name "${deb_prefix}*.deb" | head -n 1)
        if [ -n "$file" ]; then
            echo "Installing [ $file ] ..."
            sudo dpkg -i "$file" > /dev/null 
        else
            echo "Package starting with [$deb_prefix] not found."
        fi
    done
    # Fix any dependency issues
    sudo apt-get install -f -y > /dev/null 
}

InstallForHubV3() {

	echo "InstallForHubV3 ..."
	apt-get autoremove -y
	apt-get clean
	
	#kernel modules to load at boot time
	# echo "aml_sdio" | sudo tee -a /etc/modules
	#echo "vlsicomm" | sudo tee -a /etc/modules
	#echo "sdio_bt" | sudo tee -a /etc/modules

	# Configure NetworkManager to only manage wlan0
	config_file="/etc/NetworkManager/NetworkManager.conf"
	
	if [[ -f "$config_file" ]]; then
		echo "Configuring NetworkManager ..."
		
		# Check and add [main] section configurations
		if ! grep -q "^\[main\]" "$config_file"; then
			echo -e "\n[main]" | sudo tee -a "$config_file" > /dev/null
		fi
		
		# Add dns=default if not present
		if ! grep -q "^dns=default" "$config_file"; then
			sudo sed -i '/^\[main\]/a dns=default' "$config_file"
		fi
		
		# Add rc-manager=file if not present
		if ! grep -q "^rc-manager=file" "$config_file"; then
			sudo sed -i '/^\[main\]/a rc-manager=file' "$config_file"
		fi
		
		# Check and configure [ifupdown] section
		if ! grep -q "^\[ifupdown\]" "$config_file"; then
			echo -e "\n[ifupdown]" | sudo tee -a "$config_file" > /dev/null
			echo "managed=true" | sudo tee -a "$config_file" > /dev/null
		else
			# Change managed=false to managed=true if exists
			sudo sed -i '/^\[ifupdown\]/,/^\[/ s/^managed=false/managed=true/' "$config_file"
		fi
		
		# Check and add [keyfile] section configurations
		if ! grep -q "^\[keyfile\]" "$config_file"; then
			echo -e "\n[keyfile]" | sudo tee -a "$config_file" > /dev/null
		fi
		
		# Add unmanaged-devices if not present
		if ! grep -q "^unmanaged-devices=interface-name:\*,except:interface-name:wlan0" "$config_file"; then
			sudo sed -i '/^\[keyfile\]/a unmanaged-devices=interface-name:*,except:interface-name:wlan0' "$config_file"
		fi
	else
		echo "File $config_file does not exist. Exiting script."
	fi

	echo "DefaultTimeoutStopSec=15s" >> /etc/systemd/system.conf
	echo "DefaultTimeoutStopSec=15s" >> /etc/systemd/user.conf
	
	# Configure NTP servers in timesyncd.conf
	timesyncd_conf="/etc/systemd/timesyncd.conf"
	if [[ -f "$timesyncd_conf" ]]; then
		echo "Configuring NTP servers in $timesyncd_conf ..."
		cat > "$timesyncd_conf" <<-'EOF'
		[Time]
		NTP=0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org
		FallbackNTP=0.debian.pool.ntp.org 1.debian.pool.ntp.org 2.debian.pool.ntp.org 3.debian.pool.ntp.org
		EOF
	else
		echo "Warning: $timesyncd_conf does not exist."
	fi
	
	echo "Enable bluetooth experimental mode ..."
	BLUETOOTH_SERVICE="/usr/lib/systemd/system/bluetooth.service"
	sed -i 's|ExecStart=/usr/libexec/bluetooth/bluetoothd|ExecStart=/usr/libexec/bluetooth/bluetoothd --experimental|' "$BLUETOOTH_SERVICE" || true
	
	if [  -d "/tmp/overlay/bl706_cache" ]; then
		echo "Install pip3 packages for bl706/702 flash tools ..."
		pip install --no-index --find-links=/tmp/overlay/bl706_cache pylink-square==0.5.0  pyserial==3.5 ecdsa==0.15  portalocker==2.0.0 pycryptodome==3.9.8 bflb-crypto-plus==1.0 pycklink==0.1.1 --break-system-packages
	fi

	if [ -f "/tmp/overlay/bl706_cache/ifaddr-0.2.0-py3-none-any.whl" ]; then
		echo "Install pip3 packages for zeroconf ..."
		pip install --no-index --find-links=/tmp/overlay/bl706_cache ifaddr==0.2.0 zeroconf==0.147.0 --break-system-packages
	fi
	
	mkdir -p /usr/local/thirdreality/bin
	mkdir -p /usr/local/thirdreality/config
	mkdir -p /usr/local/thirdreality/data

	mkdir -p /usr/local/hubv3/bin
	mkdir -p /usr/local/hubv3/config
	mkdir -p /usr/local/hubv3/data

	mkdir -p /var/lib/homeassistant/homeassistant
	mkdir -p /var/lib/homeassistant/matter_server

	rm -rf /var/lib/apt/lists/*
	rm -rf /usr/lib/firmware/qcom
	rm -rf /usr/lib/firmware/{aic8800,ap6210,ap6212,ap6275p,ath10k,ath11k,ath12k,mediatek,novatek,rtw88,rtw89}
	rm -rf /usr/lib/linux-image-$(uname -r)/rockchip
}

InstallOpenMediaVault() {
	echo "InstallOpenMediaVault ..."
} 

UnattendedStorageBenchmark() {
	# Function to create Armbian images ready for unattended storage performance testing.
	# Useful to use the same OS image with a bunch of different SD cards or eMMC modules
	# to test for performance differences without wasting too much time.

	rm /root/.not_logged_in_yet

	apt-get -qq install time

	wget -qO /usr/local/bin/sd-card-bench.sh https://raw.githubusercontent.com/ThomasKaiser/sbc-bench/master/sd-card-bench.sh
	chmod 755 /usr/local/bin/sd-card-bench.sh

	sed -i '/^exit\ 0$/i \
	/usr/local/bin/sd-card-bench.sh &' /etc/rc.local
} # UnattendedStorageBenchmark

InstallAdvancedDesktop()
{
	apt-get install -yy transmission libreoffice libreoffice-style-tango meld remmina thunderbird kazam avahi-daemon
	[[ -f /usr/share/doc/avahi-daemon/examples/sftp-ssh.service ]] && cp /usr/share/doc/avahi-daemon/examples/sftp-ssh.service /etc/avahi/services/
	[[ -f /usr/share/doc/avahi-daemon/examples/ssh.service ]] && cp /usr/share/doc/avahi-daemon/examples/ssh.service /etc/avahi/services/
	apt clean
} # InstallAdvancedDesktop


Main "$@"

