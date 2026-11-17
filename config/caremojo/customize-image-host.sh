#!/bin/bash
#
# customize-image-host.sh -- runs on the BUILD HOST, before the chroot.
#
# The Hub software is not taken from a git clone here. It comes from the
# offline bundle CareMojo publishes as a GitHub Release, because that bundle is
# what the production line installs. Baking the same artifact keeps the image
# and the line on one build: same code tree, same layout
# (/opt/caremojo/audio-hub), same installer, no second copy to drift.
#
# Upgrading the image to a newer CareMojo build means dropping a newer
# caremojo-trhub-v3-offline-*.tar.gz into CARE_MOJO_BUNDLE_DIR. Nothing else in
# this hook, or in the chroot half, has to change for that.
#
# The bundle carries the cloud config and the Tailscale/GitHub credentials, so
# it is verified against the release's own .sha256 before anything is unpacked.

CARE_MOJO_BUNDLE_DIR="${CARE_MOJO_BUNDLE_DIR:-${SRC}/cache/sources/caremojo-offline}"
CARE_MOJO_STAGE_NAME="caremojo-offline-stage"

caremojo_should_run() {
	[[ "${BOARD}" == *caremojo* ]]
}

caremojo_stage_bundle() {
	if ! caremojo_should_run; then
		display_alert "customize-image-host: skipping" "board ${BOARD} is not a CareMojo image" "info"
		return 0
	fi

	# Newest wins when several approved bundles sit in the cache side by side.
	local bundle
	bundle="$(ls -1t "${CARE_MOJO_BUNDLE_DIR}"/caremojo-trhub-v3-offline-*.tar.gz 2>/dev/null | head -1)"
	[[ -n "${bundle}" ]] || exit_with_error \
		"No CareMojo offline bundle: put caremojo-trhub-v3-offline-*.tar.gz in this directory" \
		"${CARE_MOJO_BUNDLE_DIR}"

	if [[ -f "${bundle}.sha256" ]]; then
		( cd "$(dirname "${bundle}")" && sha256sum -c "$(basename "${bundle}").sha256" ) ||
			exit_with_error "CareMojo bundle checksum mismatch" "${bundle}"
		display_alert "CareMojo bundle verified" "$(basename "${bundle}")" "info"
	else
		display_alert "WARNING: no .sha256 beside the bundle, shipping it unverified" "${bundle}" "wrn"
	fi

	local dest="${SDCARD}/root/${CARE_MOJO_STAGE_NAME}"
	mkdir -p "${dest}" || exit_with_error "Unable to create the stage dir" "${dest}"
	display_alert "Unpacking the CareMojo bundle" "${dest}" "info"
	# --strip-components=1 drops the bundle's own top-level directory so the
	# chroot half sees install.sh, audio-hub.tar.gz, hub.env and BUILD_INFO
	# directly. The ._* entries are AppleDouble files left by packing on macOS.
	run_host_command_logged tar -xzf "${bundle}" -C "${dest}" \
		--strip-components=1 --exclude='._*' ||
		exit_with_error "Unable to unpack the CareMojo bundle" "${bundle}"

	local sha
	sha="$(sed -n 's/^HEAD_SHA=//p' "${dest}/BUILD_INFO" 2>/dev/null)"
	display_alert "CareMojo bundle built from" "${sha:-unknown}" "info"
}

# The chroot half lives in config/caremojo/caremojo-image.sh and is appended to
# customize-image.sh by make-armbian-build-release.sh; here it only has to land
# inside the target rootfs. $SDCARD is the target's root, writable from the host.
caremojo_stage_chroot_script() {
	local script="${SRC}/config/caremojo/caremojo-image.sh"
	[[ -f "${script}" ]] || exit_with_error "Missing the chroot half" "${script}"
	display_alert "Staging the CareMojo chroot script" "/tmp/caremojo-image.sh in the image" "info"
	install -m755 "${script}" "${SDCARD}/tmp/caremojo-image.sh"
}

caremojo_stage_bundle
caremojo_stage_chroot_script
