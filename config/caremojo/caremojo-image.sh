#!/bin/bash
#
# customize-image.sh -- runs INSIDE the target chroot (no network).
#
# Bakes the approved CareMojo offline bundle into a TRHub-V3 rootfs so a
# factory box needs no SD card, no serial session and no hand-run install.sh.
#
# The application still comes from CareMojo's own bundle and is installed by
# their own packaging/hub/install.sh -- this script does not reimplement that
# installer. It only reshapes the run for a build chroot (no systemd running, no
# network, nothing to start) and adds the few things their installer does not
# cover on this board. See Main for both lists.

# The framework calls this as: customize-image.sh RELEASE LINUXFAMILY BOARD BUILD_DESKTOP ARCH
# Nothing else from the build host is exported into the chroot.
RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4
ARCH=$5

# Their installer's own layout. Keeping it means the OTA updater, the units and
# the docs all describe the same path, and nothing has to be re-templated.
APP="/opt/caremojo/audio-hub"
STAGE="/root/caremojo-offline-stage"
P1_IGNORE_QUIRK="6675:3498:i"
ARMBIAN_ENV="/boot/armbianEnv.txt"
# What the box calls itself. The serial console and the login banner both print
# this: 10-armbian-header runs `figlet -f big " $VENDOR"`, and getty prints
# /etc/issue. Overridable so the same branch can serve another partner.
BRAND="${CARE_MOJO_BRAND:-CareMojo}"

log() { echo "[caremojo-image] $*"; }

# The build framework sets VENDOR="ThirdReality" in
# userpatches/config-linuxbox-images.conf, which reaches these four files and
# the motd script. Renaming the vendor here keeps the vendor config untouched
# for every other board on this branch.
branding_pass() {
	log "branding the image as ${BRAND}"

	# 10-armbian-header sources both and prefers the image-release value.
	local f
	for f in /etc/armbian-image-release /etc/armbian-release; do
		[[ -f "$f" ]] || continue
		sed -i "s|^VENDOR=.*|VENDOR=\"${BRAND}\"|" "$f"
	done

	# Printed by getty before the login prompt, on the console and over ssh.
	for f in /etc/issue /etc/issue.net; do
		[[ -f "$f" ]] || continue
		sed -i "s|^ThirdReality |${BRAND} |" "$f"
	done

	# Keep the version and codename, replace only the leading vendor name.
	if [[ -f /etc/os-release ]]; then
		sed -i -e "s|^PRETTY_NAME=\"ThirdReality |PRETTY_NAME=\"${BRAND} |" \
			-e "s|^ARMBIAN_PRETTY_NAME=\"ThirdReality |ARMBIAN_PRETTY_NAME=\"${BRAND} |" \
			/etc/os-release
	fi

	# The GPL notice under /etc; cosmetic, but it is what reads as "who made it".
	[[ -f /etc/armbian.txt ]] && sed -i "s|^Vendor:.*|Vendor:         ${BRAND}|" /etc/armbian.txt

	log "branding done (banner, issue, os-release)"
}

# The supervisor verifies that one of its expected application units is
# installed and, when none is, declares the box SYS_SYSTEM_CORRUPTED: the LED
# blinks white at 1 Hz, which a family reads as "this thing is broken".
#
# Its required_any_of list is home-assistant / zigbee2mqtt / matter2mqtt /
# openhab. This image deliberately ships none of them -- the box is a
# watch-offload hub -- so the check can never pass as shipped. Adding
# watch-to-cloud, the unit everything else on this image depends on, makes the
# check mean something true here instead of disabling it.
#
# Verified on the board: "Component check passed: watch-to-cloud.service is
# installed", LED goes solid blue, "Clearing LED SYS_SYSTEM_CORRUPTED state".
supervisor_component_check_pass() {
	local conf=/var/lib/hubv3-supervisor/configuration.yaml
	[[ -f "${conf}" ]] || { log "WARNING: ${conf} missing, supervisor check left as is"; return 0; }

	if grep -qE '^[[:space:]]*-[[:space:]]*"watch-to-cloud.service"' "${conf}"; then
		log "supervisor component check already accepts watch-to-cloud"
		return 0
	fi

	# Insert right after the required_any_of: key so the list stays readable.
	if grep -q '^  required_any_of:' "${conf}"; then
		sed -i '/^  required_any_of:/a\    - "watch-to-cloud.service"' "${conf}"
		log "supervisor component check now accepts watch-to-cloud.service"
	else
		log "WARNING: required_any_of not found in ${conf}; the LED may blink CORRUPTED"
	fi
}

# device_prefixes maps BOARD to the prefix in the device name the supervisor
# reports ("3RHUB-A1B2C3D4"). Only trhubv3 is listed, so every other board --
# this one included -- falls to default, which is "3RCARE-". That prefix
# belongs to ThirdReality's Care Hub (trhubv3b, model 3RCH01091H); using it here
# would report our box as a different product.
#
# This board is the same hardware and the same model id (3RLB01081MH) as
# trhubv3, so it takes trhubv3's prefix.
supervisor_device_prefix() {
	local conf=/var/lib/hubv3-supervisor/configuration.yaml
	[[ -f "${conf}" ]] || return 0

	if grep -qE '^[[:space:]]*trhubv3caremojo:' "${conf}"; then
		log "supervisor device prefix already set for this board"
		return 0
	fi

	if grep -q '^  device_prefixes:' "${conf}"; then
		sed -i '/^  device_prefixes:/a\    trhubv3caremojo: "3RHUB-"' "${conf}"
		log "supervisor device prefix: 3RHUB- (was falling through to 3RCARE-)"
	else
		log "WARNING: device_prefixes not found in ${conf}; the device name will read 3RCARE-"
	fi
}

# Runs their installer the way a build chroot needs it, and nothing more.
run_vendor_installer() {
	log "unpacking the CareMojo application into ${APP}"
	install -d -m755 "${APP}"
	tar -xzf "${STAGE}/audio-hub.tar.gz" -C "${APP}"
	chown -R root:root "${APP}"

	# The bundle's BUILD_INFO carries BUILT_AT_EPOCH and
	# install-offline-package.sh uses it to lift a stale factory clock before
	# the install. That is skipped here on purpose: inside a build chroot
	# `date -u -s` sets the build host's clock, and the image is assembled with
	# the host's time anyway (files carry their build timestamps).

	# Their installer refuses to run without these and the bundle carries them,
	# so hand over the bundled copies. This leaves the box in the same state the
	# line reaches by running the same installer from the same bundle.
	local -a args=(--no-start)
	[[ -s "${STAGE}/hub.env" ]] || { log "ERROR: ${STAGE}/hub.env missing"; exit 1; }
	args+=(--env-file "${STAGE}/hub.env")
	[[ -s "${STAGE}/tailscale-authkey" ]] && args+=(--tailscale-authkey "${STAGE}/tailscale-authkey")
	[[ -s "${STAGE}/github-token" ]] && args+=(--github-token "${STAGE}/github-token")
	local sha
	sha="$(sed -n 's/^HEAD_SHA=//p' "${STAGE}/BUILD_INFO" 2>/dev/null || true)"
	[[ -n "${sha}" ]] && args+=(--installed-sha "${sha}")

	# --no-start: enabling is wanted, starting is not (nothing runs here).
	# SYSTEMD_OFFLINE=1: the documented way to use systemctl in a chroot; it
	# makes daemon-reload a no-op and lets enable write the symlink.
	log "running their install.sh ${args[*]}"
	( cd / && SYSTEMD_OFFLINE=1 bash "${APP}/packaging/hub/install.sh" "${args[@]}" ) ||
		{ log "ERROR: their install.sh failed"; exit 1; }
}

# Their installer enables the units only in the branch that also starts them
# (`systemctl enable --now`), and it starts them under set -e, which a chroot
# cannot do. With --no-start it enables tailscaled and nothing else. An image
# has to come up running the stack, so enable what the bundle installed.
#
# The list is read from the bundle's own packaging/systemd directory rather than
# copied from their script: a newer bundle that adds or drops a unit is picked
# up without touching this file.
enable_caremojo_units() {
	local dir="${APP}/packaging/systemd" f name

	for f in "${dir}"/*.service "${dir}"/*.timer; do
		[[ -f "${f}" ]] || continue
		name="${f##*/}"
		case "${name}" in
			caremojo-bt-select.service)
				log "skipping ${name} (Intel 7265 only)"
				continue
				;;
			caremojo-update.service)
				# Its timer starts it. Enabling the oneshot would run an OTA
				# on the first boot of every factory box.
				continue
				;;
		esac
		# Their installer already templated the unit into /etc/systemd/system.
		# Enable only what is really there: a unit named in the bundle but not
		# installed (their installer skips some conditionally) would otherwise
		# get a symlink to a missing file, which systemd reports as a failure on
		# every boot.
		if [[ ! -f "/etc/systemd/system/${name}" ]]; then
			log "skipping ${name}: not installed by their installer"
			continue
		fi
		# SYSTEMD_OFFLINE makes systemctl work here; systemd creates the
		# wants/ link itself, into whatever target the [Install] section names.
		if SYSTEMD_OFFLINE=1 systemctl enable "${name}" >/dev/null 2>&1; then
			log "enabled ${name}"
			continue
		fi
		# An image whose stack is installed but not enabled boots and looks fine,
		# and only fails in the field. Stopping the build here is the cheaper
		# outcome; every unit in the bundle is expected to enable.
		log "ERROR: could not enable ${name}"; exit 1
	done
}

# Their installer runs install-msc-gate, which rewrites armbianEnv.txt in place;
# armbian-hardware-optimization reads usbstoragequirks from there on every boot.
# Nothing to do but confirm it landed: a missing quirk on a docked band is the
# one failure mode that reaches into a watch's filesystem.
confirm_p1_quirk() {
	if grep -q "${P1_IGNORE_QUIRK}" "${ARMBIAN_ENV}" 2>/dev/null; then
		log "P1 storage quirk present in ${ARMBIAN_ENV}"
	else
		log "WARNING: ${P1_IGNORE_QUIRK} missing from ${ARMBIAN_ENV}; a docked band would not be gated"
	fi
}

# Newer than the approved bundle. iOS serves Battery Level only over a paired
# link, so bluetoothd's battery plugin makes BlueZ ask the iPhone to pair, the
# pairing fails, the kernel drops the link and the Admin app's WiFi setup ends in
# "The hub dropped the connection". Safe to apply when their installer already
# did it (it writes the same drop-in).
bluetooth_no_battery() {
	local dropin=/etc/systemd/system/bluetooth.service.d/caremojo-no-battery.conf
	[[ -f "${dropin}" ]] && { log "bluetoothd battery plugin already disabled"; return 0; }
	local svc=/lib/systemd/system/bluetooth.service
	[[ -f "${svc}" ]] || { log "WARNING: ${svc} missing; battery plugin left in place"; return 0; }
	local exec_line
	exec_line="$(awk '/^ExecStart=/ { sub(/^ExecStart=/, ""); print; exit }' "${svc}")"
	[[ -n "${exec_line}" ]] || return 0
	mkdir -p /etc/systemd/system/bluetooth.service.d
	cat > "${dropin}" <<EOF
# bluetoothd without its battery plugin. iOS serves Battery Level only over a
# paired link: BlueZ asks the iPhone to pair, the pairing fails and the kernel
# drops the link, so the Admin app's WiFi setup ends in "The hub dropped the
# connection". The Hub never needs a phone's battery. Delete this file to undo.
[Service]
ExecStart=
ExecStart=${exec_line} --noplugin=battery
EOF
	log "bluetoothd: battery plugin disabled (iOS pairing fix)"
}

Main() {
	[[ "${BOARD}" == *caremojo* ]] || { log "board ${BOARD} is not a CareMojo image, skipping"; return 0; }
	[[ -f "${STAGE}/install.sh" ]] ||
		{ log "ERROR: ${STAGE} is missing (did customize-image-host.sh run?)"; exit 1; }

	run_vendor_installer
	enable_caremojo_units

	# What their installer leaves to us: things that exist only because this is
	# an Armbian image, plus one fix newer than the approved bundle.
	confirm_p1_quirk
	bluetooth_no_battery
	branding_pass
	supervisor_component_check_pass
	supervisor_device_prefix

	# The bundle's own copy of the credentials is spent; the files their
	# installer wrote (/etc/caremojo/*, clients/.env.cloud) stay in the image.
	rm -rf "${STAGE}"

	log "done: the box boots into the CareMojo stack (unclaimed, no device identity)"
} # Main

Main "$@"
