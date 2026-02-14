//! Strategy for resolving download URLs from GitHub Releases.

use anyhow::{Context, Result};

use crate::config::StrategyDef;
use crate::utils::{http::HttpClient, interpolate};

use super::{extract_artifacts, json_str, select_artifact};

/// Resolves a download URL from GitHub Releases.
pub async fn resolve(
    client: &HttpClient,
    strategy_def: &StrategyDef,
    plugin_json: &serde_json::Value,
    platform: &str,
    name: &str,
) -> Result<Option<String>> {
    let api_template = strategy_def
        .api_template
        .as_deref()
        .context("Github strategy missing api_template")?;
    let artifact_filter = strategy_def
        .artifact_filter
        .as_deref()
        .context("Github strategy missing artifact_filter")?;
    let download_template = strategy_def
        .download_template
        .as_deref()
        .context("Github strategy missing download_template")?;

    let owner = json_str(plugin_json, "owner");
    let repo = json_str(plugin_json, "repo");

    let api_url = interpolate(
        api_template,
        &[("owner", &owner), ("repo", &repo), ("platform", platform)],
    );

    let response: serde_json::Value = client
        .fetch_json(&api_url)
        .await
        .with_context(|| format!("GitHub API fetch failed for {name}: {api_url}"))?;

    let artifacts = extract_artifacts(&response, artifact_filter);
    if artifacts.is_empty() {
        anyhow::bail!("No artifacts for {name}");
    }

    let priorities = strategy_def.priority.as_deref().unwrap_or(&[]);
    let selected = select_artifact(&artifacts, platform, priorities)
        .with_context(|| format!("No matching artifact for {name}"))?;

    let dl_url = interpolate(
        download_template,
        &[
            ("artifact", &selected),
            ("owner", &owner),
            ("repo", &repo),
            ("platform", platform),
        ],
    );

    Ok(Some(dl_url))
}
