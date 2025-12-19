# Plugin Management Guide

## Overview

Everest includes an automated plugin management system that handles downloading, linking, and updating plugins across multiple servers. This guide covers how to manage plugins effectively.

## Plugin Management System

### Architecture

```
Plugin Lifecycle:
1. Define in update.json (download source)
2. Define in server.json (which servers need it)
3. Run updater → downloads to libraries/plugins/
4. Updater creates symlinks → servers/*/plugins/
5. Server loads plugin on start
```

### Directory Structure

```
libraries/
└── plugins/
    ├── velocity/        # Velocity proxy plugins
    │   ├── geyser-velocity-*.jar
    │   └── LuckPerms-Velocity-*.jar
    └── paper/           # Paper server plugins
        ├── LuckPerms-*.jar
        └── mcMMO-*.jar

servers/
├── proxy/
│   └── plugins/
│       ├── geyser-velocity-*.jar -> ../../../libraries/plugins/velocity/geyser-*
│       └── ...
└── wildy/
    └── plugins/
        ├── LuckPerms-*.jar -> ../../../libraries/plugins/paper/LuckPerms-*
        └── ...
```

## Adding Plugins

### Auto-Download Plugins

For plugins with public download URLs:

#### 1. Add Download Source to update.json

```json
{
  "plugins": {
    "paper": {
      "PluginName": "https://example.com/plugin/download"
    }
  }
}
```

Supported sources:
- **Direct JAR URLs**: `https://example.com/plugin.jar`
- **Jenkins CI**: `https://ci.example.com/job/PluginName`
- **GitHub Releases**: `https://api.github.com/repos/user/plugin/releases`
- **Custom APIs**: Any URL returning a JAR file

#### 2. Add to Server Configuration

Edit `config/server.json`:

```json
{
  "servers": {
    "wildy": {
      "plugins": {
        "PluginName": "auto://PluginName-*"
      }
    }
  }
}
```

The pattern `PluginName-*` will match any JAR starting with `PluginName-`.

#### 3. Download and Install

```bash
./scripts/updater
```

This will:
- Download the plugin to `libraries/plugins/<engine>/`
- Create a symlink in `servers/wildy/plugins/`

#### 4. Restart Server

```bash
tmux send-keys -t wildy "stop" C-m
# Server will auto-restart
```

### Manual Plugins

For premium or private plugins that require manual download:

#### 1. Add Note to update.json

```json
{
  "notes": {
    "plugins": {
      "paper": {
        "PremiumPlugin": "https://www.spigotmc.org/resources/plugin.1234/"
      }
    }
  }
}
```

#### 2. Download Plugin Manually

Download the plugin JAR and place in:
```bash
libraries/plugins/paper/PremiumPlugin-1.0.0.jar
```

#### 3. Add to Server Configuration

```json
{
  "servers": {
    "wildy": {
      "plugins": {
        "PremiumPlugin": "manual://PremiumPlugin-*"
      }
    }
  }
}
```

#### 4. Run Updater

```bash
./scripts/updater
```

The updater will create symlinks for manual plugins.

#### 5. Restart Server

```bash
tmux send-keys -t wildy "stop" C-m
```

## Updating Plugins

### Update All Plugins

```bash
# Download latest versions
./scripts/updater

# Stop servers
tmux send-keys -t wildy "stop" C-m
tmux send-keys -t proxy "end" C-m

# Wait for shutdown
sleep 10

# Restart servers
./servers/proxy/start.sh
./servers/wildy/start.sh
```

### Update Single Plugin

For auto-download plugins:

```bash
# Run updater (will fetch latest)
./scripts/updater

# Restart server
tmux send-keys -t wildy "stop" C-m
```

For manual plugins:

```bash
# Download new version manually
wget https://example.com/plugin-2.0.0.jar -O libraries/plugins/paper/Plugin-2.0.0.jar

# Remove old version
rm libraries/plugins/paper/Plugin-1.0.0.jar

# Run updater to update symlink
./scripts/updater

# Restart server
tmux send-keys -t wildy "stop" C-m
```

### Version Pinning

To prevent auto-updates, use specific version in pattern:

```json
{
  "plugins": {
    "PluginName": "auto://PluginName-1.2.3.jar"
  }
}
```

