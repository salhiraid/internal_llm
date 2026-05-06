#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${INTERNAL_LLM_HOME:-$HOME/internal-llm}"
cd "$BASE_DIR/open-webui"
docker compose down

"$BASE_DIR/scripts/stop-llama.sh"
