# Ubuntu Installation Guide

This guide shows how to build the same internal LLM stack on an Ubuntu machine.

Target stack:

- Ubuntu server or desktop
- `llama.cpp` in Docker
- Open WebUI in Docker
- Nginx reverse proxy with HTTPS
- CoreDNS for `internal.local`
- Prometheus and Grafana
- team browser access

Target URLs:

- `https://llm.internal.local`
- `https://grafana.internal.local`

This guide is written for a simple, practical installation, not a hardened production environment.

## What you will build

```text
Team Browser
  -> https://llm.internal.local
  -> Nginx
  -> Open WebUI
  -> llama.cpp container
  -> GGUF model
```

Monitoring:

```text
Prometheus
  -> llama.cpp metrics
  -> nginx exporter
  -> Open WebUI health
Grafana
  -> Prometheus
```

## Assumptions

This guide assumes:

- Ubuntu 22.04 or 24.04
- Docker Engine and Docker Compose plugin will be used
- the server has a fixed LAN IP
- you want teammates on the same network to reach the service
- you are okay using `mkcert` for an internal trusted certificate

Example values used below:

- server hostname: `llm-server`
- server LAN IP: `192.168.1.50`
- LLM URL: `llm.internal.local`
- Grafana URL: `grafana.internal.local`
- Prometheus URL: `prometheus.internal.local`
- install root: `/opt/internal-llm`

Replace those values with your real ones.

## 1. Prepare the Ubuntu machine

Update packages:

```bash
sudo apt update
sudo apt upgrade -y
```

Install basic tools:

```bash
sudo apt install -y \
  ca-certificates \
  curl \
  git \
  gnupg \
  lsb-release \
  jq \
  python3 \
  python3-pip \
  python3-venv \
  openssl
```

Check the machine:

```bash
uname -a
lsb_release -a
free -h
df -h
```

## 2. Install Docker Engine and Compose

Remove old packages if present:

```bash
sudo apt remove -y docker docker-engine docker.io containerd runc
```

Set up Docker’s apt repository:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
```

Install Docker:

```bash
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Enable and start Docker:

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

Optional but convenient, allow your user to run Docker without `sudo`:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

Verify:

```bash
docker --version
docker compose version
docker ps
```

## 3. Create the project structure

Create folders:

```bash
sudo mkdir -p /opt/internal-llm/{models,open-webui/nginx,open-webui/dns,open-webui/monitoring,grafana-data,backups,scripts,certs,logs}
sudo chown -R "$USER:$USER" /opt/internal-llm
```

Create a Python virtual environment for model downloads:

```bash
python3 -m venv /opt/internal-llm/.venv
/opt/internal-llm/.venv/bin/pip install --upgrade pip
/opt/internal-llm/.venv/bin/pip install huggingface_hub
```

## 4. Download a GGUF model

Example model:

- repo: `bartowski/Llama-3.2-3B-Instruct-GGUF`
- file: `Llama-3.2-3B-Instruct-Q4_K_M.gguf`

Download it:

```bash
/opt/internal-llm/.venv/bin/hf download \
  bartowski/Llama-3.2-3B-Instruct-GGUF \
  Llama-3.2-3B-Instruct-Q4_K_M.gguf \
  --local-dir /opt/internal-llm/models
```

Verify:

```bash
ls -lh /opt/internal-llm/models
```

## 5. Create certificates with mkcert

Install `mkcert`:

```bash
sudo apt install -y libnss3-tools
curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
chmod +x mkcert-v*-linux-amd64
sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert
```

Initialize local CA:

```bash
mkcert -install
```

Generate certificates:

```bash
cd /opt/internal-llm/certs
mkcert -cert-file internal.local.pem -key-file internal.local-key.pem \
  llm.internal.local grafana.internal.local prometheus.internal.local
cp "$(mkcert -CAROOT)/rootCA.pem" /opt/internal-llm/certs/rootCA.pem
```

Important:

- this trusts the CA on the Ubuntu server itself
- each teammate must also trust `rootCA.pem` on their own machine if you want no browser warning

## 6. Create the environment file

Create `/opt/internal-llm/open-webui/.env`:

