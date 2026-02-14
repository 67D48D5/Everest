use anyhow::{Context, Result};
use regex::Regex;

use crate::utils::http::HttpClient;

/// Resolves a download URL from EngineHub (TeamCity HTML scrape).
pub async fn resolve(
    client: &HttpClient,
    plugin_json: &serde_json::Value,
    platform: &str,
    name: &str,
) -> Result<Option<String>> {
    let project = plugin_json
        .get("project")
        .and_then(|v| v.as_str())
        .with_context(|| format!("No project for EngineHub: {name}"))?;

    let page_url = format!(
        "https://builds.enginehub.org/job/{}/last-successful?branch=master",
        project.to_lowercase()
    );

    let html = client
        .fetch_html(&page_url)
        .await
        .with_context(|| format!("EngineHub fetch failed: {name}"))?;

    // Extract jar download URLs from TeamCity CI links
    let re = Regex::new(r#"https://ci\.enginehub\.org/repository/download/[^"]+\.jar[^"]*"#)?;

    let jars: Vec<String> = re
        .find_iter(&html)
        .map(|m| m.as_str().to_string())
        .collect();

    if jars.is_empty() {
        anyhow::bail!("No jars found on EngineHub for {name}");
    }

    // Platform-aware selection
    let selected = if platform == "velocity" {
        jars.iter().find(|j| j.to_lowercase().contains("velocity"))
    } else {
        jars.iter()
            .find(|j| j.to_lowercase().contains("bukkit"))
            .or_else(|| jars.iter().find(|j| j.to_lowercase().contains("paper")))
    };

    let selected = selected.unwrap_or(&jars[0]);

    // Fix HTML entities
    let url = selected.replace("&amp;", "&");

    Ok(Some(url))
}
