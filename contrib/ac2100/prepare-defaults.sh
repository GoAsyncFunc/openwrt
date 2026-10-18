#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."
mkdir -p files/etc/uci-defaults
cp contrib/ac2100/99-ac2100-localization files/etc/uci-defaults/99-ac2100-localization
chmod 755 files/etc/uci-defaults/99-ac2100-localization
sh -n files/etc/uci-defaults/99-ac2100-localization
