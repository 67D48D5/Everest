use anyhow::{Context, Result};
use regex::Regex;

use crate::utils::http::HttpClient;

/// Resolves a download URL from Zrips.net (HTML scrape).
/// Supports two link patterns:
///   A) download.php?file=XXX.jar
///   B) Direct absolute/relative .jar URLs
pub async fn resolve(
    client: &HttpClient,
    plugin_json: &serde_json::Value,
    name: &str,
) -> Result<Option<String>> {
    let url_field = plugin_json.get("url").and_then(|v| v.as_str());
    let project_field = plugin_json.get("project").and_then(|v| v.as_str());

    let page_url = if let Some(url) = url_field {
        let mut u = url.to_string();
        if !u.ends_with('/') {
            u.push('/');
        }
        u
    } else if let Some(project) = project_field {
        format!("https://www.zrips.net/{project}/")
    } else {
        anyhow::bail!("No url or project for Zrips: {name}");
    };

    let html = client
        .fetch_html(&page_url)
        .await
        .with_context(|| format!("Zrips fetch failed: {name}"))?;

    // Pattern A: download.php?file=XXX.jar
    let re_download = Regex::new(r#"(?i)href="(download\.php\?file=[^"]*\.jar)""#)?;

    if let Some(cap) = re_download.captures(&html) {
        let jar_link = &cap[1];
        return Ok(Some(format!("{page_url}{jar_link}")));
    }

    // Pattern B: direct .jar links
    let re_jar = Regex::new(r#"(?i)href="([^"]*\.jar)""#)?;

    if let Some(cap) = re_jar.captures(&html) {
        let jar_link = &cap[1];

        let resolved = if jar_link.starts_with("http") {
            jar_link.to_string()
        } else if jar_link.starts_with('/') {
            format!("https://www.zrips.net{jar_link}")
        } else {
            format!("{page_url}{jar_link}")
        };

        return Ok(Some(resolved));
    }

    anyhow::bail!("No jar found on Zrips for {name}");
}
