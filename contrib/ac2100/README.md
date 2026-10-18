# Redmi AC2100

`AC2100` 分支基于已同步 OpenWrt 官方上游的 `main`。
当前上游基线为 `71194c985d8a97ea49fe42d9cebf6f739d729154`。

适用机型为红米 AC2100 / RM2100，构建 profile 为
`xiaomi_redmi-router-ac2100`，平台为 `ramips/mt7621`。

目前确定的定制只有：

- LuCI 简体中文，包括基础界面、防火墙、软件包管理和值守升级翻译。
- 默认语言设为 `zh_cn`。
- 默认时区设为 `Asia/Shanghai`，UCI 时区值为 `CST-8`。

内核、硬件定义、无线驱动与平台默认软件包沿用此 `main` 基线。
管理 IP、主机名、AP 桥接、无线名称、额外插件及其他定制待定。
R66S 的配置和打包覆盖文件不适用于本分支。

更新和安装官方 feeds 后，在本工作目录准备构建配置：

```sh
sh contrib/ac2100/prepare-defaults.sh
cp config/ac2100.config .config
make defconfig
```

`prepare-defaults.sh` 只生成本机型的本地化首次初始化脚本。
它不修改默认 IP、DHCP 或无线配置。`files/` 与 `.config` 为忽略的生成文件。
更改 `config/ac2100.config` 后需重新生成 `.config`。

## 固件编译与产物

推送本分支（或手动触发 `workflow_dispatch`）会运行
`.github/workflows/ac2100.yml`：`defaults-checks` 先检查本地化首次初始化脚本
的内容，`build` 再安装构建依赖、更新并安装 feeds、生成 `.config`（`make
defconfig` 后逐项断言目标/机型/中文语言包确实生效）、下载源码、编译、校验产物
并上传。

Actions 工件 `ac2100-firmware-<run_number>` 中的镜像，前缀为
`openwrt-ramips-mt7621-xiaomi_redmi-router-ac2100-`：

| 文件后缀 | 用途 |
| --- | --- |
| `squashfs-kernel1.bin` | 首次安装：写入 NAND 的 `kernel1` 分区 |
| `squashfs-rootfs0.bin` | 首次安装：写入 NAND 的 `rootfs0` 分区 |
| `squashfs-sysupgrade.bin` | 已运行 OpenWrt 后的 LuCI / `sysupgrade` 升级 |
| `initramfs-kernel.bin` | RAM 启动，用于救砖或临时验证 |

同目录的 `*-ac2100.manifest`（软件包清单）、`profiles.json`、`sha256sums` 与
`*.buildinfo` 一并上传；日志与解析后的 `.config` 在
`ac2100-logs-<run_number>` 工件里。

校验步骤确认：四个镜像各存在且非空；`sha256sums` 全部通过；`profiles.json`
列出该机型与三个安装镜像名；`sysupgrade.bin` 是含 `CONTROL`/`kernel`/`root`
的 tar；清单里含 LuCI 与四个简体中文语言包。

首次安装沿用机型加入上游时的说明（提交 `f3792690c4`）：先取得 shell 并把两个
镜像传到路由器，然后

```sh
mtd write openwrt-ramips-mt7621-xiaomi_redmi-router-ac2100-squashfs-kernel1.bin kernel1
nvram set uart_en=1
nvram set bootdelay=5
nvram set flag_try_sys1_failed=1
nvram commit
mtd -r write openwrt-ramips-mt7621-xiaomi_redmi-router-ac2100-squashfs-rootfs0.bin rootfs0
```

恢复官方固件需要 PXE/TFTP 服务并按住复位键启动，细节见上面的提交说明。

编译由 Actions 完成；真机刷机、无线与首次启动行为尚未验证。
