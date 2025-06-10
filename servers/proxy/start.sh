#!/usr/bin/env bash
set -euo pipefail

# Configuration
SERVER_NAME="proxy"
SERVER_ENGINE="velocity"
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

# Java flags (Velocity flags)
JAVA_FLAGS=(
  -Xms512M
  -Xmx1024M
  -XX:+UseG1GC
  -XX:+AlwaysPreTouch
  -XX:+ParallelRefProcEnabled
  -XX:+UnlockExperimentalVMOptions
  -XX:G1HeapRegionSize=4M
  -XX:MaxInlineLevel=15
  -Djna.nosys=true
  -Duser.timezone=Asia/Seoul
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
