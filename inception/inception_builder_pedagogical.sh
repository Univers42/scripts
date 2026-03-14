#!/usr/bin/env bash
# Inception 42 - Pedagogical Builder (MVP)
#
# Goal:
# - Let the user type service names (GitHub CLI-style loop) instead of yes/no prompts.
# - Generate a minimal, runnable Docker skeleton with clear teaching comments.
# - Resolve stable Alpine-oriented tags from Docker Hub when possible.
# To stop every docker container, run: docker stop $(docker ps -q)
# To remove every docker image, run: docker rmi $(docker images -q) --force

set -euo pipefail

SERVICES=(nginx mariadb wordpress redis ftp adminer static)
SELECTED_SERVICES=()

OUTPUT_DIR=""
DOMAIN_NAME=""

DB_NAME=""
DB_USER=""
DB_PASSWORD=""
DB_ROOT_PASSWORD=""

WP_TITLE=""
WP_ADMIN_USER=""
WP_ADMIN_PASSWORD=""
WP_ADMIN_EMAIL=""

REDIS_PASSWORD=""
FTP_USER=""
FTP_PASSWORD=""

# Resolved image references
IMG_ALPINE_BASE=""
IMG_NGINX=""
IMG_WORDPRESS=""
IMG_REDIS=""
IMG_ADMINER=""
IMG_MARIADB_BASE=""
IMG_FTP_BASE=""
IMG_STATIC_BASE=""

print_title() {
    cat << 'EOF'
=============================================================
 Inception 42 - Pedagogical Builder (MVP)
=============================================================
EOF
}

say() {
    printf '%s\n' "$1"
}

ask_line() {
    local prompt="$1"
    local var_name="$2"
    local default_value="${3:-}"
    local value=""

    if [ -n "$default_value" ]; then
        printf "%s [%s]: " "$prompt" "$default_value"
    else
        printf "%s: " "$prompt"
    fi
    read -r value
    [ -z "$value" ] && value="$default_value"
    printf -v "$var_name" '%s' "$value"
}

ask_secret() {
    local prompt="$1"
    local var_name="$2"
    local value=""

    while true; do
        printf "%s: " "$prompt"
        read -rs value
        printf '\n'
        [ -n "$value" ] && break
        say "Value cannot be empty."
    done
    printf -v "$var_name" '%s' "$value"
}

contains_service() {
    local target="$1"
    local s
    for s in "${SELECTED_SERVICES[@]}"; do
        [ "$s" = "$target" ] && return 0
    done
    return 1
}

is_known_service() {
    local target="$1"
    local s
    for s in "${SERVICES[@]}"; do
        [ "$s" = "$target" ] && return 0
    done
    return 1
}

add_service_if_missing() {
    local target="$1"
    contains_service "$target" || SELECTED_SERVICES+=("$target")
}

remove_service_if_present() {
    local target="$1"
    local rebuilt=()
    local s
    for s in "${SELECTED_SERVICES[@]}"; do
        [ "$s" != "$target" ] && rebuilt+=("$s")
    done
    SELECTED_SERVICES=("${rebuilt[@]}")
}

print_service_catalog() {
    say "Available services:"
    say "- nginx"
    say "- mariadb"
    say "- wordpress"
    say "- redis"
    say "- ftp"
    say "- adminer"
    say "- static"
    say ""
    say "Commands:"
    say "- done                 Finish selection"
    say "- list                 Show selected services"
    say "- help                 Show help"
    say "- remove <service>     Remove one selected service"
}

fetch_tag_list() {
    local repo="$1"
    local url="https://registry.hub.docker.com/v2/repositories/library/${repo}/tags?page_size=100"
    command -v curl >/dev/null 2>&1 || return 1

    curl -fsSL "$url" 2>/dev/null \
        | grep -oE '"name":"[^"]+"' \
        | sed -E 's/"name":"([^"]+)"/\1/' \
        || true
}

pick_stable_alpine_tag() {
    local repo="$1"
    local regex="$2"
    local fallback="$3"
    local chosen=""

    chosen="$({
        fetch_tag_list "$repo" \
            | grep -Ei "$regex" \
            | grep -Evi 'alpha|beta|rc|dev|test|debug' \
            | sort -V \
            | tail -n 1
    } 2>/dev/null || true)"

    [ -n "$chosen" ] && printf '%s' "$chosen" || printf '%s' "$fallback"
}

