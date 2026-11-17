# CareMojo partner image (`hubv3caremojo`)

A TRHub-V3 image with CareMojo's approved offline bundle installed, so a factory
box needs no SD card, no serial session and no hand-run `install.sh`. Same
hardware, same kernel, same U-Boot as `hubv3`; only the rootfs payload differs.

The application is **not** re-implemented here. The image carries the same
artifact the production line installs, and CareMojo's own
`packaging/hub/install.sh` installs it during the build, inside the chroot.

## Build

```sh
# on an x86-64 Linux builder with docker
./make-armbian-build-release.sh -b hubv3caremojo -d us -r v2.14.01.55
```

Output: `output/images/caremojo_armbian_24.11_bookworm_<kernel>_<rev>.burn.img.zip`,
flashed with the Amlogic USB Burning Tool (same as `hubv3`).

## Where the application comes from

`config/caremojo/customize-image-host.sh` runs on the build host and stages the
approved offline bundle from the `p3-golden-1` GitHub Release. That is the same
bundle the production line copies to a USB stick.

| variable | default | meaning |
|---|---|---|
| `CARE_MOJO_BUNDLE_DIR` | `$SRC/cache/sources/caremojo-offline` | where the bundle is cached |
| `CARE_MOJO_REPO` | `peakmojo/audio-hub` | the Repository the Release lives in |
| `CARE_MOJO_RELEASE` | `p3-golden-1` | the Release tag to download |
| `CARE_MOJO_BUNDLE` | `caremojo-trhub-v3-offline-p3-golden-1.tar.gz` | the asset inside that Release |

The bundle is chosen **by name**, not "newest file in the directory": the image
records which build it carries, and a stray or half-copied download must not
silently become the next release.

### Where the bundle comes from, and when

```
<CARE_MOJO_BUNDLE_DIR>/<CARE_MOJO_BUNDLE>       exists?  -> reuse it
<CARE_MOJO_BUNDLE_DIR>/<CARE_MOJO_BUNDLE>.sha256 exists?  -> reuse it
otherwise -> gh release download <CARE_MOJO_RELEASE> --repo <CARE_MOJO_REPO>
              --pattern '<CARE_MOJO_BUNDLE>*' --clobber
```

Both files must be cached to skip the download: a bundle present while its
`.sha256` is missing still takes the download path, and `--clobber` is what lets
gh overwrite the existing bundle there.

A cached bundle is never re-downloaded, so repeated builds cost nothing and work
on a machine with no network to GitHub. The Release assets are private, so the
download goes through `gh` and its credential store rather than an anonymous
curl: the builder needs `gh` installed and `gh auth login` done once. Without
either, the build stops and says so.

Both files are then verified against the Release's own `.sha256` before anything
is unpacked. A missing bundle, a missing checksum or a mismatch **fails the
build**. The bundle carries the install payload *and* the cloud / Tailscale /
GitHub credentials, so an unverified one must never reach an image.

The commit the bundle was built from is printed at build time
(`CareMojo bundle built from <sha>`) and lands inside the image as
`/opt/caremojo/audio-hub/INSTALLED_SHA`.

### Upgrading to a newer Release

Either point the variables at the new Release and let the build fetch it:

```sh
CARE_MOJO_RELEASE=p3-golden-2 \
CARE_MOJO_BUNDLE=caremojo-trhub-v3-offline-p3-golden-2.tar.gz \
  ./make-armbian-build-release.sh -b hubv3caremojo -d us -r v2.14.01.55
```

...or copy both files into `CARE_MOJO_BUNDLE_DIR` by hand and set
`CARE_MOJO_BUNDLE` to its name; no download is attempted. This is the only path
when the builder has no `gh` or no GitHub access.

The cache is keyed by file name, so a new name downloads once and the previous
bundle stays on disk for rollback. Nothing in either hook has to change.

## What ends up in the image

`/opt/caremojo/audio-hub` is their own layout, produced by their installer. The
image does not put a second copy anywhere else, so the OTA updater patches the
tree the image shipped.

