# Container Image Sources

Verified image source links for `deploy/docker-compose.yml`.

- `ghcr.io/ggml-org/llama.cpp:server`
  - GitHub Container Registry package: https://github.com/orgs/ggml-org/packages/container/package/llama.cpp
- `ghcr.io/open-webui/open-webui:main`
  - GitHub Container Registry package: https://github.com/open-webui/open-webui/pkgs/container/open-webui
- `nginx:stable-alpine`
  - Docker Hub official nginx image: https://hub.docker.com/_/nginx
  - Tag listing filter (`stable-alpine`): https://hub.docker.com/_/nginx/tags?name=stable-alpine
- `coredns/coredns:latest`
  - Docker Hub image: https://hub.docker.com/r/coredns/coredns
- `prom/prometheus:latest`
  - Docker Hub image: https://hub.docker.com/r/prom/prometheus
- `prom/blackbox-exporter:latest`
  - Docker Hub image: https://hub.docker.com/r/prom/blackbox-exporter
  - Prometheus docs reference for this image: https://prometheus.io/docs/guides/multi-target-exporter/
- `nginx/nginx-prometheus-exporter:1.4.2`
  - Docker Hub image: https://hub.docker.com/r/nginx/nginx-prometheus-exporter
- `grafana/grafana:latest`
  - Docker Hub image: https://hub.docker.com/r/grafana/grafana
  - Grafana Docker docs: https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/

## Note on TLS registry errors
If pull fails with `x509: certificate signed by unknown authority`, install your internal/corporate root CA into the host trust store used by Docker, then restart Docker.

### Corporate PC guidance
If you are on a company-managed PC and see this TLS error while pulling images, **yes** — you should install your company root/intermediate certificate chain so Docker can trust your company TLS inspection proxy.

## If `docker compose pull` fails: recovery checklist

1. Confirm Docker itself is healthy:
   ```bash
   docker version
   docker info
   ```
2. Test direct pull for a known image:
   ```bash
   docker pull nginx:stable-alpine
   ```
3. Check host clock (TLS fails if time is wrong):
   ```bash
   timedatectl status
   ```
4. Install your organization root CA on the host and refresh certs:
   ```bash
   sudo cp <your-root-ca>.crt /usr/local/share/ca-certificates/<your-root-ca>.crt
   sudo update-ca-certificates
   sudo systemctl restart docker
   ```
   If your company provides multiple certs (root + intermediate), install all of them.
5. Retry the failing pull with verbose output:
   ```bash
   cd /opt/internal-llm/open-webui
   docker compose pull --quiet=false
   ```
6. If your network requires an HTTPS proxy, configure Docker daemon proxy settings and restart Docker.
7. As a temporary workaround for a single blocked registry, switch that image to an official mirror (for example Docker Hub) if available.

## Installing `pki-setup.ps1` on Windows

If your IT team provided `pki-setup.ps1`, run it from an **elevated PowerShell** (Run as Administrator):

```powershell
cd $HOME\Downloads
Set-ExecutionPolicy -Scope Process Bypass
.\pki-setup.ps1
```

Then restart Docker Desktop and retry pull:

```powershell
docker pull nginx:stable-alpine
```

If script execution is blocked, check the file is unblocked first:

```powershell
Unblock-File .\pki-setup.ps1
.\pki-setup.ps1
```

## If you are using WSL

If Docker runs through **Docker Desktop on Windows** (the common WSL setup), run `pki-setup.ps1` in **Windows PowerShell (Admin)**, not inside WSL.  
Then restart Docker Desktop and retry pulls from WSL.

Example from WSL after Docker Desktop restart:

```bash
docker pull nginx:stable-alpine
docker compose pull
```

If Docker daemon is installed fully inside Linux/WSL (not Docker Desktop), install the CA in that Linux distro and restart the Linux Docker service.

### WSL without Docker Desktop

If you do **not** use Docker Desktop, your Docker daemon trust is controlled by your Linux distro in WSL.

