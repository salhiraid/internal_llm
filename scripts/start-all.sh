#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${INTERNAL_LLM_HOME:-$HOME/internal-llm}"

"$BASE_DIR/scripts/stop-llama.sh" || true

cd "$BASE_DIR/open-webui"
docker compose up -d

echo "Open WebUI local fallback: http://localhost:3000"
echo "Team URL: https://llm.internal.local"
echo "Grafana URL: https://grafana.internal.local"
