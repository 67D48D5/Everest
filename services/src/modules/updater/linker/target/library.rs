//! Module for linking library resources into server instances based on mounts configuration.

use std::path::Path;

use anyhow::Result;
use serde_json::Value;

use log::{info, warn};

/// Symlinks resources from libraries/common into server instances based on mounts config.
pub async fn run(resolved: &Value, root: &Path) -> Result<()> {
    let common_root = root.join("libraries/common");
    let servers_root = root.join("servers");

    std::fs::create_dir_all(&servers_root)?;

    info!("Starting mount linking...");

    // Find servers (keys with .engine)
    let servers: Vec<String> = resolved
        .as_object()
        .map(|obj| {
            obj.iter()
                .filter(|(_, v)| v.is_object() && v.get("engine").is_some())
                .map(|(k, _)| k.clone())
                .collect()
        })
        .unwrap_or_default();

    for server in &servers {
        let server_dir = servers_root.join(server);

        if !server_dir.is_dir() {
            warn!("Server directory missing: {server}. Creating...");
            std::fs::create_dir_all(&server_dir)?;
        }

        // Check for mounts
        let mounts = resolved
            .get(server)
            .and_then(|v| v.get("mounts"))
            .and_then(|v| v.as_object());

        let mounts = match mounts {
            Some(m) => m,
            None => {
                info!("No mounts for {server}. Skipping.");
                continue;
            }
        };

        info!("Processing mounts: {server}");

        for (name, mount) in mounts {
            let src = mount.get("src").and_then(|v| v.as_str()).unwrap_or("");
            let dest = mount.get("dest").and_then(|v| v.as_str()).unwrap_or("");

            if src.is_empty() || dest.is_empty() {
                warn!("Invalid mount entry in {server}: name={name}");
                continue;
            }

            let source_path = common_root.join(src);
            let dest_path = server_dir.join(dest);

            link_resource(&source_path, &dest_path, name, server)?;
        }
    }

    info!("Mount linking complete.");
    Ok(())
}

fn link_resource(source_path: &Path, dest_path: &Path, name: &str, tag: &str) -> Result<()> {
    if !source_path.exists() {
        warn!("Source missing for {tag}/{name}: {}", source_path.display());
        warn!("Creating empty directory: {}", source_path.display());
        std::fs::create_dir_all(source_path)?;
    }

    if let Some(parent) = dest_path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    // Remove existing target
    if dest_path.is_symlink() {
        std::fs::remove_file(dest_path)?;
    } else if dest_path.is_dir() {
        warn!("Replacing directory with symlink: {}", dest_path.display());
        std::fs::remove_dir_all(dest_path)?;
    } else if dest_path.is_file() {
        warn!("Replacing file with symlink: {}", dest_path.display());
        std::fs::remove_file(dest_path)?;
    }

    #[cfg(unix)]
    std::os::unix::fs::symlink(source_path, dest_path)?;

    info!("{tag}: {name} → {}", dest_path.display());
    Ok(())
}
