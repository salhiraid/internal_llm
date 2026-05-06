# Ubuntu Setup After Cloning This Repo

This guide is for the case where you clone this repository onto a fresh Ubuntu machine and want to bring the whole stack up from the repo contents.

It is intentionally detailed and command-by-command.

What you will get:

- Dockerized `llama.cpp`
- Open WebUI
- Nginx with HTTPS
- CoreDNS for `internal.local`
- Prometheus and Grafana

Main URL:

- `https://llm.internal.local`

## 0. Choose your values first

Before you start, decide these values for your Ubuntu machine:

- your Linux username
- your server LAN IP
- your install path
- your internal DNS names
- your first GGUF model filename

Example values used below:

- user: `raid`
- server IP: `192.168.1.50`
- install path: `/opt/internal-llm`
- LLM URL: `llm.internal.local`
- Grafana URL: `grafana.internal.local`
- Prometheus URL: `prometheus.internal.local`
- model filename: `Llama-3.2-3B-Instruct-Q4_K_M.gguf`

You must replace these example values with your real ones where needed.

## 1. Clone the repo

Pick a working directory and clone the repo:

```bash
cd ~
git clone git@github.com:salhiraid/internal_llm.git
cd internal_llm
```

If you use HTTPS instead of SSH:

```bash
cd ~
git clone https://github.com/salhiraid/internal_llm.git
cd internal_llm
```

Check the repo tree:

```bash
find . -maxdepth 3 -type f | sort
```

You should see:

- `deploy/docker-compose.yml`
- `deploy/nginx/nginx.conf`
- `deploy/dns/Corefile`
- `deploy/monitoring/prometheus.yml`
- `deploy/monitoring/blackbox.yml`
- `.env.example`
- `scripts/`

## 2. Install system packages

Update package indexes:

```bash
sudo apt update
sudo apt upgrade -y
```

Install base packages:

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
  openssl \
  libnss3-tools