| path | contents |
|---|---|
| `/opt/caremojo/audio-hub` | the bundle's `audio-hub.tar.gz`, unpacked (code, 8 aarch64 binaries, watch firmware) |
| `/opt/caremojo/audio-hub/packaging/hub/offline/` | the offline cache, kept: 185 `.deb`, 11 `.whl`, the Tailscale tgz |
| `/opt/caremojo/audio-hub/venv` | Python venv built from the offline wheels |
| `/opt/caremojo/audio-hub/INSTALLED_SHA` | the commit the bundle was built from |
| `/opt/caremojo/update.sh` | OTA updater, outside the app tree |
| `/etc/systemd/system/` | their units + `run-caremojo\x2dwatch.mount`, enabled (not started) |
| `/etc/systemd/journald.conf.d/20-caremojo-persistent.conf` | persistent journal |
| `/etc/udev/rules.d/99-caremojo-thirdreality-p1.rules` | P1 CDC/MSC device permissions |
| `/etc/sudoers.d/caremojo-msc-remount` | the one command the service user may run as root |
| `/usr/local/sbin/caremojo-msc-attach`, `caremojo-backup-wifi` | USB remount helper, backup-WiFi helper |
| `/usr/bin/tailscale`, `/usr/sbin/tailscaled`, `tailscaled.service` | from the bundle |
| `/var/lib/caremojo/{queue,device-archive,watch-events,hub-audio/RECORD}` | runtime state, `caremojo:caremojo` |
| `/boot/armbianEnv.txt` | `usbstoragequirks=...,6675:3498:i` |
| user/group | `caremojo` (system, nologin), in `dialout`, `audio`, `plugdev` |

### Why the offline cache is kept

`install-offline-package.sh` unpacks `audio-hub.tar.gz`, `offline/` included, to
`/opt/caremojo/audio-hub`. On a line box the cache stays on eMMC after the stick
is removed. `update.sh` also relies on it: it excludes `./packaging/hub/offline`
from the code backup and uses it as `CAREMOJO_WHEEL_DIR` for the pip ensure step.
Image boxes must match line boxes, so the cache is not pruned.

### Credentials in the image

Unlike the earlier git-clone approach, **the image contains credentials**, because
the bundle does and their `install.sh` requires them:

| file | contents |
|---|---|
| `/opt/caremojo/audio-hub/clients/.env.cloud` | cloud config (URL, anon key, ingest token) |
| `/etc/caremojo/tailscale-authkey` | Tailscale provisioning credential |
| `/etc/caremojo/github-token` | read-only PAT for the OTA updater |

Consequence: **one image belongs to one agency.** A bundle is built per agency
(`build-offline-package.sh --env-file`), so shipping to a second agency means
obtaining their bundle and rebuilding the image with `CARE_MOJO_BUNDLE` pointed
at it. `device-auth.env` is still per-device and is never in the image.

## Two deviations from their installer, both required by a chroot

| flag | why |
|---|---|
| `--no-start` | `systemctl enable --now` fails in a chroot (`start` returns 5) and their installer runs under `set -e`, so it would abort. Their own flag enables without starting, which is what an image wants. |
| `SYSTEMD_OFFLINE=1` | the documented way to run `systemctl` in a chroot: `daemon-reload` becomes a no-op, `enable` still writes the symlink. |

`date -u -s "@BUILT_AT_EPOCH"` from `install-offline-package.sh` is **not**
carried over: inside a build chroot it would set the build host's clock.

Their `--no-start` branch enables `tailscaled` and nothing else, so the image
enables the units itself, reading the list from the bundle's own
`packaging/systemd`. A unit is enabled only if `/etc/systemd/system/<name>`
really exists -- no symlink to a missing file. A unit that *is* installed but
fails to enable **fails the build**: an image whose stack is installed but not
enabled boots and looks fine, and only fails in the field.
`caremojo-bt-select` (Intel 7265 only) is skipped, and
`caremojo-update.service` is enabled only through its timer -- enabling the
service directly would start an OTA during the build, and the timer owns the
schedule (see *OTA* below).

## OTA: the box does not stay on the bundle

The bundle decides what a box boots with, not what it runs for long.
`caremojo-update.timer` fires **about two minutes after boot**, then every
**15 minutes**, and `caremojo-update.service` pulls the latest `hub-stable` code
and applies it with a health check and automatic rollback.

Measured on a flashed box: right after the flash `INSTALLED_SHA` read
`b88fe1835408` (the bundle); the first timer run moved it to `99c3a9fb1228` and
installed that revision's own systemd units, boot MSC gate and
`caremojo-no-battery.conf`. A factory box therefore reaches `hub-stable` on its
first boot and does **not** stay on `p3-golden-1`.

Two consequences worth knowing:

