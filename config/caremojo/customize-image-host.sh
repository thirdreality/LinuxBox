#!/bin/bash
#
# customize-image-host.sh -- runs on the BUILD HOST, before the chroot.
#
# Its only job is to make the CareMojo source tree available on the host and
# copy it into the target rootfs. The chroot has no network and no access to
# the build framework's variables, so the clone/update must happen here.
#
# Semantics asked for by the partner: if the cache dir is missing, clone it;
# if it is present, update it to the requested ref and move on.
#
# The chroot side (customize-image.sh) only consumes what this leaves behind.

CARE_MOJO_REPO="${CARE_MOJO_REPO:-git@github.com:peakmojo/audio-hub.git}"
CARE_MOJO_REF="${CARE_MOJO_REF:-hub-stable}"     # Hubs track hub-stable, never main
CARE_MOJO_CACHE="${CARE_MOJO_CACHE:-${SRC}/cache/sources/audio-hub}"
CARE_MOJO_DEST="${SDCARD}/home/caremojo/audio-hub"

# The repository is private. No credential is stored here: the builder's own
# SSH key (or gh's credential helper, when CARE_MOJO_REPO is an HTTPS URL)
# is what the clone uses, the same way a developer clones it. If the build
# runs in a container, mount that key in or prime the cache first -- the
# cache, once present, needs no network access at all.

caremojo_should_run() {
	[[ "${BOARD}" == *caremojo* ]]
}

caremojo_fetch_sources() {
	if ! caremojo_should_run; then
		display_alert "customize-image-host: skipping" "board ${BOARD} is not a CareMojo image" "info"
		return 0
	fi

	if [[ ! -d "${CARE_MOJO_CACHE}/.git" ]]; then
		display_alert "Cloning CareMojo audio-hub" "${CARE_MOJO_REF} -> ${CARE_MOJO_CACHE}" "info"
		mkdir -p "$(dirname "${CARE_MOJO_CACHE}")" || exit_with_error "Unable to create cache dir" "${CARE_MOJO_CACHE}"
		run_host_command_logged git clone --depth 1 --branch "${CARE_MOJO_REF}" \
			"${CARE_MOJO_REPO}" "${CARE_MOJO_CACHE}" ||
			exit_with_error "Unable to clone audio-hub (private repo: give the builder SSH access, or prime ${CARE_MOJO_CACHE} by hand)" "${CARE_MOJO_REPO}"
	else
		display_alert "Updating CareMojo audio-hub" "${CARE_MOJO_REF} in ${CARE_MOJO_CACHE}" "info"
		run_host_command_logged git -C "${CARE_MOJO_CACHE}" fetch --depth 1 origin "${CARE_MOJO_REF}" ||
			exit_with_error "Unable to fetch ${CARE_MOJO_REF}" "${CARE_MOJO_REPO}"
		run_host_command_logged git -C "${CARE_MOJO_CACHE}" checkout --force FETCH_HEAD ||
			exit_with_error "Unable to check out ${CARE_MOJO_REF}" "${CARE_MOJO_CACHE}"
	fi

	local sha
	sha="$(git -C "${CARE_MOJO_CACHE}" rev-parse HEAD)"
	display_alert "CareMojo source" "${CARE_MOJO_REF} @ ${sha}" "info"
	# Record what the image was built from, so a factory box can be traced back.
	printf '%s %s\n' "${CARE_MOJO_REF}" "${sha}" > "${CARE_MOJO_CACHE}/.caremojo-build-ref"

	caremojo_verify_binaries
	caremojo_copy_to_rootfs
	caremojo_stage_chroot_script
}