```

Check the machine:

```bash
uname -a
lsb_release -a
free -h
df -h
ip addr
```

Write down the server LAN IP you want to use.

## 3. Install Docker Engine and Docker Compose

Remove old Docker packages if they exist:

```bash
sudo apt remove -y docker docker-engine docker.io containerd runc
```

Add Docker’s repo:

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

Enable Docker:

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

Optional but recommended, allow your user to run Docker without `sudo`:

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

## 4. Create the live install path

This repo is the tracked source. The live runtime should be a separate directory.

Create it:

```bash
sudo mkdir -p /opt/internal-llm
sudo chown -R "$USER:$USER" /opt/internal-llm
```

Now create the runtime structure:

```bash
mkdir -p /opt/internal-llm/models
mkdir -p /opt/internal-llm/open-webui/nginx
mkdir -p /opt/internal-llm/open-webui/dns
mkdir -p /opt/internal-llm/open-webui/monitoring
mkdir -p /opt/internal-llm/scripts
mkdir -p /opt/internal-llm/certs
mkdir -p /opt/internal-llm/backups
mkdir -p /opt/internal-llm/logs
```

## 5. Copy the repo files into the live runtime path

Run these commands from the cloned repo root:

```bash
cp deploy/docker-compose.yml /opt/internal-llm/open-webui/docker-compose.yml
cp deploy/nginx/nginx.conf /opt/internal-llm/open-webui/nginx/nginx.conf
cp deploy/dns/Corefile /opt/internal-llm/open-webui/dns/Corefile
cp deploy/monitoring/prometheus.yml /opt/internal-llm/open-webui/monitoring/prometheus.yml
cp deploy/monitoring/blackbox.yml /opt/internal-llm/open-webui/monitoring/blackbox.yml
cp scripts/*.sh /opt/internal-llm/scripts/
chmod +x /opt/internal-llm/scripts/*.sh
```

Create the real environment file from the example:

```bash
cp .env.example /opt/internal-llm/open-webui/.env
```

## Alternative: run directly from the cloned repo (no `/opt` copy)

If you prefer to run everything from your clone path (for example `~/internal_llm`) and skip copying files into `/opt/internal-llm`, use this flow:

```bash
cd ~/internal_llm
mkdir -p open-webui/nginx open-webui/dns open-webui/monitoring
cp deploy/docker-compose.yml open-webui/docker-compose.yml
cp deploy/nginx/nginx.conf open-webui/nginx/nginx.conf
cp deploy/dns/Corefile open-webui/dns/Corefile
cp deploy/monitoring/prometheus.yml open-webui/monitoring/prometheus.yml
cp deploy/monitoring/blackbox.yml open-webui/monitoring/blackbox.yml
cp .env.example open-webui/.env
mkdir -p models certs backups logs
```

Set the base path variable so scripts target this clone:

```bash
export INTERNAL_LLM_HOME="$PWD"
```

Optional startup variables:

```bash
export INTERNAL_LLM_IMAGE_DIR="/opt/docker-images"   # where *.tar images are stored
export INTERNAL_LLM_AUTOLOAD_IMAGES="1"              # auto docker load from INTERNAL_LLM_IMAGE_DIR
export INTERNAL_LLM_ENABLE_DNS="0"                   # default: do not start dns container
export INTERNAL_LLM_STRICT_DNS="0"                   # if ENABLE_DNS=1 and port 53 is busy, fallback instead of fail
```

Then run:

```bash
./scripts/start-all.sh
```

## 6. Create a Python virtual environment for model downloads

```bash
python3 -m venv /opt/internal-llm/.venv
/opt/internal-llm/.venv/bin/pip install --upgrade pip
/opt/internal-llm/.venv/bin/pip install huggingface_hub
```

Verify:

```bash
/opt/internal-llm/.venv/bin/hf --help
```

## 7. Download the model

Download the starter GGUF model:

```bash
/opt/internal-llm/.venv/bin/hf download \
  bartowski/Llama-3.2-3B-Instruct-GGUF \
  Llama-3.2-3B-Instruct-Q4_K_M.gguf \
  --local-dir /opt/internal-llm/models
```

Check it:

```bash
ls -lh /opt/internal-llm/models
```

## 8. Install mkcert and create certificates

Install `mkcert`:

```bash
curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
chmod +x mkcert-v*-linux-amd64
sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert
```

Initialize the local CA:

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

## 9. Edit the parameters that must change

Now edit the live `.env` file:

```bash
nano /opt/internal-llm/open-webui/.env
```

Change these values:

### `WEBUI_ADMIN_EMAIL`

Set your admin email:

```dotenv
WEBUI_ADMIN_EMAIL=admin@company.local
```

### `WEBUI_ADMIN_PASSWORD`

Set a strong password:

```dotenv
WEBUI_ADMIN_PASSWORD=ChangeThisStrongPassword123!
```

### `WEBUI_SECRET_KEY`

Generate a random key:

```bash
openssl rand -hex 32
```

Paste it into:

```dotenv
WEBUI_SECRET_KEY=your_generated_hex_here
```

### `ENABLE_SIGNUP`

If team members should be able to create accounts:

```dotenv
ENABLE_SIGNUP=true
```

If you want only admin-created accounts:

```dotenv
ENABLE_SIGNUP=false
```

### `DEFAULT_USER_ROLE`

For team onboarding with admin review:

```dotenv
DEFAULT_USER_ROLE=pending
```

### Team account creation flow (recommended)

Use this combination in `.env`:

```dotenv
ENABLE_SIGNUP=true
DEFAULT_USER_ROLE=pending
```

What happens next:

1. Team member opens `https://llm.internal.local` (or `http://<server-ip>:3000` fallback) and clicks **Sign Up**.
2. Their account is created in **pending** state (cannot use models until approved).
3. Admin logs in with `WEBUI_ADMIN_EMAIL` and opens **Admin Panel → Users**.
4. Admin changes the new user role from `pending` to `user` (or `admin` if needed).

If users cannot see the **Sign Up** button, check `ENABLE_SIGNUP=true` in `.env` and restart the stack:

```bash
cd open-webui
docker compose up -d --pull never
```

### `LLAMA_MODEL_FILE`

This must exactly match the GGUF filename you downloaded:

```dotenv
LLAMA_MODEL_FILE=Llama-3.2-3B-Instruct-Q4_K_M.gguf
```

### `LLAMA_MODEL_ALIAS`

Usually keep this the same as the model filename:

```dotenv
LLAMA_MODEL_ALIAS=Llama-3.2-3B-Instruct-Q4_K_M.gguf
```

### `LLAMA_CTX_SIZE`

If you see errors like `request (...) exceeds the available context size (...)`, increase context size.

Start with:

```dotenv
LLAMA_CTX_SIZE=8192
```

If your GPU has enough VRAM, you can try larger values (e.g. `12288` or `16384`). If VRAM is limited, reduce context size.

### `LAN_IP`

Set the real Ubuntu server LAN IP:

```dotenv
LAN_IP=192.168.1.50
```

### `LLM_HOSTNAME`

Set the internal LLM DNS name:

```dotenv
LLM_HOSTNAME=llm.internal.local
```

### TLS cert file names for NGINX

NGINX now renders config from a template, so you can move this repo to any machine and just change `.env` values (no hardcoded hostnames in nginx config).

```dotenv
NGINX_CERT_FILE=internal.local.pem
NGINX_CERT_KEY_FILE=internal.local-key.pem
```

These files must exist in `certs/` (mounted as `/etc/nginx/certs`).

### `GRAFANA_HOSTNAME`

Set the Grafana DNS name:

```dotenv
GRAFANA_HOSTNAME=grafana.internal.local
```

### `PROMETHEUS_HOSTNAME`

Set the Prometheus DNS name:

```dotenv
PROMETHEUS_HOSTNAME=prometheus.internal.local
```

### `GRAFANA_ADMIN_PASSWORD`

Set a strong password:

```dotenv
GRAFANA_ADMIN_PASSWORD=another_strong_password_here
```

### `WEBUI_URL`

Set the public LLM URL:

```dotenv
WEBUI_URL=https://llm.internal.local
```

## 10. Edit the DNS config with your real server IP

Open:

```bash
nano /opt/internal-llm/open-webui/dns/Corefile
```

Find this line:

```text
192.168.0.32 llm.internal.local grafana.internal.local prometheus.internal.local
```

Replace `192.168.0.32` with your real Ubuntu server IP, for example:

```text
192.168.1.50 llm.internal.local grafana.internal.local prometheus.internal.local
```

You can also change the upstream resolvers if needed:

```text
forward . 1.1.1.1 8.8.8.8
```

## 11. Optional: adjust Nginx hostnames

If you changed the hostnames from `llm.internal.local` or `grafana.internal.local`, update:

```bash
nano /opt/internal-llm/open-webui/nginx/nginx.conf
```

Update every `server_name` line to match your chosen names.

If you kept the default names, you do not need to change anything.

## 12. Validate the stack config

```bash
cd /opt/internal-llm/open-webui
docker compose --env-file .env config
```

This should print the full resolved config without errors.

## 13. Start the stack

Pull images:

```bash
cd /opt/internal-llm/open-webui
docker compose --env-file .env pull
```

Start everything:

```bash
docker compose --env-file .env up -d
```

Check containers:

```bash
docker ps
```

You should see:

- `internal-llm-llama-cpp`
- `open-webui`
- `internal-llm-nginx`
- `internal-llm-dns`
- `internal-llm-prometheus`
- `internal-llm-blackbox`
- `internal-llm-nginx-exporter`
- `internal-llm-grafana`

## 14. Verify the local services

### Check the model API

```bash
curl http://127.0.0.1:8080/v1/models
```

You should see your model name.

### Check a real completion

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

### Check Open WebUI

```bash
curl http://127.0.0.1:3000/health
```

### Check HTTPS locally

If the hostname does not resolve locally yet, add a temporary local host entry:

```bash
echo "127.0.0.1 llm.internal.local grafana.internal.local prometheus.internal.local" | sudo tee -a /etc/hosts
```

Then test:

```bash
curl -k https://llm.internal.local/health
curl -kI https://grafana.internal.local/login
```

## 15. Make it usable for the team

Your teammates need two things:

### A. DNS resolution

They must resolve:

- `llm.internal.local`
- `grafana.internal.local`

Best options:

1. set your router to hand out the Ubuntu server as DNS
2. or set each teammate’s DNS server manually to your Ubuntu server IP

### B. Certificate trust

Each teammate should import:

- `/opt/internal-llm/certs/rootCA.pem`

into their trusted root certificate store.

Without that, browsers will warn about the certificate.

## 16. Open firewall ports if needed

If you use `ufw`:

```bash
sudo ufw allow 53/tcp
sudo ufw allow 53/udp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

## 17. Use the helper scripts

Start:

```bash
/opt/internal-llm/scripts/start-all.sh
```

Stop:

```bash
/opt/internal-llm/scripts/stop-all.sh
```

Status:

```bash
/opt/internal-llm/scripts/status.sh
```

Logs:

```bash
/opt/internal-llm/scripts/logs.sh
```

List models:

```bash
/opt/internal-llm/scripts/list-models.sh
```

Download another model:

```bash
/opt/internal-llm/scripts/download-model.sh <repo> <filename> [--activate]
```

Switch active model:

```bash
/opt/internal-llm/scripts/use-model.sh <filename>
```

## 18. What to change later when you swap models

If you download a different model, only these values need to change:

- `LLAMA_MODEL_FILE`
- `LLAMA_MODEL_ALIAS`

The helper script does this for you if you use:

```bash
/opt/internal-llm/scripts/use-model.sh YourModelFile.gguf
```

## 19. Troubleshooting

### `docker compose up -d` fails

Check:

```bash
cd /opt/internal-llm/open-webui
docker compose --env-file .env config
```

### `llama.cpp` keeps restarting

Check:

```bash
cd /opt/internal-llm/open-webui
docker compose logs --tail=100 llama-cpp
ls -lh /opt/internal-llm/models
grep '^LLAMA_MODEL_' /opt/internal-llm/open-webui/.env
```

Most likely causes:

- wrong model filename
- missing GGUF
- not enough RAM

### Open WebUI opens but has no model

Check:

```bash
curl http://127.0.0.1:8080/v1/models
cd /opt/internal-llm/open-webui
docker compose logs --tail=100 open-webui
```

### Team machines cannot open `llm.internal.local`

Check:

- their DNS settings
- firewall rules
- whether they trust `rootCA.pem`

## 20. Optional auto-start with systemd

Create:

```bash
sudo nano /etc/systemd/system/internal-llm.service
```

Paste:

```ini
[Unit]
Description=Internal LLM Docker Stack
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/internal-llm/open-webui
ExecStart=/usr/bin/docker compose --env-file .env up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable internal-llm.service
sudo systemctl start internal-llm.service
```

Check:

```bash
systemctl status internal-llm.service
```

## 21. Final quick checklist

After setup, these should all work:

```bash
docker ps
curl http://127.0.0.1:8080/v1/models
curl http://127.0.0.1:3000/health
curl -k https://llm.internal.local/health
```

Then from a teammate machine:

- browser opens `https://llm.internal.local`
- no DNS error
- no certificate warning after CA import
- user can sign in or sign up

## 22. Short summary

After cloning this repo on Ubuntu, the flow is:

1. install Docker and Python tools
2. copy repo files into `/opt/internal-llm`
3. create `.env`
4. download a GGUF model
5. generate certs
6. update the values that must match your server
7. start Docker Compose
8. verify local URLs
9. point team DNS to the Ubuntu box
10. import the internal CA on team machines
