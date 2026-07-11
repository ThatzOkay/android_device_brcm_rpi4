#!/bin/bash

#
# Copyright (C) 2021-2022 KonstaKANG
#
# SPDX-License-Identifier: Apache-2.0
#

exit_with_error() {
  echo $@
  exit 1
}

if [ -z ${TARGET_PRODUCT} ]; then
  exit_with_error "TARGET_PRODUCT environment variable is not set. Run lunch first."
fi

if [ -z ${ANDROID_PRODUCT_OUT} ]; then
  exit_with_error "ANDROID_PRODUCT_OUT environment variable is not set. Run lunch first."
fi

for PARTITION in "boot" "system" "vendor"; do
  if [ ! -f ${ANDROID_PRODUCT_OUT}/${PARTITION}.img ]; then
    exit_with_error "Partition image not found. Run 'make ${PARTITION}image' first."
  fi
done

VERSION=RaspberryVanillaAOSP15
DATE=$(date +%Y%m%d)
TARGET=$(echo ${TARGET_PRODUCT} | sed 's/^aosp_//')
IMGNAME=${VERSION}-${DATE}-${TARGET}.img
IMGSIZE=15360000000

BOOT_PARTITION_SIZE=128
SYSTEM_PARTITION_SIZE=3072
VENDOR_PARTITION_SIZE=384
METADATA_PARTITION_SIZE=16

if [ -f ${ANDROID_PRODUCT_OUT}/${IMGNAME} ]; then
  exit_with_error "${ANDROID_PRODUCT_OUT}/${IMGNAME} already exists!"
fi

echo "Creating image file ${ANDROID_PRODUCT_OUT}/${IMGNAME}..."
sudo fallocate -l ${IMGSIZE} ${ANDROID_PRODUCT_OUT}/${IMGNAME}
sync

echo "Creating partitions..."
# GPT partitioning (sgdisk), keeping the same partition NUMBERS the rest of
# this script (and wrimg.sh) already assume: 1=boot, 5=system, 6=vendor,
# 7=metadata, 3=userdata. GPT doesn't need an extended-partition container or
# contiguous numbering, so partition 2/4 are simply left unused. Each
# partition is also given a GPT NAME (-c) matching what ramdisk/fstab.rpi4
# references via /dev/block/by-name/<name>, so first-stage init can find the
# right partition regardless of whether it enumerates as mmcblk0pN (SD/eMMC)
# or sdaN (USB SSD) -- see androidboot.boot_devices in BoardConfig.mk.
# Partition 1 is typed EFI System (ef00) since it's a FAT32 filesystem (see
# wrimg.sh) read directly by the RPi4 firmware; RPi4 EEPROM firmware accepts
# either "Microsoft basic data" or "EFI system partition" for this. The
# other partitions keep sgdisk's default Linux filesystem type (8300),
# matching fdisk's previous default (0x83) for the same partitions.
sudo sgdisk -o \
  -n 1:0:+${BOOT_PARTITION_SIZE}M -t 1:ef00 -c 1:boot \
  -n 5:0:+${SYSTEM_PARTITION_SIZE}M -c 5:system \
  -n 6:0:+${VENDOR_PARTITION_SIZE}M -c 6:vendor \
  -n 7:0:+${METADATA_PARTITION_SIZE}M -c 7:metadata \
  -n 3:0:0 -c 3:userdata \
  ${ANDROID_PRODUCT_OUT}/${IMGNAME}
sync

LOOPDEV=$(sudo kpartx -av ${ANDROID_PRODUCT_OUT}/${IMGNAME} | awk 'NR==1{ sub(/p[0-9]$/, "", $3); print $3 }')
if [ -z ${LOOPDEV} ]; then
  exit_with_error "Unable to find loop device!"
fi
echo "Image mounted as /dev/${LOOPDEV}"
sleep 1

echo "Copying boot..."
sudo dd if=${ANDROID_PRODUCT_OUT}/boot.img of=/dev/mapper/${LOOPDEV}p1 bs=1M
echo "Copying system..."
sudo dd if=${ANDROID_PRODUCT_OUT}/system.img of=/dev/mapper/${LOOPDEV}p5 bs=1M
echo "Copying vendor..."
sudo dd if=${ANDROID_PRODUCT_OUT}/vendor.img of=/dev/mapper/${LOOPDEV}p6 bs=1M
echo "Creating metadata..."
sudo mkfs.ext4 /dev/mapper/${LOOPDEV}p7 -I 512 -L metadata
echo "Creating userdata..."
sudo mkfs.ext4 /dev/mapper/${LOOPDEV}p3 -I 512 -L userdata
sync

sudo kpartx -d "/dev/${LOOPDEV}"
sudo losetup -d "/dev/${LOOPDEV}"
sudo chown ${USER}:${USER} ${ANDROID_PRODUCT_OUT}/${IMGNAME}

echo "Done, created ${ANDROID_PRODUCT_OUT}/${IMGNAME}!"
exit 0
