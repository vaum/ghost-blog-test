services:
  db:
    image: mysql:8.0
    command: --default-authentication-plugin=mysql_native_password
    restart: unless-stopped
    env_file:
      - ./ghost.env
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      TZ: ${TIMEZONE}
    volumes:
      - db-data:/var/lib/mysql
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -u root -p$${MYSQL_ROOT_PASSWORD} --silent"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s

  ghost:
    image: ghost:{{GHOST_VERSION}}
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    env_file:
      - ./ghost.env
    environment:
      TZ: ${TIMEZONE}
    expose:
      - "2368"
    volumes:
      - ghost-content:/var/lib/ghost/content
    healthcheck:
      test: ["CMD-SHELL", "node -e \"require('http').get('http://127.0.0.1:2368', (r) => process.exit(r.statusCode < 500 ? 0 : 1)).on('error', () => process.exit(1))\""]
      interval: 15s
      timeout: 5s
      retries: 20
      start_period: 40s

  caddy:
    image: caddy:2.8
    restart: unless-stopped
    depends_on:
      ghost:
        condition: service_healthy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./status:/srv/status:ro
      - caddy-data:/data
      - caddy-config:/config

volumes:
  ghost-content:
  db-data:
  caddy-data:
  caddy-config:
