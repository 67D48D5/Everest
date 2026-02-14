//! Strategy for resolving direct (static) download URLs.

use anyhow::Result;

use crate::config::StrategyDef;
use crate::utils::interpolate;

/// Resolves a direct (static) download URL.
pub fn resolve(
    strategy_def: &StrategyDef,
    plugin_json: &serde_json::Value,
    platform: &str,
) -> Result<Option<String>> {
    let template = strategy_def.download_template.as_deref().unwrap_or("{url}");

    let url = plugin_json
        .get("url")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let resolved = interpolate(template, &[("url", url), ("platform", platform)]);

    if resolved.is_empty() {
        Ok(None)
    } else {
        Ok(Some(resolved))
    }
}
