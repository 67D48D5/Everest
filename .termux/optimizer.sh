#!/system/bin/sh

# Power Management Optimizations
## Disable Doze mode & reset battery stats
dumpsys deviceidle disable
dumpsys battery reset

## Set CPU governors to performance
for gov_file in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
  echo performance >"$gov_file" 2>/dev/null
done

## Set I/O scheduler to noop
for blockdev in /sys/block/*/queue/scheduler; do
  echo noop >"$blockdev" 2>/dev/null
done

## Set swappiness
echo 80 >/proc/sys/vm/swappiness 2>/dev/null

## Set oom_score_adj for Android apps to prevent them from being killed
(
  while true; do
    for uid in $(ls /proc | grep '^[0-9]' | xargs -I{} sh -c "cat /proc/{}/status 2>/dev/null | grep '^Uid:' | awk '{print \$2}'" | sort -u); do
      if id "$uid" 2>/dev/null | grep -q 'u0_a'; then
        for pid in $(pgrep -u "$uid"); do
          echo -1000 >/proc/$pid/oom_score_adj 2>/dev/null
        done
      fi
    done
    sleep 32
  done
) &
