//! Generic launcher module for Minecraft multiple servers.

use std::{path::Path, process::Command};

use anyhow::{Context, Result, bail};
use log::{info, warn};

use crate::utils::pick_latest;

// EngineType enum and LaunchArgs struct are defined here for better organization and separation of concerns.
#[derive(Debug, Clone, Copy)]
pub enum EngineType {
    Paper,
    Velocity,
    Unknown,
}

impl From<&str> for EngineType {
    fn from(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "paper" => Self::Paper,
            "velocity" => Self::Velocity,
            _ => Self::Unknown,
        }
    }
}

impl std::fmt::Display for EngineType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Paper => f.write_str("paper"),
            Self::Velocity => f.write_str("velocity"),
            Self::Unknown => f.write_str("unknown"),
        }
    }
}

pub struct LaunchArgs {
    pub server_name: String,
    pub engine_type: String,
    pub extra_java_flags: Vec<String>,
}

/// Builds JVM flags: common G1GC base + engine-specific tuning + user extras.
fn build_jvm_flags(engine: EngineType, extra_flags: &[String]) -> Vec<String> {
    let mut flags: Vec<String> = vec![
        "-XX:+UseG1GC".into(),
        "-XX:+AlwaysPreTouch".into(),
        "-XX:+ParallelRefProcEnabled".into(),
        "-XX:+UnlockExperimentalVMOptions".into(),
        "-Duser.timezone=Asia/Seoul".into(),
    ];

    match engine {
        EngineType::Paper => {
            flags.extend([
                "-XX:+DisableExplicitGC".into(),
                "-XX:+PerfDisableSharedMem".into(),
                "-XX:G1HeapRegionSize=8M".into(),
                "-XX:G1HeapWastePercent=5".into(),
                "-XX:G1MaxNewSizePercent=40".into(),
                "-XX:G1MixedGCCountTarget=4".into(),
                "-XX:G1MixedGCLiveThresholdPercent=90".into(),
                "-XX:G1NewSizePercent=30".into(),
                "-XX:G1RSetUpdatingPauseTimePercent=5".into(),
                "-XX:G1ReservePercent=20".into(),
                "-XX:InitiatingHeapOccupancyPercent=15".into(),
                "-XX:MaxGCPauseMillis=200".into(),
                "-XX:MaxTenuringThreshold=1".into(),
                "-XX:SurvivorRatio=32".into(),
                "-Dusing.aikars.flags=https://mcflags.emc.gs".into(),
                "-Daikars.new.flags=true".into(),
            ]);
        }
        EngineType::Velocity => {
            flags.extend([
                "-XX:G1HeapRegionSize=4M".into(),
                "-XX:MaxInlineLevel=15".into(),
            ]);
        }
        EngineType::Unknown => {
            warn!("Unknown engine type, using default G1GC flags only.");
        }
    }

    flags.extend_from_slice(extra_flags);
    flags
}

pub fn run(args: &LaunchArgs, root: &Path) -> Result<()> {
    let server_dir = root.join("servers").join(&args.server_name);
    let engine_dir = root.join("libraries/engines");
    let tmux_session = &args.server_name;
    let engine_type = EngineType::from(args.engine_type.as_str());

    if !server_dir.is_dir() {
        bail!(
            "Server directory does not exist: '{}'",
            server_dir.display()
        );
    }

    let pattern = format!("{}*.jar", engine_type);
    let jar_path = pick_latest(&engine_dir, &pattern)
        .with_context(|| format!("Engine JAR not found for type: '{}'", engine_type))?;

    let jar_absolute_path = jar_path
        .canonicalize()
        .context("Failed to resolve absolute path of engine JAR")?;

    let java_flags = build_jvm_flags(engine_type, &args.extra_java_flags);
    let java_cmd_str = format!(
        "java {} -jar \"{}\" nogui",
        java_flags.join(" "),
        jar_absolute_path.display()
    );

    let loop_script = format!(
        "while true; do \
            echo \"[launcher] Starting server...\"; \
            {}; \
            echo \"[launcher] Server stopped. Restarting in 3s...\"; \
            sleep 3; \
        done",
        java_cmd_str
    );

    if check_tmux_session_exists(tmux_session)? {
        warn!("Tmux session '{}' already exists.", tmux_session);
        info!("Attach via: tmux attach -t {}", tmux_session);
        return Ok(());
    }

    start_tmux_session(tmux_session, &server_dir, &loop_script)?;
    info!(
        "Server '{}' started in tmux session '{}'",
        args.server_name, tmux_session
    );

    Ok(())
}

/// Check if a tmux session with the given name already exists.
fn check_tmux_session_exists(session_name: &str) -> Result<bool> {
    let status = Command::new("tmux")
        .args(["has-session", "-t", session_name])
        .output()
        .context("Failed to execute tmux has-session")?
        .status;

    Ok(status.success())
}

/// Create a new tmux session with the given name, working directory, and command script to execute.
fn start_tmux_session(session_name: &str, cwd: &Path, command_script: &str) -> Result<()> {
    // For tmux new-session -d -s name -c dir "bash -c 'command'"
    Command::new("tmux")
        .args([
            "new-session",
            "-d",
            "-s",
            session_name,
            "-c",
            &cwd.to_string_lossy(),
            "--",
            "bash",
            "-c",
            command_script,
        ])
        .spawn()
        .context("Failed to spawn tmux session")?
        .wait()
        .context("Failed to wait for tmux creation")?;

    Ok(())
}