```dotenv
WEBUI_ADMIN_EMAIL=admin@company.local
WEBUI_ADMIN_PASSWORD=ChangeThisStrongPassword123!
WEBUI_SECRET_KEY=replace_with_openssl_random_hex
ENABLE_SIGNUP=true
DEFAULT_USER_ROLE=pending
LLAMA_MODEL_FILE=Llama-3.2-3B-Instruct-Q4_K_M.gguf
LLAMA_MODEL_ALIAS=Llama-3.2-3B-Instruct-Q4_K_M.gguf
LAN_IP=192.168.1.50
LLM_HOSTNAME=llm.internal.local
GRAFANA_HOSTNAME=grafana.internal.local
PROMETHEUS_HOSTNAME=prometheus.internal.local
GRAFANA_ADMIN_PASSWORD=replace_with_strong_password
WEBUI_URL=https://llm.internal.local
```

Generate a secret key:

```bash
openssl rand -hex 32
```

## 7. Create docker-compose.yml

Create `/opt/internal-llm/open-webui/docker-compose.yml`:

```yaml
volumes:
  open-webui-data:
  grafana-data:

services:
  llama-cpp:
    image: ghcr.io/ggml-org/llama.cpp:server
    container_name: internal-llm-llama-cpp
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - ../models:/models:ro
    command:
      - -m
      - /models/${LLAMA_MODEL_FILE}
      - --alias
      - ${LLAMA_MODEL_ALIAS}
      - --host
      - 0.0.0.0
      - --port
      - "8080"
      - --ctx-size
      - "4096"
      - --parallel
      - "2"
      - --cont-batching
      - --metrics

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    depends_on:
      - llama-cpp
    ports:
      - "127.0.0.1:3000:8080"
    volumes:
      - open-webui-data:/app/backend/data
    environment:
      WEBUI_AUTH: "true"
      ENABLE_SIGNUP: "${ENABLE_SIGNUP}"
      DEFAULT_USER_ROLE: "${DEFAULT_USER_ROLE}"
      WEBUI_ADMIN_EMAIL: "${WEBUI_ADMIN_EMAIL}"
      WEBUI_ADMIN_PASSWORD: "${WEBUI_ADMIN_PASSWORD}"
      WEBUI_SECRET_KEY: "${WEBUI_SECRET_KEY}"
      WEBUI_URL: "${WEBUI_URL}"
      ENABLE_OLLAMA_API: "false"
      ENABLE_OPENAI_API: "true"
      OPENAI_API_BASE_URLS: "http://llama-cpp:8080/v1"
      OPENAI_API_KEYS: "dummy-key"

  nginx:
    image: nginx:stable-alpine
    container_name: internal-llm-nginx
    restart: unless-stopped
    depends_on:
      - open-webui
      - grafana
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ../certs:/etc/nginx/certs:ro

  dns:
    image: coredns/coredns:latest
    container_name: internal-llm-dns
    restart: unless-stopped
    command: -conf /etc/coredns/Corefile
    ports:
      - "53:53/tcp"
      - "53:53/udp"
    volumes:
      - ./dns/Corefile:/etc/coredns/Corefile:ro

  prometheus:
    image: prom/prometheus:latest
    container_name: internal-llm-prometheus
    restart: unless-stopped
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--web.enable-lifecycle"
    ports:
      - "127.0.0.1:9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./monitoring/blackbox.yml:/etc/prometheus/blackbox.yml:ro

  blackbox-exporter:
    image: quay.io/prometheus/blackbox-exporter:latest
    container_name: internal-llm-blackbox
    restart: unless-stopped
    command:
      - "--config.file=/etc/blackbox_exporter/config.yml"
    volumes:
      - ./monitoring/blackbox.yml:/etc/blackbox_exporter/config.yml:ro

  nginx-exporter:
    image: nginx/nginx-prometheus-exporter:1.4.2
    container_name: internal-llm-nginx-exporter
    restart: unless-stopped
    depends_on:
      - nginx
    command:
      - "--nginx.scrape-uri=http://nginx:18080/stub_status"

  grafana:
    image: grafana/grafana:latest
    container_name: internal-llm-grafana
    restart: unless-stopped
    depends_on:
      - prometheus
    ports:
      - "127.0.0.1:3001:3000"
    environment:
      GF_SECURITY_ADMIN_USER: "admin"
      GF_SECURITY_ADMIN_PASSWORD: "${GRAFANA_ADMIN_PASSWORD}"
      GF_SERVER_ROOT_URL: "https://${GRAFANA_HOSTNAME}"
      GF_METRICS_ENABLED: "true"
    volumes:
      - grafana-data:/var/lib/grafana
```

