#!/bin/bash
# ==============================================================
# Inception 42 Project Builder
# Generates a complete Docker infrastructure for the 42 Inception
# project based on user-selected services.
#
# Usage: bash inception_builder.sh
# ==============================================================

# ---- Colors ----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
WHITE='\033[1;37m'
NC='\033[0m'

# ---- Service catalog -------------------------------------------------------
ALL_SERVICES=(nginx mariadb wordpress redis ftp adminer static)
MANDATORY_SERVICES=(nginx mariadb wordpress)
SELECTED_SERVICES=()

# ---- Project config (populated by gather_config) ---------------------------
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
WP_USER=""
WP_USER_PASSWORD=""
WP_USER_EMAIL=""
REDIS_PASSWORD=""
FTP_USER=""
FTP_PASSWORD=""

# ---- UI helpers ------------------------------------------------------------
print_header() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║      Inception 42 Project Builder        ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

section() { echo -e "\n${YELLOW}${BOLD}▶ $1${NC}"; }
ok()      { echo -e "  ${GREEN}✓${NC} $1"; }
info()    { echo -e "  ${CYAN}ℹ${NC} $1"; }
err()     { echo -e "  ${RED}✗${NC} $1"; }

ask() {
    local prompt="$1" varname="$2" default="${3:-}" secret="${4:-no}"
    local value=""
    if [ -n "$default" ]; then
        echo -ne "  ${WHITE}$prompt ${CYAN}[$default]${NC}: "
    else
        echo -ne "  ${WHITE}$prompt${NC}: "
    fi
    if [ "$secret" = "yes" ]; then
        read -rs value; echo
    else
        read -r value
    fi
    [ -z "$value" ] && value="$default"
    printf -v "$varname" '%s' "$value"
}

ask_required() {
    local prompt="$1" varname="$2" secret="${3:-no}"
    while true; do
        ask "$prompt" "$varname" "" "$secret"
        local val; eval "val=\$$varname"
        [ -n "$val" ] && break
        err "This field is required."
    done
}

# ---- Service helpers -------------------------------------------------------
has_service() {
    local s
    for s in "${SELECTED_SERVICES[@]}"; do
        [ "$s" = "$1" ] && return 0
    done
    return 1
}

service_desc() {
    case "$1" in
        nginx)     echo "Nginx — TLS/SSL reverse proxy" ;;
        mariadb)   echo "MariaDB — database server" ;;
        wordpress) echo "WordPress + PHP-FPM" ;;
        redis)     echo "Redis — object cache for WordPress" ;;
        ftp)       echo "vsftpd — FTP server for WordPress files" ;;
        adminer)   echo "Adminer — web-based database admin UI" ;;
        static)    echo "Static website" ;;
        *)         echo "$1" ;;
    esac
}

is_mandatory() {
    local s
    for s in "${MANDATORY_SERVICES[@]}"; do
        [ "$s" = "$1" ] && return 0
    done
    return 1
}

# ---- Service selection -----------------------------------------------------
select_services() {
    section "Service Selection"
    echo ""
    echo -e "  ${BOLD}Mandatory services (always included):${NC}"
    for s in "${MANDATORY_SERVICES[@]}"; do
        echo -e "    ${GREEN}✓${NC} $(service_desc "$s")"
    done
    echo ""
    echo -e "  ${BOLD}Bonus services:${NC}"
    local i=1
    for s in "${ALL_SERVICES[@]}"; do
        if ! is_mandatory "$s"; then
            echo -e "    ${CYAN}[$i]${NC} $(service_desc "$s")"
        fi
        ((i++))
    done
    echo ""
    echo -e "  Enter the numbers of the bonus services you want (space-separated)."
    echo -e "  Press Enter to skip all bonus services."
    echo -ne "  > "
    read -r selections

    SELECTED_SERVICES=("${MANDATORY_SERVICES[@]}")
    for num in $selections; do
        if [[ "$num" =~ ^[0-9]+$ ]]; then
            local idx=$((num - 1))
            local target="${ALL_SERVICES[$idx]:-}"
            [ -z "$target" ] && continue
            has_service "$target" || SELECTED_SERVICES+=("$target")
        fi
    done

    echo ""
    echo -e "  ${BOLD}Selected services:${NC}"
    for s in "${SELECTED_SERVICES[@]}"; do
        ok "$(service_desc "$s")"
    done
}

