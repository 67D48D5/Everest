#!/system/bin/sh

# Disable Doze mode
dumpsys deviceidle disable

# Set CPU governor to performance for all CPUs
(
  for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    gov_file="$cpu/cpufreq/scaling_governor"
    if [ -f "$gov_file" ]; then
      echo performance >"$gov_file" 2>/dev/null
    fi
  done
) &

# Set I/O scheduler to noop
for blockdev in /sys/block/*/queue/scheduler; do
  echo noop >"$blockdev" 2>/dev/null
done

# Set swappiness to somewhat higher value in order to prevent `OOM Killer` from killing the processes
echo 80 >/proc/sys/vm/swappiness 2>/dev/null

# Set the CPU governor for the moderate cpuset
echo performance >/sys/devices/system/cpu/cpufreq/policy0/scaling_governor
