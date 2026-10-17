#!/bin/bash
# Linux-only integration checks on disposable sparse images and loop devices.
set -euo pipefail
cd "$(dirname "$0")/../.."
source contrib/r66s/r66s-data-setup
test_dir=$(mktemp -d)
test_loop=
finish() {
    if [ -n "$test_loop" ]; then
        umount "$test_dir/mount" 2>/dev/null || true
        losetup -d "$test_loop"
    fi
    # Explicitly delete only files created by this test, then the empty directory.
    rm -f "$test_dir/card.img"
    rmdir "$test_dir/mount" "$test_dir"
}
trap finish EXIT
mkdir "$test_dir/mount"

# Substitute only OpenWrt's block-info frontend; the partitioning, formatting
# and kernel partition discovery below use real Linux tools/block devices.
r66s_data_info() {
    local dev="$1" fields
    fields=$(blkid -p -o export "$dev" 2>/dev/null) || return 0
    printf '%s: ' "$dev"
    printf '%s\n' "$fields" | awk -F= '/^(UUID|TYPE|LABEL)=/ { printf "%s=\"%s\" ", $1, $2 }'
    echo
}
new_card() {
    if [ -n "$test_loop" ]; then losetup -d "$test_loop"; fi
    rm -f "$test_dir/card.img"
    truncate -s "$1" "$test_dir/card.img"
    printf 'label: dos\nstart=65536, size=65536, type=83\nstart=196608, size=%s, type=83\n' "$2" |
        sfdisk "$test_dir/card.img" >/dev/null
    test_loop=$(losetup --find --show --partscan "$test_dir/card.img")
    udevadm settle
}

# Nominal 32 GB, fixed 1 GiB root: append and format remaining space.
new_card 31266439168 2097152
before=$(sfdisk --dump "$test_loop" | grep -E '^/dev/.*p[12] ')
r66s_data_prepare "$test_loop"
uuid=$R66S_DATA_UUID
test -n "$uuid"
test "$(r66s_data_field "${test_loop}p3" TYPE)" = ext4
test "$before" = "$(sfdisk --dump "$test_loop" | grep -E '^/dev/.*p[12] ')"

# Exercise the source's actual sysupgrade decision logic: extra data partition
# survives a matching layout, and changed system geometry must be refused.
source package/base-files/files/lib/upgrade/legacy-sdcard.sh
legacy_sdcard_get_partitions() {
    printf '1 65536 65536\n2 196608 %s\n' "$test_root_sectors" > /tmp/partmap.image
    printf '1 65536 65536\n2 196608 2097152\n3 2293760 58773504\n' > /tmp/partmap.bootdisk
}
v() { echo "$*" >&2; }
test_root_sectors=2097152
UPGRADE_OPT_SAVE_PARTITIONS=1
test "$(legacy_sdcard_upgrade_mode unused "$test_loop")" = partitions
test_root_sectors=1048576
test "$(legacy_sdcard_upgrade_mode unused "$test_loop")" = refuse

mount "${test_loop}p3" "$test_dir/mount"
echo keep-me > "$test_dir/mount/preserved.txt"
umount "$test_dir/mount"
r66s_data_prepare "$test_loop"
test "$uuid" = "$R66S_DATA_UUID"
mount "${test_loop}p3" "$test_dir/mount"
test "$(cat "$test_dir/mount/preserved.txt")" = keep-me
umount "$test_dir/mount"

# Existing unknown third partition must never be reformatted or adopted.
e2label "${test_loop}p3" user-data
before=$(dd if="${test_loop}p3" bs=4096 count=16 status=none | sha256sum)
if r66s_data_prepare "$test_loop"; then echo 'Accepted unknown partition' >&2; exit 1; fi
test "$before" = "$(dd if="${test_loop}p3" bs=4096 count=16 status=none | sha256sum)"

# A crash after partition creation, before mkfs: refuse to format on retry.
wipefs --all "${test_loop}p3" >/dev/null
if r66s_data_prepare "$test_loop"; then echo 'Formatted existing blank partition' >&2; exit 1; fi

# Unsupported size and old 512 MiB layout leave the table unchanged.
for spec in '8589934592 2097152' '31266439168 1048576'; do
    read -r bytes sectors <<< "$spec"
    new_card "$bytes" "$sectors"
    before=$(sfdisk --dump "$test_loop")
    if r66s_data_prepare "$test_loop"; then echo 'Accepted unsupported layout' >&2; exit 1; fi
    test "$before" = "$(sfdisk --dump "$test_loop")"
done
echo 'PASS: create ext4, preserve boot/root and data, reject unknown/crash/old layouts'
