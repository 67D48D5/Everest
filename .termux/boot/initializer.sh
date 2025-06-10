#!/data/data/com.termux/files/usr/bin/sh

# Prevent device sleep
termux-wake-lock

# Load environment variables
if [ -f /data/data/com.termux/files/home/.termux/.env ]; then
  . /data/data/com.termux/files/home/.termux/.env
fi

# Load optimizer script
OPTIMIZER_SCRIPT="$HOME/.termux/optimizer.sh"
[ -f "$OPTIMIZER_SCRIPT" ] && pgrep -f "$OPTIMIZER_SCRIPT" >/dev/null || su -c "nohup sh $OPTIMIZER_SCRIPT >/dev/null 2>&1 &"

# Service Watchdog
while true; do
  for svc in sshd mysqld php-fpm nginx; do
    sv up "$svc" || sv restart "$svc"
  done
  sleep 10
done
