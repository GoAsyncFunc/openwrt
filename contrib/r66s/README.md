# R66S: official OpenWrt with LEDE hardware adaptations

## Source baselines

- Destination: `goasyncfunc/openwrt`, based on OpenWrt
  `71e991a8c01af94fb1fd6d6e4e2d259ce0ff36da` (Rockchip Linux 6.18.55).
- Reference: `coolsnowwolf/lede`
  `30169012ecc638da9a7ecde72037d624da67b131`.
- Observed hardware: FastRhino R66S, RK3568, about 1 GiB RAM,
  two RTL8125 PCIe NICs, booting from a 32 GB microSD card.

This is an R66S hardware adaptation, not a replacement of the OpenWrt
distribution with LEDE. A successful build does not establish that the
previous DHCP failure has been fixed.

## Changes

- Import LEDE's `rk3568-r66s.dts` and `rk3568-fastrhino.dtsi`, including
  its SD card, PCIe, regulators, reset button and LED definitions.
- Keep the official `lunzn_fastrhino-r66s` build profile and image name;
  select `rk3568-r66s` as the kernel device tree. The runtime board name
  becomes `fastrhino,r66s`, matching LEDE and the observed working firmware.
- Add the runtime board name to network initialization and image metadata.
  Keep the official board ID accepted by the existing profile metadata.
  LAN remains `eth0`, WAN remains `eth1`, with MAC addresses derived from
  the microSD CID. Physical port order must still be checked on hardware.
- Select the existing official `kmod-r8125-rss` package instead of
  `kmod-r8169`. Its driver source version, RSS/multiple-queue options and
  disabled ASPM already match the LEDE reference.
- Import LEDE's opt-in `led-data` device-tree support into the driver,
  and increment the package release. Do not import its unused `label`
  interface-naming patch: this R66S device tree has no NIC `label` properties.
- Remove R66S from the single-IRQ CPU affinity rule, matching LEDE's
  exclusion of R66S while using the RSS driver.

The official FIT kernel image, boot script, image layout and U-Boot 2026.10
remain in use. Both repositories select the upstream
`fastrhino-r66s-rk3568` U-Boot board; LEDE's extra R6xS U-Boot patch adds
R68S, not R66S. Official RK3568 DDR initialization is v1.23, matching LEDE;
official BL31 is v1.45 while LEDE uses v1.44. These bootloader differences
are deliberately recorded, not represented as tested equivalent. If boot
fails before Linux, capture serial output before changing the boot chain.

## Build

Use the **Build R66S firmware** GitHub Actions workflow at
`.github/workflows/r66s.yml`. Relevant pushes to the `r66s` branch run it
automatically. It can also be started from the Actions page with **Run
workflow**, or from the command line:

```sh
gh workflow run r66s.yml --repo GoAsyncFunc/openwrt --ref r66s
gh run list --repo GoAsyncFunc/openwrt --workflow r66s.yml --branch r66s
```

The inherited all-kernel and all-core-package workflows exclude pushes to
`r66s`, so this branch uses the dedicated firmware build instead of running
duplicate upstream build matrices. Their other triggers are unchanged.

The workflow uses an Ubuntu 24.04 GitHub-hosted runner. It installs build
dependencies, updates the feeds, expands `config/r66s-lede.config` with
`make defconfig`, checks the driver selection, downloads sources and performs
a full `make -j2 V=s` firmware build. No local Docker environment is required.
Downloaded sources are cached; feed revisions and the full resolved
configuration are saved with the build artifacts.

The configuration enables LuCI and ethtool, with a 1024 MiB SquashFS root
partition. Simplified Chinese translations are included for the LuCI base
interface, firewall and package manager. LuCI keeps its upstream automatic
language selection; Chinese can also be selected in System > System >
Language and Style. OpenClash includes its own Simplified Chinese translation.
It does not embed a password. During compilation, the workflow runs
`sh contrib/r66s/prepare-defaults.sh` to generate `files/bin/config_generate`
from the upstream network generator, with its default LAN IP already set to
`192.168.77.1`. The normal `/24` mask is retained. This copy is packaged into
the firmware through the standard build overlay; no additional first-boot
address-changing script is installed. Upstream source and board scripts are
unchanged. Run the same preparation command before a manual local build.
Clean installations and factory resets use `192.168.77.1/24`, and DHCP uses
`192.168.77.0/24`. Upgrades retaining settings keep the saved LAN address.

After a successful build, the workflow checks the compressed firmware,
using `fwtool` to strip appended signature/metadata from a temporary copy
before running `gzip -t`. The original upgrade image is kept intact, and
both R66S board IDs are checked in the extracted metadata. It also checks
the package manifest (RSS driver present, competing drivers absent), and the
compiled device tree's runtime board ID. Download the `r66s-firmware-N`
artifact from the run for the image, checksums and build metadata. The
`r66s-logs-N` artifact contains logs and `.config`, including on failed builds.
Artifacts are retained for 14 days. A green workflow verifies compilation
and artifact checks, not hardware boot or DHCP operation.

## Bundled OpenClash

The R66S configuration selects OpenClash and its runtime dependencies for
Firewall4/nftables: `luci-compat`, `dnsmasq-full` with DHCP and nftset support,
`ip-full`, Bash, curl, CA certificates, Ruby/YAML, unzip, TUN, inet-diag and
nft-tproxy kernel modules. The minimal `dnsmasq` and `ip-tiny` packages are
disabled to avoid conflicting providers.

