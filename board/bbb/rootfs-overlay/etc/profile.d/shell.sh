#!/bin/sh
# Shell configuration for BusyBox ash.
# History persists via /data/root bind-mounted to /root (data-persist.service).

# Make non-login sub-shells also source this file
export ENV=/etc/profile.d/shell.sh

# History — HISTFILE must be set explicitly for ash to save/load
export HISTFILE="$HOME/.ash_history"
export HISTSIZE=1000

# On SIGTERM/SIGHUP, exit cleanly so ash's built-in SAVE_ON_EXIT runs.
# BusyBox ash's "history -w" is a no-op (the builtin ignores all flags),
# so we must trigger exitshell() → save_history() by calling "exit".
# Without this, systemd's SIGTERM during shutdown leaves the shell alive
# until SIGKILL (DefaultTimeoutStopSec), and history is never written.
trap 'exit 0' HUP TERM

# Prompt: green user @ blue BBB : yellow path $
export PS1='\[\e[1;32m\]\u\[\e[0m\]@\[\e[1;34m\]BBB\[\e[0m\]:\[\e[1;33m\]\w\[\e[0m\]\$ '
export EDITOR=vi

alias ll='ls -la'
alias la='ls -A'
alias vim='vi'
alias ..='cd ..'
alias ...='cd ..; cd ..'
alias ....='cd ..; cd ..; cd ..'
# Force-reboot (skips clean shutdown). History is lost — use normal 'reboot' instead.
rebootf() { sync; reboot -f; }