# ---- Configuration ---------------------------------------------------------
gather_config() {
    section "Project Configuration"
    ask "Output directory" OUTPUT_DIR "inception"
    ask "Domain name (e.g. login.42.fr)" DOMAIN_NAME "mylogin.42.fr"

    section "MariaDB Configuration"
    ask          "Database name"          DB_NAME        "wordpress"
    ask          "Database username"      DB_USER        "wpuser"
    ask_required "Database user password" DB_PASSWORD    yes
    ask_required "Database root password" DB_ROOT_PASSWORD yes

    if has_service "wordpress"; then
        section "WordPress Configuration"
        ask          "Site title"               WP_TITLE           "My Inception Site"
        ask          "Admin username"           WP_ADMIN_USER      "admin"
        ask_required "Admin password"           WP_ADMIN_PASSWORD  yes
        ask          "Admin email"              WP_ADMIN_EMAIL     "admin@${DOMAIN_NAME}"
        ask          "Regular user username"    WP_USER            "user1"
        ask_required "Regular user password"   WP_USER_PASSWORD   yes
        ask          "Regular user email"       WP_USER_EMAIL      "user1@${DOMAIN_NAME}"
    fi

    if has_service "redis"; then
        section "Redis Configuration"
        ask_required "Redis password" REDIS_PASSWORD yes
    fi

    if has_service "ftp"; then
        section "FTP Configuration"
        ask          "FTP username" FTP_USER     "ftpuser"
        ask_required "FTP password" FTP_PASSWORD yes
    fi
}

# ---- Directory structure ---------------------------------------------------
make_dirs() {
    local base="$OUTPUT_DIR/srcs/requirements"
    for s in "${SELECTED_SERVICES[@]}"; do
        mkdir -p "$base/$s/conf"
        mkdir -p "$base/$s/tools"
    done
    ok "Directory structure created"
}

# ---- .gitignore ------------------------------------------------------------
gen_gitignore() {
    cat > "$OUTPUT_DIR/.gitignore" << 'EOF'
# Secrets — never commit these
srcs/.env
EOF
    ok ".gitignore generated"
}

# ---- .env ------------------------------------------------------------------
gen_env() {
    local f="$OUTPUT_DIR/srcs/.env"
    cat > "$f" << EOF
# ---- Domain ----
DOMAIN_NAME=${DOMAIN_NAME}

# ---- MariaDB ----
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}

# ---- WordPress ----
WP_TITLE=${WP_TITLE}
WP_ADMIN_USER=${WP_ADMIN_USER}
WP_ADMIN_PASSWORD=${WP_ADMIN_PASSWORD}
WP_ADMIN_EMAIL=${WP_ADMIN_EMAIL}
WP_USER=${WP_USER}
WP_USER_PASSWORD=${WP_USER_PASSWORD}
WP_USER_EMAIL=${WP_USER_EMAIL}
EOF
    has_service "redis" && echo "REDIS_PASSWORD=${REDIS_PASSWORD}" >> "$f"
    if has_service "ftp"; then
        printf 'FTP_USER=%s\nFTP_PASSWORD=%s\n' "$FTP_USER" "$FTP_PASSWORD" >> "$f"
    fi
    ok ".env generated"
}

