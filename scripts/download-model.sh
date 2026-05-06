#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <huggingface-repo> <gguf-filename> [--activate]"
  exit 1
fi

BASE_DIR="${INTERNAL_LLM_HOME:-$HOME/internal-llm}"
HF_BIN="$BASE_DIR/.venv/bin/hf"
MODELS_DIR="$BASE_DIR/models"
REPO="$1"
FILENAME="$2"
ACTIVATE="${3:-}"

if [ ! -x "$HF_BIN" ]; then
  echo "Hugging Face CLI not found in $HF_BIN"
  exit 1
fi

mkdir -p "$MODELS_DIR"

"$HF_BIN" download "$REPO" "$FILENAME" --local-dir "$MODELS_DIR"

echo "Downloaded: $MODELS_DIR/$FILENAME"

if [ "$ACTIVATE" = "--activate" ]; then
  "$BASE_DIR/scripts/use-model.sh" "$FILENAME"
fi
