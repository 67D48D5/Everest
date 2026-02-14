use std::collections::HashMap;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use log::{error, info, warn};
use serde_json::Value;

use crate::config::StrategyDef;
use crate::modules::updater::getter::strategy;
use crate::utils::{atomic_swap, http::HttpClient, try_fallback};

/// Downloads plugins using strategy definitions.
pub async fn run(
    resolved: &Value,
    strategies: &HashMap<String, StrategyDef>,
    root: &Path,
) -> Result<u32> {
    let plugin_lib_root = root.join("libraries/plugins");
    tokio::fs::create_dir_all(&plugin_lib_root).await?;

    let client = HttpClient::new()?;

    info!("Starting plugin updates...");

    // Find platforms (keys with .plugins)
    let platforms: Vec<String> = resolved
        .as_object()
        .map(|obj| {
            obj.iter()
                .filter(|(_, v)| v.is_object() && v.get("plugins").is_some())
                .map(|(k, _)| k.clone())
                .collect()
        })
        .unwrap_or_default();

    let mut total_failed = 0u32;

    for platform in &platforms {
        info!("Processing platform: {platform}");

        let platform_root = plugin_lib_root.join(platform);
        let target_dir = platform_root.join("Managed");
        tokio::fs::create_dir_all(&platform_root).await?;

        // Create temp dir
        let temp_dir = tempdir_in(&platform_root).await?;

        // Get plugins for this platform
        let plugins = resolved
            .get(platform)
            .and_then(|v| v.get("plugins"))
            .and_then(|v| v.as_object());

        let plugins = match plugins {
            Some(p) => p,
            None => continue,
        };

        let mut handles = Vec::new();

        for (name, plugin_json) in plugins {
            let client = client.clone();
            let name = name.clone();
            let plugin_json = plugin_json.clone();
            let platform = platform.clone();
            let strategies = strategies.clone();
            let temp_dir = temp_dir.clone();
            let target_dir = target_dir.clone();

            handles.push(tokio::spawn(async move {
                download_plugin(
                    &client,
                    &platform,
                    &name,
                    &plugin_json,
                    &strategies,
                    &temp_dir,
                    &target_dir,
                )
                .await
            }));
        }

        let mut failed = 0u32;
        for handle in handles {
            match handle.await {
                Ok(Ok(())) => {}
                Ok(Err(e)) => {
                    error!("{e:#}");
                    failed += 1;
                }
                Err(e) => {
                    error!("Task panicked: {e}");
                    failed += 1;
                }
            }
        }

        // Check if anything was downloaded
        let has_files = std::fs::read_dir(&temp_dir)
            .map(|d| d.count() > 0)
            .unwrap_or(false);

        if !has_files {
            warn!("No plugins downloaded for {platform}.");
            let _ = tokio::fs::remove_dir_all(&temp_dir).await;
            continue;
        }

        if failed > 0 {
            error!("{platform}: {failed} plugin(s) failed. Preserving existing Managed dir.");
            let _ = tokio::fs::remove_dir_all(&temp_dir).await;
            total_failed += failed;
            continue;
        }

        // Atomic swap: temp → Managed
        info!("Swapping Managed directory for {platform}...");
        atomic_swap(&temp_dir, &target_dir)?;

        info!("All plugins updated for {platform}.");
    }

    info!("Plugin updates complete.");
    Ok(total_failed)
}

async fn download_plugin(
    client: &HttpClient,
    platform: &str,
    name: &str,
    plugin_json: &Value,
    strategies: &HashMap<String, StrategyDef>,
    dest_dir: &Path,
    fallback_dir: &Path,
) -> Result<()> {
    let tag = format!("{name} ({platform})");

    // Determine strategy
    let strategy_name = plugin_json
        .get("strategy")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    if strategy_name.is_empty() {
        warn!("No strategy defined for {tag}. Skipping.");
        return Ok(());
    }

    let strategy_def = strategies
        .get(strategy_name)
        .with_context(|| format!("Unknown strategy '{strategy_name}' for {tag}"))?;

    // Manual: preserve existing, log update URL
    if strategy_def.strategy_type == "manual" {
        let manual_url = plugin_json.get("url").and_then(|v| v.as_str());
        warn!("Manual download required: {tag}");
        if let Some(url) = manual_url {
            warn!("  → {url}");
        }
        let _ = try_fallback(name, fallback_dir, dest_dir);
        return Ok(());
    }

    // Resolve download URL
    let resolved_url = strategy::resolve_url(
        client,
        strategy_name,
        strategy_def,
        plugin_json,
        platform,
        name,
    )
    .await;

    let resolved_url: String = match resolved_url {
        Ok(Some(url)) => url,
        other => {
            if let Err(e) = &other {
                error!("Failed to resolve URL for {tag}: {e:#}");
            } else {
                error!("Failed to resolve URL for {tag}");
            }
            return use_fallback(name, &tag, fallback_dir, dest_dir);
        }
    };

    // Determine filename
    let url_path = resolved_url.split('?').next().unwrap_or(&resolved_url);
    let filename = url_path.rsplit('/').next().unwrap_or("plugin.jar");
    let filename = if filename.ends_with(".jar") {
        filename.to_string()
    } else {
        format!("{name}.jar")
    };

    let target = dest_dir.join(&filename);

    info!("Downloading: {tag} → {filename}...");

    match client.download_file(&resolved_url, &target).await {
        Ok(()) => {
            info!("Downloaded: {tag} → {filename}");
            Ok(())
        }
        Err(e) => {
            warn!("Download failed for {tag}: {e:#}. Trying fallback...");
            use_fallback(name, &tag, fallback_dir, dest_dir)
        }
    }
}

/// Attempts to recover a plugin from the fallback (previous Managed) directory.
fn use_fallback(name: &str, tag: &str, fallback_dir: &Path, dest_dir: &Path) -> Result<()> {
    if try_fallback(name, fallback_dir, dest_dir)? {
        info!("Preserved: {tag} (fallback)");
        Ok(())
    } else {
        anyhow::bail!("No fallback available for {tag}")
    }
}

/// Creates a temporary directory inside the given parent.
async fn tempdir_in(parent: &Path) -> Result<PathBuf> {
    let name = format!(".tmp_managed_{}", std::process::id());
    let path = parent.join(name);
    tokio::fs::create_dir_all(&path).await?;
    Ok(path)
}
