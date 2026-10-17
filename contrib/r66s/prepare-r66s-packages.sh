#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."
source_repository=GoAsyncFunc/r66s-packages
source_revision=5b2bffdf1f1677c963dc00bb2c66ea456324766e
source_tar_sha=24b84192f0f42bfa84f5cd093b5308912ea783e8f8a0a715090ae18cec19c069
cache=dl/r66s-packages
source_archive="$cache/source-$source_revision.tar.gz"
source_dir="$cache/R66SPackages-$source_revision"
package_dir=package/openwrt-packages/r66s-docker

mkdir -p "$cache" package/openwrt-packages
if [ ! -f "$source_archive" ]; then
	GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-"ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$PWD/contrib/r66s/github-known-hosts"}
	export GIT_SSH_COMMAND
	source_checkout=$(mktemp -d "${TMPDIR:-/tmp}/r66s-packages-source.XXXXXX")
	trap 'rm -rf "$source_checkout"' EXIT
	git init -q "$source_checkout"
	git -C "$source_checkout" fetch --depth=1 "git@github.com:$source_repository.git" "$source_revision"
	git -C "$source_checkout" -c tar.umask=0002 archive --format=tar --prefix="R66SPackages-$source_revision/" FETCH_HEAD packages/r66s-docker patches > "$source_checkout/source.tar"
	gzip -n -c "$source_checkout/source.tar" > "$source_archive.part"
	mv "$source_archive.part" "$source_archive"
fi

gzip -t "$source_archive"
actual=$(gzip -dc "$source_archive" | shasum -a 256 | awk '{print $1}')
[ "$actual" = "$source_tar_sha" ] || {
	echo "Source tar checksum mismatch: $source_archive" >&2
	exit 1
}

if [ "${1:-}" = --source-only ]; then
	exit 0
fi

tar -xzf "$source_archive" -C "$cache" \
	"R66SPackages-$source_revision/packages/r66s-docker" \
	"R66SPackages-$source_revision/patches"
if [ -e "$package_dir" ] || [ -L "$package_dir" ]; then
	test -L "$package_dir"
	case "$(readlink "$package_dir")" in
		"$PWD/$source_dir/packages/r66s-docker") ;;
		*) echo "Unexpected R66S package link: $package_dir" >&2; exit 1 ;;
	esac
	ln -sfn "$PWD/$source_dir/packages/r66s-docker" "$package_dir"
else
	ln -s "$PWD/$source_dir/packages/r66s-docker" "$package_dir"
fi
test -f "$package_dir/Makefile"

# OpenWrt's current APK metadata validator rejects the upstream `v` prefix.
patch -d feeds/dockerlib/collections/luci-lib-docker -p1 \
    < "$source_dir/patches/0001-luci-lib-docker-apk-version.patch"
patch -d feeds/dockerman/applications/luci-app-dockerman -p1 \
    < "$source_dir/patches/0002-luci-app-dockerman-apk-version.patch"
grep -Fqx 'PKG_VERSION:=0.3.4' feeds/dockerlib/collections/luci-lib-docker/Makefile
grep -Fqx 'PKG_VERSION:=0.5.26' feeds/dockerman/applications/luci-app-dockerman/Makefile
printf 'R66S private packages: %s@%s\n' "$source_repository" "$source_revision"
