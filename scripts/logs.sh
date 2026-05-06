#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${INTERNAL_LLM_HOME:-$HOME/internal-llm}"

echo "Following llama.cpp container logs. Press Ctrl-C to stop."
echo "Open WebUI logs are available with:"
echo "  cd $BASE_DIR/open-webui && docker compose logs -f open-webui"
echo "Nginx/Grafana/Prometheus/DNS logs are available with:"
echo "  cd $BASE_DIR/open-webui && docker compose logs -f nginx grafana prometheus dns"
echo
cd "$BASE_DIR/open-webui"
docker compose logs -f llama-cpp
