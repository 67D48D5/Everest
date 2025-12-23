# Configuration Guide

## Overview

Everest uses multiple configuration files to manage servers, plugins, and updates. This guide covers all major configuration options.

## Configuration Files

### Repository Structure

```shell
config/
├── server.json    # Server and plugin definitions
└── update.json    # Update sources and versions
```

## server.json

Defines which plugins should be installed on each server.

### Structure

```json
{
  "servers": {
    "<server-name>": {
      "engine": "<engine-type>",
      "plugins": {
        "<plugin-name>": "<source-pattern>"
      }
    }
  }
}
```

### Example

```json
{
  "servers": {
    "proxy": {
      "engine": "velocity",
      "plugins": {
        "geyser": "auto://geyser-velocity*",
        "luckperms": "auto://LuckPerms-Velocity-*"
      }
    },
    "wildy": {
      "engine": "paper",
      "plugins": {
        "LuckPerms": "auto://LuckPerms-*",
        "CMI": "manual://CMI-*"
      }
    }
  }
}
```

### Plugin Source Patterns

**Auto-download plugins**:

- `auto://<pattern>` - Plugin will be downloaded automatically
- Pattern uses glob matching (e.g., `LuckPerms-*`)
- Downloaded plugins are stored in `libraries/plugins/<engine>/`

**Manual plugins**:

- `manual://<pattern>` - Plugin must be manually downloaded
- Pattern used to identify plugin in `libraries/plugins/<engine>/`
- Useful for premium/private plugins

### Adding a New Plugin

1. For auto-download plugins, add to `update.json` first
2. Add entry to `server.json`:

```json
"PluginName": "auto://PluginName-*"
```

1. Run updater:

```bash
./scripts/updater
```

### Removing a Plugin

1. Remove entry from `server.json`
2. Run updater (will remove symlink):

```bash
./scripts/updater
```

1. Optionally delete from library:

```bash
rm libraries/plugins/<engine>/<plugin>.jar
```

## update.json

Defines download sources and versions for engines and plugins.

### Config Structure

```json
{
  "engines": {
    "<engine-type>": {
      "version": "<version>"
    }
  },
  "plugins": {
    "<engine-type>": {
      "<plugin-name>": "<download-url>"
    }
  },
  "notes": {
    "plugins": {
      "<engine-type>": {
        "<plugin-name>": "<manual-download-url>"
      }
    }
  }
}
```

### Engines Section

Specifies engine versions to download:

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

**Supported Engines**:

- `paper`: Paper server (Bukkit/Spigot fork)
- `velocity`: Velocity proxy

### Plugins Section

URLs for auto-downloadable plugins:

```json
{
  "plugins": {
    "velocity": {
      "geyser": "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/velocity",
      "luckperms": "https://ci.lucko.me/job/LuckPerms"
    },
    "paper": {
      "LuckPerms": "https://ci.lucko.me/job/LuckPerms",
      "Chunky": "https://ci.codemc.io/view/Author/job/pop4959/job/Chunky"
    }
  }
}
```

**Supported URL Types**:

- Direct JAR downloads
- Jenkins CI servers
- GitHub releases (via API)
- Custom download endpoints

### Notes Section

Manual download references for premium/private plugins:

```json
{
  "notes": {
    "plugins": {
      "paper": {
        "CMI": "https://www.spigotmc.org/resources/cmi.3742/updates/",
        "CoreProtect": "https://github.com/PlayPro/CoreProtect/"
      }
    }
  }
}
```

### Adding a New Auto-Download Plugin

1. Add to `update.json`:

```json
{
  "plugins": {
    "paper": {
      "NewPlugin": "https://example.com/plugin/download"
    }
  }
}
```

1. Add to `server.json`:

```json
{
  "servers": {
    "wildy": {
      "plugins": {
        "NewPlugin": "auto://NewPlugin-*"
      }
    }
  }
}
```

1. Run updater:

```bash
./scripts/updater
```

## Server-Specific Configuration

### Velocity (Proxy)

**Main config**: `servers/proxy/velocity.toml`

#### Velocity Key Settings

**Network**:

```toml
bind = "0.0.0.0:25565"  # Listen on all interfaces
online-mode = true       # Mojang authentication
```

**MOTD**:

```toml
motd = """
<gradient:#5e4fa2:#f79459><bold>⛰ Everest MC</bold></gradient>
<gray>▶ Survival, Build, Explore</gray>
"""
```

**Backend Servers**:

```toml
[servers]
Wildy = "127.0.0.1:1422"

try = ["Wildy"]  # Default server
```

**Forwarding**:

```toml
player-info-forwarding-mode = "modern"
forwarding-secret-file = "fwkey.pem"
```

**Query**:

```toml
[query]
enabled = true
port = 25565
map = "Everest"
```

### Paper (Game Server)

**Main config**: `servers/wildy/server.properties`

#### Wildy Key Settings

**Server**:

```properties
server-port=1422
online-mode=false  # Proxy handles auth
max-players=48
difficulty=hard
gamemode=survival
```

**World**:

```properties
level-name=wwild
level-seed=4078373055178575627
level-type=normal
spawn-protection=0
```

**Performance**:

```properties
view-distance=10
simulation-distance=8
entity-broadcast-range-percentage=75
```

**Paper-Specific**: `servers/wildy/config/paper-global.yml`

```yaml
proxies:
  velocity:
    enabled: true
    online-mode: true
    secret: "<content of fwkey.pem>"

chunk-loading:
  min-chunk-load-threads: 2
  autoconfig-send-distance: true
```

### Start Scripts