## 8. Create nginx.conf

Create `/opt/internal-llm/open-webui/nginx/nginx.conf`:

```nginx
worker_processes auto;

events {
  worker_connections 1024;
}

http {
  include /etc/nginx/mime.types;
  default_type application/octet-stream;

  sendfile on;
  tcp_nopush on;
  keepalive_timeout 65;
  client_max_body_size 100m;

  map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
  }

  limit_req_zone $binary_remote_addr zone=perip:10m rate=20r/s;

  upstream open_webui_upstream {
    server open-webui:8080;
  }

  upstream grafana_upstream {
    server grafana:3000;
  }

  server {
    listen 18080;
    location /stub_status {
      stub_status;
      access_log off;
      allow all;
    }
  }

  server {
    listen 80;
    server_name llm.internal.local grafana.internal.local;
    return 301 https://$host$request_uri;
  }

  server {
    listen 443 ssl;
    http2 on;
    server_name llm.internal.local;

    ssl_certificate /etc/nginx/certs/internal.local.pem;
    ssl_certificate_key /etc/nginx/certs/internal.local-key.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;

    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    limit_req zone=perip burst=40 nodelay;

    location /health {
      proxy_pass http://open_webui_upstream/health;
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-Proto https;
    }

    location / {
      proxy_pass http://open_webui_upstream;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
    }
  }

  server {
    listen 443 ssl;
    http2 on;
    server_name grafana.internal.local;

    ssl_certificate /etc/nginx/certs/internal.local.pem;
    ssl_certificate_key /etc/nginx/certs/internal.local-key.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;

    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    location / {
      proxy_pass http://grafana_upstream;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
    }
  }
}
```

## 9. Create CoreDNS config

Create `/opt/internal-llm/open-webui/dns/Corefile`:

```text
.:53 {
  log
  errors
  hosts {
    192.168.1.50 llm.internal.local grafana.internal.local prometheus.internal.local
    fallthrough
  }
  forward . 1.1.1.1 8.8.8.8
  cache 30
}
```

Replace `192.168.1.50` with your real server IP.

## 10. Create Prometheus configs

Create `/opt/internal-llm/open-webui/monitoring/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["prometheus:9090"]

  - job_name: llama_cpp
    metrics_path: /metrics
    static_configs:
      - targets: ["llama-cpp:8080"]

  - job_name: grafana
    metrics_path: /metrics
    static_configs:
      - targets: ["grafana:3000"]

  - job_name: nginx
    static_configs:
      - targets: ["nginx-exporter:9113"]

  - job_name: webui_health
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - http://open-webui:8080/health
          - https://llm.internal.local/health
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
```

Create `/opt/internal-llm/open-webui/monitoring/blackbox.yml`:

```yaml
modules:
  http_2xx:
    prober: http
    timeout: 10s
    http:
      method: GET
      preferred_ip_protocol: "ip4"
```

## 11. Start the stack

```bash
cd /opt/internal-llm/open-webui
docker compose config
docker compose pull
docker compose up -d
```

Verify containers:

```bash
docker ps
```

## 12. Verify llama.cpp

Check the model API:

```bash
curl http://127.0.0.1:8080/v1/models
```

Test a short completion:

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
    "messages": [
      {
        "role": "user",
        "content": "Say hello in one short sentence."
      }
    ]
  }'
