# Deployment Guide

## Prerequisites

### System Requirements

- **OS**: Linux (Ubuntu 20.04+ recommended)
- **Java**: OpenJDK 21 or higher
- **RAM**: Minimum 4GB (8GB+ recommended)
- **Disk**: 10GB+ free space
- **CPU**: 2+ cores recommended

### Required Software

```bash
# Install Java 21
sudo apt update
sudo apt install openjdk-21-jdk

# Install tmux for process management
sudo apt install tmux

# Install utilities
sudo apt install curl jq git
```

## Initial Setup

### 1. Clone Repository

```bash
git clone https://github.com/67D48D5/Everest.git
cd Everest
```

### 2. Configure Environment (Optional)

Create a `.env` file in the root directory for environment variables:

```bash
# Example .env file
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
TZ=Asia/Seoul
```

### 3. Download Engines and Plugins

Run the updater to download Paper, Velocity, and all plugins:

```bash
./scripts/updater
```

This will:
- Download Paper and Velocity engines
- Download all configured plugins
- Create symlinks in server directories
- Take 5-10 minutes depending on internet speed

### 4. Configure Velocity Forwarding

Generate a forwarding secret key:

```bash
# Generate a random secret
openssl rand -base64 32 > servers/proxy/fwkey.pem
```

Copy this key to Paper servers:

```bash
# For Wildy server
cp servers/proxy/fwkey.pem servers/wildy/fwkey.pem
```

Update Paper server configuration:

```yaml
# servers/wildy/config/paper-global.yml
proxies:
  velocity:
    enabled: true
    online-mode: true
    secret: <content of fwkey.pem>
```

### 5. Configure Firewall

Only expose the proxy port to the internet:

```bash
# Allow proxy port
sudo ufw allow 25565/tcp

# Deny direct access to backend servers
sudo ufw deny 1422/tcp

# Enable firewall
sudo ufw enable
```

### 6. Accept Minecraft EULA

Edit `servers/wildy/eula.txt`:

```
eula=true
```

## Starting Servers

### Start in Correct Order

1. **Start Proxy First** (if backend servers not ready, proxy will queue players)
```bash
./servers/proxy/start.sh
```

2. **Start Backend Servers**
```bash
./servers/wildy/start.sh
```

### Verify Servers Running

```bash
# Check tmux sessions
tmux ls

# Expected output:
# proxy: 1 windows (created ...)
# wildy: 1 windows (created ...)

# Check processes
pgrep -af java
```

### Attach to Server Console

```bash
# Attach to proxy
tmux attach -t proxy

# Attach to wildy
tmux attach -t wildy

# Detach: Ctrl+B then D
```

## Configuration

### Domain Setup

Point your domain to the server IP:

```
# DNS A Record
play.67d48d5.me -> <SERVER_IP>
```

### SRV Record (Optional)

For custom port support:

```
# DNS SRV Record
_minecraft._tcp.play.67d48d5.me
Priority: 0
Weight: 5
Port: 25565
Target: play.67d48d5.me
```

## Post-Deployment

### 1. Set Up Permissions

Attach to proxy console:
```bash
tmux attach -t proxy
```

Grant yourself admin permissions:
```
lpv user <username> permission set *
```

### 2. Configure Plugins

Key plugins to configure:

**CoreProtect** (Block logging):
```bash
tmux attach -t wildy
# In console:
co inspect
```

**GriefPrevention** (Land claims):
- Players can claim land with a golden shovel
- Configure claim blocks in `servers/wildy/plugins/GriefPreventionData/config.yml`

**CMI** (Server management):
- Extensive configuration in `servers/wildy/plugins/CMI/config.yml`
- Set up economy, kits, warps, etc.

### 3. Pre-generate World

To reduce lag, pre-generate the world:

```bash
tmux attach -t wildy
# In console:
chunky world wwild
chunky radius 5000
chunky start
```

This will pre-generate a 10,000x10,000 block area.

## Maintenance

### Stopping Servers

To stop a server gracefully:

```bash
# Attach to console
tmux attach -t wildy

# Type 'stop' command
stop

# Or send via tmux
tmux send-keys -t wildy "stop" C-m
```

### Restarting Servers

Servers auto-restart on crash. To manually restart:

```bash
# Attach to console
tmux attach -t wildy

# Type 'stop', server will auto-restart
stop
```

To restart without auto-restart:

```bash
# Kill the tmux session
tmux kill-session -t wildy

# Start again
./servers/wildy/start.sh
```

### Updating Plugins

```bash
# Update all plugins
./scripts/updater

# Stop servers
tmux send-keys -t wildy "stop" C-m
tmux send-keys -t proxy "end" C-m

# Wait for shutdown (10 seconds)
sleep 10

# Restart servers
./servers/proxy/start.sh
./servers/wildy/start.sh
```