**Proxy**: `servers/proxy/start.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

SERVER_NAME="proxy"
SERVER_ENGINE="velocity"

JAVA_FLAGS=(
  -Xms387M
  -Xmx768M
)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "$SCRIPT_DIR/../..")"

"$ROOT_PATH/scripts/launcher" "$SERVER_NAME" "$SERVER_ENGINE" "${JAVA_FLAGS[@]}"
```

**Game Server**: `servers/wildy/start.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

SERVER_NAME="wildy"
SERVER_ENGINE="paper"

JAVA_FLAGS=(
  -Xms3072M
  -Xmx3072M
)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "$SCRIPT_DIR/../..")"

"$ROOT_PATH/scripts/launcher" "$SERVER_NAME" "$SERVER_ENGINE" "${JAVA_FLAGS[@]}"
```

**Customization**:

- `SERVER_NAME`: Must match directory name in `servers/`
- `SERVER_ENGINE`: Must be `velocity` or `paper`
- `JAVA_FLAGS`: Adjust `-Xms` and `-Xmx` for memory allocation

## Plugin Configuration

### LuckPerms

**Proxy**: `servers/proxy/plugins/luckperms/config.yml`
**Game**: `servers/wildy/plugins/LuckPerms/config.yml`

Key settings:

```yaml
server: wildy  # Server name for permissions context
storage-method: h2  # or mysql for shared permissions

sync-minutes: 3  # How often to sync with storage
```

### Geyser (Bedrock Support)

**Config**: `servers/proxy/plugins/Geyser-Velocity/config.yml`

```yaml
bedrock:
  address: 0.0.0.0
  port: 19132  # Bedrock default port

remote:
  address: 127.0.0.1
  port: 25565  # Velocity port
```

### CoreProtect (Logging)

**Config**: `servers/wildy/plugins/CoreProtect/config.yml`

```yaml
database:
  engine: sqlite  # or mysql
  
logging:
  block-place: true
  block-break: true
  block-burn: true
  explosion: true
```

### GriefPrevention (Claims)

**Config**: `servers/wildy/plugins/GriefPreventionData/config.yml`

```yaml
Claims:
  InitialBlocks: 100
  BlocksAccruedPerHour: 100
  MaxAccruedBlocks: 80000
  
  MinimumWidth: 5
  MinimumArea: 25
```

### mcMMO (RPG Skills)

**Config**: `servers/wildy/plugins/mcMMO/config.yml`

```yaml
Skills:
  Mining:
    Enabled: true
  Woodcutting:
    Enabled: true
  Excavation:
    Enabled: true
```

## Environment Variables

Optional `.env` file in repository root:

```bash
# Java configuration (adjust path for your system)
# For amd64: /usr/lib/jvm/java-21-openjdk-amd64
# For arm64: /usr/lib/jvm/java-21-openjdk-arm64
JAVA_HOME=/usr/lib/jvm/java-21-openjdk

# Timezone
TZ=Asia/Seoul

# Custom environment variables
CUSTOM_VAR=value
```

Variables are automatically loaded by the launcher script.

## Firewall Configuration

### UFW (Ubuntu)

```bash
# Allow proxy port
sudo ufw allow 25565/tcp

# Allow Bedrock port (if using Geyser)
sudo ufw allow 19132/udp

# Deny backend ports
sudo ufw deny 1422/tcp

# Enable firewall
sudo ufw enable
```

### iptables

```bash
# Allow proxy
iptables -A INPUT -p tcp --dport 25565 -j ACCEPT

# Allow Bedrock
iptables -A INPUT -p udp --dport 19132 -j ACCEPT

# Deny backend
iptables -A INPUT -p tcp --dport 1422 -j DROP

# Save rules
iptables-save > /etc/iptables/rules.v4
```

## Best Practices

### Memory Allocation

**General Rules**:

- Set `-Xms` and `-Xmx` to the same value for Paper
- Leave 1-2GB for system (total RAM - server allocation)
- Velocity is lightweight (512-768MB sufficient)

**Example for 8GB Server**:

- System: 1GB
- Proxy: 768MB
- Wildy: 6GB (6144MB)

### View Distance

Balance performance vs. experience:

- High-performance: 6-8 chunks
- Balanced: 10 chunks
- High-quality: 12-15 chunks

### Backup Configuration

Files to backup regularly:

- `config/` - All configuration
- `servers/*/plugins/*/` - Plugin data
- `servers/*/world*/` - World files
- `servers/proxy/plugins/luckperms/` - Permissions
- `servers/proxy/fwkey.pem` - Forwarding secret

### Update Strategy

1. Test updates on staging server
2. Backup before updating
3. Update proxy last (allows backend updates first)
4. Monitor logs after update
5. Keep previous versions for rollback

## Troubleshooting

### Configuration Validation

Check JSON syntax:

```bash
jq empty config/server.json
jq empty config/update.json
```

### View Effective Configuration

```bash
# View current plugin links
ls -la servers/wildy/plugins/

# View current engine
ls -la libraries/engines/
```

### Reset Configuration

To reset a plugin configuration:

```bash
# Backup current config
cp servers/wildy/plugins/PluginName/config.yml config.yml.bak

# Delete and restart (plugin will regenerate)
rm servers/wildy/plugins/PluginName/config.yml
tmux send-keys -t wildy "reload confirm" C-m
```

## Additional Resources

- [Velocity Documentation](https://velocitypowered.com/wiki/)
- [Paper Documentation](https://docs.papermc.io/)
- [LuckPerms Wiki](https://luckperms.net/wiki/)
- [Geyser Wiki](https://wiki.geysermc.org/)
