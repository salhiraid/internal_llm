#!/usr/bin/env bash
set -euo pipefail

echo "Following llama.cpp container logs. Press Ctrl-C to stop."
echo "Open WebUI logs are available with:"
echo "  cd $HOME/internal-llm/open-webui && docker compose logs -f open-webui"
echo "Nginx/Grafana/Prometheus/DNS logs are available with:"
echo "  cd $HOME/internal-llm/open-webui && docker compose logs -f nginx grafana prometheus dns"
echo
cd "$HOME/internal-llm/open-webui"
docker compose logs -f llama-cpp
