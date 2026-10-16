#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."
source_revision=e553e82e01c697aefbe1555261a503f425e00ccd
core_revision=276ae9d8e7f7d9b9814ae23e015cfe29804b2cbe
source_sha=bbdbdbc3959ed55270b42d4a5d04fce835684567bfef35a15a472a3ab84ada6c
core_sha=aae510c46001b8784b1480be94c3c740db9b387e5419604abaafa4189cd99c6d
cache=dl/r66s-openclash
source_archive="$cache/source-$source_revision.tar.gz"
core_archive="$cache/core-$core_revision-arm64.tar.gz"
source_dir="$cache/OpenClash-$source_revision"
package_dir=package/openwrt-packages/luci-app-openclash

fetch() {
	url=$1
	archive=$2
	expected=$3
	if [ ! -f "$archive" ]; then
		curl -fL --retry 3 --connect-timeout 20 --max-time 300 "$url" -o "$archive.part"
		mv "$archive.part" "$archive"
	fi
	actual=$(shasum -a 256 "$archive" | awk '{print $1}')
	[ "$actual" = "$expected" ] || {
		echo "Checksum mismatch: $archive" >&2
		return 1
	}
}

mkdir -p "$cache" package/openwrt-packages
fetch "https://codeload.github.com/vernesong/OpenClash/tar.gz/$source_revision" "$source_archive" "$source_sha"
fetch "https://raw.githubusercontent.com/vernesong/OpenClash/$core_revision/master/meta/clash-linux-arm64.tar.gz" "$core_archive" "$core_sha"
tar -xzf "$source_archive" -C "$cache" "OpenClash-$source_revision/luci-app-openclash"
core_dir="$source_dir/luci-app-openclash/root/etc/openclash/core"
mkdir -p "$core_dir"
tar -xzf "$core_archive" -C "$core_dir" clash
mv "$core_dir/clash" "$core_dir/clash_meta"
chmod 755 "$core_dir/clash_meta"
# Set the architecture used by OpenClash's future core updates at build time.
config_file="$source_dir/luci-app-openclash/root/etc/config/openclash"
sed "s/option core_version '0'/option core_version 'linux-arm64'/" "$config_file" > "$cache/openclash.config"
cp "$cache/openclash.config" "$config_file"
# The upstream package invokes po2lmo but omits its host build dependency.
makefile="$source_dir/luci-app-openclash/Makefile"
sed '/^PKG_BUILD_DIR:=/i\
PKG_BUILD_DEPENDS:=luci-base/host\
' "$makefile" > "$cache/openclash.Makefile"
cp "$cache/openclash.Makefile" "$makefile"

package_source="$PWD/$source_dir/luci-app-openclash"
if [ -e "$package_dir" ] || [ -L "$package_dir" ]; then
	test -L "$package_dir"
	test "$(readlink "$package_dir")" = "$package_source"
else
	ln -s "$package_source" "$package_dir"
fi
file "$core_dir/clash_meta" | grep -q 'ARM aarch64'
test -s "$source_dir/luci-app-openclash/root/etc/openclash/Country.mmdb"
test -s "$source_dir/luci-app-openclash/root/etc/openclash/GeoSite.dat"
printf 'OpenClash source: %s\nARM64 Meta core: %s\n' "$source_revision" "$core_revision"
