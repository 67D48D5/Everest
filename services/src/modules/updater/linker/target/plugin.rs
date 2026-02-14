//! Module for linking plugin JARs from libraries/plugins into server plugin directories.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use anyhow::Result;
use log::{error, info, warn};
use serde_json::Value;

use crate::utils::{interpolate, pick_latest};

/// Links plugin JARs from libraries/plugins into server plugin directories.
pub async fn run(
    resolved: &Value,
    definitions: &HashMap<String, String>,
    root: &Path,
) -> Result<()> {
    let plugin_lib_root = root.join("libraries/plugins");
    let servers_root = root.join("servers");

    std::fs::create_dir_all(&plugin_lib_root)?;
    std::fs::create_dir_all(&servers_root)?;

    // Find servers (keys with .engine)
    let servers: Vec<(String, String)> = resolved
        .as_object()
        .map(|obj| {
            obj.iter()
                .filter_map(|(k, v)| {
                    let engine = v.get("engine")?.as_str()?;
                    Some((k.clone(), engine.to_string()))
                })
                .collect()
        })
        .unwrap_or_default();

    for (server, engine) in &servers {
        let server_dir = servers_root.join(server);

        if !server_dir.is_dir() {
            warn!("Server dir missing: {server}. Skipping.");
            continue;
        }

        info!("Linking plugins: {server} ({engine})");
        link_server_plugins(resolved, definitions, server, engine, &server_dir, root)?;
    }

    info!("Plugin linking complete.");
    Ok(())
}

fn link_server_plugins(
    resolved: &Value,
    definitions: &HashMap<String, String>,
    server: &str,
    engine: &str,
    server_dir: &Path,
    root: &Path,
) -> Result<()> {
    let dest_dir = server_dir.join("plugins");
    std::fs::create_dir_all(&dest_dir)?;

    let plugins_json = resolved.get(server).and_then(|v| v.get("plugins"));

    let plugins_json = match plugins_json {
        Some(v) if v.is_object() => v,
        _ => {
            warn!("No plugins configured for {server}. Skipping.");
            return Ok(());
        }
    };

    // Build in temp dir
    let temp_dir = server_dir.join(format!(".plugins_build_{}", std::process::id()));
    std::fs::create_dir_all(&temp_dir)?;

    let mut linked = 0u32;
    let mut missing = 0u32;

    // Detect format: flat vs grouped
    let format = detect_format(plugins_json);

    if format == "flat" {
        // Flat: { "name": { "type": "managed|manual", "pattern": "glob" } }
        if let Some(obj) = plugins_json.as_object() {
            for (name, entry) in obj {
                let ptype = entry.get("type").and_then(|v| v.as_str()).unwrap_or("");
                let pattern = entry.get("pattern").and_then(|v| v.as_str()).unwrap_or("");

                let category = match ptype {
                    "managed" => "Managed",
                    "manual" => "Manual",
                    other => {
                        warn!("Unknown type '{other}' for {name} in {server}. Skipping.");
                        continue;
                    }
                };

                let src_dir = match resolve_src_dir(definitions, category, engine, root) {
                    Some(d) => d,
                    None => {
                        warn!("No path definition for category '{category}'");
                        continue;
                    }
                };

                if link_one_plugin(name, pattern, &src_dir, &temp_dir) {
                    linked += 1;
                } else {
                    missing += 1;
                }
            }
        }
    } else {
        // Grouped: { "Managed": { "name": { "pattern": "..." } }, "Manual": {...} }
        if let Some(obj) = plugins_json.as_object() {
            for (category, entries) in obj {
                let src_dir = match resolve_src_dir(definitions, category, engine, root) {
                    Some(d) => d,
                    None => {
                        warn!("No path definition for category '{category}'. Skipping.");
                        continue;
                    }
                };

                if let Some(entries_obj) = entries.as_object() {
                    for (name, entry) in entries_obj {
                        let pattern = entry.get("pattern").and_then(|v| v.as_str()).unwrap_or("");
                        if link_one_plugin(name, pattern, &src_dir, &temp_dir) {
                            linked += 1;
                        } else {
                            missing += 1;
                        }
                    }
                }
            }
        }
    }

    // Nothing linked → preserve existing
    if linked == 0 {
        warn!("No plugins linked for {server}. Preserving existing.");
        let _ = std::fs::remove_dir_all(&temp_dir);
        return Ok(());
    }

    // Safe apply: only touch jars we manage
    let backup_dir = server_dir.join(format!(".plugins_backup_{}", std::process::id()));
    std::fs::create_dir_all(&backup_dir)?;

    // Backup existing managed jars
    let temp_jars: Vec<String> = std::fs::read_dir(&temp_dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().is_some_and(|ext| ext == "jar"))
        .map(|e| e.file_name().to_string_lossy().to_string())
        .collect();

    for jar_name in &temp_jars {
        let target = dest_dir.join(jar_name);
        if target.exists() || target.is_symlink() {
            let backup = backup_dir.join(jar_name);
            let _ = std::fs::rename(&target, &backup);
        }
    }

    // Apply new jars
    let mut failed_apply = false;
    for entry in std::fs::read_dir(&temp_dir)? {
        let entry = entry?;
        if !entry.path().extension().is_some_and(|ext| ext == "jar") {
            continue;
        }
        if std::fs::rename(entry.path(), dest_dir.join(entry.file_name())).is_err() {
            failed_apply = true;
            break;
        }
    }

    // Rollback on failure
    if failed_apply {
        warn!("Apply failed for {server}. Rolling back...");
        for entry in std::fs::read_dir(&backup_dir).into_iter().flatten() {
            if let Ok(entry) = entry {
                let _ = std::fs::rename(entry.path(), dest_dir.join(entry.file_name()));
            }
        }
        let _ = std::fs::remove_dir_all(&backup_dir);
        error!("Failed to apply plugins for {server}.");
        return Ok(());
    }

    let _ = std::fs::remove_dir_all(&backup_dir);
    let _ = std::fs::remove_dir_all(&temp_dir);

    if missing > 0 {
        warn!("Linked for {server}, but {missing} plugin(s) missing.");
    } else {
        info!("All plugins linked for {server}.");
    }

    Ok(())
}

/// Detects whether the plugins config is flat or grouped.
fn detect_format(plugins_json: &Value) -> &'static str {
    if let Some(obj) = plugins_json.as_object() {
        if let Some((_, first_val)) = obj.iter().next() {
            if first_val.get("pattern").is_some() {
                return "flat";
            }
        }
    }
    "grouped"
}

/// Resolves the source directory for a plugin category.
fn resolve_src_dir(
    definitions: &HashMap<String, String>,
    category: &str,
    engine: &str,
    root: &Path,
) -> Option<PathBuf> {
    let template = definitions.get(category)?;
    let resolved = interpolate(template, &[("engine", engine)]);
    Some(root.join(resolved))
}

/// Links a single plugin jar.
fn link_one_plugin(name: &str, pattern: &str, src_dir: &Path, temp_dir: &Path) -> bool {
    let src_file = pick_latest(src_dir, pattern);

    match src_file {
        Some(src) if src.is_file() => {
            let dest = temp_dir.join(format!("{name}.jar"));
            #[cfg(unix)]
            {
                if std::os::unix::fs::symlink(&src, &dest).is_ok() {
                    let basename = src.file_name().unwrap_or_default().to_string_lossy();
                    info!("Linked: {name}.jar → {basename}");
                    return true;
                }
            }
            false
        }
        _ => {
            warn!("Not found: {name} ({pattern}) in {}", src_dir.display());
            false
        }
    }
}
