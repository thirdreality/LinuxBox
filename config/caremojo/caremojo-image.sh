#!/bin/bash
#
# customize-image.sh -- runs INSIDE the target chroot (no network).
#
# Bakes the CareMojo watch-offload stack into a TRHub-V3 rootfs so a factory
# box needs no SD/USB bundle, no serial session and no hand-run install.sh.
# The source tree was cloned and copied to /home/caremojo/audio-hub by
# customize-image-host.sh before this script ran.
#
# What this deliberately does NOT do (compared with packaging/hub/install.sh):
#   * no apt/PyPI -- the packages are already in the image (see the board's
#     PACKAGE_LIST_BOARD) and no Hub service runs Python any more;
#   * no /boot remount -- armbianEnv.txt is written directly, so
#     install-msc-gate and its read-only dance are not needed;
#   * no service start -- configure-image only enables; the factory power-on
#     is the first boot.
#
# Credentials are never baked in. clients/.env.cloud, /etc/caremojo/device-auth.env
# and /etc/caremojo/tailscale-authkey are injected at the factory (ENROLL or
# the offline bundle), and the services start in a degraded but harmless state
# until they exist.

# The framework calls this as: customize-image.sh RELEASE LINUXFAMILY BOARD BUILD_DESKTOP ARCH
# Nothing else from the build host is exported into the chroot.
RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4
ARCH=$5

APP="/home/caremojo/audio-hub"
SVC_USER="caremojo"
SVC_HOME="/home/caremojo"
UNIT_SRC="${APP}/packaging/systemd"
STATE_DIR="/var/lib/caremojo"
P1_IGNORE_QUIRK="6675:3498:i"
ARMBIAN_ENV="/boot/armbianEnv.txt"

CORE_UNITS=(
	watch-to-cloud.service
	hub-audio-recorder.service
	hub-audio-handoff-beacon.service
	caremojo-uploader.service
	caremojo-ble.service
	caremojo-power-limits.service
	hub-status-web.service
	caremojo-btagent.service
	caremojo-provision.service
	caremojo-boot-evidence.service
	caremojo-boot-complete.service
)
OTA_UNITS=(caremojo-update.service caremojo-update.timer)

log() { echo "[caremojo-image] $*"; }

enable_unit() {
	local u="$1"
	mkdir -p /etc/systemd/system/multi-user.target.wants
	if ! systemctl enable "$u" >/dev/null 2>&1; then
		ln -sfn "/etc/systemd/system/$u" "/etc/systemd/system/multi-user.target.wants/$u"
	fi
}

install_unit() {
	local u="$1"
	install -m644 "${UNIT_SRC}/${u}" "/etc/systemd/system/${u}"
}

