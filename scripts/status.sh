#!/usr/bin/env bash
set -euo pipefail

echo "llama.cpp container:"
docker ps --filter "name=internal-llm-llama-cpp" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true

echo
echo "llama.cpp /v1/models:"
curl -sS http://127.0.0.1:8080/v1/models || true

echo
echo "llama.cpp /health:"
curl -sS http://127.0.0.1:8080/health || true

echo
echo "Containers:"
docker ps --filter "name=open-webui" --filter "name=internal-llm"

echo
echo "Open WebUI health:"
curl -sS http://127.0.0.1:3000/health || true
echo

echo "LAN HTTPS:"
curl -ksS https://llm.internal.local/health || true
echo

echo "Grafana:"
curl -ksSI https://grafana.internal.local/login | head -n 1 || true
echo
