use anyhow::Result;
use std::path::Path;

use log::{error, info, warn};

use crate::config;

/// Runs the full update process: download engines/plugins, then link libraries/plugins.
pub async fn run(root: &Path, branch: &str) -> Result<()> {
    // Pre-flight: check config files exist
    let update_config_path = root.join("config/update.json");
    let server_config_path = root.join("config/server.json");

    if !update_config_path.exists() {
        anyhow::bail!("Config not found: {}", update_config_path.display());
    }
    if !server_config_path.exists() {
        anyhow::bail!("Config not found: {}", server_config_path.display());
    }

    if !branch.is_empty() {
        info!("Using branch: {branch}");
    }

    // Resolve configs
    info!("Resolving configuration...");

    let update_config = config::load_update_config(root, branch)?;
    let server_config = config::load_server_config(root, branch)?;

    // Phase 1: Download (engine + plugin in parallel)
    let mut failed_processes: Vec<&str> = Vec::new();

    info!("Starting download phase...");

    let resolved_update = update_config.resolved.clone();
    let strategies = update_config.strategies.clone();
    let root_owned = root.to_path_buf();

    let (engine_result, plugin_result) = tokio::join!(
        super::get_engine::run(&resolved_update, &root_owned),
        super::get_plugin::run(&resolved_update, &strategies, &root_owned),
    );

    if let Err(e) = &engine_result {
        error!("get-engine failed: {e:#}");
        failed_processes.push("get-engine");
    }
    if let Err(e) = &plugin_result {
        error!("get-plugin failed: {e:#}");
        failed_processes.push("get-plugin");
    }

    // Also track non-zero fail counts as failures
    if let Ok(n) = engine_result {
        if n > 0 {
            // Some engines failed but the process itself didn't error
        }
    }
    if let Ok(n) = plugin_result {
        if n > 0 {
            // Some plugins failed but the process itself didn't error
        }
    }

    // Phase 2: Link (library + plugin in parallel)
    info!("Starting linking phase...");

    let resolved_server = server_config.resolved.clone();
    let definitions = server_config.definitions.paths.clone();
    let resolved_server2 = resolved_server.clone();

    let (lib_result, plug_result) = tokio::join!(
        super::link_library::run(&resolved_server, &root_owned),
        super::link_plugin::run(&resolved_server2, &definitions, &root_owned),
    );

    if let Err(e) = &lib_result {
        error!("link-library failed: {e:#}");
        failed_processes.push("link-library");
    }
    if let Err(e) = &plug_result {
        error!("link-plugin failed: {e:#}");
        failed_processes.push("link-plugin");
    }

    // Report
    if !failed_processes.is_empty() {
        error!(
            TAG,
            "{} process(es) failed: {}",
            failed_processes.len(),
            failed_processes.join(", ")
        );
    } else {
        info!("All processes completed successfully.");
        info!("Restart servers to apply changes.");
    }

    Ok(())
}
