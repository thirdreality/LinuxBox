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
# Upgrading the image to a newer CareMojo build means pointing CARE_MOJO_BUNDLE /
# CARE_MOJO_RELEASE at the newer Release. Nothing else in this hook, or in the
# chroot half, has to change for that.
#
# A bundle already in CARE_MOJO_BUNDLE_DIR is reused as is; only a missing one is
# downloaded (gh release download, needs `gh auth login` on the builder). The
# bundle carries the cloud config and the Tailscale/GitHub credentials, so it is
# verified against the release's own .sha256 before anything is unpacked.

CARE_MOJO_BUNDLE_DIR="${CARE_MOJO_BUNDLE_DIR:-${SRC}/cache/sources/caremojo-offline}"
# Which Release the bundle comes from, and which file inside it. The bundle is
# chosen by name, not "newest file in the directory": the image records which
# build it carries, and a stray or half-copied download must not silently become
# the next release.
CARE_MOJO_REPO="${CARE_MOJO_REPO:-peakmojo/audio-hub}"
CARE_MOJO_RELEASE="${CARE_MOJO_RELEASE:-p3-golden-1}"
CARE_MOJO_BUNDLE="${CARE_MOJO_BUNDLE:-caremojo-trhub-v3-offline-p3-golden-1.tar.gz}"
CARE_MOJO_STAGE_NAME="caremojo-offline-stage"

caremojo_should_run() {
	[[ "${BOARD}" == *caremojo* ]]
}

# Reuse a bundle that is already cached; only fetch it when absent. The release
# assets are private, so this uses gh's credential store rather than an
# anonymous curl. Both files are fetched together and both are needed: the
# .sha256 is what the verification below trusts.
caremojo_fetch_bundle() {
	local bundle="${CARE_MOJO_BUNDLE_DIR}/${CARE_MOJO_BUNDLE}"

	if [[ -f "${bundle}" && -f "${bundle}.sha256" ]]; then
		display_alert "CareMojo bundle already cached" "${CARE_MOJO_BUNDLE}" "info"
		return 0
	fi

	command -v gh >/dev/null 2>&1 || exit_with_error \
		"Bundle ${CARE_MOJO_BUNDLE} is not cached and gh is not installed. Install gh and run 'gh auth login', or copy ${CARE_MOJO_BUNDLE} and ${CARE_MOJO_BUNDLE}.sha256 into this directory by hand" \
		"${CARE_MOJO_BUNDLE_DIR}"

	mkdir -p "${CARE_MOJO_BUNDLE_DIR}" || exit_with_error "Unable to create" "${CARE_MOJO_BUNDLE_DIR}"
	display_alert "Downloading CareMojo bundle" "${CARE_MOJO_REPO}@${CARE_MOJO_RELEASE}/${CARE_MOJO_BUNDLE}" "info"
	run_host_command_logged gh release download "${CARE_MOJO_RELEASE}" \
		--repo "${CARE_MOJO_REPO}" \
		--pattern "${CARE_MOJO_BUNDLE}*" \
		--dir "${CARE_MOJO_BUNDLE_DIR}" ||
		exit_with_error "gh release download failed (private repo: is the builder authenticated? see 'gh auth status')" \
			"${CARE_MOJO_REPO}@${CARE_MOJO_RELEASE}"

	[[ -f "${bundle}" ]] || exit_with_error "The Release has no asset named ${CARE_MOJO_BUNDLE}" "${CARE_MOJO_REPO}@${CARE_MOJO_RELEASE}"
}

caremojo_stage_bundle() {
	if ! caremojo_should_run; then
		display_alert "customize-image-host: skipping" "board ${BOARD} is not a CareMojo image" "info"
		return 0
	fi

	local bundle="${CARE_MOJO_BUNDLE_DIR}/${CARE_MOJO_BUNDLE}"
	caremojo_fetch_bundle

	# The bundle carries the install payload and the cloud/Tailscale/GitHub
	# credentials. An unverified one must not reach an image, so a missing
	# checksum fails the build rather than only warning.
	[[ -f "${bundle}.sha256" ]] || exit_with_error \
		"No checksum beside the bundle: expected ${CARE_MOJO_BUNDLE}.sha256 (it ships in the same Release)" \
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
