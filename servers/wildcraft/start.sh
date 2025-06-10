#!/usr/bin/env bash
set -euo pipefail

# Configuration
SERVER_ENGINE="paper"
SERVER_NAME="wildcraft"
TMUX_SESSION="$SERVER_NAME"

# Ensure prerequisites
for cmd in tmux java; do
  command -v "$cmd" &>/dev/null || {
    echo "❌ '$cmd' not found" >&2
    exit 1
  }
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PATH="$(realpath "${SCRIPT_DIR}/../..")"
SERVER_DIR="${ROOT_PATH}/servers/${SERVER_NAME}"
ENGINE_DIR="${ROOT_PATH}/libraries/engines"

# Enter server directory
cd "$SERVER_DIR" || {
  echo "❌ Failed to enter $SERVER_DIR" >&2
  exit 1
}

# Find latest engine JAR (version-aware sort)
JAR_FILE=$(find "$ENGINE_DIR" -maxdepth 1 -type f -name "${SERVER_ENGINE}*.jar" | sort -V | tail -n1)
if [[ -z "$JAR_FILE" || ! -f "$JAR_FILE" ]]; then
  echo "❌ Engine not found for: $SERVER_ENGINE" >&2
  exit 1
fi

# Java flags (Aikar flags)
JAVA_FLAGS=(
  -Xms2048M
  -Xmx4096M
  -XX:+UseG1GC
  -XX:+ParallelRefProcEnabled
  -XX:+UnlockExperimentalVMOptions
  -XX:+PerfDisableSharedMem
  -XX:+DisableExplicitGC
  -XX:+AlwaysPreTouch
  -XX:MaxGCPauseMillis=200
  -XX:G1NewSizePercent=30
  -XX:G1MaxNewSizePercent=40
  -XX:G1HeapRegionSize=8M
  -XX:G1ReservePercent=20
  -XX:G1HeapWastePercent=5
  -XX:G1MixedGCCountTarget=4
  -XX:InitiatingHeapOccupancyPercent=15
  -XX:G1MixedGCLiveThresholdPercent=90
  -XX:G1RSetUpdatingPauseTimePercent=5
  -XX:SurvivorRatio=32
  -XX:MaxTenuringThreshold=1
  -Dusing.aikars.flags=https://mcflags.emc.gs
  -Daikars.new.flags=true
  -Dpaper.disableJNA=true
  -Duser.timezone=Asia/Seoul
  -Djna.nosys=true
)

# Start command as array
START_CMD=(java "${JAVA_FLAGS[@]}" -jar "$JAR_FILE" nogui)

# Wrapper of tmux session
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "⚠️ Tmux session '$TMUX_SESSION' already exists."

  # Check if server process is alive
  if ! pgrep -f "[j]ava.*$(basename "$JAR_FILE")" >/dev/null; then
    echo "💀 Session alive, but server is down. Restarting..."
    tmux send-keys -t "$TMUX_SESSION" "stop" C-m
    sleep 1
    tmux send-keys -t "$TMUX_SESSION" "${START_CMD[@]}" C-m
    echo "🔁 Restarted server at $(date)"
  else
    echo "✅ Server is already running."
  fi
else
  # Create new detached tmux session
  tmux new-session -s "$TMUX_SESSION" -d -- "${START_CMD[@]}"
fi