- The bundle still matters: it is what the box runs before the first update,
  what it falls back to if an update rolls back, and the `offline/` cache the
  pip step and the OTA both use.
- The first boot can miss the run. The board has no RTC, so the clock starts at
  the build timestamp and jumps when NTP answers; on one boot here that jump was
  1h23m47s, past the `OnBootSec=2min` trigger point, and the timer sat at
  `NextElapse=infinity` for the rest of that boot. If a box comes up on an old
  SHA, `systemctl start caremojo-update.service` (start the service, not the
  timer) forces the run, and a reboot restores the schedule.

## What is added on top of the bundle

Their installer does not cover these; they exist because this is an Armbian
image, or because the approved bundle predates the fix:

| item | why |
|---|---|
| `usbstoragequirks=6675:3498:i` in `armbianEnv.txt` | their `install-msc-gate` writes it too; this only confirms it landed. A missing quirk on a docked band reaches into a watch's filesystem. |
| `20-usb-mount.rules` / `hubv3-usb-sync` not packaged | a docked watch is also a USB block device; the automount races READY/SETTIME and can reset the port. Removed at packaging time, so no unit and no udev trigger exist. |
| `33-ama-usb.rules` kept | matches only ThirdReality accessories (VID `31b6`), never the P1 dock (VID `6675`) |
| CareMojo branding (`VENDOR`, `/etc/issue`, `os-release`, `/etc/armbian.txt`) | the build framework sets `VENDOR="ThirdReality"`, which the boot banner and login prompt print |
| `/etc/t3r-release` | written per board name by the framework; without it the supervisor reports `Version v0.0.1` |
| supervisor `required_any_of` includes `watch-to-cloud.service` | the bundle ships none of the four units it expects (HA / zigbee2mqtt / matter2mqtt / openhab), so it declared the box `SYS_SYSTEM_CORRUPTED` and blinked the LED white |
| `BOARD=trhubv3` in `/etc/armbian-release` (the build board is still `trhubv3caremojo`) | two ThirdReality programs read `BOARD` and match `trhubv3` exactly: `/usr/local/bin/supervisor` for the device prefix (anything else falls to `default` = `3RCARE-`, the Care Hub prefix) and `/usr/lib/armbian/factory-reset.sh` `get_trhub_model()` (anything else takes the non-HubV3 branch). The hardware is a HubV3; `caremojo` is a software variant, and `VENDOR`, `os-release` and `t3r-release` already say so. Armbian's own scripts key on `BOARDFAMILY` (`trhub`) and `BOARD_NAME` (`TRHub-V3`), so they are unaffected. |
| `bluetoothd` without its battery plugin | newer than the bundle. iOS serves Battery Level only over a paired link; the plugin makes BlueZ ask to pair, pairing fails, the kernel drops the link and the Admin app's WiFi setup ends in "The hub dropped the connection". |

The BSP package is still `armbian-bsp-cli-trhubv3caremojo-current`, and reinstalling
it writes `BOARD=trhubv3caremojo` back. It has no apt source, so that only happens
by hand. After a manual reinstall, `sed -i 's/^BOARD=.*/BOARD=trhubv3/'
/etc/armbian-release` restores it.

## Open items

**`supervisor.service`** (ThirdReality HA/Zigbee/Thread supervisor) **is
installed and enabled**, exactly as on stock `hubv3` and as the partner asked.
It comes from `config/sources/families/trhub.conf` (`SUPERVISOR_VERSION`), which
this board inherits unchanged. Watch the memory headroom on ~1.9 GB RAM with both
stacks running.

The supervisor's backup path is `/mnt/R3Backup`, which only exists while a USB
stick is automounted -- and that automount is removed on this image. Backup and
restore through the supervisor's web UI therefore cannot work here.

**Factory reset** takes the HubV3 branch of `/usr/lib/armbian/factory-reset.sh`,
because the image reports `BOARD=trhubv3`. Run once on a CareMojo box (by
invoking the script directly, not through the reset button), it showed what that
branch actually does here:

| what | result |
|---|---|
| `thirdreality-*` packages | none installed, so `dpkg` removed nothing |
| `zigbee2mqtt` / `linuxbox-hubv3-bridge` | neither unit exists, both removals skip |
| `/opt/caremojo/audio-hub`, `/etc/caremojo/*`, `clients/.env.cloud` | **kept** |
| Tailscale login state | **kept** |
| `/var/lib/caremojo` | **kept** |
| NetworkManager connections | **all deleted** (`nmcli con delete` runs over every profile) |
| `caremojo-backup-wifi` profile (`set baryphone`, production line step 4) | expected to be deleted too, by the same command -- inferred from the script, not tested separately |
| `/var/lib/homeassistant/{homeassistant,matter_server}` | recreated empty |

