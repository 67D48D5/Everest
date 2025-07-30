#!/data/data/com.termux/files/usr/bin/sh

# Prevent device sleep
termux-wake-lock

# Load environment variables
ENV_FILE="$HOME/.termux/.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

# Service Watchdog
while true; do
  for svc in sshd mysqld; do
    sv up "$svc" || sv restart "$svc"
  done
  sleep 10
done
