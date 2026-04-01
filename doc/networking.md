# Networking on BeagleBone Black

This document describes how Ethernet networking is configured in this Buildroot
system, covering the hardware, kernel drivers, device tree, and userspace
network configuration.

## Table of Contents

1. [Hardware Overview](#hardware-overview)
2. [Kernel Driver Stack](#kernel-driver-stack)
3. [Device Tree Configuration](#device-tree-configuration)
4. [Userspace Network Configuration](#userspace-network-configuration)
5. [Boot-time Network Bringup](#boot-time-network-bringup)
6. [Troubleshooting](#troubleshooting)

---

## Hardware Overview

The BeagleBone Black has a single 10/100 Ethernet port. The signal path is:

```
RJ45 jack  <-->  SMSC LAN8710A PHY  <-->  AM335x CPSW  <-->  Linux kernel
                 (MII, addr 0)             (SoC peripheral)
```

- **AM335x CPSW** (Common Platform Switch): A two-port Ethernet switch built
  into the AM335x SoC. The BeagleBone Black uses only port 1. Port 2 is
  disabled in the device tree.

- **SMSC LAN8710A**: The external Ethernet PHY on the BBB rev C. It connects
  to the CPSW via MII (Media Independent Interface) and is managed via MDIO
  (Management Data Input/Output). The PHY has a hardware reset tied to GPIO1[8].

- **DAVINCI MDIO**: The MDIO controller inside the AM335x that communicates
  with the PHY for link negotiation, speed detection, and status monitoring.

The CPSW, MDIO, and PHY are all standard TI OMAP/AM335x peripherals and are
well-supported in mainline Linux.

---

## Kernel Driver Stack

The kernel is built from the `omap2plus_defconfig`, which includes all required
networking drivers as built-in (not modules). This means the drivers are
available immediately at boot — no initramfs or module loading required.

### Relevant kernel config options

| Config option              | Value | Purpose                                       |
|----------------------------|-------|-----------------------------------------------|
| `CONFIG_TI_CPSW=y`        | built-in | CPSW Ethernet switch driver (main driver)   |
| `CONFIG_TI_CPSW_SWITCHDEV=y` | built-in | CPSW switchdev support                   |
| `CONFIG_TI_CPTS=y`        | built-in | CPSW PTP clock support                      |
| `CONFIG_TI_DAVINCI_EMAC=y`| built-in | DAVINCI EMAC (legacy, also used by CPSW)    |
| `CONFIG_SMSC_PHY=y`       | built-in | SMSC LAN8710A PHY driver (BBB rev C)        |
| `CONFIG_MICREL_PHY=y`     | built-in | Micrel PHY (some BBB variants/capes)        |
| `CONFIG_AT803X_PHY=y`     | built-in | Atheros PHY (other TI boards)               |
| `CONFIG_DP83848_PHY=y`    | built-in | DP83848 PHY (TI EVMs)                       |
| `CONFIG_DP83867_PHY=y`    | built-in | DP83867 Gigabit PHY (newer TI boards)       |

Multiple PHY drivers are included because `omap2plus_defconfig` is a
multi-board config covering all OMAP2+ platforms. The kernel matches the
correct PHY driver at runtime based on the PHY ID register.

### Driver probe order

At boot, the kernel:

1. Probes the CPSW platform device from the device tree.
2. Initializes the DAVINCI MDIO controller.
3. Scans the MDIO bus for PHYs (finds LAN8710A at address 0).
4. Matches the PHY to the SMSC PHY driver based on the PHY ID.
5. Registers the `eth0` network interface.

You can verify this worked by checking `dmesg`:

```
cpsw 4a100000.ethernet: initialized cpsw ale with 1024 entries
cpsw 4a100000.ethernet: cpsw: Detected MACID = xx:xx:xx:xx:xx:xx
```

---

## Device Tree Configuration

The network hardware is described in `am335x-bone-common.dtsi`, which is
included by `am335x-boneblack.dts`. The key nodes are:

### Pin multiplexing

The AM335x pins are shared between peripherals. The device tree configures the
pins for MII mode:

- **cpsw_default**: Sets MII1 data, clock, and control pins for normal
  operation.
- **cpsw_sleep**: Low-power pin state for suspend.
- **davinci_mdio_default**: MDIO data (MDIO) and clock (MDC) pins.

### CPSW node

```dts
&cpsw_port1 {
    phy-handle = <&ethphy0>;
    phy-mode = "mii";
    ti,dual-emac-pvid = <1>;
    status = "okay";
};

&cpsw_port2 {
    status = "disabled";
};
```

Port 1 is enabled with MII mode, connected to `ethphy0`. Port 2 is unused on
the BeagleBone Black.

### MDIO and PHY

```dts
&davinci_mdio {
    ethphy0: ethernet-phy@0 {
        reg = <0>;           /* PHY address 0 on MDIO bus */
        reset-gpios = <&gpio1 8 GPIO_ACTIVE_LOW>;  /* GPIO1[8] for PHY reset */
    };
};
```

The PHY address (0) must match the LAN8710A's PHYAD pin strapping on the PCB.
The GPIO reset is asserted during driver probe to ensure a clean PHY state.

### DTB selection

The boot script (`board/bbb/boot.cmd`) loads `am335x-boneblack.dtb`. If you
are using a different BeagleBone variant, update the DTB name in the boot
script. Available DTBs in the boot partition:

- `am335x-bone.dtb` — original BeagleBone (white)
- `am335x-boneblack.dtb` — BeagleBone Black
- `am335x-boneblack-wireless.dtb` — BeagleBone Black Wireless
- `am335x-bonegreen.dtb` — BeagleBone Green
- `am335x-bonegreen-wireless.dtb` — BeagleBone Green Wireless

---

## Userspace Network Configuration

### BR2_SYSTEM_DHCP

The Buildroot option `BR2_SYSTEM_DHCP="eth0"` (set in `defconfig`) causes the
`ifupdown-scripts` package to generate `/etc/network/interfaces` at build time:

```
# interface file auto-generated by buildroot

auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
  pre-up /etc/network/nfs_check
  wait-delay 15
  hostname $(hostname)
```

This is generated by `buildroot/package/ifupdown-scripts/ifupdown-scripts.mk`.
The file is created during the buildroot build, not at runtime.

### What each line does

| Line | Purpose |
|------|---------|
| `auto eth0` | Bring up eth0 automatically when `ifup -a` is called at boot |
| `iface eth0 inet dhcp` | Use DHCP to obtain an IP address |
| `pre-up /etc/network/nfs_check` | Safety check: skips ifdown if root is NFS-mounted (prevents bricking NFS-booted dev setups) |
| `wait-delay 15` | Wait up to 15 seconds for DHCP lease |
| `hostname $(hostname)` | Send the board's hostname in DHCP requests |

### Init system integration

The system uses BusyBox init (`BR2_INIT_BUSYBOX=y`). The network is brought up
by the `S40network` init script, installed by the `ifupdown-scripts` package
to `/etc/init.d/S40network`. This script runs `ifup -a`, which reads
`/etc/network/interfaces` and brings up all `auto`-marked interfaces.

The boot order relevant to networking:

```
S01syslogd     — start syslog (so network errors are logged)
S02klogd       — start kernel log daemon
S20urandom     — seed random number generator
S40network     — bring up lo and eth0 (DHCP)
...
S80swupdate    — start SWUpdate daemon (needs network for web UI)
```

S40network runs before S80swupdate, ensuring the network is available for
SWUpdate's web interface on port 8080.

### DHCP client

BusyBox provides `udhcpc` as the DHCP client. When `ifup` brings up eth0 with
`inet dhcp`, it invokes `udhcpc` which:

1. Sends DHCP DISCOVER on eth0.
2. Receives DHCP OFFER from the network's DHCP server.
3. Configures the IP address, subnet mask, default gateway, and DNS.
4. Runs `/usr/share/udhcpc/default.script` to apply the lease.

### Static IP alternative

To use a static IP instead of DHCP, change `BR2_SYSTEM_DHCP` to empty (`""`)
in menuconfig and add a custom `/etc/network/interfaces` to the rootfs overlay
(`board/bbb/rootfs-overlay/etc/network/interfaces`):

```
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.1.100
    netmask 255.255.255.0
    gateway 192.168.1.1
```

Then set DNS in `board/bbb/rootfs-overlay/etc/resolv.conf`:

```
nameserver 8.8.8.8
```

Rebuild with `make`. The overlay files take precedence over buildroot-generated
ones.

---

## Boot-time Network Bringup

The full sequence from power-on to a working network connection:

```
1. Kernel boots, probes CPSW driver from device tree
2. CPSW driver initializes the switch hardware
3. DAVINCI MDIO driver probes, finds LAN8710A PHY at address 0
4. PHY is reset via GPIO1[8], then initialized
5. eth0 network interface is registered
6. (kernel finishes booting, starts init)
7. S40network runs: ifup -a
8. ifup reads /etc/network/interfaces
9. ifup brings up lo (loopback)
10. ifup brings up eth0:
    a. Calls pre-up script (nfs_check)
    b. Starts udhcpc on eth0
    c. udhcpc sends DHCP DISCOVER
    d. Receives DHCP OFFER/ACK
    e. Configures IP, gateway, DNS
11. eth0 is up with an IP address
12. S80swupdate starts, binds web UI to 0.0.0.0:8080
```

---

## Troubleshooting

### Step 1: Check if the kernel sees the hardware

```bash
ls /sys/class/net/
```

Expected output: `eth0  lo`

If `eth0` is missing, the CPSW driver did not probe successfully. Check the
kernel log:

```bash
dmesg | grep -i cpsw
dmesg | grep -i eth
```

**Possible causes if eth0 is missing:**

- Wrong DTB loaded. Verify in U-Boot: the boot script loads
  `am335x-boneblack.dtb`. If you're on a different board variant, the DTB
  must match.
- Pin multiplexing conflict. Another device tree overlay or cape may have
  claimed the MII pins. Check `dmesg` for pinctrl errors.
- Kernel config mismatch. If you've customized the kernel defconfig, verify
  that `CONFIG_TI_CPSW=y` is still set: `zcat /proc/config.gz | grep TI_CPSW`
  (if `CONFIG_IKCONFIG_PROC=y` is enabled).

### Step 2: Check if the PHY was detected

```bash
dmesg | grep -i mdio
dmesg | grep -i phy
```

Look for lines like:

```
davinci_mdio 4a101000.mdio: davinci mdio revision X.X, bus freq to YYYYY
libphy: 4a101000.mdio: probed
```

If the PHY is not detected:
- Check the Ethernet cable and port for physical damage.
- The PHY reset GPIO may not be toggling correctly. Check `dmesg` for GPIO
  errors.

### Step 3: Manually bring up the interface

```bash
ifup eth0
```

Or manually:

```bash
ip link set eth0 up
udhcpc -i eth0
```

Check the link status:

```bash
ip link show eth0
cat /sys/class/net/eth0/carrier     # 1 = cable connected, 0 = no link
cat /sys/class/net/eth0/speed       # 100 for 100Mbps
```

### Step 4: Verify DHCP

If the interface is up but has no IP:

```bash
udhcpc -i eth0 -f -n    # foreground, fail if no lease
```

- **No DHCP server**: Verify your network has a DHCP server. Try a static IP
  instead (see above).
- **Cable issue**: Check `carrier` in sysfs. If 0, the cable or switch port
  may be bad.
- **VLAN or 802.1X**: Some managed switches require port configuration before
  granting a DHCP lease.

### Step 5: Test connectivity

```bash
ping -c 3 <gateway-ip>    # test local network
ping -c 3 8.8.8.8         # test internet (if gateway routes to internet)
```

If local ping works but internet doesn't, check the default route:

```bash
ip route
# Should show: default via <gateway-ip> dev eth0
```

### Interface naming

Some kernel versions or configurations may use predictable interface names
(e.g., `end0`, `enp0s0`) instead of the classic `eth0`. Check what interfaces
exist:

```bash
ls /sys/class/net/
```

If the interface is named differently, update `BR2_SYSTEM_DHCP` in the
defconfig to match (e.g., `BR2_SYSTEM_DHCP="end0"`), rebuild, and reflash.

Predictable names are controlled by `systemd-udevd` or `eudev`. With BusyBox
mdev (the default in this build), classic names (`eth0`) are used.

### Common issues reference

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| No `eth0` in `/sys/class/net/` | CPSW driver didn't probe | Check DTB, check `dmesg` for errors |
| `eth0` exists, carrier=0 | No cable or bad cable | Check physical connection |
| `eth0` exists, carrier=1, no IP | DHCP server unreachable | Try `udhcpc -i eth0` manually, or use static IP |
| `eth0` named `end0` instead | Predictable interface naming | Update `BR2_SYSTEM_DHCP` to `"end0"` |
| Network up but no internet | Missing default route | Check `ip route`, verify gateway config |
| SWUpdate web UI unreachable | Network not up before S80swupdate | Verify S40network runs successfully |
