#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${INTERNAL_LLM_HOME:-$(cd "$SCRIPT_DIR/.." && pwd)}"
IMAGE_DIR="${INTERNAL_LLM_IMAGE_DIR:-/opt/docker-images}"
AUTOLOAD_IMAGES="${INTERNAL_LLM_AUTOLOAD_IMAGES:-1}"
ALLOW_NO_DNS="${INTERNAL_LLM_ALLOW_NO_DNS:-1}"

"$BASE_DIR/scripts/stop-llama.sh" || true

cd "$BASE_DIR/open-webui"
docker compose down --remove-orphans || true

if [ "$AUTOLOAD_IMAGES" = "1" ] && [ -d "$IMAGE_DIR" ]; then
  shopt -s nullglob
  TAR_FILES=("$IMAGE_DIR"/*.tar)
  shopt -u nullglob
  if [ "${#TAR_FILES[@]}" -gt 0 ]; then
    echo "Loading offline Docker images from $IMAGE_DIR ..."
    for f in "${TAR_FILES[@]}"; do
      echo "Loading $f"
      docker load -i "$f"
    done
  fi
fi

if ss -ltn "( sport = :53 )" 2>/dev/null | grep -q ":53" || ss -lun "( sport = :53 )" 2>/dev/null | grep -q ":53"; then
  if [ "$ALLOW_NO_DNS" = "0" ]; then
    echo "Port 53 is already in use. Either stop the process using port 53, or run:"
    echo "  INTERNAL_LLM_ALLOW_NO_DNS=1 $0"
    echo "or start with no dns profile (default behavior)."
    exit 1
  else
    echo "Port 53 is already in use; starting stack without dns service."
    docker compose up -d --pull never
  fi
else
  if [ "$ALLOW_NO_DNS" = "1" ]; then
    docker compose up -d --pull never
  else
    echo "Port 53 is free; starting stack with dns profile enabled."
    docker compose --profile dns up -d --pull never
  fi
fi

echo "Open WebUI local fallback: http://localhost:3000"
echo "Team URL: https://llm.internal.local"
echo "Grafana URL: https://grafana.internal.local"