Run inside WSL:

```bash
sudo cp <company-root-or-intermediate>.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
sudo systemctl restart docker
docker pull nginx:stable-alpine
```

If `systemctl` is unavailable in your WSL distro, restart Docker by restarting the distro session (`wsl --shutdown` from Windows, then reopen WSL) and retry the pull.

## Where to find the certificate on Windows

You can usually get the company certificate from IT, but you can also export it from Windows certificate stores:

1. Press **Win+R** → run `certlm.msc` (Local Computer certs) or `certmgr.msc` (Current User certs).
2. Go to **Trusted Root Certification Authorities** → **Certificates**.
3. Find your company root CA (issued by your company/security appliance).
4. Right-click → **All Tasks** → **Export**.
5. Export as **Base-64 encoded X.509 (.CER)**.
6. Save it, then copy that file into WSL for `update-ca-certificates`.

PowerShell export example (run as Administrator, adjust thumbprint/output path):

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Format-Table Subject,Thumbprint
Export-Certificate -Cert Cert:\LocalMachine\Root\<THUMBPRINT> -FilePath C:\Temp\company-root.cer
```

## Offline image workflow (air-gapped / restricted network)

Yes — your approach is good after copying `.tar` images to the Linux server.

Load all tar files:

```bash
for f in /tmp/docker-images/*.tar; do
  echo "Loading $f"
  sudo docker load -i "$f"
done
```

Verify loaded tags exist:

```bash
sudo docker images
```

Start compose without pulling:

```bash
cd /opt/internal-llm/open-webui
sudo docker compose up -d --pull never
```

Important checks:
- The tags loaded from tar must exactly match tags in `deploy/docker-compose.yml`.
- If using CUDA llama image, ensure compose uses the same CUDA tag you downloaded.
- Re-run this process whenever you update image tags.

## Verify platform + CUDA before choosing llama.cpp image

If `llama-cpp` container keeps restarting, first confirm architecture, NVIDIA runtime, and model path.

### 1) Verify CPU architecture

```bash
uname -m
```

- `x86_64` -> use `linux/amd64` images
- `aarch64` -> use `linux/arm64` images

### 2) Verify NVIDIA GPU + driver on host

```bash
nvidia-smi
```

If this fails, CUDA containers will not work.

### 3) Verify Docker NVIDIA runtime

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

If this fails, fix NVIDIA Container Toolkit before using `server-cuda*` images.

### 4) Pick llama.cpp image

- CPU-only: `ghcr.io/ggml-org/llama.cpp:server`
- NVIDIA CUDA: `ghcr.io/ggml-org/llama.cpp:server-cuda`
- NVIDIA CUDA 13: `ghcr.io/ggml-org/llama.cpp:server-cuda13` (only if your stack supports it)

When unsure, start with `server-cuda` instead of `server-cuda13`.

### 5) Verify model file matches compose env

Check `.env`:

```bash
grep -E '^LLAMA_MODEL_FILE=|^LLAMA_MODEL_ALIAS=' /opt/internal-llm/open-webui/.env
ls -lh /opt/internal-llm/models
```

`LLAMA_MODEL_FILE` must exactly match an existing file in `/opt/internal-llm/models`.

### 6) Test llama.cpp image manually before compose (without re-downloading)

```bash
docker run --pull=never --rm -p 8080:8080 \
  -v /opt/internal-llm/models:/models:ro \
  ghcr.io/ggml-org/llama.cpp:server-cuda \
  -m /models/<your-model>.gguf --host 0.0.0.0 --port 8080
```

If manual run works, then use the same image tag in compose.

You can verify the image already exists locally before running:

```bash
docker images | grep 'ghcr.io/ggml-org/llama.cpp'
```

### 7) Check restart reason

```bash
docker logs --tail 200 internal-llm-llama-cpp
docker inspect internal-llm-llama-cpp --format '{{.State.ExitCode}} {{.State.Error}}'
```
