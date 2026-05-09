#!/usr/bin/env bash
#
# Prepare Alpine rootfs for AOHP containers (Python + Node 24 + aohp CLI + OpenClaw).
#
# Usage:
#   ./prepare_rootfs.sh [arch] [--clean] [--cli-only]
#
# arch: x86_64 (default) or aarch64
#
# --clean     Remove cached rootfs workdir and rebuild from scratch.
# --cli-only  Fast path: rebuild cli/aohp + refresh skills / openclaw-config
#             in the existing rootfs + repack tar. Skips Node / openclaw install.
#
# Output: alpine.tar.gz in this directory.
#
# Env overrides:
#   AOHP_NODE_VERSION   Node release tag to install (default v24.9.0).
#                       Bump when a newer 24.x LTS is desired.
#   AOHP_ROOTFS_WORK    Rootfs workdir base (default ~/.cache/aohp-rootfs-work).
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

# Node 24 LTS (musl build) from unofficial-builds.nodejs.org — ships with npm.
NODE_VERSION="${AOHP_NODE_VERSION:-v24.9.0}"
case "$ARCH" in
  x86_64)  NODE_ARCH="x64" ;;
  aarch64) NODE_ARCH="arm64" ;;
esac
NODE_URL="https://unofficial-builds.nodejs.org/download/release/${NODE_VERSION}/node-${NODE_VERSION}-linux-${NODE_ARCH}-musl.tar.xz"

WORK_BASE="${AOHP_ROOTFS_WORK:-$HOME/.cache/aohp-rootfs-work}"
WORK_DIR="${WORK_BASE}/${ARCH}"
ROOTFS_DIR="${WORK_DIR}/rootfs"
DL_DIR="${WORK_DIR}/dl"
APK_CACHE="${HOME}/.cache/aohp-apk-cache"
NODE_CACHE="${HOME}/.cache/aohp-node-cache"
OUTPUT="${SCRIPT_DIR}/alpine.tar.gz"

mkdir -p "$WORK_BASE" "$DL_DIR" "$APK_CACHE" "$NODE_CACHE"

echo "[prepare_rootfs] REPO_ROOT=${REPO_ROOT}"
echo "[prepare_rootfs] ARCH=${ARCH} WORK_DIR=${WORK_DIR}"
echo "[prepare_rootfs] NODE_VERSION=${NODE_VERSION}"

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

embed_skills() {
  local src="${REPO_ROOT}/skills"
  if [[ ! -d "$src" ]]; then
    echo "[prepare_rootfs] no skills/ at repo root; skipping" >&2
    return 0
  fi
  sudo rm -rf "${ROOTFS_DIR}/opt/aohp-skills"
  sudo mkdir -p "${ROOTFS_DIR}/opt/aohp-skills"
  sudo cp -a "$src/." "${ROOTFS_DIR}/opt/aohp-skills/"
  echo "[prepare_rootfs] embedded skills from ${src}"
}