# ---- docker-compose.yml ----------------------------------------------------
gen_compose() {
    local f="$OUTPUT_DIR/srcs/docker-compose.yml"

    cat > "$f" << 'EOF'
version: '3.8'

services:
EOF

    # --- nginx ---
    if has_service "nginx"; then
        printf '  nginx:\n    build: ./requirements/nginx\n    container_name: nginx\n' >> "$f"
        local deps=()
        has_service "wordpress" && deps+=("wordpress")
        has_service "adminer"   && deps+=("adminer")
        has_service "static"    && deps+=("static")
        if [ ${#deps[@]} -gt 0 ]; then
            printf '    depends_on:\n' >> "$f"
            for d in "${deps[@]}"; do
                printf '      - %s\n' "$d" >> "$f"
            done
        fi
        cat >> "$f" << 'EOF'
    ports:
      - "443:443"
    volumes:
      - wp_data:/var/www/html
    env_file:
      - .env
    restart: unless-stopped
    networks:
      - inception

EOF
    fi

    # --- mariadb ---
    if has_service "mariadb"; then
        cat >> "$f" << 'EOF'
  mariadb:
    build: ./requirements/mariadb
    container_name: mariadb
    volumes:
      - db_data:/var/lib/mysql
    env_file:
      - .env
    restart: unless-stopped
    networks:
      - inception

EOF
    fi

    # --- wordpress ---
    if has_service "wordpress"; then
        printf '  wordpress:\n    build: ./requirements/wordpress\n    container_name: wordpress\n' >> "$f"
        local wp_deps=("mariadb")
        has_service "redis" && wp_deps+=("redis")
        printf '    depends_on:\n' >> "$f"
        for d in "${wp_deps[@]}"; do
            printf '      - %s\n' "$d" >> "$f"
        done
        cat >> "$f" << 'EOF'
    volumes:
      - wp_data:/var/www/html
    env_file:
      - .env
    restart: unless-stopped
    networks:
      - inception

EOF
    fi

    # --- redis ---
    if has_service "redis"; then
        cat >> "$f" << 'EOF'
  redis:
    build: ./requirements/redis
    container_name: redis
    env_file:
      - .env
    restart: unless-stopped
    networks:
      - inception

EOF
    fi

    # --- ftp ---
    if has_service "ftp"; then
        cat >> "$f" << 'EOF'
  ftp:
    build: ./requirements/ftp
    container_name: ftp
    ports:
      - "21:21"
      - "21100-21110:21100-21110"
    volumes:
      - wp_data:/var/www/html
    env_file:
      - .env
    restart: unless-stopped
    networks:
      - inception

EOF
    fi

    # --- adminer ---
    if has_service "adminer"; then
        cat >> "$f" << 'EOF'
  adminer:
    build: ./requirements/adminer
    container_name: adminer
    depends_on:
      - mariadb
    restart: unless-stopped
    networks:
      - inception

EOF
    fi

    # --- static ---
    if has_service "static"; then
        cat >> "$f" << 'EOF'
  static:
    build: ./requirements/static
    container_name: static
    restart: unless-stopped
    networks:
      - inception

EOF
    fi

    # --- volumes & networks ---
    # ${USER} is intentionally left unexpanded so Docker reads it at runtime
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

networks:
  inception:
    driver: bridge
EOF
    ok "docker-compose.yml generated"
}

# ---- Nginx -----------------------------------------------------------------
gen_nginx() {
    has_service "nginx" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/nginx"

    # Dockerfile
    cat > "$dir/Dockerfile" << 'EOF'
FROM debian:bullseye

RUN apt-get update && apt-get install -y \
        nginx \
        openssl \
    && rm -rf /var/lib/apt/lists/*

COPY conf/nginx.conf /etc/nginx/sites-available/default
COPY tools/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh \
    && ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default \
    && rm -f /etc/nginx/sites-enabled/000-default 2>/dev/null || true

EXPOSE 443

ENTRYPOINT ["/entrypoint.sh"]
EOF

    # Build optional proxy location blocks for bonus services
    local extra_locations=""
    if has_service "adminer"; then
        extra_locations+='
    location /adminer/ {
        proxy_pass http://adminer:8080/;
        proxy_set_header Host $host;
    }
'
    fi
    if has_service "static"; then
        extra_locations+='
    location /static/ {
        proxy_pass http://static:80/;
        proxy_set_header Host $host;
    }
'
    fi

    # nginx.conf — uses unquoted heredoc so DOMAIN_NAME and extra_locations expand
    cat > "$dir/conf/nginx.conf" << EOF
server {
    listen      443 ssl;
    listen      [::]:443 ssl;
    server_name ${DOMAIN_NAME};

    ssl_certificate     /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root  /var/www/html;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \\.php\$ {
        include         snippets/fastcgi-php.conf;
        fastcgi_pass    wordpress:9000;
    }

    location ~ /\\.ht {
        deny all;
    }
${extra_locations}}
EOF

    # entrypoint — single-quoted so DOMAIN_NAME stays as a runtime variable
    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/bin/bash
set -e

SSL_DIR=/etc/nginx/ssl

if [ ! -f "$SSL_DIR/cert.pem" ]; then
    mkdir -p "$SSL_DIR"
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "$SSL_DIR/key.pem" \
        -out    "$SSL_DIR/cert.pem" \
        -subj   "/C=FR/ST=IDF/L=Paris/O=42/CN=${DOMAIN_NAME}"
fi

exec nginx -g "daemon off;"
EOF
    chmod +x "$dir/tools/entrypoint.sh"
    ok "Nginx files generated"
}

# ---- MariaDB ---------------------------------------------------------------
gen_mariadb() {
    has_service "mariadb" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/mariadb"

    cat > "$dir/Dockerfile" << 'EOF'
FROM debian:bullseye

RUN apt-get update && apt-get install -y \
        mariadb-server \
    && rm -rf /var/lib/apt/lists/*

COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf
COPY tools/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 3306

ENTRYPOINT ["/entrypoint.sh"]
EOF

    cat > "$dir/conf/50-server.cnf" << 'EOF'
[mysqld]
user          = mysql
pid-file      = /run/mysqld/mysqld.pid
socket        = /run/mysqld/mysqld.sock
port          = 3306
basedir       = /usr
datadir       = /var/lib/mysql
bind-address  = 0.0.0.0
EOF

    # All ${...} here are runtime env-vars (single-quoted heredoc)
    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/bin/bash
set -e

DATA_DIR=/var/lib/mysql

if [ ! -d "$DATA_DIR/mysql" ]; then
    mysql_install_db --user=mysql --datadir="$DATA_DIR" > /dev/null

    # Start MariaDB temporarily for first-time initialization
    mysqld_safe --skip-networking &
    TMPPID=$!

    until mysqladmin ping --socket=/run/mysqld/mysqld.sock --silent 2>/dev/null; do
        sleep 1
    done

    mysql --socket=/run/mysqld/mysqld.sock << SQL
USE mysql;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL

    mysqladmin --socket=/run/mysqld/mysqld.sock \
        -u root -p"${DB_ROOT_PASSWORD}" shutdown
    wait "$TMPPID" 2>/dev/null || true
fi

exec mysqld --user=mysql
EOF
    chmod +x "$dir/tools/entrypoint.sh"
    ok "MariaDB files generated"
}

# ---- WordPress -------------------------------------------------------------
gen_wordpress() {
    has_service "wordpress" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/wordpress"

    cat > "$dir/Dockerfile" << 'EOF'
FROM debian:bullseye

RUN apt-get update && apt-get install -y \
        php7.4-fpm \
        php7.4-mysql \
        php7.4-curl \
        php7.4-gd \
        php7.4-mbstring \
        php7.4-xml \
        php7.4-zip \
        php7.4-redis \
        mariadb-client \
        wget \
        curl \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        -O /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

COPY conf/www.conf /etc/php/7.4/fpm/pool.d/www.conf
COPY tools/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh \
    && mkdir -p /run/php

EXPOSE 9000

ENTRYPOINT ["/entrypoint.sh"]
EOF

    cat > "$dir/conf/www.conf" << 'EOF'
[www]
user  = www-data
group = www-data

listen = 0.0.0.0:9000

listen.owner = www-data
listen.group = www-data

pm                   = dynamic
pm.max_children      = 5
pm.start_servers     = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
EOF

    # Redis setup block — assigned with single quotes so ${REDIS_PASSWORD}
    # stays as a literal and becomes a runtime variable in the generated file.
    local redis_block=""
    if has_service "redis"; then
        redis_block='
    # --- Redis object cache setup ---
    wp config set WP_REDIS_HOST     redis         --allow-root
    wp config set WP_REDIS_PORT     6379          --allow-root
    wp config set WP_REDIS_PASSWORD "${REDIS_PASSWORD}" --allow-root
    wp config set WP_CACHE          true --raw    --allow-root
    wp plugin install redis-cache --activate      --allow-root
    wp redis enable                               --allow-root'
    fi

    # Unquoted heredoc: expands ${redis_block} at generation time.
    # All other ${…} are escaped with \$ so they become runtime variables.
    cat > "$dir/tools/entrypoint.sh" << EOF
#!/bin/bash

WP_PATH=/var/www/html

mkdir -p "\$WP_PATH"
chown -R www-data:www-data "\$WP_PATH"
cd "\$WP_PATH"

# Wait for MariaDB to accept connections
until mysqladmin ping -h mariadb -u"\${DB_USER}" -p"\${DB_PASSWORD}" --silent 2>/dev/null; do
    echo "[wordpress] Waiting for MariaDB..."
    sleep 2
done

if ! wp core is-installed --path="\$WP_PATH" --allow-root 2>/dev/null; then
    wp core download --path="\$WP_PATH" --allow-root

    wp config create \\
        --path="\$WP_PATH" \\
        --dbname="\${DB_NAME}" \\
        --dbuser="\${DB_USER}" \\
        --dbpass="\${DB_PASSWORD}" \\
        --dbhost="mariadb" \\
        --allow-root

    wp core install \\
        --path="\$WP_PATH" \\
        --url="https://\${DOMAIN_NAME}" \\
        --title="\${WP_TITLE}" \\
        --admin_user="\${WP_ADMIN_USER}" \\
        --admin_password="\${WP_ADMIN_PASSWORD}" \\
        --admin_email="\${WP_ADMIN_EMAIL}" \\
        --skip-email \\
        --allow-root

    wp user create "\${WP_USER}" "\${WP_USER_EMAIL}" \\
        --role=author \\
        --user_pass="\${WP_USER_PASSWORD}" \\
        --allow-root
${redis_block}
fi

exec php-fpm7.4 -F
EOF
    chmod +x "$dir/tools/entrypoint.sh"
    ok "WordPress files generated"
}

# ---- Redis -----------------------------------------------------------------
gen_redis() {
    has_service "redis" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/redis"

    cat > "$dir/Dockerfile" << 'EOF'
FROM debian:bullseye

RUN apt-get update && apt-get install -y \
        redis-server \
    && rm -rf /var/lib/apt/lists/*

COPY conf/redis.conf /etc/redis/redis.conf
COPY tools/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 6379

ENTRYPOINT ["/entrypoint.sh"]
EOF

    cat > "$dir/conf/redis.conf" << 'EOF'
bind 0.0.0.0
port 6379
maxmemory 256mb
maxmemory-policy allkeys-lru
EOF

    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/bin/bash
set -e

# Inject password at runtime if provided
if [ -n "${REDIS_PASSWORD}" ]; then
    echo "requirepass ${REDIS_PASSWORD}" >> /etc/redis/redis.conf
fi

exec redis-server /etc/redis/redis.conf
EOF
    chmod +x "$dir/tools/entrypoint.sh"
    ok "Redis files generated"
}

# ---- FTP -------------------------------------------------------------------
gen_ftp() {
    has_service "ftp" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/ftp"

    cat > "$dir/Dockerfile" << 'EOF'
FROM debian:bullseye

RUN apt-get update && apt-get install -y \
        vsftpd \
    && rm -rf /var/lib/apt/lists/*

COPY conf/vsftpd.conf /etc/vsftpd.conf
COPY tools/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh \
    && mkdir -p /var/run/vsftpd/empty

EXPOSE 21 21100-21110

ENTRYPOINT ["/entrypoint.sh"]
EOF

    cat > "$dir/conf/vsftpd.conf" << 'EOF'
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
pasv_enable=YES
pasv_min_port=21100
pasv_max_port=21110
EOF

    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/bin/bash
set -e

if ! id "${FTP_USER}" &>/dev/null; then
    useradd -m -d /var/www/html -s /bin/bash "${FTP_USER}"
    echo "${FTP_USER}:${FTP_PASSWORD}" | chpasswd
fi

exec vsftpd /etc/vsftpd.conf
EOF
    chmod +x "$dir/tools/entrypoint.sh"
    ok "FTP files generated"
}

# ---- Adminer ---------------------------------------------------------------
gen_adminer() {
    has_service "adminer" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/adminer"

    cat > "$dir/Dockerfile" << 'EOF'
FROM debian:bullseye

RUN apt-get update && apt-get install -y \
        php7.4-fpm \
        php7.4-mysql \
        nginx \
        wget \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/www/adminer \
    && wget -q https://www.adminer.org/latest.php \
           -O /var/www/adminer/index.php

COPY conf/nginx.conf /etc/nginx/sites-available/default
COPY tools/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh \
    && mkdir -p /run/php \
    && ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
EOF

    cat > "$dir/conf/nginx.conf" << 'EOF'
server {
    listen 8080;

    root  /var/www/adminer;
    index index.php;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        include         snippets/fastcgi-php.conf;
        fastcgi_pass    unix:/run/php/php7.4-fpm.sock;
    }
}
EOF

    cat > "$dir/tools/entrypoint.sh" << 'EOF'
#!/bin/bash
set -e

php-fpm7.4 -D
exec nginx -g "daemon off;"
EOF
    chmod +x "$dir/tools/entrypoint.sh"
    ok "Adminer files generated"
}

# ---- Static site -----------------------------------------------------------
gen_static() {
    has_service "static" || return 0
    local dir="$OUTPUT_DIR/srcs/requirements/static"

    cat > "$dir/Dockerfile" << 'EOF'
FROM debian:bullseye

RUN apt-get update && apt-get install -y \
        nginx \
    && rm -rf /var/lib/apt/lists/*

COPY conf/nginx.conf /etc/nginx/sites-available/default
COPY tools/index.html /var/www/static/index.html

RUN ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOF

    cat > "$dir/conf/nginx.conf" << 'EOF'
server {
    listen 80;

    root  /var/www/static;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

    cat > "$dir/tools/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Inception — 42 Project</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background: linear-gradient(135deg, #0f0c29, #302b63, #24243e);
            color: #e0e0e0;
        }
        .card {
            text-align: center;
            padding: 3rem 4rem;
            background: rgba(255,255,255,0.05);
            border: 1px solid rgba(255,255,255,0.1);
            border-radius: 1rem;
            backdrop-filter: blur(10px);
        }
        h1 { font-size: 3.5rem; font-weight: 700; letter-spacing: .1em; }
        p  { margin-top: .75rem; font-size: 1.1rem; color: #9090c0; }
        .badge {
            display: inline-block;
            margin-top: 1.5rem;
            padding: .3rem .9rem;
            background: rgba(100,100,255,.2);
            border: 1px solid rgba(100,100,255,.4);
            border-radius: 999px;
            font-size: .85rem;
            color: #a0a0ff;
        }
    </style>
</head>
<body>
    <div class="card">
        <h1>INCEPTION</h1>
        <p>Docker Infrastructure — 42 School Project</p>
        <span class="badge">Static Site Bonus</span>
    </div>
</body>
</html>
EOF
    ok "Static site files generated"
}

# ---- Makefile --------------------------------------------------------------
gen_makefile() {
    # Use printf to write the Makefile so tab characters are preserved exactly
    printf '%s\n' \
        '# Inception Project Makefile' \
        'NAME    = inception' \
        'COMPOSE = docker compose -f srcs/docker-compose.yml --env-file srcs/.env' \
        '' \
        '.PHONY: all build up down clean fclean re logs ps' \
        '' \
        'all: up' \
        '' \
        'build:' \
        '	@mkdir -p $(HOME)/data/wordpress $(HOME)/data/mariadb' \
        '	$(COMPOSE) build' \
        '' \
        'up: build' \
        '	$(COMPOSE) up -d' \
        '' \
        'down:' \
        '	$(COMPOSE) down' \
        '' \
        'clean: down' \
        '	$(COMPOSE) down --volumes --rmi all' \
        '	@rm -rf $(HOME)/data/wordpress $(HOME)/data/mariadb' \
        '' \
        'fclean: clean' \
        '	@docker system prune -af' \
        '' \
        're: fclean all' \
        '' \
        'logs:' \
        '	$(COMPOSE) logs -f' \
        '' \
        'ps:' \
        '	$(COMPOSE) ps' \
        > "$OUTPUT_DIR/Makefile"
    ok "Makefile generated"
}

# ---- Summary ---------------------------------------------------------------
print_summary() {
    section "Project Generated Successfully"
    echo ""
    info "Output directory : ${OUTPUT_DIR}/"
    info "Domain           : https://${DOMAIN_NAME}"
    echo ""
    echo -e "  ${BOLD}Directory layout:${NC}"
    echo "  ${OUTPUT_DIR}/"
    echo "  ├── Makefile"
    echo "  ├── .gitignore"
    echo "  └── srcs/"
    echo "      ├── .env"
    echo "      ├── docker-compose.yml"
    echo "      └── requirements/"
    local last_idx=$(( ${#SELECTED_SERVICES[@]} - 1 ))
    local i=0
    for s in "${SELECTED_SERVICES[@]}"; do
        local prefix="          ├──"
        [ "$i" -eq "$last_idx" ] && prefix="          └──"
        echo "  $prefix ${s}/"
        echo "          │   ├── Dockerfile"
        echo "          │   ├── conf/"
        echo "          │   └── tools/"
        ((i++))
    done
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo -e "    1. ${CYAN}cd ${OUTPUT_DIR} && make${NC}"
    echo -e "    2. Add to /etc/hosts:  ${CYAN}127.0.0.1  ${DOMAIN_NAME}${NC}"
    echo -e "    3. Open ${CYAN}https://${DOMAIN_NAME}${NC}"
    echo ""
}

# ---- Main ------------------------------------------------------------------
main() {
    print_header
    select_services
    gather_config

    echo ""
    section "Generating Files"

    if [ -d "$OUTPUT_DIR" ]; then
        echo ""
        echo -ne "  ${YELLOW}Directory '${OUTPUT_DIR}' already exists. Overwrite? [y/N]: ${NC}"
        read -r ans
        [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
        rm -rf "$OUTPUT_DIR"
    fi

    make_dirs
    gen_gitignore
    gen_env
    gen_compose
    gen_nginx
    gen_mariadb
    gen_wordpress
    gen_redis
    gen_ftp
    gen_adminer
    gen_static
    gen_makefile

    print_summary
}

main "$@"
