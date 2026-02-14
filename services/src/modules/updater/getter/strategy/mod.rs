//! Module containing different strategies for resolving plugin download URLs.

pub mod direct;
pub mod enginehub;
pub mod github;
pub mod jenkins;
pub mod zrips;

use anyhow::Result;
use regex::Regex;
use serde_json::Value;

use crate::config::StrategyDef;
use crate::utils::http::HttpClient;

// ---------------------------------------------------------------------------
// Shared helpers used by multiple strategy implementations
// ---------------------------------------------------------------------------

/// Extracts a string field from a JSON value, returning an empty string if missing.
pub fn json_str(v: &Value, key: &str) -> String {
    v.get(key)
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string()
}

/// Extracts artifact paths from a JSON response using a jq-like filter.
///
/// Supports filters like `.artifacts[].relativePath` and `.assets[].browser_download_url`.
pub fn extract_artifacts(response: &Value, filter: &str) -> Vec<String> {
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

// ---------------------------------------------------------------------------
// Artifact selection
// ---------------------------------------------------------------------------

/// Selects the best artifact from a list based on platform keywords and priority regex hints.
///
/// Priority patterns may contain `{platform}` which is interpolated before matching.
/// Each pattern is treated as a case-insensitive regex.
///
/// Artifacts matching common non-primary classifiers (javadoc, sources, tests) are
/// automatically excluded from fallback selection unless an explicit priority matches them.
pub fn select_artifact(
    artifacts: &[String],
    platform: &str,
    priorities: &[String],
) -> Option<String> {
    // Try the explicit priority list first (supports regex patterns).
    for priority in priorities {
        let pattern = priority.replace("{platform}", platform);
        if let Ok(re) = Regex::new(&pattern) {
            if let Some(a) = artifacts.iter().find(|a| re.is_match(a)) {
                return Some(a.clone());
            }
        }
    }

    // For fallback selection, exclude well-known non-primary classifiers.
    let dominated: Vec<&String> = artifacts
        .iter()
        .filter(|a| !is_classifier_artifact(a))
        .collect();
    let candidates = if dominated.is_empty() {
        artifacts.iter().collect::<Vec<_>>()
    } else {
        dominated
    };

    // Platform-aware fallback.
    let platform_lower = platform.to_lowercase();
    if let Some(a) = candidates
        .iter()
        .find(|a| a.to_lowercase().contains(&platform_lower))
    {
        return Some((*a).clone());
    }

    // Last resort: prefer .jar files, then the first entry.
    candidates
        .iter()
        .find(|a| a.ends_with(".jar"))
        .or(candidates.first())
        .map(|a| (*a).clone())
}

/// Returns `true` if an artifact path looks like a Maven classifier artifact
/// (javadoc, sources, tests, etc.) that is almost never the desired download.
fn is_classifier_artifact(name: &str) -> bool {
    let lower = name.to_lowercase();
    lower.contains("-javadoc")
        || lower.contains("-sources")
        || lower.contains("-tests")
        || lower.contains("-test-")
        || lower.contains(".pom")
}

/// Dispatches URL resolution to the appropriate strategy implementation.
///
/// Dispatches based on the strategy **name** (case-insensitive), not the generic `type` field,
/// because multiple strategies can share the same type (e.g. "api" is used for both GitHub and Jenkins).
pub async fn resolve_url(
    client: &HttpClient,
    strategy_name: &str,
    strategy_def: &StrategyDef,
    plugin_json: &serde_json::Value,
    platform: &str,
    name: &str,
) -> Result<Option<String>> {
    match strategy_name.to_lowercase().as_str() {
        "direct" => direct::resolve(strategy_def, plugin_json, platform),
        "github" => github::resolve(client, strategy_def, plugin_json, platform, name).await,
        "jenkins" => jenkins::resolve(client, strategy_def, plugin_json, platform, name).await,
        "enginehub" => enginehub::resolve(client, plugin_json, platform, name).await,
        "zrips" => zrips::resolve(client, plugin_json, name).await,
        "manual" => Ok(None), // manual은 호출 전에 처리되지만 fallback으로 None 반환
        other => anyhow::bail!("Unknown strategy: {other}"),
    }
}
