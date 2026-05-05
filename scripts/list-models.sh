#!/usr/bin/env bash
set -euo pipefail

MODELS_DIR="$HOME/internal-llm/models"

find "$MODELS_DIR" -maxdepth 1 -type f -name '*.gguf' -print | sort
