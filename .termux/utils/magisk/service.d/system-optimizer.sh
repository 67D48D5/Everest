#!/system/bin/sh

# Disable Doze mode to prevent the device from going into deep sleep.
# This keeps background services active.
dumpsys deviceidle disable

# Set all CPU governors to 'performance' mode.
# This ensures a steady, high-frequency state for all CPU cores.
for cpu_policy in /sys/devices/system/cpu/cpufreq/policy*; do
  gov_file="$cpu_policy/scaling_governor"
  if [ -f "$gov_file" ]; then
    echo performance >"$gov_file" 2>/dev/null
  fi
done

# Set I/O scheduler to 'noop' for all block devices.
# This is a simple scheduler optimized for SSDs and minimizes disk I/O latency.
for blockdev in /sys/block/*/queue/scheduler; do
  echo noop >"$blockdev" 2>/dev/null
done

# Set swappiness to a moderate value (80).
# This would help prevent `OOM Killer` from killing the processes
echo 80 >/proc/sys/vm/swappiness 2>/dev/null

# Clear file caches to free up memory.
# This is especially useful after a long period of use.
echo 2 >/proc/sys/vm/drop_caches

# Adjust Low Memory Killer (LMK) parameters.
# The values are in pages. This setting makes the system more lenient
# with memory, reducing the chance of background app kills.
echo "18432,23040,27648,32256,36864,46080" >/sys/module/lowmemorykiller/parameters/minfree

# --- 4. Ensure CPU Cores Are Online ---
# Make sure all CPU cores are online and active.
# This prevents the system from offline cores for power saving.
echo 1 >/sys/devices/system/cpu/cpu1/online
echo 1 >/sys/devices/system/cpu/cpu2/online
echo 1 >/sys/devices/system/cpu/cpu3/online
echo 1 >/sys/devices/system/cpu/cpu4/online
echo 1 >/sys/devices/system/cpu/cpu5/online
echo 1 >/sys/devices/system/cpu/cpu6/online
echo 1 >/sys/devices/system/cpu/cpu7/online
