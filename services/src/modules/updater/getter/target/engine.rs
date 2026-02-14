//! Module for handling engine updates using the Fill API v3.

use anyhow::{Context, Result};
use log::{info, warn};
use serde_json::Value;
use std::path::Path;

use crate::utils::http::HttpClient;

const FILL_API: &str = "https://fill.papermc.io/v3";

/// Downloads the latest build for each engine defined in the resolved update config.
pub async fn run(resolved: &Value, root: &Path) -> Result<u32> {
    let engine_dir = root.join("libraries/engines");
    tokio::fs::create_dir_all(&engine_dir).await?;

    let client = HttpClient::new()?;

    info!("Starting engine updates (Fill API v3)...");

    let entries = resolved
        .as_object()
        .map(|obj| {
            obj.iter()
                .filter(|(_, v)| v.is_object() && v.get("version").is_some())
                .map(|(k, v)| {
                    let version = v
                        .get("version")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string();
                    (k.clone(), version)
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    let mut handles = Vec::new();

    for (engine, version) in entries {
        let client = client.clone();
        let engine_dir = engine_dir.clone();
        handles.push(tokio::spawn(async move {
            process_engine(&client, &engine, &version, &engine_dir).await
        }));
    }

    let mut failed = 0u32;
    for handle in handles {
        if let Err(_) | Ok(Err(_)) = handle.await {
            failed += 1;
        }
    }

    if failed > 0 {
        warn!("{failed} engine(s) failed to update.");
    }
    info!("Engine updates complete.");
    Ok(failed)
}

async fn process_engine(
    client: &HttpClient,
    engine: &str,
    version: &str,
    engine_dir: &Path,
) -> Result<()> {
    let project = engine.to_lowercase();
    let tag = format!("{project} ({version})");

    // 1. Fetch version metadata
    let version_url = format!("{FILL_API}/projects/{project}/versions/{version}");
    let version_resp: Value = client
        .fetch_json(&version_url)
        .await
        .with_context(|| format!("Failed to fetch version meta: {tag}"))?;

    if version_resp.get("ok") == Some(&Value::Bool(false)) {
        let msg = version_resp
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Unknown");
        anyhow::bail!("API error for {tag}: {msg}");
    }

    // 2. Find latest build
    let latest_build = version_resp
        .get("builds")
        .and_then(|v| v.as_array())
        .and_then(|arr| arr.iter().filter_map(|v| v.as_u64()).max());

    let latest_build = match latest_build {
        Some(b) => b,
        None => {
            warn!("No builds found for {tag}. Skipping.");
            return Ok(());
        }
    };

    // 3. Fetch build detail
    let build_url =
        format!("{FILL_API}/projects/{project}/versions/{version}/builds/{latest_build}");
    let build_resp: Value = client
        .fetch_json(&build_url)
        .await
        .with_context(|| format!("Failed to fetch build detail: {tag} (#{latest_build})"))?;

    if build_resp.get("ok") == Some(&Value::Bool(false)) {
        let msg = build_resp
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Unknown");
        anyhow::bail!("API error for {tag} (#{latest_build}): {msg}");
    }

    let dl_url = build_resp
        .pointer("/downloads/server:default/url")
        .and_then(|v| v.as_str());
    let dl_name = build_resp
        .pointer("/downloads/server:default/name")
        .and_then(|v| v.as_str());

    let dl_url = match dl_url {
        Some(u) if !u.is_empty() => u,
        _ => {
            warn!("No download URL for {tag}. Skipping.");
            return Ok(());
        }
    };

    let dl_name = match dl_name {
        Some(n) if !n.is_empty() && n != "null" => n.to_string(),
        _ => dl_url
            .rsplit('/')
            .next()
            .unwrap_or("server.jar")
            .to_string(),
    };

    // 4. Up-to-date check
    let target = engine_dir.join(&dl_name);
    if target.exists() {
        info!("Up-to-date: {tag} (#{latest_build}, {dl_name})");
        return Ok(());
    }

    // 5. Download (atomic)
    info!("Downloading: {dl_name} (#{latest_build})...");

    client
        .download_file(dl_url, &target)
        .await
        .with_context(|| format!("Download failed: {tag}"))?;

    info!("Downloaded: {tag} → {dl_name}");

    // 6. Cleanup old builds for same engine+version
    cleanup_old_builds(engine_dir, &project, version, &dl_name).await;

    Ok(())
}

async fn cleanup_old_builds(engine_dir: &Path, project: &str, version: &str, current: &str) {
    let prefix = format!("{project}-{version}-");
    let mut removed = 0u32;

    if let Ok(mut dir) = tokio::fs::read_dir(engine_dir).await {
        while let Ok(Some(entry)) = dir.next_entry().await {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with(&prefix) && name.ends_with(".jar") && name != current {
                if tokio::fs::remove_file(entry.path()).await.is_ok() {
                    removed += 1;
                }
            }
        }
    }

    if removed > 0 {
        warn!("Removed {removed} old build(s) for {project} ({version})");
    }
}
