//! Utility functions for the Everest services, including file management and HTTP operations.

pub mod http;

use std::{
    fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result};

/// Replaces `{key}` placeholders in a template string with provided values.
pub fn interpolate(template: &str, vars: &[(&str, &str)]) -> String {
    let mut result = template.to_string();
    for (key, val) in vars {
        result = result.replace(&format!("{{{key}}}"), val);
    }
    result
}

/// Finds the latest file matching a glob pattern in a directory (version-sorted).
/// Glob matching is case-insensitive for cross-platform consistency.
pub fn pick_latest(dir: &Path, pattern: &str) -> Option<PathBuf> {
    if !dir.is_dir() {
        return None;
    }

    let glob_pattern = dir.join(pattern).to_string_lossy().to_string();
    let options = glob::MatchOptions {
        case_sensitive: false,
        ..Default::default()
    };
    let mut matches: Vec<PathBuf> = glob::glob_with(&glob_pattern, options)
        .ok()?
        .filter_map(|e| e.ok())
        .filter(|p| p.is_file())
        .collect();

    matches.sort_by(|a, b| version_sort_key(a).cmp(&version_sort_key(b)));
    matches.last().cloned()
}

/// Extracts a version-sortable key from a filename.
fn version_sort_key(path: &Path) -> Vec<u64> {
    let name = path.file_name().unwrap_or_default().to_string_lossy();
    let mut parts = Vec::new();
    let mut num_buf = String::new();

    for ch in name.chars() {
        if ch.is_ascii_digit() {
            num_buf.push(ch);
        } else {
            if !num_buf.is_empty() {
                parts.push(num_buf.parse::<u64>().unwrap_or(0));
                num_buf.clear();
            }
        }
    }
    if !num_buf.is_empty() {
        parts.push(num_buf.parse::<u64>().unwrap_or(0));
    }
    parts
}

/// Tries to recover a jar from a fallback directory.
pub fn try_fallback(name: &str, fallback_dir: &Path, dest_dir: &Path) -> Result<bool> {
    if !fallback_dir.is_dir() {
        return Ok(false);
    }

    let pattern = fallback_dir
        .join(format!("*{name}*.jar"))
        .to_string_lossy()
        .to_string();

    if let Some(backup) = glob::glob(&pattern)
        .ok()
        .and_then(|mut g| g.find_map(|e| e.ok()))
    {
        let dest = dest_dir.join(backup.file_name().unwrap());
        fs::copy(&backup, &dest).with_context(|| {
            format!(
                "Failed to copy fallback {} -> {}",
                backup.display(),
                dest.display()
            )
        })?;
        return Ok(true);
    }

    Ok(false)
}

/// Atomically swaps a source directory into a destination path.
pub fn atomic_swap(src: &Path, dest: &Path) -> Result<()> {
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)?;
    }

    let backup = dest.with_extension(format!("bak.{}", std::process::id()));

    if dest.is_dir() {
        fs::rename(dest, &backup)
            .with_context(|| format!("Failed to backup {}", dest.display()))?;
    }

    if let Err(e) = fs::rename(src, dest) {
        // Restore backup on failure
        if backup.is_dir() {
            let _ = fs::rename(&backup, dest);
        }
        return Err(e).with_context(|| format!("Swap failed for {}", dest.display()));
    }

    // Clean up backup
    let _ = fs::remove_dir_all(&backup);
    Ok(())
}
