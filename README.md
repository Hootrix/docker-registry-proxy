**English** | [简体中文](README.zh-CN.md)

# Docker Registry Proxy

A Docker Hub mirror proxy based on Traefik + Nginx + Docker Registry 2.0.

## Features

- **Traefik**: Auto HTTPS certificate provisioning
- **Lightweight**: No image storage, real-time proxy forwarding
- **Auth**: htpasswd user authentication
- **Anti-abuse**: Rate limiting
- **Read-only**: Pull only, push disabled
- **Auto `library/`**: Official images work without `library/` prefix
- **Multi-upstream**: attach ghcr.io / quay.io etc. with a single command via `manage-upstreams.sh`
- **Configurable**: via `.env` file

## Architecture

```
Client → Traefik (HTTPS) → Nginx (Rate Limit) → Registry:2 (Proxy, one instance per upstream) → Upstream Registries (docker.io / ghcr.io / …)
```

## Prerequisites

- Docker & Docker Compose
- **A running Traefik instance** (required)
- Domain DNS pointed to your server

## Quick Start

### 1. Clone

```bash
cd /path/to/docker-registry-proxy
```

### 2. Generate auth file

```bash
./manage-users.sh add username
```

### 3. Configure environment

```bash
cp .env.example .env
```

Edit `.env`:

```bash
REGISTRY_DOMAIN=docker-proxy.yourdomain.com
TRAEFIK_NETWORK=traefik-net
TRAEFIK_CERTRESOLVER=letsencrypt
TRAEFIK_ENTRYPOINT=websecure
```

### 4. Initialize and start

```bash
./manage-upstreams.sh add docker.io
```

This creates the default upstream declaration `config/registries/docker.io.yml`, generates the registry configs, nginx snippets and `docker-compose.override.yml`, then starts the stack.

> Note: a bare `docker compose up -d` fails before initialization — the `registry` service is provided by the generated `docker-compose.override.yml`, so the first start must go through `add docker.io`.

## Usage

### Login

```bash
docker login docker.yourdomain.com
```

### Pull images

```bash
# Default upstream (docker.io) — no prefix needed, library/ auto-completed
docker pull docker.yourdomain.com/alpine:latest
docker pull docker.yourdomain.com/nginx:alpine
docker pull docker.yourdomain.com/bitnami/nginx:latest

# Other upstreams — upstream domain as path prefix
docker pull docker.yourdomain.com/ghcr.io/fluxcd/source-controller:latest
docker pull docker.yourdomain.com/quay.io/prometheus/node-exporter:latest
```

### User management

```bash
./manage-users.sh add username      # Add user
./manage-users.sh delete username   # Delete user
./manage-users.sh list              # List users
./manage-users.sh change username   # Change password
```

### Multi-upstream management

Manage multiple upstream registries via `manage-upstreams.sh` (declarative config, one command to apply):

```bash
./manage-upstreams.sh list                        # List all upstreams
./manage-upstreams.sh add ghcr.io                 # Add upstream, live via nginx graceful reload
./manage-upstreams.sh add ghcr.io --username me   # Private registry upstream (interactive password, stays out of shell history)
./manage-upstreams.sh add myregistry.example.com --remoteurl https://api.myregistry.example.com   # When the path prefix differs from the API endpoint (default https://<host>; docker.io defaults to registry-1.docker.io)
./manage-upstreams.sh add ghcr.io --force         # Overwrite an existing upstream declaration
./manage-upstreams.sh remove ghcr.io              # Remove a non-default upstream (cache volume kept)
./manage-upstreams.sh apply                       # Regenerate all configs and apply (run after hand-editing declarations)
```

- Declaration files live in `config/registries/<host>.yml`, gitignored (they may contain credentials — do not commit)
- Pull from an added upstream using its domain as a path prefix: `docker pull docker.yourdomain.com/ghcr.io/org/image`
- After hand-editing a declaration or changing rate-limit params in `.env`, run `./manage-upstreams.sh apply` to regenerate and apply

> **Notes**
> - The default upstream is fixed to docker.io (the `library/` completion semantics only hold for it) and cannot be removed
> - A Docker Hub repo whose first path segment equals a configured upstream domain is shadowed by that upstream (e.g. a repo literally named `quay.io`)
> - Each upstream adds one resident registry process, ~30-60MB RAM

### Upgrading from the old single-upstream deployment

```bash
./manage-upstreams.sh add docker.io
```

- The `registry` service now comes from the generated `docker-compose.override.yml`; the container is recreated automatically with the new config
- The `registry-data` cache volume, service and container names stay unchanged — cache preserved, `manage-users.sh` and other references keep working
