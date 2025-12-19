# Scripts Documentation

## Overview

Everest includes several scripts for managing servers, plugins, and engines. This guide documents all available scripts and their usage.

## Script Directory Structure

```
scripts/
├── launcher           # Generic server launcher with auto-restart
├── updater           # Plugin/engine update orchestrator
└── utils/            # Update utility scripts
    ├── get-engine.sh    # Download server engines
    ├── get-plugin.sh    # Download plugins
    ├── link-library.sh  # Link engines to servers
    └── link-plugin.sh   # Link plugins to servers
```

## launcher

Generic server launcher with tmux-based process management and auto-restart.

### Usage

```bash
launcher <server-name> <engine-type> [java-flags...]
```

### Parameters

- **server-name**: Name of server (must match directory in `servers/`)
- **engine-type**: Engine to use (`paper` or `velocity`)
- **java-flags**: Additional JVM flags (e.g., `-Xms2G -Xmx4G`)

### Examples

```bash
# Launch Velocity proxy with 768MB RAM
launcher proxy velocity -Xms387M -Xmx768M

# Launch Paper server with 3GB RAM
launcher wildy paper -Xms3072M -Xmx3072M

# Launch with custom flags
launcher creative paper -Xms2G -Xmx4G -XX:MaxGCPauseMillis=100
```

### Features

#### 1. Tmux Session Management

- Creates detached tmux session named after server
- Allows attaching to server console
- Session persists after disconnection

```bash
# View running sessions
tmux ls

# Attach to server console
tmux attach -t wildy

# Detach: Ctrl+B then D
```

#### 2. Auto-Restart Loop

Server automatically restarts on crash:

```bash
while true; do
  java [flags] -jar server.jar nogui
  echo "Server stopped, restarting in 3 seconds..."
  sleep 3
done
```

To stop permanently:
```bash
# Method 1: Kill tmux session
tmux kill-session -t wildy

# Method 2: Attach and stop manually
tmux attach -t wildy
# Then stop without restart
```

#### 3. Engine-Specific JVM Flags

**Paper Servers** (Aikars Flags):
```bash
-XX:+UseG1GC
-XX:+DisableExplicitGC
-XX:+PerfDisableSharedMem
-XX:G1HeapRegionSize=8M
-XX:MaxGCPauseMillis=200
# ... and more
```

**Velocity Proxy**:
```bash
-XX:+UseG1GC
-XX:G1HeapRegionSize=4M
-XX:MaxInlineLevel=15
```

**Common Flags** (All Servers):
```bash
-XX:+UseG1GC
-XX:+AlwaysPreTouch
-XX:+ParallelRefProcEnabled
-XX:+UnlockExperimentalVMOptions
-Duser.timezone=Asia/Seoul
```

#### 4. Environment Variables

Automatically loads from `.env` file if present:

```bash
# .env example
JAVA_HOME=/usr/lib/jvm/java-21
TZ=Asia/Seoul
CUSTOM_VAR=value
```

#### 5. Process Detection

Checks if server is already running:

```bash
# The [j]ava pattern prevents pgrep from matching itself
pgrep -f "[j]ava.*$(basename "$JAR_FILE")"
```

If session exists but server is down, automatically restarts.

### Customization

Edit `scripts/launcher` to customize:

- JVM flags per engine type
- Auto-restart delay
- Session management behavior
- Engine detection logic

### Troubleshooting

**Session already exists**:
```bash
# View existing sessions
tmux ls

# Kill old session
tmux kill-session -t wildy

# Start fresh
./servers/wildy/start.sh
```

**Engine not found**:
```bash
# Verify engine exists
ls -la libraries/engines/

# Download engines
./scripts/updater
```

**Java not found**:
```bash
# Install Java 21
sudo apt install openjdk-21-jdk

# Verify installation
java -version
```

## updater

Orchestrator script that manages engine and plugin updates.

### Usage

```bash
./scripts/updater
```

No parameters needed - reads from `config/server.json` and `config/update.json`.

### Workflow

1. **Checks prerequisites** (jq, curl, etc.)
2. **Validates config files** exist
3. **Executes get-engine.sh** to download engines
4. **Executes get-plugin.sh** to download plugins
5. **Executes link-library.sh** to link engines
6. **Executes link-plugin.sh** to link plugins

