#!/data/data/com.termux/files/usr/bin/sh

# Prevent device sleep
termux-wake-lock

# Start SSHD Immediately
sshd

# Service Watchdog
while true; do
  for svc in sshd mysqld; do
    sv up "$svc" || sv restart "$svc"
  done
  sleep 14
done