resolve_images() {
    say ""
    say "Resolving Docker Hub Alpine-stable tags (best effort)..."

    local alpine_tag
    alpine_tag="$(pick_stable_alpine_tag "alpine" '^[0-9]+\.[0-9]+\.[0-9]+$|^[0-9]+\.[0-9]+$' '3.21')"
    IMG_ALPINE_BASE="alpine:${alpine_tag}"

    local nginx_tag
    nginx_tag="$(pick_stable_alpine_tag "nginx" '^stable-alpine$|^[0-9]+(\.[0-9]+){0,2}-alpine$' 'stable-alpine')"
    IMG_NGINX="nginx:${nginx_tag}"

    local wp_tag
    wp_tag="$(pick_stable_alpine_tag "wordpress" '.*fpm.*alpine.*' 'php8.2-fpm-alpine')"
    IMG_WORDPRESS="wordpress:${wp_tag}"

    local redis_tag
    redis_tag="$(pick_stable_alpine_tag "redis" '^[0-9]+(\.[0-9]+){0,2}-alpine$|^alpine$' '7-alpine')"
    IMG_REDIS="redis:${redis_tag}"

    local adminer_tag
    adminer_tag="$(pick_stable_alpine_tag "adminer" '.*alpine.*|.*standalone.*' 'standalone')"
    IMG_ADMINER="adminer:${adminer_tag}"

    IMG_MARIADB_BASE="$IMG_ALPINE_BASE"
    IMG_FTP_BASE="$IMG_ALPINE_BASE"
    IMG_STATIC_BASE="$IMG_ALPINE_BASE"

    say "- nginx    -> $IMG_NGINX"
    say "- wordpress-> $IMG_WORDPRESS"
    say "- redis    -> $IMG_REDIS"
    say "- adminer  -> $IMG_ADMINER"
    say "- alpine   -> $IMG_ALPINE_BASE (for mariadb/ftp/static)"
}

choose_services() {
    say ""
    say "Type the name of each service you want, one at a time."
    say "Example: nginx"
    say ""
    print_service_catalog

    while true; do
        local raw=""
        local cmd=""
        local arg=""

        printf "\nWhich service do you want to implement? "
        read -r raw
        raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | xargs)"
        [ -z "$raw" ] && continue

        case "$raw" in
            done) break ;;
            list)
                [ "${#SELECTED_SERVICES[@]}" -eq 0 ] && say "No services selected yet." || say "Selected: ${SELECTED_SERVICES[*]}"
                continue
                ;;
            help)
                print_service_catalog
                continue
                ;;
        esac

        cmd="${raw%% *}"
        if [ "$cmd" = "remove" ]; then
            arg="${raw#remove }"
            if [ -z "$arg" ] || [ "$arg" = "remove" ]; then
                say "Usage: remove <service>"
                continue
            fi
            if ! is_known_service "$arg"; then
                say "Unknown service: $arg"
                continue
            fi
            remove_service_if_present "$arg"
            say "Removed: $arg"
            continue
        fi

        local token=""
        local added_any="no"
        for token in $raw; do
            if ! is_known_service "$token"; then
                say "Unknown service: $token"
                continue
            fi
            add_service_if_missing "$token"
            added_any="yes"
            say "Added: $token"
        done

        [ "$added_any" = "yes" ] && say "Current selection: ${SELECTED_SERVICES[*]}"
    done

    if [ "${#SELECTED_SERVICES[@]}" -eq 0 ]; then
        say ""
        say "No service selected. At least one service is required."
        choose_services
        return
    fi

    say ""
    say "Final selected services: ${SELECTED_SERVICES[*]}"
}

ask_global_config() {
    say ""
    ask_line "Output directory" OUTPUT_DIR "inception_pedagogical"
    ask_line "Domain name (example: login.42.fr)" DOMAIN_NAME "mylogin.42.fr"
}

ask_service_config() {
    if contains_service "mariadb"; then
        say ""
        say "MariaDB configuration"
        ask_line "Database name" DB_NAME "wordpress"
        ask_line "Database user" DB_USER "wpuser"
        ask_secret "Database user password" DB_PASSWORD
        ask_secret "Database root password" DB_ROOT_PASSWORD
    fi

    if contains_service "wordpress"; then
        say ""
        say "WordPress configuration"
        ask_line "Site title" WP_TITLE "Inception MVP"
        ask_line "Admin username" WP_ADMIN_USER "admin"
        ask_secret "Admin password" WP_ADMIN_PASSWORD
        ask_line "Admin email" WP_ADMIN_EMAIL "admin@${DOMAIN_NAME}"
    fi

    if contains_service "redis"; then
        say ""
        say "Redis configuration"
        ask_secret "Redis password" REDIS_PASSWORD
    fi

    if contains_service "ftp"; then
        say ""
        say "FTP configuration"
        ask_line "FTP user" FTP_USER "ftpuser"
        ask_secret "FTP password" FTP_PASSWORD
    fi
}