# The binaries are committed, and BUILDINFO records the hash of the sources they
# were built from plus each binary's own hash. Nothing in their repository
# enforces it: no CI workflow, no pre-commit hook, only a pytest in tests/ that
# someone has to remember to run. So a commit that edits native/src/*.c without
# rebuilding passes review, and the tag we pin would ship yesterday's bug.
#
# Verify on every build and refuse to produce an image whose binaries do not
# match their sources. Failing the build is the cheap outcome; a board that
# silently runs stale C is the expensive one, and it would look like our board.
caremojo_verify_binaries() {
	local bin="${CARE_MOJO_CACHE}/packaging/hub/bin/aarch64"
	local info="${bin}/BUILDINFO"

	if [[ ! -f "${info}" ]]; then
		display_alert "WARNING: no BUILDINFO; the binaries cannot be verified" "${bin}" "wrn"
		return 0
	fi

	local -a shatool
	if command -v sha256sum >/dev/null 2>&1; then
		shatool=(sha256sum)
	else
		shatool=(shasum -a 256)
	fi

	# Same file set, same order, same concatenation as native/build-aarch64.sh
	# -- that script wrote the number we compare against. LC_ALL=C pins the
	# glob order to byte order, which is what it and the pytest both assume.
	local recorded actual
	recorded="$(sed -n 's/^sources_sha256=//p' "${info}")"
	actual="$(cd "${CARE_MOJO_CACHE}/native" && LC_ALL=C \
		cat Makefile src/*.c src/*.h vendor/cjson/*.c vendor/cjson/*.h 2>/dev/null |
		"${shatool[@]}" | cut -d' ' -f1)"

	if [[ "${recorded}" != "${actual}" ]]; then
		exit_with_error "CareMojo binaries are STALE: native/ sources changed without a rebuild (BUILDINFO ${recorded:0:16}..., sources ${actual:0:16}...). Ask them to run native/build-aarch64.sh and commit the binaries with BUILDINFO." "${CARE_MOJO_CACHE}"
	fi
	display_alert "CareMojo binaries match their sources" "${actual:0:16}..." "info"

	# Each binary against its own recorded hash: catches a swapped or truncated
	# file even when the source hash happens to line up.
	local line key value prog got count=0
	while IFS= read -r line; do
		key="${line%%=*}"
		value="${line#*=}"
		prog="${key%_sha256}"
		[[ "${prog}" == "sources" ]] && continue
		[[ -f "${bin}/${prog}" ]] || exit_with_error "Missing CareMojo binary" "${prog}"
		got="$("${shatool[@]}" "${bin}/${prog}" | cut -d' ' -f1)"
		[[ "${got}" == "${value}" ]] ||
			exit_with_error "CareMojo binary ${prog} does not match BUILDINFO (${got:0:16}... vs ${value:0:16}...)" "${bin}"
		count=$((count + 1))
	done < <(grep '_sha256=' "${info}")
	display_alert "All CareMojo binaries match BUILDINFO" "${count} programs" "info"
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

caremojo_copy_to_rootfs() {
	display_alert "Copying CareMojo tree into the image" "${CARE_MOJO_DEST}" "info"
	mkdir -p "${CARE_MOJO_DEST}" || exit_with_error "Unable to create" "${CARE_MOJO_DEST}"

	# Everything a box runs is under packaging/, native/ is only needed if you
	# rebuild the binaries on the box (we do not), and the cloud side (gateway/,
	# migrations/, cloud/, docs/, tests/, tools/) never belongs on a hub.
	#
	# .git is dropped: the box self-updates over OTA from the tagged release,
	# it never needs history. offline/ is gitignored and absent in a clone.
	run_host_command_logged rsync -a --delete \
		--exclude='.git' \
		--exclude='venv' \
		--exclude='offline' \
		--exclude='__pycache__' \
		--exclude='*.pyc' \
		--exclude='.env.cloud' \
		--exclude='.env.insforge' \
		--exclude='device-auth.env' \
		--exclude='.insta' \
		--exclude='gateway' \
		--exclude='migrations' \
		--exclude='cloud' \
		--exclude='tests' \
		--exclude='tools' \
		--exclude='deid' \
		--exclude='data' \
		--exclude='docs' \
		"${CARE_MOJO_CACHE}/" "${CARE_MOJO_DEST}/" ||
		exit_with_error "Unable to copy audio-hub into the rootfs" "${CARE_MOJO_DEST}"

	# The chroot side runs as root and cannot chown to a user it will create
	# later; uid/gid are set there. Here we only make sure the tree is not
	# world-writable and that the entrypoints are executable.
	chmod -R go-w "${CARE_MOJO_DEST}"
	chmod +x "${CARE_MOJO_DEST}/packaging/hub/bin/aarch64/"* 2>/dev/null || true
	chmod +x "${CARE_MOJO_DEST}/clients/"*.sh 2>/dev/null || true
	chmod +x "${CARE_MOJO_DEST}/packaging/hub/"caremojo-msc-attach \
		"${CARE_MOJO_DEST}/packaging/hub/"install-msc-gate \
		"${CARE_MOJO_DEST}/packaging/hub/"caremojo-backup-wifi 2>/dev/null || true
}

caremojo_fetch_sources
