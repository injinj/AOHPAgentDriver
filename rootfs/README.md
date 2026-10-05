# AOHP Container Rootfs Templates

This directory holds the rootfs templates that `aohp-containerd` unpacks into `/data/aohp/envs/<env>/rootfs`
(installed to `/system/etc/aohp/rootfs-templates/<name>.tar.gz`). The tarballs are **not in git** (300–600 MB each).

| module | file | source |
|---|---|---|
| `aohp-rootfs-alpine` | `alpine.tar.gz` | `./prepare_rootfs.sh x86_64\|aarch64` (Alpine/musl, the stock AOHP template) |
| `aohp-rootfs-debian` | `debian.tar.gz` | **required by vendor/aohp/aohp.mk** — Debian trixie, glibc, official Node, OpenClaw, aohp CLI. Built by [injinj/aohp-agents](https://github.com/injinj/aohp-agents) `template/build-template.sh debian arm64`, published as a `templates-*` release |
| `aohp-rootfs-fedora` | `fedora.tar.gz` | optional, same release (`fedora-arm64.tar.gz`) |
| `aohp-rootfs-arch` | `arch.tar.gz` | optional, same release (`arch-arm64.tar.gz`) |

## Getting the tarballs

```bash
vendor/aohp/fetch-prebuilts.sh                 # debian (arm64) from the newest templates-* release, sha256-verified
vendor/aohp/fetch-prebuilts.sh debian fedora arch
vendor/aohp/fetch-prebuilts.sh --release templates-20261005 fedora
```

## How the optional modules stay harmless

Soong resolves `src` for every module at analysis time, even if nothing depends on it, so a plain `prebuilt_etc`
with a missing file fails the whole build. `aohp-rootfs-fedora`/`aohp-rootfs-arch` are `soong_config_module_type`
modules with `enabled: false` by default; `vendor/aohp/aohp.mk` turns on `SOONG_CONFIG_aohp_rootfs_<distro>` and
adds the module to `PRODUCT_PACKAGES` only when `rootfs/<distro>.tar.gz` exists. With only `debian.tar.gz` present
the build is exactly as before.

## Constraints the tarballs must meet (`system/core/aohp-containerd/tar_gz_extract.cpp`)

Regular files, dirs and symlinks only (hardlinks/devices are skipped), empty `dev/ proc/ sys/ run/`, everything ends
up root-owned, and the whole tar is inflated in memory on the device — keep it lean. `build-template.sh` enforces
the first two.
