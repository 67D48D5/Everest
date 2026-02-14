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
            "paper" => EngineType::Paper,
            "velocity" => EngineType::Velocity,
            _ => EngineType::Unknown,
        }
    }
}

impl std::fmt::Display for EngineType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            EngineType::Paper => "paper",
            EngineType::Velocity => "velocity",
            EngineType::Unknown => "unknown",
        };
        write!(f, "{}", s)
    }
}

pub struct LaunchArgs {
    pub server_name: String,
    pub engine_type: String,
    pub extra_java_flags: Vec<String>,
}

/// Builds the JVM flags for launching the server, combining common optimizations with engine-specific flags and user-defined extra flags.
fn build_jvm_flags(engine: EngineType, extra_flags: &[String]) -> Vec<String> {
    // Common JVM flags for Minecraft servers, optimized for low-latency and good GC performance.
    let mut flags: Vec<String> = vec![
        "-XX:+UseG1GC".into(),
        "-XX:+AlwaysPreTouch".into(),
        "-XX:+ParallelRefProcEnabled".into(),
        "-XX:+UnlockExperimentalVMOptions".into(),
        "-Duser.timezone=Asia/Seoul".into(),
    ];

    // Add engine-specific JVM flags based on known optimizations for popular Minecraft server implementations.
    // These flags are based on community recommendations and may need to be adjusted over time as JVM and server versions evolve.
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

    // User-defined extra flags are appended at the end, allowing users to override or add to the default set of JVM optimizations as needed for their specific server setup or preferences.
    // @TODO: Consider validating or sanitizing extra flags to prevent common mistakes (e.g., invalid flags, conflicting flags, etc.) and provide better error messages.
    // For now, we simply append them as-is, trusting the user to provide valid JVM flags. In the future, we could add a validation step here if needed.
    flags.extend_from_slice(extra_flags);

    flags
}

pub fn run(args: &LaunchArgs, root: &Path) -> Result<()> {
    // @TODO: Refer `schema.json` for server and engine definitions instead of hardcoding them here.
    // This will allow more flexibility and support for custom server types and engines in the future without needing code changes.
    let server_dir = root.join("servers").join(&args.server_name);
    let engine_dir = root.join("libraries/engines");

    // Define the tmux session name based on the server name.
    // This allows users to easily identify and manage multiple server sessions in tmux by their server names.
    let tmux_session = &args.server_name;

    // Validate the engine type and log a warning if it's unknown, but still attempt to launch with default flags.
    let engine_type = EngineType::from(args.engine_type.as_str());

    // Check if the engine directory exists and is a directory, otherwise return an error.
    if !server_dir.is_dir() {
        bail!(
            "Server directory does not exist: '{}'",
            server_dir.display()
        );
    }

    // Find the latest JAR matching the engine type pattern. (e.g., "paper-*.jar" for Paper)
    let pattern = format!("{}*.jar", engine_type);
    let jar_path = pick_latest(&engine_dir, &pattern)
        .with_context(|| format!("Engine JAR not found for type: '{}'", engine_type))?;

    // Convert to absolute path to avoid issues when running inside tmux with different working directories.
    // This ensures the java command can find the JAR regardless of where tmux starts.
    let jar_absolute_path = jar_path
        .canonicalize()
        .context("Failed to resolve absolute path of engine JAR")?;

    // Compose the java command with JVM flags and the server JAR.
    let java_flags = build_jvm_flags(engine_type, &args.extra_java_flags);
    let java_cmd_str = format!(
        "java {} -jar \"{}\" nogui",
        java_flags.join(" "),
        jar_absolute_path.display()
    );

    // Create a loop script that will restart the server if it crashes.
    let loop_script = format!(
        "while true; do \
            echo \"[Launcher] Starting server...\"; \
            {}; \
            echo \"[Launcher] Server stopped. Restarting in 3s...\"; \
            sleep 3; \
        done",
        java_cmd_str
    );

    // Check if the tmux session already exists to avoid creating duplicate sessions. If it exists, log a warning and skip launching.
    if check_tmux_session_exists(tmux_session)? {
        warn!("Tmux session '{}' already exists.", tmux_session);
        info!("Attach via: tmux attach -t {}", tmux_session);

        return Ok(());
    }

    // Start the tmux session with the loop script as the command to execute. The session will run in the background.
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
