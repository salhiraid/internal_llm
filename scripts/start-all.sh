#!/usr/bin/env bash
set -euo pipefail

"$HOME/internal-llm/scripts/stop-llama.sh" || true

cd "$HOME/internal-llm/open-webui"
docker compose up -d

echo "Open WebUI local fallback: http://localhost:3000"
echo "Team URL: https://llm.internal.local"
echo "Grafana URL: https://grafana.internal.local"
