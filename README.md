# Ghost on Hetzner with Tunnel-Only Admin Access

One-command deployment of Ghost on Hetzner Cloud with Docker Compose, Caddy automatic HTTPS, MySQL 8, and Tailscale SSH.

## What This Deploys

- Ubuntu 24.04 VPS on Hetzner Cloud
- Hetzner Cloud Firewall (`80/443` only, no public SSH)
- cloud-init bootstrap
- Docker Engine + Compose plugin
- Ghost + MySQL 8 + Caddy
- Tailscale with Tailscale SSH
- UFW defense in depth

## Prerequisites

- Local machine with:
  - `bash`
  - `curl`
  - `jq`
  - `hcloud`
  - `perl`
  - `timeout` (recommended) or `nc`
- Hetzner API token
- Domain already prepared for this deployment (DNS A/AAAA should ultimately point to server public IP)
- Pre-created Tailscale auth key

## One-Click Usage

1. Copy env template:
   ```bash
   cp .env.example .env
   ```
2. Fill `.env` required values.
3. Run deploy:
   ```bash
   ./deploy.sh
   ```

## Expected Outcome

After `./deploy.sh` completes successfully:

- Ghost is reachable at `https://DOMAIN`
- Admin is reachable at:
  - `https://ADMIN_DOMAIN/ghost/` (if `ADMIN_DOMAIN` is set), or
  - `https://DOMAIN/ghost/`
- Public TCP `22` is closed
- Shell access works through Tailscale only
- Script prints:
  - blog URL
  - admin URL
  - server name
  - public IP
  - Tailscale name/IP
  - next commands

## Tunnel-Only SSH Model

No public SSH exposure is configured.

Use:

```bash
tailscale ssh <SSH_ADMIN_USER>@<SERVER_NAME>
```

or, if needed:

```bash
ssh <SSH_ADMIN_USER>@<TAILSCALE_IP>
```

Do **not** rely on public `ssh <public-ip>`; it should fail.

## Update Ghost

SSH in via Tailscale, then:

```bash
cd /opt/ghost
sudo sed -i 's|image: ghost:.*|image: ghost:<new-tag>|' compose.yaml

sudo docker compose -p ghost --env-file ./ghost.env pull ghost
sudo docker compose -p ghost --env-file ./ghost.env up -d ghost
```

## Logs

```bash
# all services
sudo docker compose -p ghost -f /opt/ghost/compose.yaml --env-file /opt/ghost/ghost.env logs -f

# only Ghost
sudo docker compose -p ghost -f /opt/ghost/compose.yaml --env-file /opt/ghost/ghost.env logs -f ghost
```

## Restore / Re-Deploy

- Re-running `./deploy.sh` reuses same server/firewall names where possible.
- To rebuild from scratch:
  1. `./destroy.sh` (or `./destroy.sh --yes`)
  2. run `./deploy.sh` again.

If backups are enabled (`ENABLE_BACKUPS=true`), files are under `/var/backups/ghost`.

## Security Decisions

- Public `22/tcp` is blocked at **Hetzner firewall** and **UFW**.
- SSH password auth disabled, root login disabled.
- Admin access is through Tailscale tunnel only.
- Public exposure limited to `80/443` for web traffic.

See [architecture](docs/architecture.md) and [security](docs/security.md) for details.

## Tradeoffs

- Single VM simplicity over HA/multi-zone architecture.
- Deployment uses cloud-init + scripts (simple and readable) instead of Terraform/state management.
- Tailscale dependency for admin access introduces third-party control plane reliance.

## Troubleshooting

- `hcloud auth/context issues`: verify `HCLOUD_TOKEN` and run `hcloud server list`.
- Cert not issued yet: verify DNS points `DOMAIN` to server public IP and keep `80/443` reachable.
- Tailscale not online: inspect on server via Hetzner web console and run:
  - `systemctl status tailscaled`
  - `tailscale status`
- Stack issues:
  - `docker compose -p ghost -f /opt/ghost/compose.yaml --env-file /opt/ghost/ghost.env ps`
  - `docker compose -p ghost -f /opt/ghost/compose.yaml --env-file /opt/ghost/ghost.env logs`

## Destroy

```bash
./destroy.sh
# or non-interactive
./destroy.sh --yes
```

`destroy.sh` only deletes resources labeled as managed by this project and refuses to remove unrelated resources.
