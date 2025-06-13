#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Prevent device sleep
termux-wake-lock

# Termux storage setup
termux-setup-storage

# Install necessary packages
pkg update && pkg upgrade -y
pkg install -y termux-root termux-services openssh git wget curl jq openjdk-21 zsh mariadb tmux

# Move existing .termux directory and create a symlink
mv ~/.termux ~/.termux.bak
ln -s ~/everest/.termux ~/.termux

# @TODO: Complete the installation process
sudo cat

#!/system/bin/sh

am start -n com.termux/.HomeActivity

log() {
    echo "[TERMUX-WATCHDOG] $1"
}

while true; do
    if ! pidof com.termux >/dev/null 2>&1; then
        log "Termux stopped... Restarting it!"
        am start -n com.termux/.HomeActivity
    fi
    sleep 10
done
