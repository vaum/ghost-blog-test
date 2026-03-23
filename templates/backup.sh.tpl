#!/usr/bin/env bash

set -euo pipefail

backup_dir="/var/backups/ghost"
ts="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"

sql_file="${backup_dir}/mysql-${ts}.sql"
archive_file="${backup_dir}/ghost-content-${ts}.tar.gz"

# Database backup
if docker compose -p ghost -f /opt/ghost/compose.yaml --env-file /opt/ghost/ghost.env ps --services --filter status=running | grep -qx db; then
  docker compose -p ghost -f /opt/ghost/compose.yaml --env-file /opt/ghost/ghost.env exec -T db \
    sh -lc 'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' > "$sql_file"
  gzip -f "$sql_file"
fi

# Ghost content volume backup
if docker volume inspect ghost_ghost-content >/dev/null 2>&1; then
  docker run --rm \
    -v ghost_ghost-content:/from:ro \
    -v "$backup_dir":/to \
    alpine:3.20 sh -lc "tar -czf /to/$(basename "$archive_file") -C /from ."
fi

# Keep only last 14 backups
find "$backup_dir" -type f -name '*.gz' -mtime +14 -delete || true
find "$backup_dir" -type f -name '*.tar.gz' -mtime +14 -delete || true