Main() {
	[[ "${BOARD}" == *caremojo* ]] || { log "board ${BOARD} is not a CareMojo image, skipping"; return 0; }
	[[ -x "${APP}/packaging/hub/bin/aarch64/hub-watch" ]] \
		|| { log "ERROR: ${APP} is missing or incomplete (customize-image-host.sh did not run?)"; exit 1; }

	log "creating the ${SVC_USER} service account"
	if ! id "${SVC_USER}" >/dev/null 2>&1; then
		useradd --system --create-home --home-dir "${SVC_HOME}" --shell /usr/sbin/nologin "${SVC_USER}"
	fi
	# CDC serial, ALSA capture, and the udev-assigned device group for the P1.
	for g in dialout audio plugdev; do
		getent group "$g" >/dev/null || groupadd --system "$g"
		usermod -aG "$g" "${SVC_USER}"
	done

	log "preparing runtime state and secrets directories"
	mkdir -p "${STATE_DIR}"/{queue,device-archive,watch-events,hub-audio/RECORD}
	mkdir -p /etc/caremojo /opt/caremojo
	# The tree was copied in by the host hook as root, and /home/caremojo was
	# created by mkdir -p then left alone by useradd, so neither is owned by the
	# service account yet. install.sh gives the state dir 0750; match that.
	chown "${SVC_USER}:${SVC_USER}" "${SVC_HOME}"
	chown -R "${SVC_USER}:${SVC_USER}" "${APP}"
	chown -R "${SVC_USER}:${SVC_USER}" "${STATE_DIR}"
	chmod 750 "${STATE_DIR}" "${STATE_DIR}"/*
	chmod 755 "${SVC_HOME}"
	# /etc/caremojo stays root-owned; only the files placed there are 0600.
	chmod 755 /etc/caremojo
	chmod 755 /opt/caremojo

	log "retiring the base image's generic USB automount"
	# ThirdReality's rule automounts every USB partition at /mnt and starts
	# hubv3-usb-sync. A docked watch is also a USB block device, so that path
	# races READY/SETTIME, runs fsck against the watch and can reset the port.
	# CareMojo owns watch sync on this image. Kept as a recoverable file.
	if [[ -f /etc/udev/rules.d/20-usb-mount.rules ]]; then
		mv /etc/udev/rules.d/20-usb-mount.rules /etc/udev/rules.d/20-usb-mount.rules.caremojo-disabled
	fi
	systemctl disable hubv3-usb-sync.service >/dev/null 2>&1 || true
	# Masking in a chroot is a symlink to /dev/null; no daemon is running to ask.
	ln -sfn /dev/null /etc/systemd/system/hubv3-usb-sync.service
	rm -f /etc/systemd/system/mnt.automount /etc/systemd/system/mnt.mount

	log "installing the P1 udev rules and the MSC remount helper"
	install -m644 "${APP}/packaging/udev/99-caremojo-thirdreality-p1.rules" \
		/etc/udev/rules.d/99-caremojo-thirdreality-p1.rules
	install -m755 "${APP}/packaging/hub/caremojo-msc-attach" /usr/local/sbin/caremojo-msc-attach
	install -m440 "${APP}/packaging/sudoers/caremojo-msc-remount" /etc/sudoers.d/caremojo-msc-remount
	ln -sfn "${APP}/packaging/hub/caremojo-backup-wifi" /usr/local/sbin/caremojo-backup-wifi

	log "persisting the P1 storage ignore quirk"
	# usb_storage is built into this kernel, so a modprobe blacklist is too
	# late; the quirk has to be in armbianEnv.txt, where the base image's
	# armbian-hardware-optimization service picks it up on every boot and
	# writes it to /sys/module/usb_storage/parameters/quirks. That service
	# preserves an existing value, so this line survives boot.
	if [[ -f "${ARMBIAN_ENV}" ]]; then
		if ! grep -q "${P1_IGNORE_QUIRK}" "${ARMBIAN_ENV}"; then
			if grep -q '^usbstoragequirks=' "${ARMBIAN_ENV}"; then
				sed -i "s|^usbstoragequirks=\(.*\)$|usbstoragequirks=\1,${P1_IGNORE_QUIRK}|" "${ARMBIAN_ENV}"
			else
				echo "usbstoragequirks=${P1_IGNORE_QUIRK}" >> "${ARMBIAN_ENV}"
			fi
			log "added ${P1_IGNORE_QUIRK} to ${ARMBIAN_ENV}"
		fi
	else
		log "WARNING: ${ARMBIAN_ENV} not found; the P1 MSC gate will not persist"
	fi

	log "installing and enabling the CareMojo units"
	for u in "${CORE_UNITS[@]}"; do
		[[ -f "${UNIT_SRC}/${u}" ]] || { log "ERROR: missing unit ${u}"; exit 1; }
		install_unit "$u"
	done
	# Mount unit for the read-only watch volume. The name is systemd's escaped
	# form of /run/caremojo-watch, so it must stay byte-identical.
	install -m644 "${UNIT_SRC}/run-caremojo\\x2dwatch.mount" '/etc/systemd/system/run-caremojo\x2dwatch.mount'
	for u in "${OTA_UNITS[@]}"; do install_unit "$u"; done

	# caremojo-bt-select is Intel-7265-only and is not installed.
	[[ -f "${UNIT_SRC}/caremojo-bt-select.service" ]] && \
		log "skipping caremojo-bt-select (Intel-only)"

	for u in "${CORE_UNITS[@]}"; do enable_unit "$u"; done
	enable_unit caremojo-update.timer

	log "installing the OTA updater outside the app tree"
	install -m755 "${APP}/packaging/update/update.sh" /opt/caremojo/update.sh
	mkdir -p /etc/systemd/system/caremojo-update.service.d
	cat > /etc/systemd/system/caremojo-update.service.d/10-hub.conf <<EOF
[Service]
Environment="CAREMOJO_APP=${APP}"
Environment="CAREMOJO_USER=${SVC_USER}"
Environment="CAREMOJO_SERVICES=watch-to-cloud hub-audio-recorder hub-audio-handoff-beacon caremojo-uploader caremojo-ble hub-status-web caremojo-btagent caremojo-provision"
EOF

	log "bluetoothd without its battery plugin"
	# iOS serves Battery Level only over a paired link; the pairing fails and
	# the kernel drops the link, which breaks the Admin app's WiFi setup.
	BLUETOOTHD="$(awk '/^ExecStart=/ { sub(/^ExecStart=/, ""); print; exit }' \
		/lib/systemd/system/bluetooth.service 2>/dev/null || true)"
	if [[ -n "${BLUETOOTHD}" ]]; then
		mkdir -p /etc/systemd/system/bluetooth.service.d
		sed -e "s#@BLUETOOTHD@#${BLUETOOTHD}#" "${UNIT_SRC}/caremojo-no-battery.conf" \
			> /etc/systemd/system/bluetooth.service.d/caremojo-no-battery.conf
	else
		log "WARNING: could not read bluetooth.service ExecStart; battery plugin left in place"
	fi

	log "journald: keep boot history on durable storage"
	mkdir -p /etc/systemd/journald.conf.d
	install -m644 "${UNIT_SRC}/caremojo-persistent-journal.conf" \
		/etc/systemd/journald.conf.d/20-caremojo-persistent.conf

	log "done: the box boots into the CareMojo stack (unclaimed, no cloud config)"
} # Main

Main "$@"
