#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${INTERNAL_LLM_HOME:-$HOME/internal-llm}"
MODEL_LINK="$BASE_DIR/models/model.gguf"
PID_FILE="$BASE_DIR/logs/llama-server.pid"
LABEL="com.internal-llm.llama-server"

PIDS=""

if [ -L "$MODEL_LINK" ]; then
  MODEL_PATH="$(readlink "$MODEL_LINK")"
  case "$MODEL_PATH" in
    /*) ;;
    *) MODEL_PATH="$(cd "$(dirname "$MODEL_LINK")" && cd "$(dirname "$MODEL_PATH")" && pwd)/$(basename "$MODEL_PATH")" ;;
  esac
else
  MODEL_PATH="$MODEL_LINK"
fi

if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  echo "Removing launchctl job $LABEL"
  launchctl remove "$LABEL" 2>/dev/null || true
fi

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  PIDS="$(cat "$PID_FILE")"
else
  PIDS="$(pgrep -f "llama-server.*$MODEL_PATH" || true)"
fi

if [ -z "$PIDS" ]; then
  echo "No matching llama-server process is running."
  rm -f "$PID_FILE"
  exit 0
fi

for PID in $PIDS; do
  CMD="$(ps -p "$PID" -o command= || true)"
  case "$CMD" in
    *llama-server*"$MODEL_PATH"*)
      echo "Stopping llama-server PID $PID"
      kill "$PID" 2>/dev/null || true
      ;;
    *)
      echo "Skipping unrelated process PID $PID"
      ;;
  esac
done

sleep 2

for PID in $PIDS; do
  if kill -0 "$PID" 2>/dev/null; then
    CMD="$(ps -p "$PID" -o command= || true)"
    case "$CMD" in
      *llama-server*"$MODEL_PATH"*)
        echo "PID $PID did not stop gracefully; sending SIGTERM again."
        kill "$PID" 2>/dev/null || true
        ;;
    esac
  fi
done

rm -f "$PID_FILE"
echo "llama-server stopped."
