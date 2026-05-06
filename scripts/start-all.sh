#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${INTERNAL_LLM_HOME:-$HOME/internal-llm}"

"$BASE_DIR/scripts/stop-llama.sh" || true

cd "$BASE_DIR/open-webui"

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
  if [ "$ALLOW_NO_DNS" = "1" ]; then
    echo "Port 53 is already in use; starting stack without dns service (INTERNAL_LLM_ALLOW_NO_DNS=1)."
    docker compose up -d --scale dns=0
  else
    echo "Port 53 is already in use. Either stop the process using port 53, or run:"
    echo "  INTERNAL_LLM_ALLOW_NO_DNS=1 $0"
    echo "to start without the dns service."
    exit 1
  fi
else
  docker compose up -d
fi
docker compose up -d

echo "Open WebUI local fallback: http://localhost:3000"
echo "Team URL: https://llm.internal.local"
echo "Grafana URL: https://grafana.internal.local"
