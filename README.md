Raspberry Vanilla AOSP 15 device configuration for Raspberry Pi 4.

---

## This fork: 1GB-RAM Pi 4 boot fixes + SD/USB boot variants

Fork of raspberry-vanilla's `android_device_brcm_rpi4` (`android-15.0` /
`android-15.0.0_r20`), targeting a physical **1GB-RAM launch-batch Raspberry Pi 4**
running the Automotive OS build (`aosp_rpi4_car`) — below this project's documented
2GB minimum, which was the root cause of most of the boot instability fixed here.

Not a self-contained checkout: like upstream, this repo is one project synced by
`repo` inside a full AOSP tree, not something you can `git clone` and build standalone.
See `scripts/bootstrap.sh` below to assemble that tree.

### Branches

- **`android-15.0-rpi4-1gb-microsd`** — base branch. Boot-reliability fixes only,
  confirmed booting to a fully working CarLauncher UI on physical hardware:
  - CMA/GPU memory carve-out shrunk from 512MiB to 256MiB (`boot/config.txt`),
    freeing usable RAM from ~377MB to ~633MB.
  - VHAL re-enabled (CarService has a structural dependency on it) + a matching
    `packages/services/Car` patch (see `patches/`) for a null-pointer race that
    surfaces once VHAL is live.
  - zram (RAM-backed compressed swap, not disk-backed — disk I/O contention was
    the diagnosed bottleneck) plus `ro.hw_timeout_multiplier=3` so slow cold
    starts (SystemUI, MediaProvider) stop getting killed/retried by
    `ActivityManagerService`.
  - Boot media: original hardcoded `/dev/block/mmcblk0pN` paths + MBR/fdisk
    partitioning — SD/eMMC only.

- **`android-15.0-rpi4-1gb-usb`** — built on top of the branch above. Adds
  boot-media-agnostic partitioning so the same image can also boot from a
  USB-attached SSD (expected to help further given SD card I/O was already a
  bottleneck): GPT partitioning (`sgdisk`) with named partitions, `/dev/block/by-name/*`
  mounts in `fstab.rpi4`, and `androidboot.boot_devices=` on the kernel cmdline so
  first-stage init finds the partitions regardless of enumeration order.
  **Status: not yet confirmed booting end-to-end from USB** — in progress.

### `packages/services/Car` patch

The VHAL null-pointer fix lives in AOSP's own `packages/services/Car` tree, not in
this repo (forking that whole tree isn't practical for one patch). `patches/` here
carries it as a plain patch file — `scripts/bootstrap.sh` applies it automatically
after `repo sync`; apply it by hand otherwise:

```bash
git -C packages/services/Car apply /path/to/this/repo/patches/0001-carwatchdogd-fix-null-vhal-heartbeat-race.patch
```

### Reclone / rebuild from scratch

```bash
GITHUB_USER=<your-github-username> BOOT_VARIANT=microsd ./scripts/bootstrap.sh ~/android
# or BOOT_VARIANT=usb for the USB-boot branch
```

This does `repo init` against the upstream AOSP `android-15.0.0_r20` manifest, drops
in a local manifest that swaps `device/brcm/rpi4` for this fork/branch (everything
else stays pointed at raspberry-vanilla, same as upstream's own
`android_local_manifest`), `repo sync`s, applies the Car patch, and lunches
`aosp_rpi4_car-ap3a-userdebug`. From there:

```bash
make bootimage systemimage vendorimage -j$(nproc)   # only rebuild what actually changed
./rpi4-mkimg.sh   # packages the flashable image; needs sudo, run interactively
```

`ap3a` is the correct lunch release config for this pinned tag — not `trunk_staging`
(resolves to a later Android codename this tag doesn't match).
