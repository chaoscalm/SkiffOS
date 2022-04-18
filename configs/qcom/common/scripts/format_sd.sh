#!/bin/bash
set -e

if [ $EUID != 0 ]; then
  echo "This script requires sudo, so it might not work."
fi

if ! sudo parted -h > /dev/null; then
  echo "Please install 'parted' and try again."
  exit 1
fi

if ! command -v mkfs.vfat >/dev/null 2>&1; then
  echo "Please install 'mkfs.vfat' (usually dosfstools) and try again."
  exit 1
fi

if [ -z "$QCOM_SD" ]; then
  echo "Please set QCOM_SD and try again."
  exit 1
fi

if [ ! -b "$QCOM_SD" ]; then
  echo "$QCOM_SD is not a block device or doesn't exist."
  exit 1
fi

resources_path="${SKIFF_CURRENT_CONF_DIR}/resources"
ubootimg="$BUILDROOT_DIR/output/images/u-boot-signed.bin.sd.bin"
ubootimga="$BUILDROOT_DIR/output/images/u-boot-sunxi-with-spl.bin"
ubootimgb="$BUILDROOT_DIR/output/images/u-boot-dtb.bin"
ubootimgc="$BUILDROOT_DIR/output/images/u-boot.bin"
ubootscripts="${BUILDROOT_DIR}/output/images/hk_sd_fuse/"
sd_fuse_scr="${ubootscripts}/sd_fusing.sh"

if [ ! -f "$sd_fuse_scr" ]; then
  echo "Cannot find $sd_fuse_scr, make sure Buildroot is compiled."
  exit 1
fi

if [ ! -f "$ubootimg" ]; then
  ubootimg=$ubootimga
fi

if [ ! -f "$ubootimg" ]; then
  ubootimg=$ubootimgb
fi

if [ ! -f "$ubootimg" ]; then
  ubootimg=$ubootimgc
fi

if [ ! -f "$ubootimg" ]; then
  echo "can't find u-boot image at $ubootimg"
  exit 1
fi

if [ -z "$SKIFF_NO_INTERACTIVE" ]; then
  read -p "Are you sure? This will completely destroy all data. [y/N] " -n 1 -r
  echo
  if ! [[ $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

if [ -z "$SKIFF_NO_INTERACTIVE" ]; then
  read -p "Verify that '$QCOM_SD' is the correct device. Be sure. [y/N] " -n 1 -r
  echo
  if ! [[ $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

MKEXT4="mkfs.ext4 -F -O ^64bit"

set -x
set -e

echo "Formatting device..."
sudo dd if=/dev/zero of=$QCOM_SD bs=8k count=13 oflag=dsync

echo "Creating partitions..."
sudo partprobe ${QCOM_SD} || true

sudo parted $QCOM_SD mklabel msdos

# boot
sudo parted -a optimal $QCOM_SD mkpart primary fat32 2MiB 310MiB
sudo parted $QCOM_SD set 1 boot on

# rootfs
sudo parted -a optimal $QCOM_SD mkpart primary ext4 310MiB 600MiB

# persist
sudo parted -a optimal $QCOM_SD -- mkpart primary ext4 600MiB "100%"

echo "Waiting for partprobe..."
sync && sync
partprobe $QCOM_SD || true
sleep 2
partprobe $QCOM_SD || true

QCOM_SD_SFX=$QCOM_SD
if [ -b ${QCOM_SD}p1 ]; then
  QCOM_SD_SFX=${QCOM_SD}p
fi

if [ ! -b ${QCOM_SD_SFX}1 ]; then
    echo "Warning: it appears your kernel has not created partition files at ${QCOM_SD_SFX}."
fi

echo "Formatting boot partition..."
mkfs.vfat -F 32 ${QCOM_SD_SFX}1
fatlabel ${QCOM_SD_SFX}1 boot

echo "Formatting rootfs partition..."
$MKEXT4 -L "rootfs" ${QCOM_SD_SFX}2

echo "Formatting persist partition..."
$MKEXT4 -L "persist" ${QCOM_SD_SFX}3

sync && sync

echo "Flashing u-boot..."
cd $ubootscripts
bash ./sd_fusing.sh $QCOM_SD $ubootimg
cd -
