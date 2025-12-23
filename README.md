# Everest MC

Modern Minecraft Server Infrastructure

## Overview

Everest is a production-ready Minecraft server infrastructure designed for running multi-server networks. It features a Velocity proxy for player routing and Paper servers for game worlds, with automated plugin management and deployment scripts.

## Features

- 🚀 **Multi-Server Architecture**: `Velocity` proxy + `Paper` game servers
- 🔄 **Automated Updates**: Smart plugin and engine version management
- 🛠️ **Production-Ready**: `Tmux`-based process management with auto-restart
- 🔌 **Plugin Management**: Auto-download and link plugins from official sources
- 🎮 **Cross-Platform**: Java and Bedrock edition support via `Geyser/Floodgate`
- ⚡ **Performance Optimized**: `Aikars flags` for Paper, tuned JVM settings

## Quick Start

### Prerequisites

- Java 21 or higher
- `curl`, `jq` (for updater)
- `bash`, `tmux`

### Starting Servers

```bash
# Start the proxy server
./servers/proxy/start.sh

# Start the game server
./servers/wildy/start.sh
```

### Updating Engines & Plugins

```bash
# Download latest engines and plugins
./scripts/updater
```

## Architecture

Everest uses a proxy-based architecture:

```txt
Players → Velocity Proxy (port 25565)
              ↓
         Wildy Server (Paper, port 1422)
```

The Velocity proxy handles player connections and routes them to backend Paper servers. This allows for:

- Server switching without reconnecting
- Cross-version support (`ViaVersion`)
- Bedrock edition support (`Geyser/Floodgate`)
- Centralized ban management (`LiteBans`)

## Directory Structure

```shell
.
├── config/              # Configuration files
│   ├── server.json     # Server and plugin definitions
│   └── update.json     # Update sources and versions
├── scripts/            # Management scripts
│   ├── launcher        # Generic server launcher
│   ├── updater         # Plugin/engine update orchestrator
│   └── utils/          # Update utilities
├── servers/            # Server instances
│   ├── proxy/          # Velocity proxy
│   └── wildy/          # Paper survival server
└── libraries/          # Downloaded engines and plugins
    ├── engines/        # Paper and Velocity JARs
    └── plugins/        # Downloaded plugins
```

## Documentation

Detailed documentation is available in the `docs/` directory:

- [Architecture](docs/architecture.md) - Detailed server architecture
- [Deployment](docs/deployment.md) - Setup and deployment guide
- [Configuration](docs/configuration.md) - Configuration reference
- [Plugin Management](docs/plugin-management.md) - Managing plugins
- [Scripts](docs/scripts.md) - Script documentation

## Server Information

- **Address**: `play.67d48d5.me`
- **Version Support**: Latest Minecraft version + backwards compatibility
- **Editions**: Java Edition & Bedrock Edition
- **Discord**: <https://discord.gg/gc9F7eTYt4>

## License

This project is for the `Everest` MC community.
