# Hardware Watchdog Daemon

## What

The BeagleBone Black's AM335x SoC includes a hardware watchdog timer
(OMAP WDT).  The `watchdog` daemon pets `/dev/watchdog0` at regular
intervals.  If the system hangs — kernel panic, runaway process,
OOM — the hardware forces a reboot automatically.

This is essential for unattended boards that can't be power-cycled
manually.

## How It Works

1. The kernel driver `omap_wdt` exposes `/dev/watchdog0`.
2. The `watchdog` daemon (buildroot package) opens the device and
   writes to it every 10 seconds (configurable in `watchdog.conf`).
3. If the daemon fails to pet the device within the hardware timeout
   (~60 s for OMAP WDT), the hardware resets the SoC.

The daemon also monitors basic system health:

| Check | Threshold | Action |
|---|---|---|
| Load average (1 min) | > 24 | Reboot |
| Load average (5 min) | > 18 | Reboot |
| Available memory | < 4 MB | Reboot |

## Files

| File | Purpose |
|---|---|
| `board/bbb/rootfs-overlay/etc/watchdog.conf` | Daemon config (device, interval, health checks) |
| `board/bbb/systemd/watchdog.service` | systemd unit — starts watchdog after local-fs.target |
| `board/bbb/linux.fragment` | Kernel config: `CONFIG_WATCHDOG=y`, `CONFIG_OMAP_WATCHDOG=y` |
| `defconfig` | `BR2_PACKAGE_WATCHDOG=y` |

## Buildroot Options

```
BR2_PACKAGE_WATCHDOG=y
```

## Kernel Config (linux.fragment)

```
CONFIG_WATCHDOG=y
CONFIG_OMAP_WATCHDOG=y
```

## Verifying on the Board

```bash
# Check the device exists
ls -l /dev/watchdog0

# Check the service
systemctl status watchdog.service

# Check the daemon is petting the device
dmesg | grep omap_wdt

# Check the daemon process is running (pidof is from busybox)
pidof watchdog

# View hardware timeout (reported at boot, default 60s for OMAP WDT)
dmesg | grep 'initial timeout'
```

## Testing Watchdog Reboot (SysRq Crash)

The definitive test: trigger a kernel panic and verify the hardware
watchdog reboots the board automatically.

**Requires**: serial console access (SSH dies with the kernel) and
`CONFIG_MAGIC_SYSRQ=y` (enabled in `linux.fragment`).

### Manual Test

1. Open a serial console to the BBB (e.g. `picocom /dev/ttyUSB0`).

2. Note the current uptime:
   ```bash
   cat /proc/uptime
   ```

3. Trigger a kernel panic:
   ```bash
   echo c > /proc/sysrq-trigger
   ```

4. The kernel panics immediately.  On the serial console you'll see
   a stack trace and `Kernel panic - not syncing: sysrq triggered crash`.

5. The watchdog daemon is dead (the kernel is dead), so nothing pets
   `/dev/watchdog0`.  After ~60 seconds the OMAP WDT hardware fires
   and resets the SoC.  You'll see U-Boot start again on serial.

6. After the board boots, verify uptime is low (board rebooted):
   ```bash
   cat /proc/uptime
   ```

If the board reboots on its own after the panic, the watchdog works.

### Automated Test (labgrid)

```bash
# Safe tests only (default)
pytest tests/test_watchdog.py --lg-env tests/env.yaml -v

# Include the destructive sysrq reboot test (~90s, crashes the board)
pytest tests/test_watchdog.py --lg-env tests/env.yaml -v --run-destructive
```

The `--run-destructive` flag enables `TestWatchdogReboot` which triggers
a kernel panic via SysRq, waits ~90s for the board to come back, then
reconnects over SSH and verifies uptime is lower than before the crash.

## Configuration

Edit `board/bbb/rootfs-overlay/etc/watchdog.conf` to tune:

- `interval` — how often (seconds) to pet the watchdog
- `max-load-1` / `max-load-5` — load average reboot thresholds
- `min-memory` — minimum free memory (KB) before forced reboot

After changing, rebuild with `rm -rf output/target && make`.

## Disabling Temporarily

During kernel debugging or long-running tests, you may want to
stop the watchdog to prevent unexpected reboots:

```bash
systemctl stop watchdog.service
```

**Warning**: once the watchdog device has been opened, the hardware
timeout is armed.  Stopping the daemon will cause a reboot after
~60 seconds unless you also write `V` (the magic close character)
to the device.  The daemon handles this on clean shutdown.

## Testing

```bash
pytest tests/test_watchdog.py --lg-env tests/env.yaml -v
```