### Output

```
[11:30:00 INFO] [updater]: Checking for required tools...
[11:30:00 INFO] [updater]: Starting downloading process...
[11:30:05 INFO] [get-engine]: Downloaded paper-1.21.10.jar
[11:30:10 INFO] [get-plugin]: Downloaded LuckPerms-Velocity-5.4.jar
[11:30:15 INFO] [updater]: Starting linking process...
[11:30:16 INFO] [link-library]: Linked paper -> servers/wildy/
[11:30:17 INFO] [link-plugin]: Linked 15 plugins to servers/wildy/
[11:30:17 INFO] [updater]: Updating processes completed.
```

### Error Handling

If any step fails, updater stops and reports error:

```
[11:30:20 ERROR] [updater]: Plugin download failed.
```

Check individual utility script logs for details.

### Best Practices

- **Backup first**: Backup configs before updating
- **Schedule updates**: Run during maintenance windows
- **Test first**: Test on staging server
- **Monitor logs**: Watch for errors during update
- **Restart after**: Restart servers after updating

## Utility Scripts

### get-engine.sh

Downloads Paper and Velocity engines from official sources.

**Location**: `scripts/utils/get-engine.sh`

**Usage**:
```bash
bash scripts/utils/get-engine.sh
```

**Configuration**: Reads from `config/update.json`:
```json
{
  "engines": {
    "paper": {
      "version": "1.21.10"
    },
    "velocity": {
      "version": "3.4.0-SNAPSHOT"
    }
  }
}
```

**Output Directory**: `libraries/engines/`

**Download Sources**:
- **Paper**: PaperMC API
- **Velocity**: PaperMC API

**Features**:
- Version-aware downloads
- Skips if already downloaded
- Validates JAR files
- Cleans old versions

### get-plugin.sh

Downloads plugins from various sources.

**Location**: `scripts/utils/get-plugin.sh`

**Usage**:
```bash
bash scripts/utils/get-plugin.sh
```

**Configuration**: Reads from `config/update.json`:
```json
{
  "plugins": {
    "velocity": {
      "plugin-name": "https://download-url"
    },
    "paper": {
      "plugin-name": "https://download-url"
    }
  }
}
```

**Output Directory**: `libraries/plugins/<engine>/`

**Supported Sources**:
- Direct JAR URLs
- Jenkins CI servers
- GitHub releases
- Custom APIs

**Features**:
- Multi-source support
- Parallel downloads
- Retry on failure
- Checksum validation (when available)

### link-library.sh

Creates symlinks for engine JARs.

**Location**: `scripts/utils/link-library.sh`

**Usage**:
```bash
bash scripts/utils/link-library.sh
```

**Purpose**: Links latest engine JAR to server directories for easy access.

**Example**:
```bash
libraries/engines/paper-1.21.10.jar
  → servers/wildy/paper.jar (symlink)
```

**Features**:
- Version-aware (links latest)
- Cleans old symlinks
- Validates targets exist

### link-plugin.sh

Creates symlinks for plugin JARs in server directories.

**Location**: `scripts/utils/link-plugin.sh`

**Usage**:
```bash
bash scripts/utils/link-plugin.sh
```

**Configuration**: Reads from `config/server.json`

**Features**:
- Pattern matching for plugins
- Cleans old symlinks
- Supports auto and manual plugins
- Reports missing plugins

**Example**:
```bash
libraries/plugins/paper/LuckPerms-5.4.jar
  → servers/wildy/plugins/LuckPerms-5.4.jar (symlink)
```

## Server Start Scripts

### proxy/start.sh

Starts Velocity proxy server.

**Location**: `servers/proxy/start.sh`

**Usage**:
```bash
./servers/proxy/start.sh
```

**Configuration**:
```bash
SERVER_NAME="proxy"
SERVER_ENGINE="velocity"
JAVA_FLAGS=(
  -Xms387M
  -Xmx768M
)
```

**Customization**:
- Adjust memory allocation in `JAVA_FLAGS`
- Change server name (must match directory)
- Add custom JVM flags

### wildy/start.sh

Starts Paper game server.