prepare_output_tree() {
    if [ -d "$OUTPUT_DIR" ]; then
        say ""
        printf "Directory '%s' exists. Overwrite it? [y/N]: " "$OUTPUT_DIR"
        local answer=""
        read -r answer
        answer="${answer,,}"
        if [ "$answer" = "y" ] || [ "$answer" = "yes" ]; then
            rm -rf "$OUTPUT_DIR"
        else
            say "Aborted by user."
            exit 0
        fi
    fi

    mkdir -p "$OUTPUT_DIR/srcs/requirements"

    local s
    for s in "${SELECTED_SERVICES[@]}"; do
        mkdir -p "$OUTPUT_DIR/srcs/requirements/$s/conf"
        mkdir -p "$OUTPUT_DIR/srcs/requirements/$s/tools"
    done
}

generate_root_readme() {
    cat > "$OUTPUT_DIR/README.md" << EOF
# Inception 42 - Pedagogical Build (MVP)

This project was generated by \`inception_builder_pedagogical.sh\`.

## Learning goals of this generator

- Service selection by **typed names** in an interactive loop.
- Minimal container setup so each chosen service can boot.
- In-file comments that explain where and how to customize.

## Selected services

$(for s in "${SELECTED_SERVICES[@]}"; do echo "- $s"; done)

## Resolved image references (best effort from Docker Hub)

- nginx: \`${IMG_NGINX}\`
- wordpress: \`${IMG_WORDPRESS}\`
- redis: \`${IMG_REDIS}\`
- adminer: \`${IMG_ADMINER}\`
- alpine base: \`${IMG_ALPINE_BASE}\` (used by mariadb/ftp/static)

## Structure

- \`Makefile\`: helper commands.
- \`srcs/.env\`: env vars and credentials.
- \`srcs/docker-compose.yml\`: minimal service definitions.
- \`srcs/requirements/<service>/\`: Dockerfile + config + entrypoint.

## Quick start

\`\`\`bash
cd ${OUTPUT_DIR}
make up
\`\`\`

Optional host mapping:

\`\`\`
127.0.0.1 ${DOMAIN_NAME}
\`\`\`

## Notes

This MVP intentionally keeps inter-service wiring simple.
You are expected to improve networking, healthchecks, and hardening while learning.
EOF
}

generate_gitignore() {
    cat > "$OUTPUT_DIR/.gitignore" << 'EOF'
# Secrets and runtime variables
srcs/.env
EOF
}

generate_env() {
    local f="$OUTPUT_DIR/srcs/.env"
    {
        echo "# General domain"
        echo "DOMAIN_NAME=${DOMAIN_NAME}"
        echo ""

        if contains_service "mariadb"; then
            echo "# MariaDB"
            echo "DB_NAME=${DB_NAME}"
            echo "DB_USER=${DB_USER}"
            echo "DB_PASSWORD=${DB_PASSWORD}"
            echo "DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}"
            echo ""
        fi

        if contains_service "wordpress"; then
            echo "# WordPress"
            echo "WP_TITLE=${WP_TITLE}"
            echo "WP_ADMIN_USER=${WP_ADMIN_USER}"
            echo "WP_ADMIN_PASSWORD=${WP_ADMIN_PASSWORD}"
            echo "WP_ADMIN_EMAIL=${WP_ADMIN_EMAIL}"
            echo ""
        fi

        if contains_service "redis"; then
            echo "# Redis"
            echo "REDIS_PASSWORD=${REDIS_PASSWORD}"
            echo ""
        fi

        if contains_service "ftp"; then
            echo "# FTP"
            echo "FTP_USER=${FTP_USER}"
            echo "FTP_PASSWORD=${FTP_PASSWORD}"
            echo ""
        fi
    } > "$f"
}

generate_compose() {
    local f="$OUTPUT_DIR/srcs/docker-compose.yml"

    cat > "$f" << 'EOF'
version: "3.8"

# Pedagogical compose file.
# It focuses on getting selected containers up with minimal complexity.

services:
EOF

    if contains_service "nginx"; then
        cat >> "$f" << 'EOF'
  nginx:
    build: ./requirements/nginx
    container_name: nginx
    restart: unless-stopped
    env_file:
      - .env
    ports:
      - "443:443"
EOF
        if contains_service "wordpress"; then
            cat >> "$f" << 'EOF'
    volumes:
      - wp_data:/var/www/html
EOF
        fi
        echo "" >> "$f"
    fi

    if contains_service "mariadb"; then
        cat >> "$f" << 'EOF'
  mariadb:
    build: ./requirements/mariadb
    container_name: mariadb
    restart: unless-stopped
    env_file:
      - .env
    ports:
      - "3306:3306"
    volumes:
      - db_data:/var/lib/mysql

EOF
    fi

    if contains_service "wordpress"; then
        cat >> "$f" << 'EOF'
  wordpress:
    build: ./requirements/wordpress
    container_name: wordpress
    restart: unless-stopped
    env_file:
      - .env
    ports:
      - "9000:9000"
EOF
        if contains_service "mariadb"; then
            cat >> "$f" << 'EOF'
    environment:
      WORDPRESS_DB_HOST: mariadb:3306
      WORDPRESS_DB_NAME: ${DB_NAME}
      WORDPRESS_DB_USER: ${DB_USER}
      WORDPRESS_DB_PASSWORD: ${DB_PASSWORD}
EOF
        fi
        cat >> "$f" << 'EOF'
    volumes:
      - wp_data:/var/www/html

EOF
    fi

    if contains_service "redis"; then
        cat >> "$f" << 'EOF'
  redis:
    build: ./requirements/redis
    container_name: redis
    restart: unless-stopped
    env_file:
      - .env
    ports:
      - "6379:6379"

EOF
    fi

    if contains_service "ftp"; then
        cat >> "$f" << 'EOF'
  ftp:
    build: ./requirements/ftp
    container_name: ftp
    restart: unless-stopped
    env_file:
      - .env
    ports:
      - "21:21"
      - "21100-21110:21100-21110"
EOF
        if contains_service "wordpress"; then
            cat >> "$f" << 'EOF'
    volumes:
      - wp_data:/var/www/html
EOF
        fi
        echo "" >> "$f"
    fi

    if contains_service "adminer"; then
        cat >> "$f" << 'EOF'
  adminer:
    build: ./requirements/adminer
    container_name: adminer
    restart: unless-stopped
    ports:
      - "8080:8080"

EOF
    fi

    if contains_service "static"; then
        cat >> "$f" << 'EOF'
  static:
    build: ./requirements/static
    container_name: static
    restart: unless-stopped
    ports:
      - "8081:80"

EOF
    fi

    cat >> "$f" << 'EOF'
volumes:
  wp_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/${USER}/data/wordpress

  db_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/${USER}/data/mariadb
EOF
}

generate_makefile() {
    cat > "$OUTPUT_DIR/Makefile" << 'EOF'
# Basic Makefile for generated project.
COMPOSE = docker compose -f srcs/docker-compose.yml --env-file srcs/.env

.PHONY: build up down logs ps clean

build:
	@mkdir -p $(HOME)/data/wordpress $(HOME)/data/mariadb
	$(COMPOSE) build

up: build
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

clean: down
	$(COMPOSE) down --volumes --rmi all
EOF
}

write_service_readme() {
    local service="$1"
    local dir="$OUTPUT_DIR/srcs/requirements/$service"
    cat > "$dir/README.md" << EOF
# Service: $service

Generated as a minimal educational baseline.

## Read in order

1. \`Dockerfile\` to understand image and packages.
2. \`conf/\` for service behavior.
3. \`tools/entrypoint.sh\` for startup/runtime logic.

## Suggested learning steps

- Add healthchecks.
- Restrict exposed ports.
- Improve readiness and failure handling.
- Move sensitive values to safer secret management.
EOF
}

generate_nginx() {
    contains_service "nginx" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/nginx"

    cat > "$dir/Dockerfile" << EOF
# nginx image resolved from Docker Hub:
# ${IMG_NGINX}
# Extra package installed: openssl (for self-signed cert generation in MVP)

FROM ${IMG_NGINX}

RUN apk add --no-cache openssl bash

COPY conf/default.conf /etc/nginx/conf.d/default.conf
COPY tools/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 443
ENTRYPOINT ["/entrypoint.sh"]
EOF

    local root_location=""
    local php_location=""
    local extra_locations=""

    if contains_service "wordpress"; then
        root_location='    location / {
        try_files $uri $uri/ /index.php?$args;
    }'
        php_location='    location ~ \\.php$ {
        include fastcgi_params;
        fastcgi_pass wordpress:9000;
        fastcgi_param SCRIPT_FILENAME /var/www/html$fastcgi_script_name;
    }'
    else
        root_location='    location / {
        return 200 "nginx up";
        add_header Content-Type text/plain;
    }'
    fi

    if contains_service "adminer"; then
        extra_locations+='    location /adminer/ {
        proxy_pass http://adminer:8080/;
    }
'
    fi
    if contains_service "static"; then
        extra_locations+='    location /static/ {
        proxy_pass http://static:80/;
    }
'
    fi

    cat > "$dir/conf/default.conf" << EOF
# Minimal TLS nginx config generated for learning.
server {
    listen 443 ssl;
    server_name ${DOMAIN_NAME};

    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

${root_location}

${php_location}

${extra_locations}

    location = /health {
        return 200 'ok';
    }
}
EOF

    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/usr/bin/env sh
set -eu

mkdir -p /etc/nginx/ssl
if [ ! -f /etc/nginx/ssl/cert.pem ]; then
  openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/key.pem \
    -out /etc/nginx/ssl/cert.pem \
    -subj "/C=FR/ST=IDF/L=Paris/O=42/CN=${DOMAIN_NAME}"
fi

exec nginx -g "daemon off;"
EOF
    chmod +x "$dir/tools/entrypoint.sh"

    write_service_readme "nginx"
}

generate_mariadb() {
    contains_service "mariadb" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/mariadb"

    cat > "$dir/Dockerfile" << EOF
# Base image resolved from Docker Hub:
# ${IMG_MARIADB_BASE}
# Packages installed: mariadb, mariadb-client

FROM ${IMG_MARIADB_BASE}

RUN apk add --no-cache mariadb mariadb-client bash

COPY conf/my.cnf /etc/my.cnf
COPY tools/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /run/mysqld /var/lib/mysql

EXPOSE 3306
ENTRYPOINT ["/entrypoint.sh"]
EOF

    cat > "$dir/conf/my.cnf" << 'EOF'
[mysqld]
bind-address=0.0.0.0
port=3306
socket=/run/mysqld/mysqld.sock
EOF

    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/usr/bin/env sh
set -eu

mkdir -p /run/mysqld /var/lib/mysql
chown -R mysql:mysql /run/mysqld /var/lib/mysql

if [ ! -d /var/lib/mysql/mysql ]; then
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql >/dev/null

  mariadbd --user=mysql --skip-networking --socket=/run/mysqld/mysqld.sock &
  pid="$!"

  until mariadb-admin --socket=/run/mysqld/mysqld.sock ping --silent >/dev/null 2>&1; do
    sleep 1
  done

  mariadb --socket=/run/mysqld/mysqld.sock <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
SQL

  mariadb-admin --socket=/run/mysqld/mysqld.sock -u root -p"${DB_ROOT_PASSWORD}" shutdown
  wait "$pid" 2>/dev/null || true
fi

exec mariadbd --user=mysql --bind-address=0.0.0.0 --port=3306
EOF
    chmod +x "$dir/tools/entrypoint.sh"

    write_service_readme "mariadb"
}

generate_wordpress() {
    contains_service "wordpress" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/wordpress"

    cat > "$dir/Dockerfile" << EOF
# wordpress image resolved from Docker Hub:
# ${IMG_WORDPRESS}
# Extra package installed: bash (for wrapper entrypoint)

FROM ${IMG_WORDPRESS}

RUN apk add --no-cache bash

COPY conf/php-overrides.ini /usr/local/etc/php/conf.d/php-overrides.ini
COPY tools/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9000
ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
EOF

    cat > "$dir/conf/php-overrides.ini" << 'EOF'
; Minimal pedagogical PHP overrides
memory_limit = 256M
upload_max_filesize = 32M
post_max_size = 32M
EOF

    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/usr/bin/env sh
set -eu

# Keep startup minimal: use official wordpress entrypoint behavior.
# If DB env vars are present, wordpress image handles setup flow.
exec docker-entrypoint.sh "$@"
EOF
    chmod +x "$dir/tools/entrypoint.sh"

    write_service_readme "wordpress"
}

generate_redis() {
    contains_service "redis" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/redis"

    cat > "$dir/Dockerfile" << EOF
# redis image resolved from Docker Hub:
# ${IMG_REDIS}

FROM ${IMG_REDIS}

COPY conf/redis.conf /usr/local/etc/redis/redis.conf
COPY tools/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 6379
ENTRYPOINT ["/entrypoint.sh"]
EOF

    cat > "$dir/conf/redis.conf" << 'EOF'
bind 0.0.0.0
port 6379
appendonly yes
EOF

    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/usr/bin/env sh
set -eu

if [ -n "${REDIS_PASSWORD:-}" ]; then
  exec redis-server /usr/local/etc/redis/redis.conf --requirepass "${REDIS_PASSWORD}"
fi

exec redis-server /usr/local/etc/redis/redis.conf
EOF
    chmod +x "$dir/tools/entrypoint.sh"

    write_service_readme "redis"
}

generate_ftp() {
    contains_service "ftp" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/ftp"

    cat > "$dir/Dockerfile" << EOF
# Base image resolved from Docker Hub:
# ${IMG_FTP_BASE}
# Package installed: vsftpd

FROM ${IMG_FTP_BASE}

RUN apk add --no-cache vsftpd bash

COPY conf/vsftpd.conf /etc/vsftpd/vsftpd.conf
COPY tools/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /var/run/vsftpd/empty

EXPOSE 21 21100-21110
ENTRYPOINT ["/entrypoint.sh"]
EOF

    cat > "$dir/conf/vsftpd.conf" << 'EOF'
listen=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=21100
pasv_max_port=21110
EOF

    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/usr/bin/env sh
set -eu

if ! id "${FTP_USER}" >/dev/null 2>&1; then
  adduser -D -h /home/"${FTP_USER}" "${FTP_USER}"
  echo "${FTP_USER}:${FTP_PASSWORD}" | chpasswd
fi

exec /usr/sbin/vsftpd /etc/vsftpd/vsftpd.conf
EOF
    chmod +x "$dir/tools/entrypoint.sh"

    write_service_readme "ftp"
}

generate_adminer() {
    contains_service "adminer" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/adminer"

    cat > "$dir/Dockerfile" << EOF
# adminer image resolved from Docker Hub:
# ${IMG_ADMINER}

FROM ${IMG_ADMINER}

# Keep this container straightforward: official image already serves Adminer.
EXPOSE 8080
EOF

    cat > "$dir/conf/README.conf" << 'EOF'
Adminer uses default settings from its official image in this MVP.
Add custom web server/PHP settings here if you migrate to a custom image later.
EOF

    cat > "$dir/tools/README.tools" << 'EOF'
No custom entrypoint required for this MVP.
The official adminer image already starts correctly.
EOF

    write_service_readme "adminer"
}

generate_static() {
    contains_service "static" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/static"

    cat > "$dir/Dockerfile" << EOF
# Base image resolved from Docker Hub:
# ${IMG_STATIC_BASE}
# Package installed: nginx

FROM ${IMG_STATIC_BASE}

RUN apk add --no-cache nginx

COPY conf/default.conf /etc/nginx/http.d/default.conf
COPY tools/index.html /var/www/localhost/htdocs/index.html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

    cat > "$dir/conf/default.conf" << 'EOF'
server {
  listen 80;
  server_name _;

  root /var/www/localhost/htdocs;
  index index.html;

  location / {
    try_files $uri $uri/ =404;
  }
}
EOF

    cat > "$dir/tools/index.html" << 'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Static MVP</title>
</head>
<body>
  <h1>Static service is up</h1>
  <p>This page was generated by inception_builder_pedagogical.sh.</p>
</body>
</html>
EOF

    write_service_readme "static"
}

print_summary() {
    say ""
    say "Generation complete."
    say "Project folder: $OUTPUT_DIR"
    say "Selected services: ${SELECTED_SERVICES[*]}"
    say ""
    say "Next steps:"
    say "1) cd $OUTPUT_DIR"
    say "2) make up"
    say "3) inspect generated comments and customize each service"
}

main() {
    print_title
    choose_services
    ask_global_config
    ask_service_config
    resolve_images

    prepare_output_tree

    generate_root_readme
    generate_gitignore
    generate_env
    generate_compose
    generate_makefile

    generate_nginx
    generate_mariadb
    generate_wordpress
    generate_redis
    generate_ftp
    generate_adminer
    generate_static

    print_summary
}

main "$@"
