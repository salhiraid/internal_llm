#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${INTERNAL_LLM_HOME:-$(cd "$SCRIPT_DIR/.." && pwd)}"
IMAGE_DIR="${INTERNAL_LLM_IMAGE_DIR:-/opt/docker-images}"
AUTOLOAD_IMAGES="${INTERNAL_LLM_AUTOLOAD_IMAGES:-1}"
ENABLE_DNS="${INTERNAL_LLM_ENABLE_DNS:-0}"
STRICT_DNS="${INTERNAL_LLM_STRICT_DNS:-0}"
STARTED_WITH_DNS=0

# Prevent accidental DNS startup from inherited COMPOSE_PROFILES=dns
if [ "$ENABLE_DNS" != "1" ]; then
  unset COMPOSE_PROFILES || true
fi


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
  else
    echo "No .tar images found in $IMAGE_DIR; starting with existing local images."
  fi
fi

PORT53_IN_USE=0
PORT53_OWNER=""
if ss -ltn "( sport = :53 )" 2>/dev/null | grep -q ":53" || ss -lun "( sport = :53 )" 2>/dev/null | grep -q ":53"; then
  PORT53_IN_USE=1
  PORT53_OWNER="$(ss -ltnup 2>/dev/null | awk '/:53 / {print; found=1} END{if(!found) print "(owner details unavailable)"}')"
fi

if [ "$ENABLE_DNS" = "1" ]; then
  if [ "$PORT53_IN_USE" = "1" ]; then
    echo "Port 53 is already in use on the host:"
    echo "$PORT53_OWNER"
    if [ "$STRICT_DNS" = "1" ]; then
      echo "INTERNAL_LLM_ENABLE_DNS=1 and INTERNAL_LLM_STRICT_DNS=1 were set, so exiting."
      exit 1
    fi
    echo "Falling back to start without dns container."
    docker compose up -d --pull never
  else
    echo "Port 53 is free; starting stack with dns profile enabled."
    docker compose --profile dns up -d --pull never
    STARTED_WITH_DNS=1
  fi
else
  docker compose up -d --pull never
fi

echo "Open WebUI local fallback: http://localhost:3000"
echo "Team URL: https://llm.internal.local"
echo "Grafana URL: https://grafana.internal.local"
if [ "$STARTED_WITH_DNS" = "0" ]; then
  LAN_IP_VALUE="$(grep -E '^LAN_IP=' "$BASE_DIR/open-webui/.env" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  echo "Note: dns container is not running."
  echo "To enable it when port 53 is free: INTERNAL_LLM_ENABLE_DNS=1 ./scripts/start-all.sh"
  if [ -n "$LAN_IP_VALUE" ]; then
    echo "Add this hosts entry on client machines if needed:"
    echo "  $LAN_IP_VALUE llm.internal.local grafana.internal.local prometheus.internal.local"
  fi
fi
