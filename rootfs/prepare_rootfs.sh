#!/usr/bin/env bash
#
# Prepare Alpine rootfs for AOHP containers (Python + Node + aohp CLI).
#
# Usage:
#   ./prepare_rootfs.sh [arch] [--clean] [--cli-only]
#
# arch: x86_64 (default) or aarch64
#
# --clean     Remove cached rootfs workdir and rebuild from scratch.
# --cli-only  Only rebuild cli/aohp + copy into existing rootfs + repack tar (fast).
#
# Output: alpine.tar.gz in this directory.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Repo root must contain cli/aohp and scripts/ (do not rely on a fixed ../ depth:
# some trees have .../AOHP/AOSP/... and others .../AOSP/... under the same parent).
find_aohp_repo_root() {
  local dir="$SCRIPT_DIR"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/cli/aohp/package.json" ]] && [[ -f "$dir/scripts/build-cli.sh" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

if ! REPO_ROOT="$(find_aohp_repo_root)"; then
  echo "[prepare_rootfs] ERROR: cannot find AOHP repo root (need cli/aohp/package.json + scripts/build-cli.sh)." >&2
  echo "[prepare_rootfs] SCRIPT_DIR=$SCRIPT_DIR" >&2
  exit 1
fi
ARCH="x86_64"
CLEAN=false
CLI_ONLY=false

for a in "$@"; do
  case "$a" in
    --clean) CLEAN=true ;;
    --cli-only) CLI_ONLY=true ;;
    x86_64|aarch64) ARCH="$a" ;;
    *) echo "Unknown arg: $a" >&2; exit 1 ;;
  esac
done

ALPINE_VERSION="3.20"
ALPINE_RELEASE="3.20.0"
MIRROR="https://dl-cdn.alpinelinux.org/alpine"
ROOTFS_URL="${MIRROR}/v${ALPINE_VERSION}/releases/${ARCH}/alpine-minirootfs-${ALPINE_RELEASE}-${ARCH}.tar.gz"

WORK_BASE="${AOHP_ROOTFS_WORK:-$HOME/.cache/aohp-rootfs-work}"
WORK_DIR="${WORK_BASE}/${ARCH}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
DL_DIR="${WORK_DIR}/dl"
APK_CACHE="${HOME}/.cache/aohp-apk-cache"
OUTPUT="${SCRIPT_DIR}/alpine.tar.gz"

mkdir -p "$WORK_BASE" "$DL_DIR" "$APK_CACHE"

echo "[prepare_rootfs] REPO_ROOT=${REPO_ROOT}"
echo "[prepare_rootfs] ARCH=${ARCH} WORK_DIR=${WORK_DIR}"

embed_cli() {
  bash "${REPO_ROOT}/scripts/build-cli.sh"
  local src="${REPO_ROOT}/cli/aohp/dist/aohp.js"
  if [[ ! -f "$src" ]]; then
    echo "Missing $src — build-cli failed?" >&2
    exit 1
  fi
  sudo mkdir -p "${ROOTFS_DIR}/usr/local/bin"
  sudo cp "$src" "${ROOTFS_DIR}/usr/local/bin/aohp"
  sudo chmod 755 "${ROOTFS_DIR}/usr/local/bin/aohp"
}

repack() {
  echo "=== Packing rootfs template ==="
  (cd "${ROOTFS_DIR}" && sudo tar czf "${OUTPUT}" .)
  ls -lh "${OUTPUT}"
}

if [[ "$CLEAN" == true ]]; then
  echo "=== --clean: removing ${WORK_DIR} ==="
  sudo rm -rf "${WORK_DIR}"
fi

if [[ "$CLI_ONLY" == true ]]; then
  if [[ ! -d "${ROOTFS_DIR}/usr" ]]; then
    echo "--cli-only requires existing rootfs at ${ROOTFS_DIR}; run full build first" >&2
    exit 1
  fi
  embed_cli
  repack
  echo "=== Done (cli-only) ==="
  exit 0
fi

# Fast path: existing rootfs already has Node — refresh CLI only + repack
if [[ -d "${ROOTFS_DIR}/usr" ]] && [[ -x "${ROOTFS_DIR}/usr/bin/node" || -x "${ROOTFS_DIR}/usr/local/bin/node" ]]; then
  echo "=== Incremental: embedding CLI + repack (skip apk/chroot) ==="
  embed_cli
  repack
  echo "=== Done (incremental) ==="
  exit 0
fi

echo "=== Downloading Alpine minirootfs (${ARCH}) ==="
mkdir -p "${ROOTFS_DIR}"
TAR="${DL_DIR}/alpine-minirootfs-${ALPINE_RELEASE}-${ARCH}.tar.gz"
if [[ ! -f "$TAR" ]]; then
  wget -q -O "$TAR" "${ROOTFS_URL}"
fi
sudo tar xzf "$TAR" -C "${ROOTFS_DIR}"

echo "=== Configuring DNS ==="
echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" | sudo tee "${ROOTFS_DIR}/etc/resolv.conf" >/dev/null

sudo mkdir -p "${ROOTFS_DIR}/etc/apk/cache"
sudo mount --bind "${APK_CACHE}" "${ROOTFS_DIR}/etc/apk/cache"

cleanup_mounts() {
  sudo umount "${ROOTFS_DIR}/etc/apk/cache" 2>/dev/null || true
  sudo umount "${ROOTFS_DIR}/sys" 2>/dev/null || true
  sudo umount "${ROOTFS_DIR}/dev" 2>/dev/null || true
  sudo umount "${ROOTFS_DIR}/proc" 2>/dev/null || true
}
trap cleanup_mounts EXIT

sudo mount --bind /proc "${ROOTFS_DIR}/proc"
sudo mount --bind /dev "${ROOTFS_DIR}/dev"
sudo mount --bind /sys "${ROOTFS_DIR}/sys"

echo "=== Installing packages via chroot ==="
sudo chroot "${ROOTFS_DIR}" /bin/sh -c "
    set -e
    apk update
    apk add --no-cache python3 py3-pip nodejs
    ln -sf /usr/bin/python3 /usr/bin/python || true
    ln -sf /usr/bin/pip3 /usr/bin/pip || true
    rm -rf /var/cache/apk/*
    echo 'Python:' && python3 --version
    echo 'Node:' && node --version
"

cleanup_mounts
trap - EXIT

echo "=== Creating mount points ==="
sudo mkdir -p "${ROOTFS_DIR}/sdcard" "${ROOTFS_DIR}/tmp"
sudo chmod 1777 "${ROOTFS_DIR}/tmp"

embed_cli
repack

echo "=== Done ==="
echo "Output: ${OUTPUT}"
echo "Copy is not needed — AOHP build uses this path as prebuilt source."
