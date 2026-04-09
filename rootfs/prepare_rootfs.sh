#!/bin/bash
#
# Prepare an Alpine Linux rootfs with Python pre-installed for AOHP containers.
#
# Usage:
#   ./prepare_rootfs.sh [arch]
#
# arch: x86_64 (default, for Cuttlefish) or aarch64 (for ARM devices)
#
# Output: alpine.tar.gz in the current directory.
#
# Prerequisites: tar, wget (or curl), and optionally qemu-user-static for
#                cross-arch chroot.

set -euo pipefail

ARCH="${1:-x86_64}"
ALPINE_VERSION="3.20"
ALPINE_RELEASE="3.20.0"
MIRROR="https://dl-cdn.alpinelinux.org/alpine"

ROOTFS_URL="${MIRROR}/v${ALPINE_VERSION}/releases/${ARCH}/alpine-minirootfs-${ALPINE_RELEASE}-${ARCH}.tar.gz"
WORK_DIR="$(mktemp -d)"
ROOTFS_DIR="${WORK_DIR}/rootfs"

cleanup() {
    echo "Cleaning up ${WORK_DIR}..."
    sudo rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "=== Downloading Alpine Linux minirootfs (${ARCH}) ==="
mkdir -p "${ROOTFS_DIR}"
wget -q -O "${WORK_DIR}/alpine.tar.gz" "${ROOTFS_URL}"
tar xzf "${WORK_DIR}/alpine.tar.gz" -C "${ROOTFS_DIR}"

echo "=== Configuring DNS ==="
echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" > "${ROOTFS_DIR}/etc/resolv.conf"

echo "=== Installing Python via chroot ==="
# If cross-arch, you'd need qemu-user-static registered with binfmt_misc.
sudo mount --bind /proc "${ROOTFS_DIR}/proc"
sudo mount --bind /dev "${ROOTFS_DIR}/dev"
sudo mount --bind /sys "${ROOTFS_DIR}/sys"

sudo chroot "${ROOTFS_DIR}" /bin/sh -c "
    apk update
    apk add python3 py3-pip
    # Create a symlink so 'python' works as well.
    ln -sf /usr/bin/python3 /usr/bin/python
    ln -sf /usr/bin/pip3 /usr/bin/pip
    # Clean package cache to save space.
    rm -rf /var/cache/apk/*
    echo 'Python installed successfully:'
    python3 --version
    pip3 --version
"

sudo umount "${ROOTFS_DIR}/sys" || true
sudo umount "${ROOTFS_DIR}/dev" || true
sudo umount "${ROOTFS_DIR}/proc" || true

echo "=== Creating mount point directories ==="
mkdir -p "${ROOTFS_DIR}/sdcard"
mkdir -p "${ROOTFS_DIR}/tmp"
chmod 1777 "${ROOTFS_DIR}/tmp"

echo "=== Packing rootfs template ==="
OUTPUT="$(pwd)/alpine.tar.gz"
(cd "${ROOTFS_DIR}" && sudo tar czf "${OUTPUT}" .)

echo "=== Done ==="
echo "Output: ${OUTPUT}"
ls -lh "${OUTPUT}"
echo ""
echo "Copy this file to:"
echo "  AOSP/packages/apps/AOHPAgentDriver/rootfs/alpine.tar.gz"
