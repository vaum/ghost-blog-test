MYSQL_ROOT_PASSWORD={{MYSQL_ROOT_PASSWORD}}
MYSQL_DATABASE=ghost
MYSQL_USER=ghost
MYSQL_PASSWORD={{MYSQL_PASSWORD}}
TIMEZONE={{TIMEZONE}}

NODE_ENV=production
url=https://{{DOMAIN}}
{{GHOST_ADMIN_URL_LINE}}

database__client=mysql
database__connection__host=db
database__connection__user=ghost
database__connection__password={{MYSQL_PASSWORD}}
database__connection__database=ghost

server__host=0.0.0.0
server__port=2368
