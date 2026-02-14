//! Strategy for resolving download URLs from Jenkins CI.

use anyhow::{Context, Result};

use crate::config::StrategyDef;
use crate::utils::{http::HttpClient, interpolate};

use super::{extract_artifacts, json_str, select_artifact};

/// Resolves a download URL from Jenkins CI.
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
        .context("Jenkins strategy missing api_template")?;
    let artifact_filter = strategy_def
        .artifact_filter
        .as_deref()
        .context("Jenkins strategy missing artifact_filter")?;
    let download_template = strategy_def
        .download_template
        .as_deref()
        .context("Jenkins strategy missing download_template")?;

    let host = json_str(plugin_json, "host");
    let project = json_str(plugin_json, "project");
    let owner = json_str(plugin_json, "owner");
    let repo = json_str(plugin_json, "repo");
    let url = json_str(plugin_json, "url");

    // Jenkins path fix: projects with "/" are full paths
    let mut tmpl_api = api_template.to_string();
    let mut tmpl_dl = download_template.to_string();
    if project.contains('/') {
        tmpl_api = tmpl_api.replace("/job/{project}", "/{project}");
        tmpl_dl = tmpl_dl.replace("/job/{project}", "/{project}");
    }

    let api_url = interpolate(
        &tmpl_api,
        &[
            ("host", &host),
            ("project", &project),
            ("owner", &owner),
            ("repo", &repo),
            ("url", &url),
            ("platform", platform),
        ],
    );

    let response: serde_json::Value = client
        .fetch_json(&api_url)
        .await
        .with_context(|| format!("Jenkins API fetch failed for {name}: {api_url}"))?;

    let artifacts = extract_artifacts(&response, artifact_filter);
    if artifacts.is_empty() {
        anyhow::bail!("No artifacts for {name}");
    }

    let priorities = strategy_def.priority.as_deref().unwrap_or(&[]);
    let selected = select_artifact(&artifacts, platform, priorities)
        .with_context(|| format!("No matching artifact for {name}"))?;

    let dl_url = interpolate(
        &tmpl_dl,
        &[
            ("artifact", &selected),
            ("host", &host),
            ("project", &project),
            ("owner", &owner),
            ("repo", &repo),
            ("url", &url),
            ("platform", platform),
        ],
    );

    Ok(Some(dl_url))
}
