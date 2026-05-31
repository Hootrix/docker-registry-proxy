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
- **Configurable**: via `.env` file

## Architecture

```
Client → Traefik (HTTPS) → Nginx (Rate Limit) → Registry:2 (Proxy) → Docker Hub
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

### 4. Start

```bash
docker-compose up -d
```

## Usage

### Login

```bash
docker login docker.yourdomain.com
```

### Pull images

```bash
# Official images — no library/ prefix needed
docker pull docker.yourdomain.com/alpine:latest
docker pull docker.yourdomain.com/nginx:alpine

# Third-party images
docker pull docker.yourdomain.com/bitnami/nginx:latest
```

### User management

```bash
./manage-users.sh add username      # Add user
./manage-users.sh delete username   # Delete user
./manage-users.sh list              # List users
./manage-users.sh change username   # Change password
```

### Proxy other registries

Edit `config/registry-config.yml`:

```yaml
proxy:
  remoteurl: https://gcr.io  # or ghcr.io, quay.io, etc
```

Then restart:

```bash
docker-compose restart registry
```