Before `make defconfig`, run `sh contrib/r66s/prepare-openclash.sh` (already
included in Actions). It verifies SHA-256 hashes for the OpenClash source
archive from the `r66s` branch of `GoAsyncFunc/OpenClash` and the upstream
ARM64 Meta core, both pinned to immutable commit IDs in the script. After
updating the fork, update `source_revision` and `source_sha` in the script
to include those changes in firmware builds. Sources and downloads are
cached under `dl/r66s-openclash`, and
the generated package is linked under the ignored `package/openwrt-packages`
directory. No upstream package or feed definitions are replaced.

`GoAsyncFunc/OpenClash` is an independent private source snapshot. On cache
miss, the preparation script fetches only the pinned commit over SSH and
creates a deterministic archive of `luci-app-openclash` with `git archive`
and `gzip -n`. Compute `source_sha` with the same archive prefix
`OpenClash-<full commit SHA>/`. Actions uses the `OPENCLASH_READ_KEY` secret,
a read-only deploy key scoped to that repository; local builds need SSH
access too. `--source-only` downloads and verifies just this archive for
prefetching on the host before a Docker build. Credentials are never bundled.

The core is installed at `/etc/openclash/core/clash_meta`. Country.mmdb,
GeoSite.dat, dashboards and editor assets come from the pinned OpenClash
source. The preparation step sets the core update architecture to
`linux-arm64` and declares the missing `luci-base/host` build dependency
for `po2lmo` in the downloaded package copy. OpenClash remains disabled
until a subscription/configuration is imported and the user enables it.
No subscription, credentials or proxy rules are embedded. Additional rule
providers or datasets requested by a user's configuration may still need
network access. Actions checks package selection, the firmware manifest,
core architecture, bundled datasets and the baked-in LAN address.
Compilation does not verify proxy connectivity or routing on hardware.

## 32 GB SD storage and zram

The root partition is fixed at 1 GiB (the writable overlay is slightly smaller).
`zram-swap` and its kernel/BusyBox dependencies are bundled. The build-generated
system defaults set `zram_size_mb=512`; the upstream zram service uses LZO and
priority 100. This is compressed RAM swap, not SD-backed swap, and reserves no
512 MiB SD partition. Physical RAM use grows with the compressed pages stored.

`prepare-defaults.sh` also installs the R66S-only data initializer through the
build overlay. At first boot it verifies the boot device is nominal 32 GB SD
media, has a DOS table and the expected fixed boot/root offsets and sizes.
It appends partition 3 using the unused tail, formats it as ext4 with label
`r66s-data`, and configures UUID-based mounting at `/mnt/data` using block-mount.
It saves the original table to `/root/r66s-partitions.before`. No system
partition is moved or resized. Unexpected tables, other card capacities and
unknown existing filesystems are rejected. Existing partition 3 is never
formatted: only an ext4 partition labeled `r66s-data` at the expected offset
is reused. If power fails after creating the partition but before formatting,
the next boot refuses to format it automatically; inspect/recover it manually.

The initializer is retried after failed setup and is removed from uci-defaults
after success. On subsequent firmware upgrades/reset, the bundled initializer
can restore the data mount without formatting the recognized data partition.
It also enforces 512 MiB zram when settings from an older firmware are retained.
No Docker/Podman engine is installed by this storage change. Container data
can later be configured under `/mnt/data`, after checking the mount succeeded.

Back up and reflash the SD card once to migrate from the old 512 MiB root
layout. Do not expect the first Web upgrade to perform that migration. Future
upgrades must retain this boot/root layout and partition-preservation behavior;
`sysupgrade -p` or writing a whole-card image can destroy the data partition.
Back up data independently. Linux loop-device checks cover initialization,
idempotency/data retention and refusal paths. Hardware first boot, zram and
Web upgrade/data preservation still require testing on the actual card.

## Hardware verification

For the first test, use a spare microSD card and a clean configuration.
Keep the working card and its configuration available for recovery. Do not
force an upgrade with `sysupgrade -F` or restore an old network configuration
before checking the physical LAN/WAN mapping.

1. Check serial boot logs if no management interface becomes reachable.
   The configured serial console is UART2, 1500000 baud; verify header pinout
   and voltage before connecting an adapter.
2. Connect a computer directly to each port in turn. On the LAN port it
   should receive a `192.168.77.x` DHCP lease and reach the default LAN address
   `192.168.77.1`. On WAN it should not receive a lease from this router.
3. Confirm `ubus call system board`, `ip link`, `lspci -nnk` (if installed),
   `ethtool -i eth0`, `ethtool -i eth1`, and `dmesg` show the expected board,
   both NICs, `r8125`, and no PCIe/SD card errors. Check `/proc/interrupts`
   and ethtool queue information for RSS operation.
4. Verify WAN DHCP, LAN-to-WAN forwarding, DNS, link unplug/replug and
   cold-boot/reboot behavior. Check both 1G and 2.5G negotiation where possible.

Docker can compile and inspect this firmware, but cannot reproduce the
R66S boot ROM, power sequencing, PCIe wiring or physical NIC operation.
