# Security Notes

## Boundary Controls

- **Public SSH disabled by network policy**:
  - Hetzner firewall does not allow inbound `22/tcp`.
  - UFW does not allow public `22/tcp`.
- **Host hardening**:
  - `PasswordAuthentication no`
  - `PermitRootLogin no`
  - non-root sudo admin user provisioned
- **Tunnel-only admin access**:
  - Tailscale installed and joined with auth key
  - Tailscale SSH enabled (`tailscale up --ssh`)

## Why Both Hetzner Firewall and UFW

- Hetzner firewall blocks unwanted packets before they reach the VM.
- UFW enforces local policy as defense in depth.

## Recommended Tailscale ACL (minimal example)

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["group:admins"],
      "dst": ["tag:ghost-admin:*"]
    }
  ],
  "ssh": [
    {
      "action": "check",
      "src": ["group:admins"],
      "dst": ["tag:ghost-admin"],
      "users": ["autogroup:nonroot", "root"]
    }
  ]
}
```

Apply a matching tag strategy in Tailscale according to your org policy. This repository does not auto-manage ACLs.

## Residual Risks

- Any exposed web app still requires regular Ghost and container updates.
- Tailscale auth key lifecycle is operator-managed; use short-lived/reusable keys according to policy.
- Backup encryption-at-rest is not configured by default.
