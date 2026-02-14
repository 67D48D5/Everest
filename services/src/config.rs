//! Config loading and branch resolution for Everest services.
//! This module defines the raw config shapes (for deserialization) and the resolved config containers used by the rest of the code.
//! It also implements the logic to load configs from files and resolve branches with parent inheritance.

use anyhow::{Context, Result, bail};
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashMap;
use std::path::Path;

// ---------------------------------------------------------------------------
// Raw config shapes (for serde deserialization)
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RawConfig {
    pub default_branch: String,
    #[serde(default)]
    pub strategies: HashMap<String, StrategyDef>,
    #[serde(default)]
    pub definitions: Value,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StrategyDef {
    #[serde(rename = "type")]
    pub strategy_type: String,
    #[serde(default)]
    pub api_template: Option<String>,
    #[serde(default)]
    pub artifact_filter: Option<String>,
    #[serde(default)]
    pub download_template: Option<String>,
    #[serde(default)]
    pub priority: Option<Vec<String>>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Definitions {
    #[serde(default)]
    pub paths: HashMap<String, String>,
}

// ---------------------------------------------------------------------------
// Resolved config containers
// ---------------------------------------------------------------------------

pub struct ResolvedUpdate {
    pub resolved: Value,
    pub strategies: HashMap<String, StrategyDef>,
}

pub struct ResolvedServer {
    pub resolved: Value,
    pub definitions: Definitions,
}

// ---------------------------------------------------------------------------
// Config loading
// ---------------------------------------------------------------------------

/// Shared helper: reads a JSON config file, parses the raw shape, and resolves
/// the requested branch (falling back to `defaultBranch` when empty).
fn load_and_resolve(path: &Path, branch: &str) -> Result<(RawConfig, Value)> {
    let text = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read {}", path.display()))?;
    let raw: RawConfig = serde_json::from_str(&text)
        .with_context(|| format!("Failed to parse {}", path.display()))?;
    let full: Value = serde_json::from_str(&text)?;

    let branch_name = if branch.is_empty() {
        &raw.default_branch
    } else {
        branch
    };

    let resolved = resolve_branch(&full, branch_name)?;
    Ok((raw, resolved))
}

pub fn load_update_config(root: &Path, branch: &str) -> Result<ResolvedUpdate> {
    let (raw, resolved) = load_and_resolve(&root.join("config/update.json"), branch)?;
    Ok(ResolvedUpdate {
        resolved,
        strategies: raw.strategies,
    })
}

pub fn load_server_config(root: &Path, branch: &str) -> Result<ResolvedServer> {
    let (raw, resolved) = load_and_resolve(&root.join("config/server.json"), branch)?;

    let definitions: Definitions = if raw.definitions.is_object() {
        serde_json::from_value(raw.definitions)?
    } else {
        Definitions {
            paths: HashMap::new(),
        }
    };

    Ok(ResolvedServer {
        resolved,
        definitions,
    })
}

// ---------------------------------------------------------------------------
// Branch resolution (recursive parent merge)
// ---------------------------------------------------------------------------

fn resolve_branch(config: &Value, branch_name: &str) -> Result<Value> {
    let branches = config
        .get("branches")
        .context("Config missing 'branches' key")?;

    resolve_branch_recursive(branches, branch_name, &mut Vec::new())
}

fn resolve_branch_recursive(
    branches: &Value,
    name: &str,
    visited: &mut Vec<String>,
) -> Result<Value> {
    if visited.contains(&name.to_string()) {
        bail!("Circular branch dependency detected: {name}");
    }
    visited.push(name.to_string());

    let branch = branches
        .get(name)
        .with_context(|| format!("Branch not found: {name}"))?
        .clone();

    if let Some(parent_name) = branch.get("parent").and_then(|v| v.as_str()) {
        let parent = resolve_branch_recursive(branches, parent_name, visited)?;
        let mut merged = parent;
        deep_merge(&mut merged, &branch);
        // Remove the "parent" key from the merged result
        if let Some(obj) = merged.as_object_mut() {
            obj.remove("parent");
        }
        Ok(merged)
    } else {
        Ok(branch)
    }
}

/// Deep merges `overlay` into `base`. Objects are merged recursively; other types are overwritten.
fn deep_merge(base: &mut Value, overlay: &Value) {
    match (base, overlay) {
        (Value::Object(base_map), Value::Object(overlay_map)) => {
            for (key, overlay_val) in overlay_map {
                let entry = base_map.entry(key.clone()).or_insert(Value::Null);
                deep_merge(entry, overlay_val);
            }
        }
        (base, overlay) => {
            *base = overlay.clone();
        }
    }
}
