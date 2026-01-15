# Everest MC

Modern Minecraft Server Infrastructure

## Overview

Everest is a production-ready Minecraft server infrastructure designed for running multi-server networks. It features a Velocity proxy for player routing and Paper servers for game worlds, with automated plugin management and deployment scripts.

## Features

- **Multi-Server Architecture**: `Velocity` proxy + `Paper` game servers
- **Automated Updates**: Smart plugin and engine version management
- **Production-Ready**: `Tmux`-based process management with auto-restart
- **Plugin Management**: Auto-download and link plugins from official sources
- **Cross-Platform**: Java and Bedrock edition support via `Geyser/Floodgate`
- **Performance Optimized**: `Aikars flags` for Paper, tuned JVM settings

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
├── config/             # Configuration files
│   ├── server.json     # Server instance and plugin definitions
│   └── update.json     # Update sources and versions
├── libraries/          # Downloaded engines and plugins
│   ├── common/         # Shared libraries
│   ├── engines/        # Paper and Velocity JARs
│   └── plugins/        # Downloaded plugins
├── scripts/            # Management scripts
│   ├── everest         # Main management script
│   └── utils/          # Management utilities scripts
└── servers/            # Server instances
    ├── velocity/       # Velocity proxy
    └── wildy/          # Paper survival server
```

## Server Information

- **Address**: `play.67d48d5.me`
- **Version Support**: Latest Minecraft version + backwards compatibility
- **Editions**: Java Edition & Bedrock Edition
- **Discord**: <https://discord.gg/gc9F7eTYt4>

## Scope

This repository focuses on **server orchestration and automation**.
Game content, plugins, and engines are intentionally treated as external dependencies

## License

> This project is for the `Everest MC` community.

For management scripts and **utilities authored in this repository**, [MIT License](LICENSE) is applied.

For **all** other components, please refer to their `respective` licenses.
