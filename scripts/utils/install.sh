#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../..")"

# Prevent device sleep
termux-wake-lock

# Termux storage setup
termux-setup-storage

# Update package lists and upgrade installed packages
pkg update && pkg upgrade -y

# Install necessary packages
pkg install -y termux-root termux-services tsu
pkg install -y zsh openssh mosh git wget curl jq openjdk-21 tmux jq mariadb tmux tree fzf zip unzip neovim vim

# Enable Termux services
bash -c "sv-enable mysqld && sv-enable sshd"

# Move existing .termux directory and create a symlink
mv ~/.termux ~/.termux.bak
ln -sf $(realpath ${ROOT_PATH}/.termux) ~/.termux

# Allow script execution
chmod -R +x ${ROOT_PATH}/scripts
chmod +x ~/.termux/boot/*.sh ~/.termux/optimizer.sh

# Create or append to the Termux startup script for Magisk
STARTUP_SCRIPT="/data/adb/services.d/start-termux.sh"
sudo cat <<'EOF' | sudo tee "${STARTUP_SCRIPT}" >/dev/null
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
EOF

# Ensure the startup script is executable
sudo chmod +x "${STARTUP_SCRIPT}"
