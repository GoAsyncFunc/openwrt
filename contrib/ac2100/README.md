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

尚未完成固件编译、刷机或真机无线验证。