**Location**: `servers/wildy/start.sh`

**Usage**:
```bash
./servers/wildy/start.sh
```

**Configuration**:
```bash
SERVER_NAME="wildy"
SERVER_ENGINE="paper"
JAVA_FLAGS=(
  -Xms3072M
  -Xmx3072M
)
```

**Customization**:
- Adjust memory based on server load
- Add performance flags
- Configure timezone

## Creating New Servers

To create a new server with automated startup:

### 1. Create Server Directory

```bash
mkdir servers/newserver
```

### 2. Create Start Script

```bash
cat > servers/newserver/start.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

SERVER_NAME="newserver"
SERVER_ENGINE="paper"

JAVA_FLAGS=(
  -Xms2048M
  -Xmx2048M
)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "$SCRIPT_DIR/../..")"

"$ROOT_PATH/scripts/launcher" "$SERVER_NAME" "$SERVER_ENGINE" "${JAVA_FLAGS[@]}"
EOF

chmod +x servers/newserver/start.sh
```

### 3. Configure in server.json

```json
{
  "servers": {
    "newserver": {
      "engine": "paper",
      "plugins": {
        "LuckPerms": "auto://LuckPerms-*"
      }
    }
  }
}
```

### 4. Run Updater

```bash
./scripts/updater
```

### 5. Accept EULA

```bash
echo "eula=true" > servers/newserver/eula.txt
```

### 6. Start Server

```bash
./servers/newserver/start.sh
```

## Advanced Usage

### Custom Updater Workflow

Create custom update script for specific needs:

```bash
#!/bin/bash
# custom-update.sh

# Backup configs
tar -czf backup-$(date +%Y%m%d).tar.gz servers/*/plugins/*/config.yml

# Update
./scripts/updater

# Restart servers
tmux send-keys -t wildy "stop" C-m
tmux send-keys -t proxy "end" C-m

sleep 10

./servers/proxy/start.sh
./servers/wildy/start.sh

echo "Update complete!"
```

### Scheduled Updates

Use cron for automated updates:

```bash
# Edit crontab
crontab -e

# Add entry (weekly updates on Sunday 3 AM)
0 3 * * 0 /path/to/Everest/scripts/updater && /path/to/restart-servers.sh
```

### Debug Mode

Run scripts with debug output:

```bash
# Bash debug mode
bash -x scripts/updater

# Verbose logging
bash -v scripts/utils/get-plugin.sh
```

## Troubleshooting

### Script Fails to Execute

```bash
# Check permissions
ls -la scripts/launcher

# Make executable
chmod +x scripts/launcher
chmod +x scripts/updater
chmod +x scripts/utils/*.sh
```

### Missing Dependencies

```bash
# Install required tools
sudo apt update
sudo apt install tmux openjdk-21-jdk curl jq git
```

### Path Issues

Scripts use relative paths from repository root:

```bash
# Always run from repository root
cd /path/to/Everest
./scripts/updater

# Not like this:
cd scripts
./updater  # May fail
```

### Tmux Not Available

```bash
# Install tmux
sudo apt install tmux

# Or use screen instead (requires modifying launcher)
```

## Best Practices

### Script Maintenance

- **Keep scripts updated**: Pull latest changes regularly
- **Test changes**: Test script modifications on staging
- **Document customizations**: Note any custom changes
- **Version control**: Commit script changes to Git

### Error Handling

- **Check exit codes**: Ensure scripts exit on error (`set -e`)
- **Log outputs**: Redirect outputs for debugging
- **Validate inputs**: Check required files exist
- **Handle failures gracefully**: Provide clear error messages

### Performance

- **Parallel operations**: Run independent tasks concurrently
- **Efficient downloads**: Reuse existing downloads
- **Clean old files**: Remove unused versions regularly
- **Optimize symlinks**: Update links efficiently

## Additional Resources

- [Bash Scripting Guide](https://www.gnu.org/software/bash/manual/)
- [Tmux Documentation](https://github.com/tmux/tmux/wiki)
- [JVM Tuning Guide](https://aikar.co/2018/07/02/tuning-the-jvm-g1gc-garbage-collector-flags-for-minecraft/)
- [Paper Documentation](https://docs.papermc.io/)
