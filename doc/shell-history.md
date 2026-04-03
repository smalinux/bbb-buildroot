# Shell History Persistence

## What

Shell command history survives reboots and OTA updates on the BeagleBone Black.

## How it works

Three things make this work:

1. **Persistent storage**: `data-persist.service` bind-mounts `/data/root` over `/root`
   at boot. Since ash writes history to `$HOME/.ash_history` (= `/root/.ash_history`),
   the file lives on the `/data` partition which is never overwritten by RAUC OTA.

2. **BusyBox ash SAVE_ON_EXIT**: ash is compiled with `CONFIG_FEATURE_EDITING_SAVEHISTORY=y`
   and `CONFIG_FEATURE_EDITING_SAVE_ON_EXIT=y`. On clean exit, `exitshell()` calls
   `save_history()` which writes in-memory history to the file. This is the **only**
   mechanism that actually writes history — see the bug section below.

3. **Boot ordering**: `data-persist.service` runs `Before=getty.target` so the
   bind-mount is in place before any login shell starts. Without this, ash would
   write to the ephemeral rootfs `/root/` and the file would be hidden when the
   bind-mount happens later.

4. **Signal trap**: `profile.d/shell.sh` sets `trap 'exit 0' HUP TERM` so the
   shell exits cleanly on SIGTERM (systemd shutdown) and SIGHUP (terminal hangup),
   triggering SAVE_ON_EXIT.

## The `history -w` bug in BusyBox ash

BusyBox ash's `history` builtin **ignores all flags** (`-w`, `-r`, `-c`, etc.).
The implementation in `ash.c` is:

```c
historycmd(int argc UNUSED_PARAM, char **argv UNUSED_PARAM)
{
    show_history(line_input_state);  // just prints, ignores flags
    return EXIT_SUCCESS;
}
```

This means `history -w` does NOT write history to disk — it simply prints the
history list to stdout. Any trap relying on `history -w` to persist history is
silently broken.

### Why SSH worked but serial console didn't

The `history -w` bug was masked by a difference in how SSH and serial sessions
end during system shutdown:

**SSH (dropbear)**:
1. systemd stops dropbear → SSH connection drops → PTY closes
2. Shell detects EOF on stdin → calls `exitshell()` (clean exit)
3. `save_history()` runs inside `exitshell()` → history saved

**Serial console (agetty)**:
1. systemd sends SIGTERM to serial-getty cgroup
2. Old trap ran `history -w` → printed history to stdout (no-op)
3. Shell continued running (trap handlers don't cause exit)
4. After `DefaultTimeoutStopSec` (10s), systemd sent SIGKILL
5. Shell killed instantly → `exitshell()` never ran → history lost

### The fix

Replace the broken trap:
```sh
# BROKEN — history -w is a no-op in BusyBox ash
trap 'history -w 2>/dev/null' EXIT HUP TERM

# FIXED — exit cleanly so SAVE_ON_EXIT runs
trap 'exit 0' HUP TERM
```

No EXIT trap is needed because `exitshell()` calls `save_history()` before
running EXIT trap handlers.

## Why `login` clears the environment (and why it doesn't matter)

BusyBox `login` (without `-p`) calls `clearenv()`, wiping all environment
variables including HISTFILE/ENV/HISTSIZE from systemd's `DefaultEnvironment`.
Only TERM, PATH, HOME, SHELL, USER, LOGNAME survive.

This does **not** break history because BusyBox ash loads history lazily:

1. Shell starts → sources `/etc/profile` → `/etc/profile.d/shell.sh` → sets HISTFILE
2. Shell enters interactive mode → first prompt triggers `load_history()`
3. HISTFILE is already set by step 1 → history loads correctly

The `DefaultEnvironment` in systemd still serves a purpose: it sets `ENV` for
non-login subshells (e.g., running `sh` interactively), which source `shell.sh`
via the ENV mechanism.

## Files involved

| File | Role |
|------|------|
| `board/bbb/systemd/data-persist.service` | Ordering: `Before=getty.target` |
| `board/bbb/systemd/data-persist.sh` | Bind-mounts `/data/root` → `/root` |
| `board/bbb/rootfs-overlay/etc/profile.d/shell.sh` | HISTFILE, HISTSIZE, signal trap, aliases |
| `board/bbb/systemd/10-environment.conf` | DefaultEnvironment for ENV/HISTFILE (non-login shells) |

## Force-reboot

`reboot -f` skips clean shutdown, so ash never runs its exit handler and history
is lost. Use normal `reboot` instead, which triggers systemd shutdown → SIGTERM →
trap → clean exit → history saved.
