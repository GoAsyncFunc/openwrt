#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."
source_file=package/base-files/files/bin/config_generate
output_file=files/bin/config_generate

# Generate a build overlay without editing the upstream source file.
test "$(grep -Fc '192.168.1.1' "$source_file")" -eq 1
mkdir -p files/bin
sed 's/192\.168\.1\.1/192.168.77.1/' "$source_file" > "$output_file"
chmod 755 "$output_file"
sh -n "$output_file"
grep -Fq 'lan) ipad=${ipaddr:-"192.168.77.1"}' "$output_file"