## Removing Plugins

### 1. Remove from server.json

```json
{
  "servers": {
    "wildy": {
      "plugins": {
        // Remove this line:
        // "PluginName": "auto://PluginName-*"
      }
    }
  }
}
```

### 2. Run Updater

```bash
./scripts/updater
```

This removes the symlink from `servers/wildy/plugins/`.

### 3. Restart Server

```bash
tmux send-keys -t wildy "stop" C-m
```

### 4. Optionally Remove from Library

```bash
rm libraries/plugins/paper/PluginName-*.jar
```

Also remove from `update.json` if no longer needed.

## Plugin Dependencies

### Dependency Management

Some plugins require other plugins. The updater doesn't handle dependencies automatically, so you must add them manually.

Example: TAB requires PlaceholderAPI

```json
{
  "servers": {
    "wildy": {
      "plugins": {
        "PlaceholderAPI": "auto://PlaceholderAPI-*",
        "TAB": "auto://TAB-*"
      }
    }
  }
}
```

### Common Dependencies

- **PlaceholderAPI**: Required by TAB, CMI, many others
- **Vault**: Required by economy plugins
- **ProtocolLib**: Required by TAB, some anti-cheat plugins
- **CMILib**: Required by CMI

## Plugin Configuration

### Initial Configuration

After installing a plugin:

1. Start server (plugin generates default config)
2. Stop server
3. Edit configuration in `servers/wildy/plugins/PluginName/`
4. Start server again

### Hot Reload

Some plugins support reloading configuration without restart:

```bash
tmux attach -t wildy

# In console:
/pluginname reload
# or
/reload confirm  # Reloads all plugins (not recommended for production)
```

### Configuration Backup

Before updating plugins, backup configurations:

```bash
# Backup all plugin configs
tar -czf plugin-configs-$(date +%Y%m%d).tar.gz servers/wildy/plugins/*/config.yml servers/wildy/plugins/*/config/
```

## Installed Plugins

### Velocity Proxy Plugins

| Plugin | Purpose | Config |
|--------|---------|--------|
| Geyser | Bedrock edition support | `servers/proxy/plugins/Geyser-Velocity/config.yml` |
| Floodgate | Bedrock authentication | `servers/proxy/plugins/floodgate/config.yml` |
| LuckPerms | Permission management | `servers/proxy/plugins/luckperms/config.yml` |
| ViaVersion | Multi-version support | `servers/proxy/plugins/viaversion/config.yml` |
| ViaBackwards | Older version support | `servers/proxy/plugins/viabackwards/config.yml` |
| LiteBans | Ban management | `servers/proxy/plugins/litebans/config.yml` |
| CMIV | CMI proxy integration | `servers/proxy/plugins/CMIV/config.yml` |

### Paper Server Plugins

| Plugin | Purpose | Config |
|--------|---------|--------|
| CMI | Server management suite | `servers/wildy/plugins/CMI/config.yml` |
| CMILib | CMI library | - |
| CoreProtect | Block logging | `servers/wildy/plugins/CoreProtect/config.yml` |
| GriefPrevention | Land claims | `servers/wildy/plugins/GriefPreventionData/config.yml` |
| LuckPerms | Permissions | `servers/wildy/plugins/LuckPerms/config.yml` |
| mcMMO | RPG skills | `servers/wildy/plugins/mcMMO/config.yml` |
| WorldGuard | Region protection | `servers/wildy/plugins/WorldGuard/config.yml` |
| TAB | Tablist/scoreboard | `servers/wildy/plugins/TAB/config.yml` |
| FastAsyncWorldEdit | World editing | `servers/wildy/plugins/FastAsyncWorldEdit/config.yml` |
| Chunky | World pre-generation | `servers/wildy/plugins/Chunky/config.yml` |
| ChunkyBorder | World borders | `servers/wildy/plugins/ChunkyBorder/config.yml` |
| PlaceholderAPI | Placeholder system | `servers/wildy/plugins/PlaceholderAPI/config.yml` |
| Vault | Economy/permissions API | `servers/wildy/plugins/Vault/config.yml` |
| MobFarmManager | Farm management | `servers/wildy/plugins/MobFarmManager/config.yml` |
| ProtocolLib | Protocol library | `servers/wildy/plugins/ProtocolLib/config.yml` |

