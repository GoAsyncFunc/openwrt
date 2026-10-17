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
  the microSD CID. Bind their names using OpenWrt's existing preinit device-path
  mechanism: LAN is `3c0400000.pcie` / `0001:11:00.0`, and WAN is
  `3c0800000.pcie` / `0002:21:00.0`. Both full sysfs paths were read from the
  working R66S on 2026-10-17. Preinit handles temporary names before assigning
  the desired names, including reversed probe ordering. The binding keeps the
  presently working physical LAN port as LAN; the user confirmed the connected
  port is labeled LAN on the enclosure, with only that Ethernet link active.
  Reboot stability of this binding still requires hardware testing.
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
updating the fork, update `source_revision` and `source_tar_sha` in the script
to include those changes in firmware builds. Sources and downloads are
cached under `dl/r66s-openclash`, and
the generated package is linked under the ignored `package/openwrt-packages`
directory. No upstream package or feed definitions are replaced.

`GoAsyncFunc/OpenClash` is an independent private source snapshot. On cache
miss, the preparation script fetches only the pinned commit over SSH and
creates an archive of `luci-app-openclash` with `git -c tar.umask=0002 archive`
and `gzip -n`. Because gzip output varies across platforms, `source_tar_sha`
checks the uncompressed tar payload; gzip integrity is checked separately.
Compute it with `git -c tar.umask=0002 archive --format=tar
--prefix=OpenClash-<full commit SHA>/ <full commit SHA> luci-app-openclash
| shasum -a 256`. Actions uses the `OPENCLASH_READ_KEY` secret,
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

## Private preconfigured OpenClash firmware

The public firmware workflow remains generic: OpenClash is disabled until
configured. Personal subscription URLs and node credentials must never be
committed here or injected into this public workflow.

`prepare-personal-openclash.py` accepts a private JSON bundle on stdin and
generates a build overlay with a complete, downloaded `kitty.fo.yaml` plus its
subscription settings. Downloads and automatic updates use User-Agent
`clash-verge/v2.4.5`. The downloaded YAML is preserved verbatim to avoid
changing credential/Reality scalar values during serialization.
It selects redir-host mixed mode and rule mode, enables
OpenClash at boot with a 10-second delay, and schedules subscription updates
daily at 04:00 in the router's configured timezone. The embedded profile is
available before the first update; it does not depend on a first-boot download.
Other subscription entries and saved DNS-hijack state are excluded.

The private `GoAsyncFunc/openwrt-actions` repository has a separate
**R66S private preconfigured firmware** workflow. It consumes the
`R66S_PERSONAL_OPENCLASH` Actions secret. A separate first job builds the requested
source incrementally and saves a generic GHCR snapshot without that secret.
The second job restores the snapshot and rebuilds only the root filesystem/images.
No personalized state
is committed or pushed to GHCR. Sensitive build logs are not uploaded. The
resulting firmware itself contains credentials and must remain private.

The private capture helper downloads the selected subscription afresh and
tests it with the running router's core before setting the secret. To refresh
the embedded profile in later firmware, run that helper again; runtime
subscription updates do not refresh the Actions secret. Generic images and
GHCR snapshots remain usable without that secret. A fresh install/reset uses
the personal defaults; preserving settings on upgrade preserves existing
settings instead. First boot and actual proxy connectivity require hardware
verification, even after successful configuration and image checks.

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

## Docker / Dockerman integration notes (pending)

Recorded on 2026-10-17 for future implementation. Docker and Dockerman are
not yet bundled; no Docker networking configuration has been applied.

- Keep the existing Firewall4/nftables and OpenClash setup. Review the exact
  pinned dockerd package and startup script before choosing a firewall backend.
  Do not assume that selecting the packages alone completes integration.
- Docker's default iptables backend can set forwarding policy to DROP,
  affecting the router's LAN-to-WAN forwarding, including IPv6. Check whether
  `ip-forward-no-drop` is needed and how the installed package accepts it;
  do not assume an arbitrary UCI option is passed to dockerd.
- Configure Docker's firewall zone, container NAT and published-port access
  explicitly. Do not use global forwarding ACCEPT or disable Docker's firewall
  rules as a blanket workaround. Docker's native nftables backend is currently
  experimental and requires checking the OpenWrt script's DOCKER-USER handling.
- Verify bridge-container outbound access/DNS, LAN access to published ports,
  intended WAN restrictions, and unaffected LAN-to-WAN IPv4/IPv6 forwarding.
  Repeat after firewall reload, OpenClash restart, WAN reconnect and reboot.
- For an initial Cloudflare Tunnel container, host networking can reduce
  bridge/NAT complexity; it does not establish that Docker bridge mode works.
