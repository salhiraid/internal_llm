#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${INTERNAL_LLM_HOME:-$HOME/internal-llm}"
MODEL_LINK="$BASE_DIR/models/model.gguf"
LOG_DIR="$BASE_DIR/logs"
LOG_FILE="$LOG_DIR/llama-server.log"
PID_FILE="$LOG_DIR/llama-server.pid"
LABEL="com.internal-llm.llama-server"

mkdir -p "$LOG_DIR"

if [ ! -f "$MODEL_LINK" ]; then
  echo "Model not found: $MODEL_LINK"
  echo "Place a GGUF model there, or symlink model.gguf to your downloaded GGUF file."
  exit 1
fi

if [ -L "$MODEL_LINK" ]; then
  MODEL_PATH="$(readlink "$MODEL_LINK")"
  case "$MODEL_PATH" in
    /*) ;;
    *) MODEL_PATH="$(cd "$(dirname "$MODEL_LINK")" && cd "$(dirname "$MODEL_PATH")" && pwd)/$(basename "$MODEL_PATH")" ;;
  esac
else
  MODEL_PATH="$MODEL_LINK"
fi

MODEL_NAME="$(basename "$MODEL_PATH")"

if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  echo "llama-server launchctl job is already loaded."
  exit 0
fi

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "llama-server is already running with PID $(cat "$PID_FILE")"
  exit 0
fi

if pgrep -f "llama-server.*$MODEL_PATH" >/dev/null 2>&1; then
  PID="$(pgrep -f "llama-server.*$MODEL_PATH" | head -n 1)"
  echo "$PID" > "$PID_FILE"
  echo "llama-server is already running with PID $PID"
  exit 0
fi

ARGS=(
  -m "$MODEL_PATH"
  --alias "$MODEL_NAME"
  --host 0.0.0.0
  --port 8080
  --ctx-size 4096
  --parallel 2
  --metrics
)

HELP="$(llama-server --help 2>&1 || true)"

if printf '%s\n' "$HELP" | grep -q -- "--cont-batching"; then
  ARGS+=(--cont-batching)
else
  echo "Note: --cont-batching is not supported by this llama-server; starting without it."
fi

if printf '%s\n' "$HELP" | grep -q -- "--gpu-layers"; then
  ARGS+=(--gpu-layers all)
elif printf '%s\n' "$HELP" | grep -q -- "--n-gpu-layers"; then
  ARGS+=(--n-gpu-layers 999)
else
  echo "Note: GPU layer flag is not supported by this llama-server; starting without it."
fi

echo "Starting llama-server..."
echo "Model: $MODEL_NAME"
echo "Log: $LOG_FILE"

CMD="exec llama-server"
for ARG in "${ARGS[@]}"; do
  printf -v QUOTED_ARG "%q" "$ARG"
  CMD="$CMD $QUOTED_ARG"
done
printf -v QUOTED_LOG "%q" "$LOG_FILE"
CMD="$CMD >> $QUOTED_LOG 2>&1"

launchctl submit -l "$LABEL" -- /bin/zsh -lc "$CMD"

sleep 2

PID="$(lsof -nP -iTCP:8080 -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true)"
if [ -n "$PID" ]; then
  echo "$PID" > "$PID_FILE"
  echo "llama-server started with PID $PID"
else
  echo "llama-server failed to start. Last 80 log lines:"
  tail -n 80 "$LOG_FILE" || true
  exit 1
fi
