#!/system/bin/sh

# Wait for 18 seconds to ensure all services are up
sleep 18

# First time start
am start -n com.termux/.HomeActivity

# Logging function
log_msg() {
    log -t "[$(date '+%H:%M:%S') TERMUX-WD]: $1"
}

# Ensure Termux is running
# Protect Termux from being killed by the system
(
    while true; do
        pid=$(pidof "com.termux")
        if [ -z "$pid" ]; then
            log_msg "Termux app not running, starting..."
            am start -n "com.termux/.HomeActivity"
            sleep 18
        else
            echo -17 >/proc/"$pid"/oom_adj 2>/dev/null
            echo -1000 >/proc/"$pid"/oom_score_adj 2>/dev/null
        fi

        sleep 24
    done
) &