## Troubleshooting

### Plugin Not Loading

1. **Check logs**:
```bash
tmux attach -t wildy
# Look for error messages
```

2. **Verify symlink**:
```bash
ls -la servers/wildy/plugins/PluginName*
# Should show symlink to libraries/plugins/
```

3. **Check dependencies**:
- Read plugin documentation for required dependencies
- Ensure all dependencies are installed

4. **Check Paper version**:
- Some plugins require specific Paper versions
- Update Paper if needed

### Plugin Conflicts

Two plugins may conflict:

1. **Identify conflict**:
```bash
tmux attach -t wildy
# Look for error messages mentioning plugin names
```

2. **Disable one plugin**:
```bash
mv servers/wildy/plugins/ConflictingPlugin.jar servers/wildy/plugins/disabled/
```

3. **Restart and test**:
```bash
tmux send-keys -t wildy "stop" C-m
```

### Update Failures

If updater fails:

1. **Check internet connection**:
```bash
curl -I https://ci.lucko.me/job/LuckPerms
```

2. **Check update.json syntax**:
```bash
jq empty config/update.json
```

3. **Manual download**:
```bash
# Download manually and place in libraries/plugins/
wget https://example.com/plugin.jar -O libraries/plugins/paper/Plugin.jar
```

4. **Check download script logs**:
```bash
bash -x scripts/updater
```

### Outdated Plugins

If a plugin is outdated:

1. **Check for updates**:
- Visit plugin's website/GitHub
- Check if update.json URL is correct

2. **Update manually**:
- Download latest version
- Replace in `libraries/plugins/`
- Run updater to update symlinks

3. **Update source URL**:
- If URL changed, update `update.json`

### Permission Issues

If plugins can't write files:

```bash
# Fix ownership
chown -R $(whoami):$(whoami) servers/wildy/plugins/

# Fix permissions
chmod -R 755 servers/wildy/plugins/
```

## Best Practices

### Plugin Selection

- **Essential plugins only**: More plugins = more overhead
- **Maintained plugins**: Check update frequency
- **Compatible versions**: Ensure Paper version compatibility
- **Trusted sources**: Use official download URLs

### Update Strategy

1. **Test updates**: Test on staging server first
2. **Backup first**: Backup configurations and data
3. **Read changelogs**: Check for breaking changes
4. **Update gradually**: Don't update all plugins at once
5. **Monitor logs**: Watch for errors after updating

### Configuration Management

- **Version control**: Commit configs to Git
- **Document changes**: Note why configs were changed
- **Use defaults**: Only change what's necessary
- **Regular backups**: Automate config backups

### Performance Optimization

- **Disable unused features**: Turn off unnecessary plugin features
- **Optimize database**: Use appropriate database for plugins
- **Monitor resource usage**: Use Spark plugin for profiling
- **Limit entity tracking**: Configure plugin entity limits

## Advanced Topics

### Custom Plugin Development

To add custom plugins:

1. Build plugin JAR
2. Place in `libraries/plugins/<engine>/`
3. Add to `server.json` with `manual://` prefix
4. Run updater

### Shared Plugin Libraries

For multiple servers sharing plugins:

```bash
# Single library, multiple symlinks
libraries/plugins/paper/SharedPlugin.jar
  ← servers/server1/plugins/SharedPlugin.jar
  ← servers/server2/plugins/SharedPlugin.jar
```

### Plugin Version Management

Track plugin versions:

```bash
# List all installed plugins with versions
ls -la servers/wildy/plugins/*.jar | awk '{print $NF}' | sed 's/.*\///'
```

Create version manifest:
```bash
# Generate plugin list
for jar in servers/wildy/plugins/*.jar; do
  basename "$jar"
done > plugin-versions.txt
```

## Additional Resources

- [SpigotMC Resources](https://www.spigotmc.org/resources/)
- [Bukkit Plugins](https://dev.bukkit.org/bukkit-plugins)
- [Paper Plugin List](https://hangar.papermc.io/)
- [Velocity Plugin List](https://hangar.papermc.io/Velocity)