```

## 13. Verify Open WebUI and HTTPS

Local checks:

```bash
curl http://127.0.0.1:3000/health
curl -k https://llm.internal.local/health
curl -kI https://grafana.internal.local/login
```

If `llm.internal.local` does not resolve on the Ubuntu server itself, add a temporary host entry:

```bash
echo "127.0.0.1 llm.internal.local grafana.internal.local prometheus.internal.local" | sudo tee -a /etc/hosts
```

## 14. Make DNS work for the team

You have three practical options:

### Option A: point team devices to this Ubuntu server as DNS

Set their DNS server to:

- `192.168.1.50`

### Option B: configure your router to hand out this DNS server

This is usually the easiest team-wide option.

### Option C: manually add host entries on each machine

This is fine for testing, but not ideal long-term.

## 15. Trust the internal CA on team machines

Copy this file from the Ubuntu server:

- `/opt/internal-llm/certs/rootCA.pem`

Install it into each teammate’s trusted root store.

Without that, browsers will show a certificate warning.

## 16. Create helper scripts

Create `/opt/internal-llm/scripts/start-all.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /opt/internal-llm/open-webui
docker compose up -d
echo "LLM URL: https://llm.internal.local"
echo "Grafana URL: https://grafana.internal.local"
```

Create `/opt/internal-llm/scripts/stop-all.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /opt/internal-llm/open-webui
docker compose down
```

Create `/opt/internal-llm/scripts/status.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "llama.cpp:"
docker ps --filter "name=internal-llm-llama-cpp" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true

echo
echo "llama.cpp /v1/models:"
curl -sS http://127.0.0.1:8080/v1/models || true

echo
echo "Open WebUI health:"
curl -sS http://127.0.0.1:3000/health || true

echo
echo "HTTPS:"
curl -ksS https://llm.internal.local/health || true
echo
```

Create `/opt/internal-llm/scripts/logs.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /opt/internal-llm/open-webui
docker compose logs -f llama-cpp open-webui nginx prometheus grafana dns
```

Make them executable:

```bash
chmod +x /opt/internal-llm/scripts/*.sh
```

## 17. Optional: auto-start with systemd

Create `/etc/systemd/system/internal-llm.service`:

```ini
[Unit]
Description=Internal LLM Docker Stack
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/internal-llm/open-webui
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

Enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable internal-llm.service
sudo systemctl start internal-llm.service
```

Check:

```bash
systemctl status internal-llm.service
```

## 18. Model switching on Ubuntu

If you download another GGUF, update:

- `LLAMA_MODEL_FILE`
- `LLAMA_MODEL_ALIAS`

in `/opt/internal-llm/open-webui/.env`

Then recreate the inference container:

```bash
cd /opt/internal-llm/open-webui
docker compose up -d --force-recreate llama-cpp
```

## 19. Common problems

### `llama.cpp` container keeps restarting

Check:

```bash
cd /opt/internal-llm/open-webui
docker compose logs --tail=100 llama-cpp
ls -lh /opt/internal-llm/models
grep '^LLAMA_MODEL_' /opt/internal-llm/open-webui/.env
```

Most common causes:

- wrong model filename
- GGUF missing
- not enough RAM
- unsupported model format

### Open WebUI opens but shows no models

Check:

```bash
curl http://127.0.0.1:8080/v1/models
docker compose logs --tail=100 open-webui
```

### Team browsers cannot open the URL

Check:

- DNS settings
- firewall rules
- CA trust on client machines

### HTTPS works locally but not on team machines

Usually one of:

- clients are not using the Ubuntu DNS server
- clients do not trust `rootCA.pem`
- firewall blocks port `443`

## 20. Ubuntu firewall notes

If you use `ufw`, allow the required ports:

```bash
sudo ufw allow 53/tcp
sudo ufw allow 53/udp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

## 21. Maintenance checklist

After any change:

```bash
docker ps
curl -sS http://127.0.0.1:8080/v1/models
curl -sS http://127.0.0.1:3000/health
curl -ksS https://llm.internal.local/health
```

Weekly:

- check disk usage in `/opt/internal-llm/models`
- remove unused models
- review Prometheus and Grafana
- rotate weak passwords if needed
- back up `.env`, compose files, and model list

## 22. Final summary

On Ubuntu, this stack is straightforward:

- `llama.cpp` is the local model server
- the GGUF file is the model
- Open WebUI is the browser interface
- Nginx provides HTTPS
- CoreDNS gives friendly internal DNS names
- Prometheus and Grafana provide monitoring
- teammates open `https://llm.internal.local`

If you later want, this can be extended with:

- router-integrated DNS
- stronger secrets handling
- automated backups
- external database for Open WebUI
- SSO or a stricter user-management flow
