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
# The approved bundle, by name. Not "newest file in the directory": the image
# records which build it carries, and a stray or half-copied download must not
# silently become the next release.
CARE_MOJO_BUNDLE="${CARE_MOJO_BUNDLE:-caremojo-trhub-v3-offline-p3-golden-1.tar.gz}"
CARE_MOJO_STAGE_NAME="caremojo-offline-stage"

caremojo_should_run() {
	[[ "${BOARD}" == *caremojo* ]]
}

caremojo_stage_bundle() {
	if ! caremojo_should_run; then
		display_alert "customize-image-host: skipping" "board ${BOARD} is not a CareMojo image" "info"
		return 0
	fi

	local bundle="${CARE_MOJO_BUNDLE_DIR}/${CARE_MOJO_BUNDLE}"
	[[ -f "${bundle}" ]] || exit_with_error \
		"Approved CareMojo bundle not found. Put ${CARE_MOJO_BUNDLE} in this directory, or set CARE_MOJO_BUNDLE to the bundle you mean to ship" \
		"${CARE_MOJO_BUNDLE_DIR}"

	# The bundle carries the install payload and the cloud/Tailscale/GitHub
	# credentials. An unverified one must not reach an image, so a missing
	# checksum fails the build rather than only warning.
	[[ -f "${bundle}.sha256" ]] || exit_with_error \
		"No checksum beside the bundle: expected ${CARE_MOJO_BUNDLE}.sha256 (download it from the same Release)" \
		"${bundle}.sha256"
	( cd "${CARE_MOJO_BUNDLE_DIR}" && sha256sum -c "${CARE_MOJO_BUNDLE}.sha256" ) ||
		exit_with_error "CareMojo bundle checksum mismatch" "${bundle}"
	display_alert "CareMojo bundle verified" "${CARE_MOJO_BUNDLE}" "info"

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
