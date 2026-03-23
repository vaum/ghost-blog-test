# Architecture

This project deploys Ghost to a single Hetzner Cloud VPS (Ubuntu 24.04) with first-boot provisioning from cloud-init.

## Components

- **Hetzner Cloud server**: one VM, created by `hcloud` CLI.
- **Hetzner Cloud Firewall**: only inbound `80/tcp`, `443/tcp`, and ICMP; no public `22/tcp`.
- **UFW on host**: default deny inbound, allows `80/tcp`, `443/tcp`, and `tailscale0` interface traffic.
- **Tailscale + Tailscale SSH**: private admin access path (tailnet only).
- **Docker Compose stack** (`/opt/ghost/compose.yaml`):
  - `ghost`
  - `db` (MySQL 8)
  - `caddy` (public TLS + reverse proxy)

## Data Persistence

- Ghost content: Docker volume `ghost-content`
- MySQL data: Docker volume `db-data`
- Caddy cert storage: Docker volume `caddy-data`

## Provisioning Flow

1. Local `deploy.sh` validates `.env`, dependencies, and Hetzner auth.
2. Templates are rendered into `.generated/`.
3. Firewall is created/reused.
4. Server is created/reused with cloud-init user-data.
5. Cloud-init installs Docker, Tailscale, UFW, writes `/opt/ghost/*`, starts stack.
6. Cloud-init writes `/var/lib/bootstrap-complete` and publishes `/__bootstrap` status.
7. Local post-checks validate HTTPS, redirect, firewall posture, and closed public port 22.

## Access Pattern

- Public traffic: `https://DOMAIN` (and optional `https://ADMIN_DOMAIN`)
- Admin shell: `tailscale ssh <SSH_ADMIN_USER>@<SERVER_NAME>`
- Optional direct Tailscale IP SSH: `ssh <SSH_ADMIN_USER>@<tailscale-ip>`