Every CareMojo unit came back healthy after the reboot. So on a CareMojo box
**factory reset clears only the WiFi, and keeps the identity (`device-auth`),
the cloud config and the Tailscale state.** Whether that is the intended
behaviour is the partner's call, not this image's.

The `serial-getty@ttyAML0`, `apt-daily.timer` and `apt-daily-upgrade.timer`
units the script re-enables are **already enabled in the image** (their
`*.wants/` links are in the rootfs), so factory reset changes nothing there.
`apt-daily.service` and `unattended-upgrades.service` have no `[Install]`
section at all (they are static), so their `enable` is a no-op.

**Still untested: the reset button itself.** The script was run directly; the
button -> supervisor -> script path has not been exercised.

**Bluetooth `Opcode 0x2005 failed: -16`** (`EBUSY`) appears in the kernel log
about every 10 seconds -- 57 times in one boot. `0x2005` is LE Set Random
Address, and two of their units drive `hci0` at once: `caremojo-ble` keeps a
scan running while `caremojo-provision` advertises, so the controller is busy
when the address is set. It is log noise, not a fault: `hci0` reports
`UP RUNNING` with zero errors and `/run/caremojo-ble/status.json` shows
`scanning: true`. It does keep writing to the persistent journal.

## Factory flow (after the image is flashed)

Follow `docs/FACTORY_INSTALL.md` in the audio-hub repo, but **skip its Hub steps
1 and 2** -- those install the bundle from an SD/USB stick, which this image has
already done. Start at **step 3**:

1. ~~Build the offline bundle, copy it to a stick, mount it, `bash install.sh`~~
2. ~~`sha256sum -c SHA256SUMS` and run the installer on the box~~
3. **Check services:** `systemctl list-units 'caremojo-*' 'hub-*' 'watch-to-cloud'`
   -- all active, none failed.
4. **Backup WiFi:** `caremojo-backup-wifi set baryphone`.
5. **Cloud:** this bundle points at its own agency. For a different one, edit
   `clients/.env.cloud` and `systemctl restart watch-to-cloud`. OTA never touches
   that file.
6. **Identity:** two paths, both end at `/etc/caremojo/device-auth.env`:
   - as `FACTORY_INSTALL.md` describes -- generate it in the Portal repo with
     `node scripts/provision-device-identity.mjs …` and copy it to the box;
   - or let the first OTA land (see *OTA* above) and enrol over BLE with
     characteristic `ca12b004`, which `p3-golden-1` does not have.
   Then `systemctl restart watch-to-cloud`. Until this step is done,
   `watch-to-cloud` logs `per-Hub credentials not configured: docking only` on
   every start. That message is expected, not a fault -- the unit still does the
   docking half (READY, SETTIME, firmware).
7. Confirm a heartbeat in `hub_heartbeat` and `tailscale status`.
8. Label the box `Hub-NN` and its serial (first 8 of `cat /etc/machine-id`).

Steps 3-8 assume the box is on the network. On an image box the WiFi join and the
backend connection are done with the Admin app over BLE, which is what step 3
verifies.

### Do not run the USB installer on an image box

`install-offline-package.sh` refuses to install into a non-empty
`/opt/caremojo/audio-hub`:

```
refusing to overlay non-empty /opt/caremojo/audio-hub
```

That is correct behaviour, not a fault: the image already installed that bundle.
Re-running the stick installer on a flashed box does nothing useful. The way to
update an image box is the OTA timer (`caremojo-update.timer`, tracking
`hub-stable`) or a reflash.

### Do not source `factory-reset.sh` while inspecting it

`/usr/lib/armbian/factory-reset.sh` has **no `main` guard** -- loading it runs the
whole reset: it deletes NetworkManager connections, wipes the supervisor's
`backup/` and `archives/`, sets the LED white and reboots. Reading a function out
of it means extracting the body first, e.g.

```sh
sed -n '/^get_trhub_model/,/^}/p' /usr/lib/armbian/factory-reset.sh
```

and then reasoning about the input by hand. Never `source` it, never pipe it into
`bash` to "see what happens".
