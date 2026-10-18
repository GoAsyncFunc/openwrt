#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."
source_file=package/base-files/files/bin/config_generate
output_file=files/bin/config_generate

# Generate a build overlay without editing the upstream source file.
test "$(grep -Fc '192.168.1.1' "$source_file")" -eq 1
test "$(grep -Fc "set system.@system[-1].timezone='GMT0'" "$source_file")" -eq 1
test "$(grep -Fc "set system.@system[-1].zonename='UTC'" "$source_file")" -eq 1
mkdir -p files/bin
sed -e 's/192\.168\.1\.1/192.168.77.1/' \
    -e "s|set system\.@system\[-1\]\.timezone='GMT0'|set system.@system[-1].timezone='CST-8'|" \
    -e "s|set system\.@system\[-1\]\.zonename='UTC'|set system.@system[-1].zonename='Asia/Shanghai'|" "$source_file" |
    awk '/set system\.@system\[-1\]\.timezone=/ {
        print "\t\tset system.@system[-1].zram_size_mb=\047512\047"
    } { print }' > "$output_file"
chmod 755 "$output_file"
sh -n "$output_file"
grep -Fq 'lan) ipad=${ipaddr:-"192.168.77.1"}' "$output_file"
grep -Fq "set system.@system[-1].zram_size_mb='512'" "$output_file"
grep -Fq "set system.@system[-1].timezone='CST-8'" "$output_file"
grep -Fq "set system.@system[-1].zonename='Asia/Shanghai'" "$output_file"
mkdir -p files/usr/sbin files/etc/uci-defaults
cp contrib/r66s/r66s-data-setup files/usr/sbin/r66s-data-setup
chmod 755 files/usr/sbin/r66s-data-setup
printf '#!/bin/sh\n/usr/sbin/r66s-data-setup\n' > files/etc/uci-defaults/95-r66s-storage
chmod 755 files/etc/uci-defaults/95-r66s-storage

# Docker 网络初始化必须早于 96-r66s-docker：dockerd 的 uciadd 在服务运行时会
# 拒绝改动配置，所以先由 94 建立 docker 区域与转发，再由 96 启动守护进程。
cp contrib/r66s/r66s-docker-network files/usr/sbin/r66s-docker-network
chmod 755 files/usr/sbin/r66s-docker-network
cmp contrib/r66s/r66s-docker-network files/usr/sbin/r66s-docker-network
printf '#!/bin/sh\n/usr/sbin/r66s-docker-network\n' > files/etc/uci-defaults/94-r66s-docker-network
chmod 755 files/etc/uci-defaults/94-r66s-docker-network
grep -Fxq '/usr/sbin/r66s-docker-network' files/etc/uci-defaults/94-r66s-docker-network
