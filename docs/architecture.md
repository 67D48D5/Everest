# Server Architecture

## Overview

Everest MC uses a multi-tiered architecture designed for scalability, reliability, and cross-platform compatibility. The infrastructure separates concerns between proxy and game servers, allowing for independent scaling and maintenance.

## Architecture Diagram

```txt
┌─────────────────────────────────────────────────────────┐
│                       Internet                          │
└────────────────────┬────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         │  Port 25565 (Public)  │
         └───────────┬───────────┘
                     │
    ┌────────────────▼────────────────┐
    │      Velocity Proxy Server      │
    │  - Player authentication        │
    │  - Server routing               │
    │  - Cross-version support        │
    │  - Bedrock edition support      │
    │  - Centralized permissions      │
    └────────────────┬────────────────┘
                     │
         ┌───────────┴───────────┐
         │   Internal Network    │
         │    (127.0.0.1)        │
         └───────────┬───────────┘
                     │
    ┌────────────────▼────────────────┐
    │    Paper Server (Wildy)         │
    │         Port 1422               │
    │  - Survival gameplay            │
    │  - World management             │
    │  - Game plugins                 │
    │  - Player data                  │
    └─────────────────────────────────┘
```

## Components

### 1. Velocity Proxy

**Purpose**: Frontend proxy that handles all player connections

**Key Features**:

- Player authentication with Mojang servers
- Modern forwarding for player info to backend servers
- Plugin ecosystem for proxy-level features
- Protocol translation (ViaVersion, ViaBackwards)
- Cross-platform support (Geyser, Floodgate)

**Configuration**: `servers/proxy/velocity.toml`

**Plugins**:

- **Geyser**: Bedrock edition support
- **Floodgate**: Bedrock player authentication
- **LuckPerms**: Permission management
- **ViaVersion/ViaBackwards**: Multi-version support
- **LiteBans**: Centralized ban system
- **CMIV**: CMI integration for Velocity

**Resource Allocation**:

- RAM: 387MB min, 768MB max
- JVM: G1GC with optimized flags

### 2. Paper Server (Wildy)

**Purpose**: Backend survival game server

**Key Features**:

- Paper (high-performance Spigot fork)
- Survival gameplay with enhanced features
- World protection and management
- RPG elements via mcMMO
- Anti-grief measures

**Configuration**: `servers/wildy/server.properties`, `spigot.yml`, `bukkit.yml`

**Plugins**:

- **CMI**: Core management suite
- **CoreProtect**: Block logging and rollback
- **GriefPrevention**: Land claiming system
- **LuckPerms**: Permission management
- **mcMMO**: RPG skill system
- **WorldGuard**: Region protection
- **TAB**: Scoreboard and tablist
- **FastAsyncWorldEdit**: World editing
- **Chunky**: Pre-generation and borders
- **PlaceholderAPI**: Dynamic placeholders
- **Vault**: Economy and permissions API
- **MobFarmManager**: Farm management
- **ProtocolLib**: Protocol manipulation library

**Resource Allocation**:

- RAM: 3072MB (fixed)
- JVM: Aikars flags optimized for Paper

### 3. Launcher Script

**Location**: `scripts/launcher`

**Purpose**: Generic server launcher with auto-restart functionality

**Features**:

- Tmux session management
- Auto-restart on crash
- Engine-specific JVM tuning
- Environment variable loading
- Process monitoring

**Usage**:

```bash
launcher <server-name> <engine-type> [java-flags...]
```

### 4. Update System

**Location**: `scripts/updater` and `scripts/utils/`

**Purpose**: Automated plugin and engine management

**Components**:

- `get-engine.sh`: Downloads Paper/Velocity from official sources
- `get-plugin.sh`: Downloads plugins from various sources
- `link-library.sh`: Creates symlinks for engines
- `link-plugin.sh`: Creates symlinks for plugins

**Configuration**: `config/server.json`, `config/update.json`

## Network Flow

### Player Connection Flow

1. **Player connects** to `play.67d48d5.me:25565`
2. **Velocity receives** connection and authenticates with Mojang
3. **Velocity forwards** player to Wildy server (127.0.0.1:1422)
4. **Paper accepts** connection with modern forwarding verification
5. **Player plays** on the Wildy survival server

### Data Flow

- **Player data**: Stored on Paper server (Wildy)
- **Permissions**: Synchronized between Velocity and Paper via LuckPerms
- **Bans**: Managed centrally on Velocity via LiteBans
- **World data**: Stored on Paper server

## Security Considerations

### Network Security

- **Forwarding Secret**: Velocity and Paper share a secret key (`fwkey.pem`) to verify player info
- **Firewall**: Only port 25565 should be exposed publicly
- **Internal Network**: Backend servers only accept connections from localhost

### Authentication

- **Online Mode**: Enabled on Velocity for Mojang authentication
- **Offline Mode**: Bedrock players authenticated via Floodgate
- **Force Key Authentication**: Enabled for enhanced security

### Permission System

- **LuckPerms**: Unified permission system across proxy and backend
- **Contexts**: Different permissions can apply based on server context

## Process Management

### Tmux Sessions

Each server runs in its own tmux session:

- `proxy`: Velocity proxy server
- `wildy`: Paper game server

### Auto-Restart

Servers automatically restart on crash via the launcher script's restart loop.

### Monitoring

Check server status:

```bash
# List tmux sessions
tmux ls

# Attach to a server
tmux attach -t proxy
tmux attach -t wildy

# Check if Java process is running
pgrep -f "java.*velocity"
pgrep -f "java.*paper"
```

## Scaling Considerations

### Horizontal Scaling

To add more game servers:

1. Create new server directory in `servers/`
2. Add server to `velocity.toml` under `[servers]`
3. Create start script with appropriate port and resources
4. Update `config/server.json` for plugin management

### Vertical Scaling

Adjust JVM memory flags in each server's `start.sh`:

- `-Xms`: Minimum heap size
- `-Xmx`: Maximum heap size

### Performance Tuning

- **Paper**: Uses Aikars flags for optimal garbage collection
- **Velocity**: Lightweight configuration for proxy workload
- **Timezone**: Set to Asia/Seoul via `-Duser.timezone`

## Backup Strategy

### Critical Data

Directories to backup:

- `servers/wildy/wwild/` - Main world
- `servers/wildy/wwild_nether/` - Nether world
- `servers/wildy/wwild_the_end/` - End world
- `servers/wildy/plugins/*/` - Plugin data (especially CMI, LuckPerms, CoreProtect)
- `servers/proxy/plugins/luckperms/` - Proxy permissions
- `config/` - Configuration files

### Plugin Data

- **CoreProtect**: Block logging database
- **GriefPrevention**: Land claims
- **CMI**: Player data, homes, warps
- **LuckPerms**: Permissions and groups

## Disaster Recovery

### Server Crash

Auto-restart is handled by the launcher script. Check logs:

```bash
tmux attach -t <server-name>
# View scrollback: Ctrl+B then [
```

### World Corruption

1. Stop the server
2. Restore world from backup
3. Run CoreProtect rollback if needed
4. Restart server

### Plugin Issues

1. Check logs in tmux session
2. Disable problematic plugin (remove from plugins/ directory)
3. Restart server
4. Report issue to plugin developer
