#!/system/bin/sh

# Power Management Optimizations
## Disable Doze mode & reset battery stats
dumpsys deviceidle disable
dumpsys battery reset

## Set CPU governor to performance for all CPUs
(
  for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    gov_file="$cpu/cpufreq/scaling_governor"
    if [ -f "$gov_file" ]; then
      echo performance >"$gov_file" 2>/dev/null
    fi
  done
) &

## Set I/O scheduler to noop
for blockdev in /sys/block/*/queue/scheduler; do
  echo noop >"$blockdev" 2>/dev/null
done

## Set swappiness
echo 80 >/proc/sys/vm/swappiness 2>/dev/null

## Make sure the CPU cores are online
echo 0-7 >/dev/cpuset/moderate/cpus

## Set oom_score_adj for Android apps to prevent them from being killed
(
  while true; do
    TERMUX_PID=$(pidof com.termux)
    if [ -n "$TERMUX_PID" ]; then
      echo -1000 >/proc/$TERMUX_PID/oom_score_adj 2>/dev/null
    fi

    for pid in /proc/[0-9]*; do
      uid=$(grep '^Uid:' "$pid/status" 2>/dev/null | awk '{print $2}')
      if [ -n "$uid" ]; then
        username=$(id "$uid" 2>/dev/null)
        echo "$username" | grep -q 'u0_a' && echo -1000 >"$pid/oom_score_adj" 2>/dev/null
      fi
    done

    sleep 32
  done
) &
