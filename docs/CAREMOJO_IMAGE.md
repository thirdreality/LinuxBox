# CareMojo partner image (`hubv3caremojo`)

A TRHub-V3 image with the CareMojo watch-offload stack baked in, so a factory
box needs no SD/USB bundle, no serial session and no hand-run `install.sh`.
Same hardware, same kernel, same U-Boot as `hubv3`; only the rootfs payload
differs.

## Build

```sh
# on an x86-64 Linux builder with docker
CARE_MOJO_TOKEN=<read-only PAT for peakmojo/audio-hub> \
  ./make-armbian-build-release.sh -b hubv3caremojo -d us -r v2.14.01.55
```

Output: `output/images/thirdreality_hubv3caremojo_armbian_24.11_bookworm_<kernel>_<rev>.burn.img.zip`,
flashed with the Amlogic USB Burning Tool (same as `hubv3`).

### Where the CareMojo source comes from

`userpatches/customize-image-host.sh` runs on the build host:

| cache state | action |
|---|---|
| `cache/sources/audio-hub/.git` missing | `git clone --depth 1 --branch $CARE_MOJO_REF` |
| present | `git fetch --depth 1` + `checkout FETCH_HEAD` (update in place) |

| variable | default | meaning |
|---|---|---|
| `CARE_MOJO_REF` | `hub-stable` | the tag Hubs track; never `main` |
| `CARE_MOJO_TOKEN` | — | read-only PAT; makes the private clone work over HTTPS with no SSH agent |
| `CARE_MOJO_CACHE` | `$SRC/cache/sources/audio-hub` | where the clone lives |
| `CARE_MOJO_REPO` | `git@github.com:peakmojo/audio-hub.git` | used when no token is set |

The resolved commit is written to `/home/caremojo/audio-hub/.caremojo-build-ref`
inside the image, so a fielded box can be traced back to an exact audio-hub
commit.

Files copied: `packaging/` and `clients/` (everything a box runs).
Excluded: `gateway/`, `migrations/`, `cloud/`, `tools/`, `tests/`, `docs/`,
`deid/`, `data/`, `.git`, `venv`, `offline/`, and every `.env*` / `device-auth.env`.

## What ends up in the image

| path | contents |
|---|---|
| `/home/caremojo/audio-hub` | the tree above, owned by `caremojo` |
| `/etc/systemd/system/` | 13 CareMojo units + `run-caremojo\x2dwatch.mount`, enabled (not started) |
| `/etc/systemd/system/bluetooth.service.d/caremojo-no-battery.conf` | bluetoothd without the battery plugin |
| `/etc/systemd/journald.conf.d/20-caremojo-persistent.conf` | persistent journal |
| `/etc/udev/rules.d/99-caremojo-thirdreality-p1.rules` | P1 CDC/MSC device permissions |
| `/etc/udev/rules.d/20-usb-mount.rules.caremojo-disabled` | the base image's automount, renamed (recoverable) |
| `/etc/sudoers.d/caremojo-msc-remount` | the one command the service user may run as root |
| `/usr/local/sbin/caremojo-msc-attach`, `caremojo-backup-wifi` | USB remount helper, backup-WiFi helper |
| `/opt/caremojo/update.sh` | OTA updater, outside the app tree |
| `/var/lib/caremojo/{queue,device-archive,watch-events,hub-audio/RECORD}` | runtime state, `caremojo:caremojo 0750` |
| `/boot/armbianEnv.txt` | `usbstoragequirks=…,6675:3498:i` |
| user/group | `caremojo` (system, nologin), in `dialout`, `audio`, `plugdev` |

`hubv3-usb-sync.service` is masked, and `caremojo-bt-select.service` (Intel
7265 only) is not installed.

## What is deliberately NOT in the image

No credentials. The box boots unclaimed and keeps running; these are injected
at the factory:

| file | how |
|---|---|
| `/etc/caremojo/device-auth.env` | Admin app ENROLL (`CA12B004`), or the offline bundle |
| `clients/.env.cloud` | per-agency cloud config, or edited on the box |
| `/etc/caremojo/tailscale-authkey` | factory provisioning |
| `/etc/caremojo/github-token` | factory provisioning; without it OTA no-ops |

## Differences from `packaging/hub/install.sh`

Baking removes several runtime steps that only exist because a stock box had to
be converted in place:

| stock `install.sh` | image |
|---|---|
| mask `hubv3-usb-sync`, rename `20-usb-mount.rules` at runtime | done at build time, no window where both run |
| `install-msc-gate` remounts `/boot` read-write, edits, restores | `armbianEnv.txt` written directly; `install-msc-gate` not needed |
| `sed`-templates `/home/caremojo/audio-hub` into each unit | units are byte-identical to upstream |
| offline `apt`/`pip` from `offline/` | packages come from `PACKAGE_LIST_BOARD`; no Hub service runs Python |
| starts services at the end of the install | units are enabled only; the factory power-on is the first start |

## Open item

**`supervisor.service`** (ThirdReality HA/Zigbee/Thread supervisor) is still
installed and enabled by `config/sources/families/trhub.conf`, as on stock
`hubv3`. The CareMojo stack does not use it. On ~1.9 GB RAM it is a candidate
for removal; this image keeps it until the partner confirms, then flip
`CARE_MOJO_KEEP_SUPERVISOR` in `trhub.conf`.

## Factory flow (after the image is flashed)

1. Flash `burn.img`, power from the original adapter (never a USB cable).
2. On power-on the box advertises over BLE, unclaimed, nothing recorded.
3. Admin app: join WiFi, then ENROLL against the agency backend.
4. Register `Hub-NN` in the agency inventory, stage its identity.
5. `tools/assign_hub.sh` at the home claims it and sets the room.

Details: `docs/FACTORY_INSTALL.md` in the audio-hub repo.
