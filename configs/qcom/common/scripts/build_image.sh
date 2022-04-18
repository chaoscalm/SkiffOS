#!/bin/bash

if [ $EUID != 0 ]; then
    echo "This script requires sudo, so it might not work."
fi

set -e

if [ -z "$QCOM_IMAGE" ]; then
    echo "Please set QCOM_IMAGE to the path to the output image."
    exit 1
fi

if [[ "$QCOM_IMAGE" != /* ]]; then
    # the "make" command is run from the skiff root,
    # it's most intuitive to take that as the base path
    QCOM_IMAGE=$SKIFF_ROOT_DIR/$QCOM_IMAGE
fi

echo "Allocating sparse image..."
fallocate -l 1G $QCOM_IMAGE

echo "Setting up loopback device..."
export QCOM_SD=$(losetup --show -fP $QCOM_IMAGE)
function cleanup {
  echo "Removing loopback device..." || true
  sync || true
  losetup -d $QCOM_SD || true
}
trap cleanup EXIT

if [ -z "${QCOM_SD}" ] || [ ! -b ${QCOM_SD} ]; then
    echo "Failed to setup loop device."
    exit 1
fi

# Setup no interactive since we know its a brand new file.
export SKIFF_NO_INTERACTIVE=1

echo "Using loopback device at ${QCOM_SD}"
$SKIFF_CURRENT_CONF_DIR/scripts/format_sd.sh
$SKIFF_CURRENT_CONF_DIR/scripts/install_sd.sh

