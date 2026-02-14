//! Everest - Minecraft Server Management CLI
//! This CLI tool allows you to easily launch and manage Minecraft servers using tmux sessions.
//! It also provides an update command to fetch the latest server engines and plugins from GitHub.

mod config;
mod utils;

mod modules;

use std::path::PathBuf;

use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "everest", version = "3.0.0")]
#[command(about = "Everest - Minecraft Server Management CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Launch a Minecraft server in a tmux session with auto-restart
    Launch {
        /// Server name (must match a directory in servers/)
        server: String,

        /// Engine type (paper, velocity, etc.)
        #[arg(long, default_value = "paper")]
        engine: String,

        /// Extra JVM flags passed to java
        #[arg(last = true)]
        java_flags: Vec<String>,
    },

    /// Update engines and plugins from configured sources
    Update {
        /// Config branch to use (defaults to defaultBranch in config)
        #[arg(long, default_value = "")]
        branch: String,
    },
}

fn find_root() -> Result<PathBuf> {
    // Walk up from the executable's directory to find the project root
    // (identified by having a config/ directory)
    let exe = std::env::current_exe()?;
    let mut dir = exe.parent().map(|p| p.to_path_buf());

    // Also check current working directory
    let cwd = std::env::current_dir()?;
    if cwd.join("config").is_dir() {
        return Ok(cwd);
    }

    while let Some(d) = dir {
        if d.join("config").is_dir() {
            return Ok(d);
        }
        dir = d.parent().map(|p| p.to_path_buf());
    }

    anyhow::bail!("Could not find Everest project root (no `config` directory found)");
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .format_timestamp_secs()
        .init();

    let cli = Cli::parse();
    let root = find_root()?;

    match cli.command {
        Commands::Launch {
            server,
            engine,
            java_flags,
        } => {
            let args = modules::launcher::LaunchArgs {
                server_name: server,
                engine_type: engine,
                extra_java_flags: java_flags,
            };
            modules::launcher::run(&args, &root)?;
        }
        Commands::Update { branch } => {
            modules::updater::run(&root, &branch).await?;
        }
    }

    Ok(())
}
