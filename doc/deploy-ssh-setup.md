# Deploy Script SSH Setup

## Problem

The deploy script (`deploy.sh`) uses SSH/SCP to upload and install RAUC
bundles on the BeagleBone Black. Two issues make this painful out of the box:

1. **Host key changes on every reflash.** Dropbear (the SSH server on the
   board) regenerates its host keys on first boot. After flashing a new SD
   card image or completing an OTA update to a new rootfs slot, the host key
   changes. OpenSSH on the host then refuses to connect with a
   `REMOTE HOST IDENTIFICATION HAS CHANGED` error.

2. **Password prompt on every command.** The script runs three SSH commands
   (scp, rauc install, reboot). Each one prompts for the root password.

## Solution

### Host key checking

The deploy script passes these SSH options to all connections:

```
-o StrictHostKeyChecking=no     # accept any host key without prompting
-o UserKnownHostsFile=/dev/null # don't save keys (avoids polluting known_hosts)
-o LogLevel=ERROR               # suppress the warning noise
```

This is appropriate for a development board on a local network. Do not use
these options for production or internet-facing hosts.

### Password authentication

The script uses `sshpass` to pass the root password non-interactively:

```
sshpass -p "$BOARD_PASS" ssh ... root@<board-ip>
```

The password defaults to `root` (matching the buildroot default set via
`BR2_TARGET_GENERIC_ROOT_PASSWD="root"` in defconfig). Override it with
the `BOARD_PASS` environment variable:

```
BOARD_PASS=mypassword ./deploy.sh 192.168.0.98
```

### Host prerequisite

Install `sshpass` on the build host:

```
# Debian/Ubuntu
sudo apt install sshpass

# Fedora
sudo dnf install sshpass
```

The script checks for `sshpass` and exits with an error if it's missing.

## Usage

```bash
# Default password (root)
./deploy.sh 192.168.0.98

# Custom password
BOARD_PASS=secret ./deploy.sh 192.168.0.98
```

## Security notes

- The default root password is `root`. Change it for any board exposed
  beyond a private development network.
- `sshpass` passes the password via an environment variable, which is
  visible in `/proc/<pid>/environ` on the host. This is acceptable for
  local development; for production deployments use SSH key-based auth.
- `StrictHostKeyChecking=no` disables MITM protection. Only use this on
  trusted local networks where you control the board.
