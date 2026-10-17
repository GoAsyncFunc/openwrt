#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."
# Pin a reviewed commit from the OpenClash package inside r66s-packages.
source_repository=GoAsyncFunc/r66s-packages
source_revision=dd3ce7327bb7a969089881c0496f32c6025ae1c4
core_revision=276ae9d8e7f7d9b9814ae23e015cfe29804b2cbe
source_tar_sha=c2cae489f13f3cd1521676d86a9c2a14c2f59da85eb7e14a6345cc34f011e122
core_sha=aae510c46001b8784b1480be94c3c740db9b387e5419604abaafa4189cd99c6d
cache=dl/r66s-openclash
source_archive="$cache/source-$source_revision.tar.gz"
core_archive="$cache/core-$core_revision-arm64.tar.gz"
source_dir="$cache/OpenClash-$source_revision/openclash"
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
if [ ! -f "$source_archive" ]; then
	GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-"ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$PWD/contrib/r66s/github-known-hosts"}
	export GIT_SSH_COMMAND
	source_checkout=$(mktemp -d "${TMPDIR:-/tmp}/r66s-openclash-source.XXXXXX")
	trap 'rm -rf "$source_checkout"' EXIT
	git init -q "$source_checkout"
	git -C "$source_checkout" fetch --depth=1 "git@github.com:$source_repository.git" "$source_revision"
	git -C "$source_checkout" -c tar.umask=0002 archive --format=tar --prefix="OpenClash-$source_revision/" FETCH_HEAD openclash/luci-app-openclash > "$source_checkout/source.tar"
	gzip -n -c "$source_checkout/source.tar" > "$source_archive.part"
	mv "$source_archive.part" "$source_archive"
fi
# gzip output differs between macOS and Linux, even with -n. Verify the
# deterministic tar payload, and check gzip integrity separately.
gzip -t "$source_archive"
actual=$(gzip -dc "$source_archive" | shasum -a 256 | awk '{print $1}')
[ "$actual" = "$source_tar_sha" ] || {
	echo "Source tar checksum mismatch: $source_archive (expected $source_tar_sha, got $actual)" >&2
	exit 1
}
if [ "${1:-}" = --source-only ]; then
	exit 0
fi
fetch "https://raw.githubusercontent.com/vernesong/OpenClash/$core_revision/master/meta/clash-linux-arm64.tar.gz" "$core_archive" "$core_sha"
tar -xzf "$source_archive" -C "$cache" "OpenClash-$source_revision/openclash/luci-app-openclash"
core_dir="$source_dir/luci-app-openclash/root/etc/openclash/core"
mkdir -p "$core_dir"
tar -xzf "$core_archive" -C "$core_dir" clash
mv "$core_dir/clash" "$core_dir/clash_meta"
chmod 755 "$core_dir/clash_meta"
# Set the architecture used by OpenClash's future core updates at build time.
config_file="$source_dir/luci-app-openclash/root/etc/config/openclash"
sed -e "s/option core_version '0'/option core_version 'linux-arm64'/" \
    -e "s/option ipv6_enable '0'/option ipv6_enable '1'/" \
    -e "s/option ipv6_dns '0'/option ipv6_dns '1'/" "$config_file" |
    awk '/option ipv6_enable / {
        print
        print "\toption ipv6_mode \0470\047"
        print "\toption enable_v6_udp_proxy \0471\047"
        next
    } { print }' > "$cache/openclash.config"
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
	case "$(readlink "$package_dir")" in
		"$PWD/$cache/"OpenClash-*/openclash/luci-app-openclash) ;;
		*) echo "Unexpected OpenClash package link: $package_dir" >&2; exit 1 ;;
	esac
	ln -sfn "$package_source" "$package_dir"
else
	ln -s "$package_source" "$package_dir"
fi
file "$core_dir/clash_meta" | grep -q 'ARM aarch64'
test -s "$source_dir/luci-app-openclash/root/etc/openclash/Country.mmdb"
test -s "$source_dir/luci-app-openclash/root/etc/openclash/GeoSite.dat"
printf 'OpenClash source: %s@%s\nARM64 Meta core: %s\n' "$source_repository" "$source_revision" "$core_revision"
