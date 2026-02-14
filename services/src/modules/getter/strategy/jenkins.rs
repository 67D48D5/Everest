use anyhow::{Context, Result};

use crate::config::StrategyDef;
use crate::modules::getter::strategy::select_artifact;
use crate::utils::{http::HttpClient, interpolate};

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

    let response = client
        .fetch_json(&api_url)
        .await
        .with_context(|| format!("Jenkins API fetch failed for {name}: {api_url}"))?;

    // Extract artifacts using the filter path
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

fn json_str(v: &serde_json::Value, key: &str) -> String {
    v.get(key)
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string()
}

/// Extracts artifact paths from a JSON response using a jq-like filter.
/// Supports `.artifacts[].relativePath` and `.assets[].browser_download_url`.
fn extract_artifacts(response: &serde_json::Value, filter: &str) -> Vec<String> {
    // Parse the filter to find array key and field key
    // e.g. ".artifacts[].relativePath" -> ("artifacts", "relativePath")
    // e.g. ".assets[].browser_download_url" -> ("assets", "browser_download_url")
    let filter = filter.trim_start_matches('.');
    let parts: Vec<&str> = filter.split("[].").collect();
    if parts.len() != 2 {
        return Vec::new();
    }

    let array_key = parts[0];
    let field_key = parts[1];

    response
        .get(array_key)
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|item| item.get(field_key).and_then(|v| v.as_str()))
                .map(|s| s.to_string())
                .collect()
        })
        .unwrap_or_default()
}
