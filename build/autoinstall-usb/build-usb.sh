#!/bin/bash
#
# Build an Ubuntu 24.04 autoinstall USB from the live-server ISO.
#
# This script downloads the ISO (or uses a cached copy), injects the
# autoinstall user-data, and writes the result to a USB drive.
#
# Usage:
#   ./build-usb.sh /dev/diskN          # macOS raw disk device
#   ./build-usb.sh /Volumes/E          # or mount point (will resolve to disk)
#
# The script must be run from the build/autoinstall-usb/ directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ISO_URL="http://pxe.cttb/ansible_assets/isos/ubuntu-24.04.2-live-server-amd64.iso"
ISO_FILE="$SCRIPT_DIR/ubuntu-24.04.2-live-server-amd64.iso"
WORK_DIR="$SCRIPT_DIR/work"
USER_DATA="$SCRIPT_DIR/user-data"
META_DATA="$SCRIPT_DIR/meta-data"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <disk-device-or-mountpoint>"
    echo "  e.g. $0 /dev/disk4   or   $0 /Volumes/E"
    exit 1
fi

TARGET="$1"

# Resolve mount point to disk device on macOS
if [[ "$TARGET" == /Volumes/* ]]; then
    TARGET_DISK=$(diskutil info "$TARGET" | grep "Device Node" | awk '{print $NF}')
    if [ -z "$TARGET_DISK" ]; then
        echo "ERROR: Could not resolve $TARGET to a disk device"
        exit 1
    fi
    echo "Resolved $TARGET -> $TARGET_DISK"
else
    TARGET_DISK="$TARGET"
fi

# Safety: confirm this is a removable disk
DISK_INFO=$(diskutil info "$TARGET_DISK" 2>/dev/null || true)
if ! echo "$DISK_INFO" | grep -q "Removable Media.*Removable"; then
    # Also check for external/USB
    if ! echo "$DISK_INFO" | grep -qi "external"; then
        echo "WARNING: $TARGET_DISK does not appear to be removable/external."
        echo "Disk info:"
        diskutil info "$TARGET_DISK" | grep -E "Device|Media|Protocol|Removable"
        read -p "Continue anyway? (yes/no): " CONFIRM
        if [ "$CONFIRM" != "yes" ]; then
            echo "Aborted."
            exit 1
        fi
    fi
fi

# Step 1: Download ISO if not cached
if [ -f "$ISO_FILE" ]; then
    echo "Using cached ISO: $ISO_FILE"
else
    echo "Downloading ISO from $ISO_URL ..."
    curl -L -o "$ISO_FILE" "$ISO_URL"
fi

echo "ISO size: $(ls -lh "$ISO_FILE" | awk '{print $5}')"

# Step 2: Extract ISO
echo "Extracting ISO..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/iso" "$WORK_DIR/nocloud"

# Extract ISO with xorriso (reliable on macOS; hdiutil often hangs on Linux ISOs)
if command -v xorriso &>/dev/null; then
    xorriso -osirrox on -indev "$ISO_FILE" -extract / "$WORK_DIR/iso"
else
    echo "ERROR: Install xorriso: brew install xorriso"
    exit 1
fi

# Step 3: Inject autoinstall config
echo "Injecting autoinstall user-data..."
cp "$USER_DATA" "$WORK_DIR/nocloud/user-data"
cp "$META_DATA" "$WORK_DIR/nocloud/meta-data"

# Modify GRUB config to add autoinstall parameter and rename entry
GRUB_CFG="$WORK_DIR/iso/boot/grub/grub.cfg"
if [ -f "$GRUB_CFG" ]; then
    # Rename the first menu entry
    sed -i.bak 's|"Try or Install Ubuntu Server"|"Autoinstall Ubuntu 24.04 Desktop (CTTB)"|' "$GRUB_CFG"
    # Inject autoinstall kernel params (handle tabs and varying whitespace before ---)
    sed -i.bak 's|/casper/vmlinuz *---|/casper/vmlinuz autoinstall ds=nocloud\\;s=/cdrom/nocloud/ ---|' "$GRUB_CFG"
    rm -f "$GRUB_CFG.bak"
    echo "GRUB config updated."
fi

# Copy nocloud directory into the ISO filesystem
cp -r "$WORK_DIR/nocloud" "$WORK_DIR/iso/nocloud"

# Step 4: Write to USB
echo ""
echo "=== WRITING TO USB ==="
echo "Target: $TARGET_DISK"
echo "This will ERASE ALL DATA on $TARGET_DISK"
read -p "Type YES to continue: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

# Unmount the USB drive
echo "Unmounting $TARGET_DISK..."
diskutil unmountDisk "$TARGET_DISK" 2>/dev/null || true

# Repack ISO with xorriso if available, otherwise use dd with the modified files
if command -v xorriso &>/dev/null; then
    echo "Repacking ISO with xorriso..."
    OUTPUT_ISO="$SCRIPT_DIR/ubuntu-24.04.2-autoinstall-dvgs-lab3.iso"
    xorriso -as mkisofs \
        -r -V 'Ubuntu 24.04 Autoinstall' \
        -o "$OUTPUT_ISO" \
        --grub2-mbr --interval:local_fs:0s-15s:zero_mbrpt,zero_gpt:"$ISO_FILE" \
        --protective-msdos-label \
        -partition_cyl_align off -partition_offset 16 \
        --mbr-force-bootable \
        -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b \
          --interval:local_fs:6264708d-6274851d::"$ISO_FILE" \
        -appended_part_as_gpt \
        -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
        -c '/boot.catalog' \
        -b '/boot/grub/i386-pc/eltorito.img' \
        -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
        -eltorito-alt-boot \
        -e '--interval:appended_partition_2:::' \
        -no-emul-boot \
        "$WORK_DIR/iso"
    echo "Writing ISO to USB..."
    sudo dd if="$OUTPUT_ISO" of="$TARGET_DISK" bs=4m status=progress
else
    echo "xorriso not found. Using dd to write original ISO + manual nocloud setup..."
    echo "Writing base ISO to USB..."
    sudo dd if="$ISO_FILE" of="$TARGET_DISK" bs=4m status=progress
    echo ""
    echo "MANUAL STEP REQUIRED:"
    echo "After dd completes, mount the USB and copy nocloud/ to the root."
    echo "Then edit boot/grub/grub.cfg to add autoinstall parameters."
fi

sync
echo ""
echo "Done! Eject with: diskutil eject $TARGET_DISK"
echo ""
echo "Boot dvgs-lab3 from USB (F12 at BIOS for boot menu)."
echo "Installation will proceed automatically."
