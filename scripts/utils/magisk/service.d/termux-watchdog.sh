#!/system/bin/sh

TERMUX_APP="com.termux"
SSHD_BIN="/data/data/com.termux/files/usr/bin/sshd"

log_msg() {
    log -t termux-watchdog "$1"
}

log_msg "Starting Termux watchdog..."

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
