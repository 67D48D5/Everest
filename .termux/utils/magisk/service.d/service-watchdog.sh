#!/system/bin/sh

# First time start
am start -n com.termux/.HomeActivity

TERMUX_APP="com.termux"
SSHD_BIN="/data/data/com.termux/files/usr/bin/sshd"
MYSQLD_BIN="/data/data/com.termux/files/usr/bin/mysqld"

# Logging function
log_msg() {
    log -t "[$(date '+%H:%M:%S') WARN]: $1"
}

# `sshd` watchdog
while true; do
    # Check if `sshd` is working
    if ! pgrep -f "sshd" >/dev/null; then
        echo "[$(date '+%H:%M:%S') WARN]: 'sshd' is not running. Starting it with root."
        su -c "/data/data/com.termux/files/usr/bin/sshd" &
    fi

    # Check if `mysqld` is working
    if ! pgrep -f "mysqld" >/dev/null; then
        echo "[$(date '+%H:%M:%S') WARN]: 'mysqld' is not running. Starting it with root."
        su -c "/data/data/com.termux/files/usr/bin/mysqld" &
    fi

    # Check if `com.termux` is running
    if ! pidof com.termux >/dev/null 2>&1; then
        log_msg "Termux stopped... Restarting it!"
        am start -n com.termux/.HomeActivity
    fi
    sleep 10

    # Wait 24 seconds
    sleep 24
done

# Protect Termux from being killed by the system
(
    while true; do
        pid=$(pidof "$TERMUX_APP")
        if [ -n "$pid" ]; then
            echo -17 >/proc/$pid/oom_adj 2>/dev/null
            echo -1000 >/proc/$pid/oom_score_adj 2>/dev/null
        fi
        sleep 40
    done
) &

# Watchdog for Termux and its services
(
    while true; do
        # Ensure Termux is running
        if ! pidof "$TERMUX_APP" >/dev/null; then
            log_msg "Termux app not running, starting..."
            am start -n com.termux/.app.TermuxActivity
            sleep 40
        fi

        # Ensure sshd is running
        pidof sshd >/dev/null || {
            log_msg "Restarting sshd..."
            su -c "$SSHD_BIN" >/dev/null 2>&1
        }

        sleep 40
    done
) &
