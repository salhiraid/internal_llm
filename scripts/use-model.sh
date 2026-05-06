#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <gguf-file-or-absolute-path>"
  exit 1
fi

BASE_DIR="${INTERNAL_LLM_HOME:-$HOME/internal-llm}"
MODELS_DIR="$BASE_DIR/models"
BACKUPS_DIR="$BASE_DIR/backups"
LINK_PATH="$MODELS_DIR/model.gguf"
ENV_FILE="$BASE_DIR/open-webui/.env"
INPUT="$1"

mkdir -p "$BACKUPS_DIR"

if [ -f "$INPUT" ]; then
  TARGET_PATH="$INPUT"
elif [ -f "$MODELS_DIR/$INPUT" ]; then
  TARGET_PATH="$MODELS_DIR/$INPUT"
else
  echo "Model file not found: $INPUT"
  exit 1
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
if [ -e "$LINK_PATH" ] || [ -L "$LINK_PATH" ]; then
  mv "$LINK_PATH" "$BACKUPS_DIR/model.gguf.backup.$TIMESTAMP"
fi

ln -s "$TARGET_PATH" "$LINK_PATH"

if [ -f "$ENV_FILE" ]; then
  python3 - "$ENV_FILE" "$(basename "$TARGET_PATH")" <<'PY'
from pathlib import Path
import sys

env_path = Path(sys.argv[1])
model_value = sys.argv[2]
lines = env_path.read_text().splitlines()
alias_updated = False
file_updated = False
for index, line in enumerate(lines):
    if line.startswith("LLAMA_MODEL_ALIAS="):
        lines[index] = f"LLAMA_MODEL_ALIAS={model_value}"
        alias_updated = True
    elif line.startswith("LLAMA_MODEL_FILE="):
        lines[index] = f"LLAMA_MODEL_FILE={model_value}"
        file_updated = True
if not alias_updated:
    lines.append(f"LLAMA_MODEL_ALIAS={model_value}")
if not file_updated:
    lines.append(f"LLAMA_MODEL_FILE={model_value}")
env_path.write_text("\n".join(lines) + "\n")
PY
fi

cd "$BASE_DIR/open-webui"
docker compose up -d --force-recreate llama-cpp

echo "Active model switched to $(basename "$TARGET_PATH")"
