#!/usr/bin/env bash
set -euo pipefail

cd "$HOME/internal-llm/open-webui"
docker compose down

"$HOME/internal-llm/scripts/stop-llama.sh"
