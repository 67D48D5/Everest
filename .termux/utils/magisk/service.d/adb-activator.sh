#!/system/bin/sh

# Wait for 12 seconds to ensure all services are up
sleep 12

# Set the ADB TCP port to `43219`
setprop service.adb.tcp.port 43219

# Restart the ADB daemon to apply the changes
stop adbd && start adbd
