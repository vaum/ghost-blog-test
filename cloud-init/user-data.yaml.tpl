#cloud-config
package_update: true
package_upgrade: true
timezone: {{TIMEZONE}}

users:
  - default
  - name: {{SSH_ADMIN_USER}}
    gecos: Ghost Administrator
    shell: /bin/bash
    groups:
      - sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true

write_files:
  - path: /opt/ghost/compose.yaml
    permissions: '0644'
    encoding: b64
    content: {{COMPOSE_B64}}

  - path: /opt/ghost/Caddyfile
    permissions: '0644'
    encoding: b64
    content: {{CADDYFILE_B64}}

  - path: /opt/ghost/ghost.env
    permissions: '0600'
    encoding: b64
    content: {{GHOST_ENV_B64}}

  - path: /usr/local/bin/ghost-write-bootstrap-status.sh
    permissions: '0755'
    encoding: b64
    content: {{STATUS_SCRIPT_B64}}

  - path: /usr/local/bin/ghost-backup.sh
    permissions: '0750'
    encoding: b64
    content: {{BACKUP_SCRIPT_B64}}

  - path: /etc/cron.d/ghost-status
    permissions: '0644'
    content: |
      */5 * * * * root /usr/local/bin/ghost-write-bootstrap-status.sh >/dev/null 2>&1

  - path: /etc/cron.d/ghost-backup
    permissions: '0644'
    encoding: b64
    content: {{BACKUP_CRON_B64}}

runcmd:
  - mkdir -p /opt/ghost/status
  - apt-get update
  - DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg jq ufw openssh-server unattended-upgrades cron
  - systemctl enable --now cron
  - systemctl enable --now ssh
  - systemctl enable --now unattended-upgrades
  - |
    if ! command -v docker >/dev/null 2>&1; then
      curl -fsSL https://get.docker.com | sh
    fi
  - systemctl enable --now docker
  - usermod -aG docker {{SSH_ADMIN_USER}}
  - curl -fsSL https://tailscale.com/install.sh | sh
  - systemctl enable --now tailscaled
  - tailscale up --authkey '{{TAILSCALE_AUTH_KEY}}' --hostname '{{SERVER_NAME}}' --ssh
  - |
    sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    grep -q '^PasswordAuthentication no$' /etc/ssh/sshd_config || echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
  - |
    sed -i -E 's/^#?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
    grep -q '^PermitRootLogin no$' /etc/ssh/sshd_config || echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
  - systemctl restart ssh
  - ufw --force reset
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - ufw allow in on tailscale0
  - ufw --force enable
  - cd /opt/ghost && docker compose -p ghost --env-file ./ghost.env up -d
  - /usr/local/bin/ghost-write-bootstrap-status.sh
  - touch /var/lib/bootstrap-complete
  - /usr/local/bin/ghost-write-bootstrap-status.sh

final_message: "Ghost bootstrap complete. Marker: /var/lib/bootstrap-complete"
