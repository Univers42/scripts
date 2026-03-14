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
WP_IMAGE_TAG=""

REDIS_PASSWORD=""
FTP_USER=""
FTP_PASSWORD=""

OVERWRITE="false"
FAST_MODE="false"
RESOLVE_TAGS="false"

# Resolved image references
IMG_ALPINE_BASE=""
IMG_NGINX=""
IMG_WORDPRESS=""
IMG_REDIS=""
IMG_ADMINER=""
IMG_MARIADB_BASE=""
IMG_FTP_BASE=""
IMG_STATIC_BASE=""

BLUE=""
CYAN=""
GREEN=""
YELLOW=""
RED=""
BOLD=""
RESET=""

init_ui() {
    if [ -t 1 ]; then
        BLUE='\033[0;34m'
        CYAN='\033[0;36m'
        GREEN='\033[0;32m'
        YELLOW='\033[0;33m'
        RED='\033[0;31m'
        BOLD='\033[1m'
        RESET='\033[0m'
    fi
}

print_title() {
    printf '\n%b' "$BLUE"
    cat << 'EOF'
╔═════════════════════════════════════════════════════╗
║   ___ _   _  ____ _____ ____ _____ ___ ___  _   _   ║
║  |_ _| \ | |/ ___| ____|  _ \_   _|_ _/ _ \| \ | |  ║
║   | ||  \| | |   |  _| | |_) || |  | | | | |  \| |  ║
║   | || |\  | |___| |___|  __/ | |  | | |_| | |\  |  ║
║  |___|_| \_|\____|_____|_|    |_| |___\___/|_| \_|  ║
║                                                     ║
║      Inception 42 - Pedagogical Builder Watchdog    ║
╚═════════════════════════════════════════════════════╝
EOF
    printf '%b' "$RESET"
}

say() {
    printf '%s\n' "$1"
}

info() {
    printf '%bℹ%b %s\n' "$CYAN" "$RESET" "$1"
}

success() {
    printf '%b✔%b %s\n' "$GREEN" "$RESET" "$1"
}

warn() {
    printf '%b⚠%b %s\n' "$YELLOW" "$RESET" "$1"
}

error() {
    printf '%b✖%b %s\n' "$RED" "$RESET" "$1"
}

section() {
    printf '\n%b▶ %s%b\n' "$BOLD$BLUE" "$1" "$RESET"
}

parse_bool() {
    # Normalize common boolean spellings from config values.
    local raw="${1:-}"
    raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | xargs)"
    case "$raw" in
        1|true|yes|y|on) printf 'true' ;;
        *) printf 'false' ;;
    esac
}

conf_get() {
    # Returns the value for <key> from a "key: value" config file.
    # Skips comment lines, strips inline comments and surrounding whitespace.
    local key="$1"
    local file="$2"
    { grep -E "^[[:space:]]*${key}[[:space:]]*:" "$file" 2>/dev/null || true; } \
        | head -n1 \
        | sed -E "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*//" \
        | sed -E 's/[[:space:]]*#.*$//' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
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

is_valid_service_name() {
    local target="$1"
    printf '%s' "$target" | grep -Eq '^[a-z0-9][a-z0-9_-]*$'
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

create_config_template() {
    local file="$1"
    cat > "$file" << 'CONF_TEMPLATE'
# =============================================================
#  Inception 42 - Builder Configuration
# =============================================================
# The builder watches this file and generates the project once
# all required fields are filled in.
#
# Lines starting with # are comments; inline comments are allowed.
# Example:   login42: johndoe   # replace with your actual login

# --- Your 42 identity ---
login42: YOUR_LOGIN        # e.g. johndoe

# --- Services to generate (space or comma-separated) ---
# Built-in pedagogical services:
#   nginx  mariadb  wordpress  redis  ftp  adminer  static
#
# Custom service names are also allowed.
# Example: nodejs api worker
#
# Built-in services get tailored Dockerfiles/config files.
# Custom services get a generic editable scaffold.
services:                  # e.g. nginx mariadb wordpress nodejs

# --- Project settings (optional - derived from login42 if blank) ---
output_dir:                # defaults to <login42>_inception
domain:                    # defaults to <login42>.42.fr

# --- Output control ---
# overwrite: if true, the output_dir will be deleted and re-created
# without prompting when it already exists.
# Set to true only after you understand what will be lost.
# Fallback: false
overwrite: false

# --- Build speed profile ---
# fast_mode: when true, speed up generation/build workflow by:
#   - skipping Docker Hub live tag discovery (uses pinned fallback tags)
#   - generating a faster Makefile workflow (parallel BuildKit build,
#     and 'make up' without forcing a rebuild every time)
# Fallback: false
fast_mode: false

# resolve_tags: when true, query Docker Hub for the latest stable tags.
# when false, use pinned fallback tags instantly (faster, offline-friendly).
# If omitted:
#   - defaults to false when fast_mode=true
#   - defaults to true when fast_mode=false
# Examples:
#   fast_mode: true
#   resolve_tags: true   # keep fast Makefile but still resolve tags
resolve_tags: false

# === MariaDB (required when 'mariadb' is in services) ===
db_name: wordpress
db_user: wpuser
db_password: CHANGE_ME
db_root_password: CHANGE_ME

# === WordPress (required when 'wordpress' is in services) ===
wp_title: My Inception Site
wp_admin_user: admin
wp_admin_password: CHANGE_ME
# leave blank to auto-generate: <login42>@student.42madrid.com
wp_admin_email:
# Optional: force a specific WordPress tag (recommended if your network
# has trouble with newly published tags).
# Example: php8.4-fpm-alpine
wp_image_tag:

# === Redis (required when 'redis' is in services) ===
redis_password: CHANGE_ME

# === FTP (required when 'ftp' is in services) ===
ftp_user: ftpuser
ftp_password: CHANGE_ME
CONF_TEMPLATE
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
    section "Resolving Docker Images"
    if [ "$RESOLVE_TAGS" = "true" ]; then
        info "Fetching Alpine-oriented tags from Docker Hub when available."
    else
        warn "Tag resolution disabled: using pinned fallback tags."
    fi

    local alpine_tag
    if [ "$RESOLVE_TAGS" = "true" ]; then
        alpine_tag="$(pick_stable_alpine_tag "alpine" '^[0-9]+\.[0-9]+\.[0-9]+$|^[0-9]+\.[0-9]+$' '3.21')"
    else
        alpine_tag='3.21'
    fi
    IMG_ALPINE_BASE="alpine:${alpine_tag}"

    local nginx_tag
    if [ "$RESOLVE_TAGS" = "true" ]; then
        nginx_tag="$(pick_stable_alpine_tag "nginx" '^stable-alpine$|^[0-9]+(\.[0-9]+){0,2}-alpine$' 'stable-alpine')"
    else
        nginx_tag='stable-alpine'
    fi
    IMG_NGINX="nginx:${nginx_tag}"

    local wp_tag
    if [ -n "$WP_IMAGE_TAG" ]; then
        wp_tag="$WP_IMAGE_TAG"
        info "Using configured WordPress tag override: wordpress:${wp_tag}"
    elif [ "$RESOLVE_TAGS" = "true" ]; then
        # Keep WordPress on conservative, broadly available Alpine tags.
        # Avoid immediately adopting very new minor tags that may be flaky
        # on some mirrors/networks right after release.
        wp_tag="$(pick_stable_alpine_tag "wordpress" '^php8\.(2|3|4)-fpm-alpine$' 'php8.4-fpm-alpine')"
    else
        wp_tag='php8.4-fpm-alpine'
    fi
    IMG_WORDPRESS="wordpress:${wp_tag}"

    local redis_tag
    if [ "$RESOLVE_TAGS" = "true" ]; then
        redis_tag="$(pick_stable_alpine_tag "redis" '^[0-9]+(\.[0-9]+){0,2}-alpine$|^alpine$' '7-alpine')"
    else
        redis_tag='7-alpine'
    fi
    IMG_REDIS="redis:${redis_tag}"

    local adminer_tag
    if [ "$RESOLVE_TAGS" = "true" ]; then
        adminer_tag="$(pick_stable_alpine_tag "adminer" '.*alpine.*|.*standalone.*' 'standalone')"
    else
        adminer_tag='standalone'
    fi
    IMG_ADMINER="adminer:${adminer_tag}"

    IMG_MARIADB_BASE="$IMG_ALPINE_BASE"
    IMG_FTP_BASE="$IMG_ALPINE_BASE"
    IMG_STATIC_BASE="$IMG_ALPINE_BASE"

    success "nginx     -> $IMG_NGINX"
    success "wordpress -> $IMG_WORDPRESS"
    success "redis     -> $IMG_REDIS"
    success "adminer   -> $IMG_ADMINER"
    success "alpine    -> $IMG_ALPINE_BASE (for mariadb/ftp/static/custom)"
}

validate_config() {
    local file="$1"
    local errors=0

    local login42
    login42="$(conf_get login42 "$file")"
    if [ -z "$login42" ] || [ "$login42" = "YOUR_LOGIN" ]; then
        error "missing: login42"
        errors=$(( errors + 1 ))
    fi

    local raw_svc
    raw_svc="$(conf_get services "$file")"
    if [ -z "$raw_svc" ]; then
        error "missing: services"
        return 1
    fi

    local svc_list
    svc_list="$(printf '%s' "$raw_svc" | tr ',' ' ' | tr '[:upper:]' '[:lower:]')"

    local svc
    for svc in $svc_list; do
        if ! is_valid_service_name "$svc"; then
            error "invalid service '$svc' (allowed: lowercase letters, digits, '-' and '_')"
            errors=$(( errors + 1 ))
        fi
    done

    local field val
    if printf '%s\n' $svc_list | grep -qx 'mariadb'; then
        for field in db_password db_root_password; do
            val="$(conf_get "$field" "$file")"
            if [ -z "$val" ] || [ "$val" = "CHANGE_ME" ]; then
                error "missing: $field (required by mariadb)"
                errors=$(( errors + 1 ))
            fi
        done
    fi

    if printf '%s\n' $svc_list | grep -qx 'wordpress'; then
        for field in wp_admin_password; do
            val="$(conf_get "$field" "$file")"
            if [ -z "$val" ] || [ "$val" = "CHANGE_ME" ]; then
                error "missing: $field (required by wordpress)"
                errors=$(( errors + 1 ))
            fi
        done

        val="$(conf_get wp_admin_email "$file")"
        if [ "$val" = "CHANGE_ME" ]; then
            error "invalid: wp_admin_email cannot be CHANGE_ME (leave blank for auto default or set an email)"
            errors=$(( errors + 1 ))
        fi
    fi

    if printf '%s\n' $svc_list | grep -qx 'redis'; then
        val="$(conf_get redis_password "$file")"
        if [ -z "$val" ] || [ "$val" = "CHANGE_ME" ]; then
            error "missing: redis_password (required by redis)"
            errors=$(( errors + 1 ))
        fi
    fi

    if printf '%s\n' $svc_list | grep -qx 'ftp'; then
        val="$(conf_get ftp_password "$file")"
        if [ -z "$val" ] || [ "$val" = "CHANGE_ME" ]; then
            error "missing: ftp_password (required by ftp)"
            errors=$(( errors + 1 ))
        fi
    fi

    [ "$errors" -eq 0 ]
}

watch_and_validate() {
    local file="$1"

    section "Configuration Watchdog"
    info "Validating $file"
    if validate_config "$file"; then
        success "Configuration is already complete."
        return 0
    fi

    warn "Edit and save '$file' at your own pace. Press Ctrl+C to abort."

    if command -v inotifywait >/dev/null 2>&1; then
        while true; do
            inotifywait -q -e close_write,modify "$file" >/dev/null 2>&1 || true
            info "File saved. Re-validating..."
            if validate_config "$file"; then
                success "Configuration completed."
                return 0
            fi
            warn "Fix the issues listed above, then save again."
        done
    else
        # Polling fallback (inotify-tools not installed)
        local last_mtime
        last_mtime="$(stat -c %Y "$file" 2>/dev/null || echo 0)"
        while true; do
            sleep 2
            local mtime
            mtime="$(stat -c %Y "$file" 2>/dev/null || echo 0)"
            if [ "$mtime" != "$last_mtime" ]; then
                last_mtime="$mtime"
                info "File saved. Re-validating..."
                if validate_config "$file"; then
                    success "Configuration completed."
                    return 0
                fi
                warn "Fix the issues listed above, then save again."
            fi
        done
    fi
}

load_config() {
    local file="$1"

    local login42
    login42="$(conf_get login42 "$file")"

    # Services
    local raw_svc
    raw_svc="$(conf_get services "$file" | tr ',' ' ' | tr '[:upper:]' '[:lower:]')"
    SELECTED_SERVICES=()
    local svc
    for svc in $raw_svc; do
        is_valid_service_name "$svc" && add_service_if_missing "$svc" || true
    done

    # Project settings
    OUTPUT_DIR="$(conf_get output_dir "$file")"
    [ -z "$OUTPUT_DIR" ] && OUTPUT_DIR="${login42}_inception"
    DOMAIN_NAME="$(conf_get domain "$file")"
    [ -z "$DOMAIN_NAME" ] && DOMAIN_NAME="${login42}.42.fr"

    # MariaDB
    DB_NAME="$(conf_get db_name "$file")"
    [ -z "$DB_NAME" ] && DB_NAME="wordpress"
    DB_USER="$(conf_get db_user "$file")"
    [ -z "$DB_USER" ] && DB_USER="wpuser"
    DB_PASSWORD="$(conf_get db_password "$file")"
    DB_ROOT_PASSWORD="$(conf_get db_root_password "$file")"

    # WordPress
    WP_TITLE="$(conf_get wp_title "$file")"
    [ -z "$WP_TITLE" ] && WP_TITLE="Inception MVP"
    WP_ADMIN_USER="$(conf_get wp_admin_user "$file")"
    [ -z "$WP_ADMIN_USER" ] && WP_ADMIN_USER="admin"
    WP_ADMIN_PASSWORD="$(conf_get wp_admin_password "$file")"
    WP_ADMIN_EMAIL="$(conf_get wp_admin_email "$file")"
    [ -z "$WP_ADMIN_EMAIL" ] && WP_ADMIN_EMAIL="${login42}@student.42madrid.com"
    WP_IMAGE_TAG="$(conf_get wp_image_tag "$file")"

    # Redis
    REDIS_PASSWORD="$(conf_get redis_password "$file")"

    # FTP
    FTP_USER="$(conf_get ftp_user "$file")"
    [ -z "$FTP_USER" ] && FTP_USER="ftpuser"
    FTP_PASSWORD="$(conf_get ftp_password "$file")"

    # Output control
    local raw_overwrite
    raw_overwrite="$(conf_get overwrite "$file")"
    OVERWRITE="$(parse_bool "$raw_overwrite")"

    # Fast mode profile
    local raw_fast_mode
    raw_fast_mode="$(conf_get fast_mode "$file")"
    FAST_MODE="$(parse_bool "$raw_fast_mode")"

    # Tag resolution profile.
    # Explicit resolve_tags overrides fast_mode defaults.
    local raw_resolve_tags
    raw_resolve_tags="$(conf_get resolve_tags "$file")"
    if [ -n "$raw_resolve_tags" ]; then
        RESOLVE_TAGS="$(parse_bool "$raw_resolve_tags")"
    else
        if [ "$FAST_MODE" = "true" ]; then
            RESOLVE_TAGS="false"
        else
            RESOLVE_TAGS="true"
        fi
    fi
}

prepare_output_tree() {
    if [ -d "$OUTPUT_DIR" ]; then
        if [ "${OVERWRITE}" = "true" ]; then
            warn "Overwriting existing directory: $OUTPUT_DIR"
            rm -rf "$OUTPUT_DIR"
        else
            printf '\n%b?%b Directory %s already exists. Replace it? [y/N]: ' "$YELLOW" "$RESET" "$OUTPUT_DIR"
            local answer=""
            read -r answer
            answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]' | xargs)"
            if [ "$answer" = "y" ] || [ "$answer" = "yes" ]; then
                warn "Replacing existing directory: $OUTPUT_DIR"
                rm -rf "$OUTPUT_DIR"
            else
                error "Aborted by user."
                exit 1
            fi
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

    local service
    for service in "${SELECTED_SERVICES[@]}"; do
        if is_known_service "$service"; then
            continue
        fi

        cat >> "$f" << EOF
  ${service}:
    build: ./requirements/${service}
    container_name: ${service}
    restart: unless-stopped
    env_file:
      - .env
    # Add ports, volumes, command, or environment here once you know
    # how this custom service should run.

EOF
    done

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
BUILDKIT = DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1
.RECIPEPREFIX := >

.PHONY: build up down logs ps clean

# ? 🔨 Builds the Docker images (creates data directories if needed)
build:
>@mkdir -p $(HOME)/data/wordpress $(HOME)/data/mariadb
>$(BUILDKIT) $(COMPOSE) build --parallel

# ? 🔄 Builds images and then starts containers (explicit rebuild path)
up-build: build
>$(COMPOSE) up -d

EOF

    if [ "$FAST_MODE" = "true" ]; then
        cat >> "$OUTPUT_DIR/Makefile" << 'EOF'

# ? 🚀 Fast mode: starts containers without forcing a rebuild each time
up:
>$(COMPOSE) up -d

EOF
    else
        cat >> "$OUTPUT_DIR/Makefile" << 'EOF'

# ? 🚀 Builds the Docker images and starts the containers in detached mode
up: build
>$(COMPOSE) up -d

EOF
    fi

    cat >> "$OUTPUT_DIR/Makefile" << 'EOF'

# ? 🧹 Stops and removes containers, networks, volumes, and images created by 'up'
down:
>$(COMPOSE) down

# ? 📝 Follows container logs
logs:
>$(COMPOSE) logs -f

# ? 🕒 Lists running containers
ps:
>$(COMPOSE) ps

# ? 📷 Lists docker images
images:
>$(COMPOSE) images

# ? 🧹 Stops and removes containers, networks, volumes, and images created by 'up'
clean: down
>$(COMPOSE) down --volumes --rmi all

# ? 🔄 Stops and removes containers, networks, volumes, and images created by 'up'
re: clean up

# ? ❓ Displays this help message
help:
>@awk '\
		BEGIN { blue = "\033[0;34m"; green = "\033[0;32m"; reset = "\033[0m"; yellow = "\033[0;33m"; print yellow "Usage: make [target]"; print "Targets:" } \
		/^# \?/ { desc = substr($$0, 5); next } \
		/^$$/ { desc = ""; next } \
		/^[a-zA-Z0-9][a-zA-Z0-9_.-]*:/ { \
			target = $$1; \
			sub(/:.*/, "", target); \
			if (target !~ /^\./) \
				printf "  " blue "%-12s" reset green "%s" reset "\n", target, desc; \
			desc = ""; \
		}' $(firstword $(MAKEFILE_LIST))

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

generate_custom_service() {
    local service="$1"
    is_known_service "$service" && return 0

    local dir="$OUTPUT_DIR/srcs/requirements/$service"

    cat > "$dir/Dockerfile" << EOF
# Generic service scaffold for: ${service}
#
# This fallback keeps the builder open-ended when you add services that
# do not yet have a dedicated pedagogical generator.
#
# Replace this base image with the official image for your stack when possible.
# Example for Node.js:
#   FROM node:alpine
#
# Fallback: ${IMG_ALPINE_BASE}

FROM ${IMG_ALPINE_BASE}

WORKDIR /app

COPY conf/README.conf /app/README.conf
COPY tools/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
EOF

    cat > "$dir/conf/README.conf" << EOF
###############################################################
# Custom service scaffold: ${service}
#
# The builder generated this file because '${service}' is not one
# of the built-in pedagogical services.
#
# What to do next:
#   1. Replace the Dockerfile base image with the official image
#      for your stack when available.
#   2. Add the real config file(s) your service needs here.
#   3. Update docker-compose.yml ports, volumes, and environment.
#
# Safe fallback:
#   Leave this scaffold in place and the container will still build,
#   but it will only run the placeholder entrypoint.
###############################################################
EOF

    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/usr/bin/env sh
# =============================================================
# Custom service entrypoint
#
# Placeholder startup script for services that do not have a
# dedicated built-in generator yet.
#
# Learning goal:
#   Use this file as the first place to encode how your service
#   boots inside a container.
#
# Safe fallback:
#   If you do not replace this script yet, it keeps the container
#   alive so you can inspect it with docker exec and iterate.
# =============================================================
set -eu

printf '%s\n' "Custom service scaffold: replace tools/entrypoint.sh with your real startup command."
printf '%s\n' "Example for Node.js: exec node server.js"

exec sh -c 'while true; do sleep 3600; done'
EOF
    chmod +x "$dir/tools/entrypoint.sh"

    write_service_readme "$service"
}

generate_nginx() {
    contains_service "nginx" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/nginx"

    cat > "$dir/Dockerfile" << EOF
# nginx image resolved from Docker Hub:
# ${IMG_NGINX}
# Extra package installed: openssl (for self-signed cert generation in MVP)

FROM ${IMG_NGINX}

RUN apk add --no-cache openssl

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
###############################################################
# nginx TLS Configuration
#
# This server block terminates HTTPS on port 443 and routes
# requests to the appropriate backend services.
# Lines starting with "#" are nginx comments (ignored at runtime).
###############################################################

server {

    ###############################################################
    # listen 443 ssl
    #
    # Accept connections on port 443 with TLS enabled.
    # TLS is mandatory for the Inception project subject.
    #
    # Fallback: 443
    ###############################################################
    listen 443 ssl;

    ###############################################################
    # server_name
    #
    # Hostname(s) this block responds to.
    # Must match the domain set in your inception.conf and
    # the CN of the self-signed certificate.
    #
    # Fallback: localhost
    ###############################################################
    server_name ${DOMAIN_NAME};

    ###############################################################
    # ssl_certificate / ssl_certificate_key
    #
    # Path to the TLS certificate and its private key.
    # The entrypoint generates a self-signed pair at first start.
    # Replace with a CA-signed certificate in production.
    #
    # Fallback: /etc/nginx/ssl/cert.pem  /etc/nginx/ssl/key.pem
    ###############################################################
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

    ###############################################################
    # ssl_protocols
    #
    # TLS protocol versions the server accepts.
    # TLSv1.2 and TLSv1.3 are the only secure options today.
    # Older versions (TLSv1, TLSv1.1) are broken and deprecated.
    #
    # Fallback: TLSv1.2 TLSv1.3
    ###############################################################
    ssl_protocols TLSv1.2 TLSv1.3;

${root_location}

${php_location}

${extra_locations}

    ###############################################################
    # location = /health
    #
    # Lightweight healthcheck endpoint.
    # Returns HTTP 200 "ok" for Docker HEALTHCHECK or any
    # monitoring tool — no upstream service is needed.
    ###############################################################
    location = /health {
        return 200 'ok';
    }
}
EOF

    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/usr/bin/env sh
# =============================================================
# nginx entrypoint
#
# Runs once at container start, before nginx itself is launched.
# Responsibilities:
#   1. Generate a self-signed TLS certificate if none exists.
#   2. Hand control to nginx in foreground mode.
#
# Learning goal:
#   Understand why containers must not daemonise ("daemon off;")
#   and how TLS certificates are usually managed at startup.
# =============================================================
set -eu

# Create the directory that will hold the TLS certificate and key.
# -p silently succeeds if the directory already exists.
mkdir -p /etc/nginx/ssl

# Only generate the certificate if it does not already exist.
# Re-generating on every start would invalidate browser trust
# on each container restart.
if [ ! -f /etc/nginx/ssl/cert.pem ]; then
  # -x509         self-signed certificate (no CA needed for MVP)
  # -nodes        no passphrase on the private key (container cannot prompt)
  # -days 365     validity period; increase for longer-lived environments
  # -newkey rsa:2048  2048-bit RSA key (minimum recommended length)
  # -subj         non-interactive subject; CN must match DOMAIN_NAME
  #
  # ${DOMAIN_NAME} is read from the container environment at runtime
  # (injected via env_file in docker-compose.yml -> srcs/.env).
  openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/key.pem \
    -out /etc/nginx/ssl/cert.pem \
    -subj "/C=FR/ST=IDF/L=Paris/O=42/CN=${DOMAIN_NAME}"
fi

# exec replaces the shell process with nginx, making nginx PID 1.
# PID 1 receives Docker stop/kill signals directly.
# "daemon off;" prevents nginx from forking into the background,
# which would exit the container since PID 1 would disappear.
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

RUN apk add --no-cache mariadb mariadb-client

COPY conf/my.cnf /etc/my.cnf
COPY tools/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /run/mysqld /var/lib/mysql

EXPOSE 3306
ENTRYPOINT ["/entrypoint.sh"]
EOF

    cat > "$dir/conf/my.cnf" << 'EOF'
###############################################################
# MariaDB Server Configuration
#
# Loaded by mariadbd at startup.
# Controls networking, socket path, and storage location.
# Lines starting with "#" are ignored by MariaDB.
# Omitted directives fall back to compiled defaults.
###############################################################

[mysqld]

###############################################################
# bind-address
#
# IP address the server listens on for TCP connections.
#
#   0.0.0.0   accept from any host — required inside Docker
#             so other containers on the bridge can connect.
#   127.0.0.1 loopback only — blocks all remote connections.
#
# Security: restrict to a specific internal IP in production.
# Fallback: 127.0.0.1
###############################################################
bind-address=0.0.0.0

###############################################################
# port
#
# TCP port the server listens on.
# All clients and docker-compose port mappings must match.
# The conventional MariaDB/MySQL port is 3306.
#
# Fallback: 3306
###############################################################
port=3306

###############################################################
# socket
#
# Path to the Unix domain socket file.
# Local processes (same container) connect via socket instead
# of TCP — faster and unaffected by bind-address.
# Used by the entrypoint healthcheck and mariadb-admin.
#
# Fallback: /tmp/mysql.sock
###############################################################
socket=/run/mysqld/mysqld.sock
EOF

    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/usr/bin/env sh
# =============================================================
# MariaDB entrypoint
#
# Initialises the data directory on first run, creates the
# application database and user, then starts the server.
#
# Learning goal:
#   Follow the two-phase init pattern:
#     1. First-run  - bootstrap with --skip-networking, configure,
#                     then shut down cleanly.
#     2. Normal run - start with full networking enabled.
#   This is the same approach used by the official MariaDB image.
# =============================================================
set -eu

# Ensure runtime directories exist with correct ownership.
# /run/mysqld   is used for the Unix socket file.
# /var/lib/mysql holds all database files.
mkdir -p /run/mysqld /var/lib/mysql
chown -R mysql:mysql /run/mysqld /var/lib/mysql

# The presence of /var/lib/mysql/mysql indicates that
# mariadb-install-db has already run; skip init on subsequent starts.
if [ ! -d /var/lib/mysql/mysql ]; then
  # Seed the system tables (mysql, information_schema, etc.).
  # --user=mysql   run as the restricted system user, not root.
  # --datadir      explicit data directory (must match my.cnf socket path).
  # >/dev/null     suppress verbose installation output.
  mariadb-install-db --user=mysql --datadir=/var/lib/mysql >/dev/null

  # Start a temporary server with no TCP networking.
  # The & backgrounds it; $! captures its PID for later shutdown.
  # --skip-networking blocks all TCP clients during init.
  mariadbd --user=mysql --skip-networking --socket=/run/mysqld/mysqld.sock &
  pid="$!"

  # Wait until the server is ready to accept socket connections.
  # mariadb-admin ping exits 0 only when the server responds.
  until mariadb-admin --socket=/run/mysqld/mysqld.sock ping --silent >/dev/null 2>&1; do
    sleep 1
  done

  # Bootstrap the application database, user, and root password.
  # All values come from container environment variables (srcs/.env).
  # \`${DB_NAME}\`  backtick-quoting handles names with special characters.
  # '%'             allows connections from any host (required in Docker).
  mariadb --socket=/run/mysqld/mysqld.sock <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
SQL

  # Shut down the temporary server before the normal start below.
  mariadb-admin --socket=/run/mysqld/mysqld.sock -u root -p"${DB_ROOT_PASSWORD}" shutdown
  wait "$pid" 2>/dev/null || true
fi

# Start the production server.
# exec replaces this shell so mariadbd becomes PID 1 and receives
# Docker's SIGTERM directly for a clean shutdown.
# --bind-address=0.0.0.0  listen on all interfaces (required for Docker).
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
# No extra package is required: the wrapper entrypoint uses /bin/sh.

FROM ${IMG_WORDPRESS}

COPY conf/php-overrides.ini /usr/local/etc/php/conf.d/php-overrides.ini
COPY tools/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9000
ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
EOF

    cat > "$dir/conf/php-overrides.ini" << 'EOF'
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; PHP Runtime Configuration Overrides
;
; Loaded by PHP-FPM after the main php.ini.
; Only the directives listed here are overridden.
; Lines starting with ";" are comments.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; memory_limit
;
; Maximum memory a single PHP process may use.
;
;   Integer followed by M (megabytes) or G (gigabytes).
;   -1 means unlimited — unsafe in production.
;
; Note: WordPress plugins and media imports are memory-hungry.
;       256M is a safe starting point for most installs.
;
; Fallback: 128M
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
memory_limit = 256M

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; upload_max_filesize
;
; Maximum size of a single uploaded file.
;
;   Must be <= post_max_size (see below).
;   Increase to allow large theme or plugin uploads.
;
; Fallback: 2M
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
upload_max_filesize = 32M

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; post_max_size
;
; Maximum size of a complete HTTP POST request body.
;
;   Should be >= upload_max_filesize because a POST with a file
;   also includes form fields and multipart boundaries.
;
; Fallback: 8M
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
post_max_size = 32M
EOF

    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/usr/bin/env sh
# =============================================================
# WordPress entrypoint
#
# Thin wrapper around the official WordPress image entrypoint.
# The official entrypoint handles:
#   - wp-config.php generation from WORDPRESS_DB_* environment vars.
#   - php-fpm startup (passed in via CMD ["php-fpm"]).
#
# Learning goal:
#   Understand why the official image's entrypoint is reused here
#   instead of being rewritten from scratch.
#   You can read the original at:
#   https://github.com/docker-library/wordpress/blob/master/docker-entrypoint.sh
#
#   To add custom setup steps (installing WP-CLI, activating a theme,
#   importing a database dump, etc.) place them before the exec line.
# =============================================================
set -eu

# All WORDPRESS_* environment variables defined in srcs/.env are
# automatically read by docker-entrypoint.sh to configure WordPress.
# "$@" forwards the CMD arguments — typically "php-fpm".
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
###############################################################
# Redis Configuration
#
# Loaded by redis-server at startup.
# Lines starting with "#" are ignored.
# Omitted directives fall back to Redis built-in defaults.
###############################################################

###############################################################
# bind
#
# Network addresses Redis listens on.
#
#   0.0.0.0   accept from any host — needed inside Docker so
#             WordPress on another container can reach Redis.
#   127.0.0.1 loopback only — blocks all remote connections.
#
# Security: always combine 0.0.0.0 with a requirepass.
# Fallback: 127.0.0.1 -::1
###############################################################
bind 0.0.0.0

###############################################################
# port
#
# TCP port Redis listens on.
# Update docker-compose.yml ports mapping if you change this.
#
# Fallback: 6379
###############################################################
port 6379

###############################################################
# appendonly
#
# Enable Append Only File (AOF) persistence.
#
#   yes  every write is logged to appendonly.aof — data
#        survives container restarts (recommended for WP cache).
#   no   data lives in memory only; lost on restart.
#
# Fallback: no
###############################################################
appendonly yes
EOF

    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/usr/bin/env sh
# =============================================================
# Redis entrypoint
#
# Starts the Redis server with optional password authentication.
#
# Learning goal:
#   See how a runtime environment variable (REDIS_PASSWORD)
#   controls a server feature at startup without baking the
#   credential into the image or the redis.conf file.
# =============================================================
set -eu

# If REDIS_PASSWORD is set and non-empty in the container env,
# pass it to redis-server via the --requirepass flag at runtime.
# This avoids storing the password in conf/redis.conf (the image layer).
#
# ${REDIS_PASSWORD:-}  the :- operator expands to an empty string when
#                      the variable is unset, preventing a fatal error
#                      under set -u.
if [ -n "${REDIS_PASSWORD:-}" ]; then
  # --requirepass overrides any requirepass line already in redis.conf.
  exec redis-server /usr/local/etc/redis/redis.conf --requirepass "${REDIS_PASSWORD}"
fi

# No password configured - start without authentication.
# Acceptable within an isolated Docker network; never expose
# port 6379 to the public internet without a password.
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

RUN apk add --no-cache vsftpd

COPY conf/vsftpd.conf /etc/vsftpd/vsftpd.conf
COPY tools/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /var/run/vsftpd/empty

EXPOSE 21 21100-21110
ENTRYPOINT ["/entrypoint.sh"]
EOF

    cat > "$dir/conf/vsftpd.conf" << 'EOF'
###############################################################
# vsftpd Configuration
#
# Controls the behaviour of the vsftpd FTP server.
# Lines starting with "#" are ignored.
# Boolean options accept YES or NO.
###############################################################

###############################################################
# listen
#
# Run vsftpd as a standalone daemon (not via inetd/xinetd).
#
#   YES  vsftpd owns its socket — required inside Docker.
#   NO   expects a super-server to pass connections (unused).
#
# Fallback: YES
###############################################################
listen=YES

###############################################################
# anonymous_enable
#
# Allow connections without a username or password.
#
#   YES  anyone can connect — almost never desirable.
#   NO   only authenticated local users can log in.
#
# Security: keep this NO.
# Fallback: NO
###############################################################
anonymous_enable=NO

###############################################################
# local_enable
#
# Allow Linux system users to authenticate over FTP.
#
#   YES  accounts created with adduser can log in.
#   NO   no one can log in when anonymous_enable is also NO.
#
# Fallback: YES
###############################################################
local_enable=YES

###############################################################
# write_enable
#
# Permit file uploads and directory creation.
#
#   YES  clients can upload — required for WordPress file sync.
#   NO   read-only FTP access.
#
# Fallback: YES
###############################################################
write_enable=YES

###############################################################
# chroot_local_user
#
# Jail each user inside their home directory after login.
#
#   YES  the user cannot navigate above their home directory.
#   NO   full filesystem traversal (dangerous).
#
# Security: keep this YES.
# Fallback: YES
###############################################################
chroot_local_user=YES

###############################################################
# allow_writeable_chroot
#
# Permit write access when the chroot root is itself writable.
#
#   YES  required when home dir is owned by the FTP user;
#        avoids "500 OOPS: writable root inside chroot".
#   NO   vsftpd refuses to start if chroot dir is writable.
#
# Fallback: YES
###############################################################
allow_writeable_chroot=YES

###############################################################
# pasv_enable
#
# Enable PASSIVE mode data transfers.
#
#   YES  the client opens the data connection — recommended
#        behind NAT/Docker where the server IP is unreachable.
#   NO   ACTIVE mode; the server connects back to the client
#        (fails behind Docker NAT).
#
# Fallback: YES
###############################################################
pasv_enable=YES

###############################################################
# pasv_min_port / pasv_max_port
#
# Port range for PASSIVE mode data connections.
# This entire range must be published in docker-compose:
#   ports: "21100-21110:21100-21110"
#
# Choose a narrow range to limit Docker port exposure.
# Fallback: 21100 / 21110
###############################################################
pasv_min_port=21100
pasv_max_port=21110
EOF

    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/usr/bin/env sh
# =============================================================
# FTP (vsftpd) entrypoint
#
# Creates the FTP user account on first run, then starts vsftpd.
#
# Learning goal:
#   Understand how Linux user accounts are managed inside Alpine
#   containers (adduser instead of useradd) and why chpasswd is
#   used to set a password non-interactively.
# =============================================================
set -eu

# Create the FTP user only if the account does not already exist.
# This is idempotent: restarting the container will not fail even
# if the volume already contains the user's home directory.
#
# id "${FTP_USER}"  checks whether the user exists (exit 0 = exists).
if ! id "${FTP_USER}" >/dev/null 2>&1; then
  # adduser -D   create the user without setting a password
  #              (-D skips the interactive password prompt).
  # -h           set the home directory; vsftpd uses this as the
  #              chroot root (see chroot_local_user in vsftpd.conf).
  adduser -D -h /home/"${FTP_USER}" "${FTP_USER}"

  # Set the password non-interactively via stdin.
  # Format expected by chpasswd: "username:password"
  echo "${FTP_USER}:${FTP_PASSWORD}" | chpasswd
fi

# exec replaces this shell with vsftpd so it becomes PID 1
# and receives Docker's SIGTERM directly for a clean shutdown.
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
###############################################################
# nginx Static Site Configuration
#
# Serves a plain directory of HTML/CSS/JS files over HTTP.
# Lines starting with "#" are nginx comments (ignored at runtime).
###############################################################

server {

  ###############################################################
  # listen
  #
  # Port this server block listens on.
  # 80 is plain HTTP, suitable for an internal bonus service
  # that sits behind the main nginx TLS reverse proxy.
  #
  # Fallback: 80
  ###############################################################
  listen 80;

  ###############################################################
  # server_name
  #
  # Hostname(s) matched by this block.
  # _  is a catch-all — matches any Host header value.
  # Use a real hostname if you run multiple server blocks.
  #
  # Fallback: _
  ###############################################################
  server_name _;

  ###############################################################
  # root
  #
  # Filesystem directory served to clients.
  # Place your index.html and assets inside this directory.
  #
  # Fallback: /var/www/localhost/htdocs
  ###############################################################
  root /var/www/localhost/htdocs;

  ###############################################################
  # index
  #
  # Default file returned when a directory is requested.
  #
  # Fallback: index.html
  ###############################################################
  index index.html;

  location / {
    ###############################################################
    # try_files
    #
    # Resolution order for incoming requests:
    #   $uri     exact file path
    #   $uri/    directory (nginx looks for index inside)
    #   =404     return 404 if neither matched
    #
    # Fallback: try_files $uri $uri/ =404;
    ###############################################################
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

generate_custom_services() {
    local service
    for service in "${SELECTED_SERVICES[@]}"; do
        generate_custom_service "$service"
    done
}

print_summary() {
    section "Generation Complete"
    success "Project folder: $OUTPUT_DIR"
    info "Selected services: ${SELECTED_SERVICES[*]}"
    printf '\n%bNext steps%b\n' "$BOLD" "$RESET"
    say "  1. cd $OUTPUT_DIR"
    say "  2. make up"
    say "  3. inspect generated comments and customize each service"
}

main() {
    local config_file="${1:-inception.conf}"

    init_ui
    print_title

    if [ ! -f "$config_file" ]; then
        section "Configuration Setup"
        info "Creating configuration template: $config_file"
        warn "Open it in your editor, fill in the fields, and save."
        create_config_template "$config_file"
    else
        section "Configuration Setup"
        info "Using existing configuration: $config_file"
    fi

    watch_and_validate "$config_file"

    section "Loading Configuration"
    success "Configuration accepted."
    load_config "$config_file"

    info "Services  : ${SELECTED_SERVICES[*]}"
    info "Directory : $OUTPUT_DIR"
    info "Domain    : $DOMAIN_NAME"
    info "Fast mode : $FAST_MODE"
    info "Resolve tags : $RESOLVE_TAGS"

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
    generate_custom_services

    print_summary
}

main "$@"
