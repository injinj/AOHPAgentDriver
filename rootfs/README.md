# AOHP Container Rootfs Template

This directory contains the rootfs template used by the AOHP container daemon.

## Building the rootfs

Run the preparation script on a Linux host:

```bash
./prepare_rootfs.sh x86_64    # For Cuttlefish (x86_64)
./prepare_rootfs.sh aarch64   # For ARM devices
```

This will produce `alpine.tar.gz` which should be placed in this directory
before building the AOSP image.

The rootfs contains Alpine Linux with Python 3 and pip pre-installed.