- Store container data under `/mnt/data/docker`, with a verified data mount
  and startup guard so a missing mount cannot fill the writable system overlay.

Related reports describe historical failure modes, not proof that the current
R66S firmware is affected or that all versions are fixed:

- [LEDE #7986: Docker bridge cannot reach the network](https://github.com/coolsnowwolf/lede/issues/7986)
- [LEDE #11284: container errors after WAN restart](https://github.com/coolsnowwolf/lede/issues/11284)
- [Docker packet filtering and router forwarding](https://docs.docker.com/engine/network/packet-filtering-firewalls/)
- [Docker native nftables backend](https://docs.docker.com/engine/network/firewall-nftables/)
- [OpenWrt dockerd default configuration](https://github.com/openwrt/packages/blob/master/utils/dockerd/files/etc/config/dockerd)

## DNS separation and leak prevention notes (pending)

Recorded on 2026-10-17 at the user's request. This is a design and acceptance
record for the future dedicated resolver; no additional DNS packages or custom
DNS firewall rules have been applied. DNS leak prevention has not been verified
on the device.

The current build now enables OpenClash IPv6 proxying and AAAA resolution by
default, using IPv6 TProxy mode for TCP and UDP. The private overlay explicitly
overrides disabled IPv6 settings captured from the existing router and disables
the IPv6 China-route bypass so the profile's rules decide direct/proxy routing.
This keeps native IPv6 available instead of disabling LAN IPv6. Generic builds
still require enabling/configuring OpenClash; private builds retain automatic
startup. An upgrade preserving an old `/etc/config/openclash` can preserve its
old disabled IPv6 settings: use the new defaults on a clean flash/reset, or
explicitly update those settings after a settings-preserving upgrade.
The live router has not been changed. IPv6 forwarding, proxy-node UDP/IPv6 exit
support, cold boot and split-tunnel results still need hardware validation;
these build defaults alone do not establish prevention of all DNS leaks.

- Goal: OpenClash handles proxy selection, traffic routing and the minimal
  DNS functions needed for domain mapping. A dedicated resolver handles DNS
  policy, upstream selection, caching and fallback. Keep dnsmasq for DHCP and
  local names. The proposed resolver is mosdns; AdGuard Home is optional for
  filtering and per-client logs. SmartDNS is not initially required. Final
  package selection and topology still need confirmation before implementation.
- Preserve OpenClash IPv6 interception when introducing the dedicated resolver;
  coordinate AAAA answers, DHCP/RA DNS advertisement and IPv6 DNS interception
  instead of allowing IPv6 connections to bypass the intended proxy rules.
- Evaluate a redir-host mapping/forwarding entry in OpenClash with mosdns as
  its upstream. Do not assume that bypassing OpenClash DNS entirely preserves
  domain routing: sniffing cannot recover every connection's hostname. Review
  the pinned OpenClash DNS interception and generated configuration before
  fixing ports or adding AdGuard Home to the request path.
- Define permitted DNS egress explicitly. Direct-domain queries may use
  approved direct upstreams; proxy-domain queries must use the intended proxy
  path without silently falling back to the ISP/router DNS. Encrypted DNS
  alone does not establish that queries leave through the intended exit.
- Handle bootstrap separately for proxy-node hostnames, resolver hostnames,
  subscription refresh and time synchronization. Document necessary direct
  exceptions, avoid circular proxy/DNS dependencies, and decide failure policy
  explicitly so proxy outages cannot silently expose proxy-domain queries.
- Cover LAN clients, router-originated requests, and future Docker containers
  (including embedded DNS forwarding and host/bridge networking). Review both
  IPv4 and IPv6, DHCP/RA-advertised DNS, hard-coded UDP/TCP port 53 queries,
  DoT/DoQ and application/browser DoH. Port 53 interception alone cannot
  prevent arbitrary encrypted DNS bypass; define the supported client policy
  and its limitations rather than claiming universal leak prevention.
- Configure one intentional query path without forwarding loops, conflicting
  DNS interception or duplicated policy ownership. Verify local names and
  reverse lookups remain available and DNS is not exposed as a WAN resolver.
- Acceptance requires device-side capture on WAN and relevant proxy/container
  interfaces, correlated with resolver and OpenClash logs. Check direct and
  proxy domains, node bootstrap and deliberate client bypass attempts on
  IPv4/IPv6. Public DNS leak test pages are supplementary evidence only.
  Repeat on cold boot, WAN reconnect, firewall reload, subscription update,
  resolver/OpenClash restart, and upstream/proxy failure; verify the chosen
  failure policy and absence of unintended direct DNS egress.

## Hardware verification

### DHCP regression report (2026-10-17, unresolved)

- The user reports no DHCP lease after flashing the private firmware from
  `GoAsyncFunc/openwrt-actions` run `39025647607`, source commit
  `af0ef1e5e3e4116866c02436bfa0b5b685dfcffa`. The Mac Ethernet interface
  self-assigned `169.254.3.20`; no DHCP packet was available through
  `ipconfig getpacket en0`. Link negotiated at 1000baseT, but IPv4 management
  at `192.168.77.1` was unreachable.
- IPv6 multicast discovery received a reply from the link-local address
  matching the router's previously observed WAN MAC. This suggests checking
  the physical LAN/WAN path, but does not prove a wiring error. SSH to that
  link-local address also timed out. Router-side DHCP/service logs and boot
  status remain unavailable; the cause is unconfirmed.
- The affected private image includes the kitty.fo profile and automatic
  OpenClash startup. It does NOT include the later IPv6 interception commit
  `10ddc07874`; do not attribute this report to that untested change.
- The first comparison image is the user-selected public firmware from
  `GoAsyncFunc/openwrt` run `39018039275`, commit
  `b4c430d13115387c42429158c1280c7a0cdfc278`. Download it first, then compare
  clean-boot DHCP and management access using the same card, power supply,
  cabling and physical ports. Record each port's behavior. This is also a
  public-versus-private configuration comparison, not an isolated source
  regression test; OpenClash startup/profile differences must be considered.
- Run `39018039275` was written through the USB reader and its full image
  extent passed read-back SHA256 verification. The user reports this version
  also fails to obtain an IP address. This means the private OpenClash overlay
  is not established as the sole cause. Exact port topology and router boot
  logs are still unverified.
- The next user-selected comparison is public run `39003379613`, commit
  `16bab5d352665d8561df3e6b6841a01647ae83a6`. USB-reader flash and read-back
  SHA256 passed, but the user again reports no DHCP address.
- Subsequent capture on Mac `en0` shows repeated DHCP client requests from
  router MAC `3a:e6:35:f4:44:97` (UDP 68 to broadcast UDP 67), alongside the
  Mac's own requests, without a server offer in the captured output. This MAC
  matches the previously observed WAN interface and current IPv6 link-local
  response. The selected source assigns `eth1` to WAN and `eth0` to LAN.
  Current evidence therefore points to the computer being connected to the
  WAN-side broadcast domain. Test the other physical port directly before
  attributing the symptom to dnsmasq or changing/flashing more firmware.
  At this stage a LAN-port DHCP test and router-side logs were still pending;
  the subsequent successful test is recorded below.
- After switching the computer to the other physical port, live SSH confirmed
  a DHCP lease `192.168.77.213`, running dnsmasq, LAN on `eth0` / `br-lan`,
  and WAN on `eth1`. The active LAN PCIe path was
  `platform/3c0400000.pcie/pci0001:10/0001:10:00.0/0001:11:00.0`, and WAN
  was `platform/3c0800000.pcie/pci0002:20/0002:20:00.0/0002:21:00.0`.
  This confirms DHCP works on the LAN side of private run `39025647607`;
  prior captures do not establish that device numbering actually changed.
  Source now pins these names to the observed paths to prevent probe-order
  changes from swapping port roles. Reboot/cold-boot validation is pending.
- The user clarifies that the cable had remained in the enclosure-labeled
  LAN port while these failures occurred. Do not describe this as user error:
  captures identify the software WAN role, not the enclosure label. The
  desired final binding must match the physical LAN/WAN labels. The user then
  confirmed that the currently working port is labeled LAN. A fresh SSH read
  showed only `eth0` had carrier, at the `3c0400000.pcie` path, with DHCP lease
  `192.168.77.213`. This confirms the proposed path-to-role orientation for
  the connected physical LAN port. The local binding has not been deployed or
  committed; random probe-order changes have not yet been reproduced.
- Timeline correction from the user: after flashing public run `39003379613`,
  the enclosure LAN port did not provide a lease; following the assistant's
  advice, the user connected to the enclosure WAN port and obtained a lease.
  With current private run `39025647607`, the enclosure LAN port now provides
  a lease, as confirmed by live SSH above. Thus the reported physical roles
  differ between these tests; do not explain all failures as incorrect cabling.
  No sysfs snapshot was collected from the working WAN-labeled connection on
  run `39003379613`, so probe-order reversal remains a hypothesis rather than
  a proven cause. Pinning roles to the current confirmed physical paths is
  the intended stabilization, with cold-boot and cross-version tests pending.

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