embed_openclaw_config() {
  local src="${REPO_ROOT}/openclaw-config"
  sudo rm -rf "${ROOTFS_DIR}/root/.openclaw"
  sudo mkdir -p "${ROOTFS_DIR}/root/.openclaw"
  if [[ -d "$src" && -f "$src/openclaw.json" ]]; then
    sudo cp -a "$src/." "${ROOTFS_DIR}/root/.openclaw/"
    echo "[prepare_rootfs] embedded openclaw-config from ${src}"
  else
    echo "[prepare_rootfs] no openclaw-config/openclaw.json; writing minimal default"
  fi

  # Normalize openclaw.json: rewrite Mac home paths, ensure workspace and
  # skills.load.extraDirs are set. Uses host python3 — written file is valid JSON.
  sudo python3 - "${ROOTFS_DIR}/root/.openclaw/openclaw.json" <<'PY'
import json, os, re, sys
p = sys.argv[1]
if os.path.exists(p):
    with open(p) as f:
        cfg = json.load(f)
else:
    cfg = {}

def rewrite(v):
    if isinstance(v, str):
        return re.sub(r"/Users/[^/]+/\.openclaw", "/root/.openclaw", v)
    if isinstance(v, list):
        return [rewrite(x) for x in v]
    if isinstance(v, dict):
        return {k: rewrite(x) for k, x in v.items()}
    return v

cfg = rewrite(cfg)
cfg.setdefault("agents", {}).setdefault("defaults", {}).setdefault(
    "workspace", "/root/.openclaw/workspace"
)
primary = cfg.get("agents", {}).get("defaults", {}).get("model", {}).get("primary")
if isinstance(primary, str) and "/" in primary:
    provider_id, model_id = primary.split("/", 1)
    provider = cfg.setdefault("models", {}).setdefault("providers", {}).get(provider_id)
    if isinstance(provider, dict) and isinstance(provider.get("models"), list):
        for model in provider["models"]:
            if isinstance(model, dict) and model.get("id") == model_id:
                model["contextWindow"] = 256000
                model["maxTokens"] = 32000
                if "image" in model.get("input", []):
                    cfg.setdefault("agents", {}).setdefault("defaults", {}).setdefault("imageModel", primary)
extra = cfg.setdefault("skills", {}).setdefault("load", {}).setdefault("extraDirs", [])
if "/opt/aohp-skills" not in extra:
    extra.append("/opt/aohp-skills")

with open(p, "w") as f:
    json.dump(cfg, f, indent=2)
PY

  sudo mkdir -p "${ROOTFS_DIR}/root/.openclaw/workspace"
  sudo chmod -R u+rwX,go-rwx "${ROOTFS_DIR}/root/.openclaw"
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
  embed_skills
  embed_openclaw_config
  repack
  echo "=== Done (cli-only) ==="
  exit 0
fi

# Fast path: rootfs already has Node 24 + openclaw installed → refresh embeds + repack.
if [[ -d "${ROOTFS_DIR}/usr" ]] \
   && [[ -x "${ROOTFS_DIR}/usr/local/bin/node" ]] \
   && [[ -d "${ROOTFS_DIR}/usr/local/lib/node_modules/openclaw" ]]; then
  echo "=== Incremental: embedding CLI + skills + openclaw-config (skip apk/chroot) ==="
  embed_cli
  embed_skills
  embed_openclaw_config
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

echo "=== Downloading Node ${NODE_VERSION} (${NODE_ARCH}-musl) ==="
NODE_TAR="${NODE_CACHE}/node-${NODE_VERSION}-linux-${NODE_ARCH}-musl.tar.xz"
if [[ ! -f "$NODE_TAR" ]]; then
  wget -q -O "$NODE_TAR" "${NODE_URL}" || {
    echo "[prepare_rootfs] ERROR: failed to download ${NODE_URL}" >&2
    echo "[prepare_rootfs] Check AOHP_NODE_VERSION is a real release on unofficial-builds.nodejs.org" >&2
    exit 1
  }
fi

echo "=== Installing Node into rootfs /usr/local ==="
sudo mkdir -p "${ROOTFS_DIR}/usr/local"
sudo tar xJf "$NODE_TAR" -C "${ROOTFS_DIR}/usr/local" --strip-components=1

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

echo "=== Installing packages + openclaw via chroot ==="
sudo chroot "${ROOTFS_DIR}" /bin/sh -s <<'CHROOT_EOF'
set -e
apk update
apk add --no-cache python3 py3-pip git openssh-client ca-certificates
ln -sf /usr/bin/python3 /usr/bin/python || true
ln -sf /usr/bin/pip3 /usr/bin/pip || true

export PATH=/usr/local/bin:$PATH

echo 'Python:' && python3 --version
echo 'Node:'   && node --version
echo 'npm:'    && npm --version

npm config set fund false
npm config set audit false
npm install -g openclaw@latest

echo 'openclaw:' && (openclaw --version || echo '(openclaw --version failed; will verify at runtime)')

rm -rf /var/cache/apk/* /root/.npm /tmp/* || true
CHROOT_EOF

cleanup_mounts
trap - EXIT

echo "=== Creating mount points ==="
sudo mkdir -p "${ROOTFS_DIR}/sdcard" "${ROOTFS_DIR}/tmp"
sudo chmod 1777 "${ROOTFS_DIR}/tmp"

embed_cli
embed_skills
embed_openclaw_config
repack

echo "=== Done ==="
echo "Output: ${OUTPUT}"
echo "Copy is not needed — AOHP build uses this path as prebuilt source."
