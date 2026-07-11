#!/usr/bin/env bash
# Bootstraps a fresh AOSP tree around this fork of raspberry-vanilla's
# android_device_brcm_rpi4, and lunches the Automotive target.
#
# Usage:
#   GITHUB_USER=youruser BOOT_VARIANT=microsd ./bootstrap.sh /path/to/android
#   GITHUB_USER=youruser BOOT_VARIANT=usb     ./bootstrap.sh /path/to/android
#
# BOOT_VARIANT selects which branch of this fork device/brcm/rpi4 is synced
# at: android-15.0-rpi4-1gb-microsd or android-15.0-rpi4-1gb-usb.
set -euo pipefail

GITHUB_USER="${GITHUB_USER:?Set GITHUB_USER=<your GitHub username>}"
BOOT_VARIANT="${BOOT_VARIANT:-microsd}"
TREE_DIR="${1:?Usage: GITHUB_USER=... BOOT_VARIANT=microsd|usb $0 /path/to/android}"

case "$BOOT_VARIANT" in
  microsd) BRANCH="android-15.0-rpi4-1gb-microsd" ;;
  usb)     BRANCH="android-15.0-rpi4-1gb-usb" ;;
  *) echo "BOOT_VARIANT must be 'microsd' or 'usb', got: $BOOT_VARIANT" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

mkdir -p "$TREE_DIR"
cd "$TREE_DIR"
TREE_DIR="$(pwd)"

echo "==> repo init (android-15.0.0_r20, ap3a release config)"
repo init -u https://android.googlesource.com/platform/manifest -b android-15.0.0_r20

mkdir -p .repo/local_manifests
sed -e "s/YOUR_GITHUB_USERNAME/${GITHUB_USER}/" -e "s/BOOT_VARIANT_BRANCH/${BRANCH}/" \
  "$REPO_ROOT/local_manifests/manifest_brcm_rpi.xml" > .repo/local_manifests/manifest_brcm_rpi.xml
cp "$REPO_ROOT/local_manifests/remove_projects.xml" .repo/local_manifests/remove_projects.xml

echo "==> repo sync (this takes a while)"
repo sync -c -j"$(nproc)"

echo "==> applying packages/services/Car watchdog patch"
git -C packages/services/Car apply \
  "${TREE_DIR}/device/brcm/rpi4/patches/0001-carwatchdogd-fix-null-vhal-heartbeat-race.patch"

echo "==> lunch aosp_rpi4_car-ap3a-userdebug"
source build/envsetup.sh
lunch aosp_rpi4_car-ap3a-userdebug

echo "==> ready. Build with: make bootimage systemimage vendorimage -j\$(nproc)"
echo "==> package the flashable image with: ./rpi4-mkimg.sh (needs sudo, run interactively)"
