# Internal LLM Server

This repository is the version-controlled home for the internal LLM stack running on the Mac at `/Users/raid/internal-llm`.

It is built for practical maintenance:

- Dockerized `llama.cpp`
- Open WebUI
- Nginx with HTTPS
- CoreDNS for `internal.local`
- Prometheus and Grafana
- helper scripts for start, stop, logs, status, and model changes

This repo keeps the important server config in git without committing secrets, model weights, certificates, or local backups.

## What this repo contains

```text
deploy/
  docker-compose.yml
  dns/Corefile
  nginx/nginx.conf
  monitoring/
    prometheus.yml
    blackbox.yml

scripts/
  start-all.sh
  stop-all.sh
  status.sh
  logs.sh
  list-models.sh
  download-model.sh
  use-model.sh
  start-llama.sh
  stop-llama.sh

docs/
  TEAM_ACCESS.md

.env.example
README.md
```

## What is not committed

These stay out of git on purpose:

- real `.env` secrets
- TLS certificates
- mkcert CA files
- GGUF model files
- Open WebUI persistent data
- local backup files
- Python virtualenv contents

## Live runtime location

The running stack lives here:

- `/Users/raid/internal-llm`

Important live paths:

- `/Users/raid/internal-llm/open-webui/docker-compose.yml`
- `/Users/raid/internal-llm/open-webui/.env`
- `/Users/raid/internal-llm/open-webui/nginx/nginx.conf`
- `/Users/raid/internal-llm/open-webui/dns/Corefile`
- `/Users/raid/internal-llm/open-webui/monitoring/prometheus.yml`
- `/Users/raid/internal-llm/scripts`
- `/Users/raid/internal-llm/models`
- `/Users/raid/internal-llm/certs`

Think of this repo as the clean source of truth you can review and share, and `/Users/raid/internal-llm` as the live deployed copy.

## Stack overview

```text
Team Browser
  -> https://llm.internal.local
  -> Nginx
  -> Open WebUI
  -> llama.cpp container
  -> GGUF model in /Users/raid/internal-llm/models
```

Monitoring path:

```text
Prometheus
  -> llama.cpp metrics
  -> nginx exporter
  -> Open WebUI health probe
  -> Grafana dashboards
```

## Main URLs

- LLM UI: `https://llm.internal.local`
- Local fallback UI: `http://localhost:3000`
- llama.cpp API: `http://127.0.0.1:8080/v1`
- Grafana: `https://grafana.internal.local`
- Prometheus: `http://127.0.0.1:9090`

## Current behavior

### Inference

`llama.cpp` currently runs as a normal Docker container.

Important note on macOS:

- this is simpler to package and version-control
- it is not the same as the older host-native Metal setup
- if you later want the best Apple Silicon acceleration again, revisit Docker Model Runner or host-native `llama-server`

### Team access

Open WebUI currently has:

- auth enabled
- signup enabled
- default new role set to `pending`

That means users can create accounts, and an admin can approve or promote them inside Open WebUI.

## Daily operations

These commands are run against the live runtime path, not directly from this repo.

### Start the server

```bash
/Users/raid/internal-llm/scripts/start-all.sh
```

### Stop the server

```bash
/Users/raid/internal-llm/scripts/stop-all.sh
```

### Check health

```bash
/Users/raid/internal-llm/scripts/status.sh
```

### Follow logs

```bash
/Users/raid/internal-llm/scripts/logs.sh
```

Useful direct log commands:

```bash
cd /Users/raid/internal-llm/open-webui
docker compose logs -f llama-cpp
docker compose logs -f open-webui
docker compose logs -f nginx grafana prometheus dns
```

## Model management

### List available models

```bash
/Users/raid/internal-llm/scripts/list-models.sh
```

### Download a model

```bash
/Users/raid/internal-llm/scripts/download-model.sh <huggingface-repo> <gguf-filename> [--activate]
```

Example:

```bash
/Users/raid/internal-llm/scripts/download-model.sh \
  bartowski/Qwen2.5-3B-Instruct-GGUF \
  Qwen2.5-3B-Instruct-Q4_K_M.gguf \
  --activate
```

### Switch the active model

```bash
/Users/raid/internal-llm/scripts/use-model.sh <gguf-file-or-absolute-path>
```

Example:

```bash
/Users/raid/internal-llm/scripts/use-model.sh Qwen2.5-3B-Instruct-Q4_K_M.gguf
```

What the switch script updates:

1. the `model.gguf` symlink in `models/`
2. `LLAMA_MODEL_FILE` in the live `.env`
3. `LLAMA_MODEL_ALIAS` in the live `.env`
4. the `llama-cpp` container

Important: the Docker container uses the real GGUF filename, not the symlink target path.

## DNS and TLS

### DNS

The CoreDNS service answers for:

- `llm.internal.local`
- `grafana.internal.local`
- `prometheus.internal.local`

Current LAN server IP:

- `192.168.0.32`

Team machines must either:

- use this Mac as DNS
- use router-level DNS forwarding
- or have local resolver or host entries

### TLS

The live certs are stored outside git in:

- `/Users/raid/internal-llm/certs`

The mkcert root CA that teammates may need to trust lives at:

- `/Users/raid/internal-llm/certs/rootCA.pem`

## Monitoring

### Grafana

- public URL: `https://grafana.internal.local`
- local port: `http://127.0.0.1:3001`

### Prometheus

- local URL: `http://127.0.0.1:9090`

Prometheus is configured to scrape:

- itself
- `llama.cpp`
- Grafana
- nginx exporter
- Open WebUI health
- public HTTPS health through blackbox probing

## How to keep this repo in sync with the live server

This repo is a clean tracked copy. The live system is separate. When you make changes:

1. edit and test the live files in `/Users/raid/internal-llm`
2. back up changed live files first
3. once the change is verified, copy the updated versions into this repo
4. commit the repo changes

Suggested sync flow:

```bash
cp /Users/raid/internal-llm/open-webui/docker-compose.yml ./deploy/docker-compose.yml
cp /Users/raid/internal-llm/open-webui/nginx/nginx.conf ./deploy/nginx/nginx.conf
cp /Users/raid/internal-llm/open-webui/dns/Corefile ./deploy/dns/Corefile
cp /Users/raid/internal-llm/open-webui/monitoring/prometheus.yml ./deploy/monitoring/prometheus.yml
cp /Users/raid/internal-llm/scripts/*.sh ./scripts/
```

Do not copy the real `.env` into git. Update `.env.example` instead when variables change.

## Safe maintenance workflow

Whenever you touch the live stack:

1. read the current file first
2. create a timestamped backup in `/Users/raid/internal-llm/backups`
3. make one small change at a time
4. validate Compose before restart
5. restart only the affected service when possible
6. verify health endpoints
7. then sync the clean version back into this repo

Good verification commands:

```bash
cd /Users/raid/internal-llm/open-webui
docker compose config
docker ps
curl -sS http://127.0.0.1:8080/v1/models
curl -sS http://127.0.0.1:3000/health
curl -ksS https://llm.internal.local/health
```

## Troubleshooting

### `llm.internal.local` does not load

Check:

- DNS on the client
- Nginx container
- TLS trust on the client

Commands:

```bash
docker ps
curl -ksS https://llm.internal.local/health
```

### Open WebUI loads but no models appear

Check:

- `internal-llm-llama-cpp` is running
- `http://127.0.0.1:8080/v1/models` returns JSON
- `LLAMA_MODEL_FILE` matches a real file in `/Users/raid/internal-llm/models`

Commands:

```bash
curl -sS http://127.0.0.1:8080/v1/models
cd /Users/raid/internal-llm/open-webui
docker compose logs --tail=100 llama-cpp
```

### `llama-cpp` container keeps restarting

Most common causes:

- wrong model filename in `.env`
- missing GGUF file
- model was renamed but `.env` was not updated
- unsupported model format
- insufficient RAM

Commands:

```bash
cd /Users/raid/internal-llm/open-webui
docker compose logs --tail=100 llama-cpp
ls -lh /Users/raid/internal-llm/models
grep '^LLAMA_MODEL_' /Users/raid/internal-llm/open-webui/.env
```

### The server is slow

Possible reasons:

- model is too large
- context size is too large
- Dockerized `llama.cpp` is using CPU rather than the faster host-native Metal path

## What to commit and what not to commit

Commit:

- compose files
- Nginx config
- DNS config
- Prometheus config
- shell scripts
- docs
- `.env.example`

Do not commit:

- real `.env`
- cert files
- root CA
- model files
- backups
- live conversation data
- virtualenvs

## Quick command reference

```bash
# start
/Users/raid/internal-llm/scripts/start-all.sh

# stop
/Users/raid/internal-llm/scripts/stop-all.sh

# status
/Users/raid/internal-llm/scripts/status.sh

# logs
/Users/raid/internal-llm/scripts/logs.sh

# list models
/Users/raid/internal-llm/scripts/list-models.sh

# download model
/Users/raid/internal-llm/scripts/download-model.sh <repo> <filename>

# switch model
/Users/raid/internal-llm/scripts/use-model.sh <filename>
```

## Final maintenance advice

If something breaks and you want the fastest path back to clarity, start with these two live files:

- `/Users/raid/internal-llm/open-webui/docker-compose.yml`
- `/Users/raid/internal-llm/open-webui/.env`

Most issues reduce to one of these:

- wrong container state
- wrong model filename
- bad DNS or TLS on the client
- Open WebUI cannot reach `llama.cpp`
