#!/bin/bash
# build-slim-iso.sh — strip the noble live-server ISO for low-RAM PXE clients.
#
# Runs ON the PXE server (pxe.cttb / container pxe24), as root. First used
# 2026-07-31 for the DRBU cslab HP 8200 Elite fleet (sudhanix26 rollout).
#
# Why: casper's `url=` PXE boot downloads the ENTIRE ISO into RAM before
# mounting it. The stock 3.0 GB live-server ISO OOMs the subiquity install on
# old lab hardware. This build keeps what an ONLINE autoinstall actually
# needs and lands around 1.5 GB:
#
#   keep  casper/ non-HWE squashfs layers   the live env + install source
#   keep  .disk/                            casper medium identity/UUID check
#   keep  dists/                            cdrom apt repo metadata — subiquity
#                                           always registers file:/cdrom as an
#                                           apt source; without a Release file
#                                           `apt-get update` exits 100 and the
#                                           install crashes at configure_apt
#   keep  pool/ (most)                      curtin installs the target kernel
#                                           and grub from here when offline
#   drop  casper/*hwe*                      PXE boots the non-HWE kernel
#   drop  pool/restricted/                  NVIDIA payloads, ~550 MB
#   drop  pool/main/l/linux-firmware/       485 MB; targets resolve the newer
#   drop  pool/main/l/linux/*modules-extra* mirror version anyway (indexes
#                                           still list these — safe only
#                                           because noble-updates/security on
#                                           the mirror always supersede them)
#
# The output ISO is not itself bootable media (no El Torito needed): PXE
# supplies kernel+initrd; casper only loop-mounts this for its squashfs and
# apt payload.
#
# Usage (on pxe.cttb):
#   sudo bash build-slim-iso.sh [SRC_ISO] [OUT_ISO]

set -euo pipefail

SRC=${1:-/srv/netinstall/ubuntu-live-server-noble-amd64.iso}
OUT=${2:-/srv/netinstall/ubuntu-live-server-noble-amd64-slim.iso}
BUILD=/srv/netinstall/build/noble-slim

command -v 7z >/dev/null || { echo "need p7zip (7z)" >&2; exit 1; }
command -v xorriso >/dev/null || { echo "need xorriso (apt-get install xorriso)" >&2; exit 1; }

rm -rf "$BUILD" && mkdir -p "$BUILD"

7z x -y "$SRC" -o"$BUILD" casper .disk dists pool

rm -f  "$BUILD"/casper/*hwe*
rm -rf "$BUILD"/pool/restricted
rm -rf "$BUILD"/pool/main/l/linux-firmware
rm -f  "$BUILD"/pool/main/l/linux/linux-modules-extra-*.deb

du -sm "$BUILD"

xorriso -as mkisofs -r -V sudhanix-noble-slim -o "$OUT.tmp" "$BUILD"
mv "$OUT.tmp" "$OUT"
chmod 644 "$OUT"
ls -lh "$OUT"
