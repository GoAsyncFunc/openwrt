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

The configuration enables LuCI and ethtool, with a 512 MiB SquashFS root
partition. It does not embed a password or change the official default LAN IP.

After a successful build, the workflow checks the compressed firmware,
the package manifest (RSS driver present, competing drivers absent), and the
compiled device tree's runtime board ID. Download the `r66s-firmware-N`
artifact from the run for the image, checksums and build metadata. The
`r66s-logs-N` artifact contains logs and `.config`, including on failed builds.
Artifacts are retained for 14 days. A green workflow verifies compilation
and artifact checks, not hardware boot or DHCP operation.

## Hardware verification

For the first test, use a spare microSD card and a clean configuration.
Keep the working card and its configuration available for recovery. Do not
force an upgrade with `sysupgrade -F` or restore an old network configuration
before checking the physical LAN/WAN mapping.

1. Check serial boot logs if no management interface becomes reachable.
   The configured serial console is UART2, 1500000 baud; verify header pinout
   and voltage before connecting an adapter.
2. Connect a computer directly to each port in turn. On the LAN port it
   should receive a DHCP lease and reach the unmodified default LAN address
   `192.168.1.1`. On WAN it should not receive a lease from this router.
3. Confirm `ubus call system board`, `ip link`, `lspci -nnk` (if installed),
   `ethtool -i eth0`, `ethtool -i eth1`, and `dmesg` show the expected board,
   both NICs, `r8125`, and no PCIe/SD card errors. Check `/proc/interrupts`
   and ethtool queue information for RSS operation.
4. Verify WAN DHCP, LAN-to-WAN forwarding, DNS, link unplug/replug and
   cold-boot/reboot behavior. Check both 1G and 2.5G negotiation where possible.

Docker can compile and inspect this firmware, but cannot reproduce the
R66S boot ROM, power sequencing, PCIe wiring or physical NIC operation.
