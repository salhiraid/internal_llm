#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${INTERNAL_LLM_HOME:-$HOME/internal-llm}"
MODELS_DIR="$BASE_DIR/models"

find "$MODELS_DIR" -maxdepth 1 -type f -name '*.gguf' -print | sort
