//! Update module for fetching the latest server engines and plugins from various sources.

pub mod getter;
pub mod linker;

use anyhow::Result;
use std::path::Path;

use log::{error, info};

use crate::config;

/// Runs the full update process: download engines/plugins, then link libraries/plugins.
pub async fn run(root: &Path, branch: &str) -> Result<()> {
    for name in ["config/update.json", "config/server.json"] {
        let path = root.join(name);
        if !path.exists() {
            anyhow::bail!("Config not found: {}", path.display());
        }
    }

    if !branch.is_empty() {
        info!("Using branch: {branch}");
    }

    info!("Resolving configuration...");
    let update_config = config::load_update_config(root, branch)?;
    let server_config = config::load_server_config(root, branch)?;

    let mut failures: Vec<&str> = Vec::new();
    let root = root.to_path_buf();

    // Phase 1: Download (engine + plugin in parallel)
    info!("Starting download phase...");

    let (engine_result, plugin_result) = tokio::join!(
        getter::target::engine::run(&update_config.resolved, &root),
        getter::target::plugin::run(&update_config.resolved, &update_config.strategies, &root),
    );

    check_counted_result(engine_result, "get-engine", &mut failures);
    check_counted_result(plugin_result, "get-plugin", &mut failures);

    // Phase 2: Link (library + plugin in parallel)
    info!("Starting linking phase...");

    let (lib_result, plug_result) = tokio::join!(
        linker::target::library::run(&server_config.resolved, &root),
        linker::target::plugin::run(
            &server_config.resolved,
            &server_config.definitions.paths,
            &root
        ),
    );

    check_result(&lib_result, "link-library", &mut failures);
    check_result(&plug_result, "link-plugin", &mut failures);

    // Summary
    if failures.is_empty() {
        info!("All processes completed successfully.");
        info!("Restart servers to apply changes.");
    } else {
        error!(
            "{} process(es) failed: {}",
            failures.len(),
            failures.join(", ")
        );
    }

    Ok(())
}

/// Checks a `Result<u32>` (fail-count) and pushes to `failures` accordingly.
fn check_counted_result<'a>(result: Result<u32>, label: &'a str, failures: &mut Vec<&'a str>) {
    match result {
        Err(e) => {
            error!("{label} failed: {e:#}");
            failures.push(label);
        }
        Ok(n) if n > 0 => {
            error!("{label}: {n} sub-task(s) failed");
            failures.push(label);
        }
        _ => {}
    }
}

/// Checks a `Result<()>` and pushes to `failures` on error.
fn check_result<'a>(result: &Result<()>, label: &'a str, failures: &mut Vec<&'a str>) {
    if let Err(e) = result {
        error!("{label} failed: {e:#}");
        failures.push(label);
    }
}