### Backup

Create a backup script:

```bash
#!/bin/bash
BACKUP_DIR="/backups/everest"
DATE=$(date +%Y%m%d_%H%M%S)

# Stop server for consistent backup
tmux send-keys -t wildy "save-all" C-m
sleep 5

# Backup worlds
tar -czf "$BACKUP_DIR/worlds_$DATE.tar.gz" \
    servers/wildy/wwild \
    servers/wildy/wwild_nether \
    servers/wildy/wwild_the_end

# Backup plugin data
tar -czf "$BACKUP_DIR/plugins_$DATE.tar.gz" \
    servers/wildy/plugins/CMI \
    servers/wildy/plugins/LuckPerms \
    servers/wildy/plugins/CoreProtect \
    servers/wildy/plugins/GriefPreventionData \
    servers/proxy/plugins/luckperms

# Backup configs
tar -czf "$BACKUP_DIR/config_$DATE.tar.gz" config/

# Keep last 7 days
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: $DATE"
```

Schedule with cron:
```bash
# Daily backup at 3 AM
0 3 * * * /path/to/backup.sh
```

## Troubleshooting

### Server Won't Start

1. Check Java version:
```bash
java -version
# Should be 21+
```

2. Check if port is in use:
```bash
netstat -tlnp | grep 25565
```

3. Check logs:
```bash
tmux attach -t proxy
# or
tmux attach -t wildy
```

### Can't Connect to Server

1. Check if proxy is running:
```bash
pgrep -af "java.*velocity"
```

2. Check if port is open:
```bash
netstat -tlnp | grep 25565
```

3. Check firewall:
```bash
sudo ufw status
```

4. Check velocity logs in tmux session

### Backend Server Not Connecting

1. Check if wildy is running:
```bash
pgrep -af "java.*paper"
```

2. Verify forwarding secret matches:
```bash
# Should be identical
cat servers/proxy/fwkey.pem
cat servers/wildy/fwkey.pem
```

3. Check Paper configuration:
```yaml
# servers/wildy/config/paper-global.yml
proxies:
  velocity:
    enabled: true
```

### High Memory Usage

1. Adjust JVM flags in `servers/wildy/start.sh`:
```bash
JAVA_FLAGS=(
  -Xms2048M  # Reduce minimum
  -Xmx2048M  # Reduce maximum
)
```

2. Reduce view distance in `servers/wildy/server.properties`:
```properties
view-distance=8
simulation-distance=6
```

3. Use Paper's optimization features:
```yaml
# servers/wildy/config/paper-world-defaults.yml
entities:
  spawning:
    per-player-mob-spawns: true
```

### Plugin Conflicts

1. Disable suspect plugin:
```bash
# Move plugin out of plugins directory
mv servers/wildy/plugins/SuspectPlugin.jar servers/wildy/plugins/disabled/
```

2. Restart server:
```bash
tmux send-keys -t wildy "stop" C-m
```

3. Check logs:
```bash
tmux attach -t wildy
```

## Security Best Practices

### 1. Firewall Configuration

- Only expose port 25565
- Backend servers should only listen on localhost
- Use UFW or iptables to restrict access

### 2. Keep Software Updated

```bash
# Update system packages
sudo apt update && sudo apt upgrade

# Update server engines and plugins
./scripts/updater
```

### 3. Regular Backups

- Automate daily backups
- Store backups off-site
- Test restore procedures

### 4. Monitor Server

- Set up monitoring (e.g., Prometheus + Grafana)
- Monitor disk space, CPU, memory
- Set up alerts for downtime

### 5. Use Strong Passwords

- Secure database passwords (if using MySQL)
- Secure RCON passwords (if enabled)
- Rotate forwarding secret periodically

## Advanced Configuration

### Multiple Backend Servers

To add another server:

1. Create server directory:
```bash
mkdir servers/creative
```

2. Add to `config/server.json`:
```json
{
  "servers": {
    "creative": {
      "engine": "paper",
      "plugins": { ... }
    }
  }
}
```

3. Add to `velocity.toml`:
```toml
[servers]
Wildy = "127.0.0.1:1422"
Creative = "127.0.0.1:1423"

try = ["Wildy"]
```

4. Create start script:
```bash
cp servers/wildy/start.sh servers/creative/start.sh
# Edit port and memory settings
```

### Custom JVM Flags

Edit `scripts/launcher` to add custom flags for specific engines.

### Performance Monitoring

Install and configure:
- Spark (plugin for profiling)
- Prometheus exporter
- Grafana dashboards

## Support

For issues with:
- **Everest infrastructure**: Check GitHub issues
- **Velocity**: https://velocitypowered.com/
- **Paper**: https://docs.papermc.io/
- **Plugins**: Check respective plugin documentation
