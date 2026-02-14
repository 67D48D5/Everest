use anyhow::{Context, Result};

use crate::config::StrategyDef;
use crate::modules::getter::strategy::select_artifact;
use crate::utils::{http::HttpClient, interpolate};

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

    let response = client
        .fetch_json(&api_url)
        .await
        .with_context(|| format!("GitHub API fetch failed for {name}: {api_url}"))?;

    // Extract artifacts
    let artifacts = extract_artifacts(&response, artifact_filter);
    if artifacts.is_empty() {
        anyhow::bail!("No artifacts for {name}");
    }

    let priorities = strategy_def.priority.as_deref().unwrap_or(&[]);
    let selected = select_artifact(&artifacts, platform, priorities)
        .with_context(|| format!("No matching artifact for {name}"))?;

    // GitHub download_template is typically just "{artifact}" (the URL itself)
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

fn json_str(v: &serde_json::Value, key: &str) -> String {
    v.get(key)
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string()
}

fn extract_artifacts(response: &serde_json::Value, filter: &str) -> Vec<String> {
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
