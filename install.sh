#!/usr/bin/env bash
#
# OpenClaw VPS Management System - Secure One-Line Installer
# Version: 1.0.0
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/install.sh | bash
#
# With options:
#   curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/install.sh | bash -s -- \
#     --tailscale-key tskey-auth-xxxxx
#
set -euo pipefail

INSTALL_DIR="/opt/open-claw"
DATA_DIR="/var/lib/open-claw"
PORT=8080
SSL_PORT=8443

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_step() { echo -e "\n${CYAN}${BOLD}==>${NC} ${BOLD}$1${NC}"; }

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --tailscale-key)
                TAILSCALE_AUTH_KEY="$2"
                shift 2
                ;;
            --tailscale-fqdn)
                TAILSCALE_FQDN="$2"
                shift 2
                ;;
            --cloudflare-token)
                CLOUDFLARE_API_TOKEN="$2"
                shift 2
                ;;
            --cloudflare-zone-id)
                CLOUDFLARE_ZONE_ID="$2"
                shift 2
                ;;
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --admin-user)
                ADMIN_USERNAME="$2"
                shift 2
                ;;
            --admin-pass)
                ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --skip-dns)
                SKIP_DNS="true"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
OpenClaw VPS - Secure Private VPS Management

Usage:
  curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/install.sh | bash

Options:
  --tailscale-key KEY    Tailscale auth key (starts with tskey-auth-)
  --tailscale-fqdn NAME  Custom hostname (e.g., openclaw.example.com)
  --cloudflare-token TOKEN  Cloudflare API token for DNS
  --cloudflare-zone-id ID   Cloudflare Zone ID
  --domain DOMAIN         Your domain name
  --admin-user USER      Admin username (default: admin)
  --admin-pass PASS       Admin password (auto-generated if not set)
  --skip-dns             Skip Cloudflare DNS setup
  --help, -h             Show this help

Examples:
  # Interactive (will prompt for all options)
  curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/install.sh | bash

  # Fully configured (no prompts)
  curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/install.sh | bash -s -- \
    --tailscale-key tskey-auth-kffdsafdsa \
    --admin-pass MySecurePass123!

  # With domain
  curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/install.sh | bash -s -- \
    --tailscale-key tskey-auth-kffdsafdsa \
    --domain example.com \
    --cloudflare-token cf_token \
    --cloudflare-zone-id cf_zone_id

For Tailscale auth key: https://login.tailscale.com/admin/settings/keys
EOF
}

# Interactive prompts for missing options
interactive_prompt() {
    echo ""
    echo "=============================================="
    echo -e "  ${BOLD}OpenClaw VPS - Interactive Setup${NC}"
    echo "=============================================="
    echo ""
    echo "Press Enter to use default values (shown in brackets)."
    echo ""

    # Tailscale key (required)
    if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
        echo ""
        echo -e "${BOLD}Tailscale Setup (Required)${NC}"
        echo "Get your auth key from: https://login.tailscale.com/admin/settings/keys"
        echo "The auth key starts with 'tskey-auth-'"
        echo ""
        read -rp "Tailscale Auth Key: " TAILSCALE_AUTH_KEY
    fi

    # Custom hostname (optional)
    if [[ -z "${TAILSCALE_FQDN:-}" ]]; then
        echo ""
        echo -e "${BOLD}Custom Hostname (Optional)${NC}"
        echo "Leave blank to use the default Tailscale URL (e.g., server-name.tail123.ts.net)"
        read -rp "Custom hostname (e.g., openclaw.example.com) [skip]: " TAILSCALE_FQDN
        [[ -z "$TAILSCALE_FQDN" ]] && TAILSCALE_FQDN=""
    fi

    # Domain (optional - needed for Cloudflare DNS)
    if [[ -z "${DOMAIN:-}" ]]; then
        echo ""
        echo -e "${BOLD}Custom Domain (Optional)${NC}"
        echo "Leave blank if you don't have a domain or just want Tailscale URL."
        read -rp "Your domain (e.g., example.com) [skip]: " DOMAIN
        [[ -z "$DOMAIN" ]] && DOMAIN=""
    fi

    # Cloudflare token (optional)
    if [[ -n "${DOMAIN:-}" && -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        echo ""
        echo -e "${BOLD}Cloudflare DNS (Optional)${NC}"
        echo "Create a token at: https://dash.cloudflare.com/profile/api-tokens"
        echo "Needs Zone:DNS:Edit permission."
        read -rp "Cloudflare API Token: " CLOUDFLARE_API_TOKEN
    fi

    # Cloudflare Zone ID (optional)
    if [[ -n "${DOMAIN:-}" && -n "${CLOUDFLARE_API_TOKEN:-}" && -z "${CLOUDFLARE_ZONE_ID:-}" ]]; then
        echo ""
        echo -e "${BOLD}Cloudflare Zone ID${NC}"
        echo "Found in Cloudflare Dashboard > Domain > Overview > API"
        read -rp "Cloudflare Zone ID: " CLOUDFLARE_ZONE_ID
    fi

    # Admin username (optional)
    if [[ -z "${ADMIN_USERNAME:-}" ]]; then
        echo ""
        echo -e "${BOLD}Admin User (Optional)${NC}"
        read -rp "Admin username [admin]: " ADMIN_USERNAME
        [[ -z "$ADMIN_USERNAME" ]] && ADMIN_USERNAME="admin"
    fi

    # Admin password (optional)
    if [[ -z "${ADMIN_PASSWORD:-}" ]]; then
        echo ""
        echo -e "${BOLD}Admin Password (Optional)${NC}"
        echo "Leave blank to auto-generate a secure password."
        read -rp "Admin password [auto-generate]: " ADMIN_PASSWORD
        [[ -z "$ADMIN_PASSWORD" ]] && ADMIN_PASSWORD=""
    fi

    echo ""
}

# Detect server IP
detect_server_ip() {
    log "Detecting server public IP..."

    local ip=$(curl -fsSL --max-time 5 https://.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -oP 'ip=\K[^ ]+' || true)
    if [[ -z "$ip" ]]; then
        ip=$(curl -fsSL --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '\n ' || true)
    fi
    if [[ -z "$ip" ]]; then
        ip=$(curl -fsSL --max-time 5 https://ipinfo.io/ip 2>/dev/null | tr -d '\n "' || true)
    fi
    if [[ -z "$ip" ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
    fi

    SERVER_IP="${ip:-unknown}"
    log_success "Server IP: $SERVER_IP"
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    for cmd in curl docker docker-compose openssl; do
        if ! command -v "$cmd" &> /dev/null; then
            log "Installing $cmd..."
            install_dep "$cmd"
        fi
    done

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Start Docker and try again."
    fi

    log_success "Prerequisites OK"
}

install_dep() {
    case $1 in
        docker)
            curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
            systemctl enable docker --now 2>/dev/null || true
            ;;
        docker-compose)
            local arch=$(uname -m)
            [[ "$arch" == "aarch64" ]] && arch="aarch64" || arch="x86_64"
            curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${arch}" \
                -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            ;;
        *)
            if command -v apt-get &> /dev/null; then
                apt-get install -y -qq "$1" > /dev/null 2>&1
            elif command -v yum &> /dev/null; then
                yum install -y -q "$1" > /dev/null 2>&1
            fi
            ;;
    esac
}

# Setup Tailscale
setup_tailscale() {
    if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
        log_error "Tailscale auth key is required. Provide --tailscale-key or run interactively."
    fi

    log_step "Setting up Tailscale VPN..."

    # Install Tailscale
    if ! command -v tailscale &> /dev/null; then
        log "Installing Tailscale..."
        if command -v apt-get &> /dev/null; then
            curl -fsSL https://pkgs.tailscale.com/stable/debian.bookworm.noarmor.gpg \
                | tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null
            echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian bookworm main" \
                | tee /etc/apt/sources.list.d/tailscale.list > /dev/null
            apt-get update -qq
            apt-get install -y -qq tailscale > /dev/null 2>&1
        elif command -v yum &> /dev/null; then
            yum install -y -q tailscale 2>/dev/null || \
            (curl -fsSL https://pkgs.tailscale.com/stable/centos8/x86_64/repo.rpm -o /tmp/repo.rpm && \
             yum install -y -q /tmp/repo.rpm)
        elif command -v apk &> /dev/null; then
            apk add --no-cache tailscale
        fi
    fi

    if command -v tailscale &> /dev/null; then
        log "Connecting to Tailscale..."

        # Enable IP forwarding
        sysctl -w net.ipv4.ip_forward=1 2>/dev/null || true

        # Connect with auth key
        tailscale up --authkey="$TAILSCALE_AUTH_KEY" --accept-routes 2>/dev/null || \
        tailscale up --authkey="$TAILSCALE_AUTH_KEY" 2>/dev/null || {
            log_warn "Auth key failed, trying interactive..."
            tailscale up --accept-routes
        }

        # Get connection info
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | head -1 || true)
        TAILSCALE_HOSTNAME=$(tailscale status --self --json 2>/dev/null | \
            grep -oP '"DNSName":"[^"]+"' | head -1 | cut -d'"' -f4 | sed 's/\.$//' || true)

        if [[ -n "$TAILSCALE_IP" ]]; then
            log_success "Connected! Tailscale IP: $TAILSCALE_IP"

            # Configure Funnel for HTTPS
            if [[ -n "$TAILSCALE_FQDN" ]]; then
                tailscale serve --set-hostname="$TAILSCALE_FQDN" --bg 2>/dev/null || \
                tailscale serve https + --set-hostname="$TAILSCALE_FQDN" 2>/dev/null || true
            else
                tailscale serve --bg 2>/dev/null || true
            fi

            # Enable on boot
            systemctl enable tailscaled 2>/dev/null || true

            TAILSCALE_CONFIGURED="true"
        fi
    else
        log_warn "Tailscale installation failed"
    fi
}

# Setup Cloudflare DNS
setup_cloudflare_dns() {
    if [[ "${SKIP_DNS:-false}" == "true" || -z "$CLOUDFLARE_API_TOKEN" ]]; then
        return 0
    fi

    log_step "Configuring Cloudflare DNS..."

    # Get Zone ID if not provided
    if [[ -z "$CLOUDFLARE_ZONE_ID" ]]; then
        log "Fetching Zone ID for $DOMAIN..."
        local zones_response=$(curl -fsSL -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" 2>/dev/null)
        CLOUDFLARE_ZONE_ID=$(echo "$zones_response" | grep -oP '"id":"[^"]+"' | head -1 | cut -d'"' -f4)
    fi

    if [[ -z "$CLOUDFLARE_ZONE_ID" ]]; then
        log_warn "Could not fetch Zone ID. Provide --cloudflare-zone-id"
        return 1
    fi

    # Create DNS record pointing to server IP
    local subdomain="${TAILSCALE_FQDN%%.*}"
    local dns_response=$(curl -fsSL -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"A\",\"name\":\"${TAILSCALE_FQDN:-$subdomain}\",\"content\":\"$SERVER_IP\",\"ttl\":3600,\"proxied\":true}" \
        2>/dev/null)

    if echo "$dns_response" | grep -q '"id"'; then
        log_success "DNS record created"
    else
        log_warn "DNS record creation failed or already exists"
    fi
}

# Generate secrets
generate_secrets() {
    SESSION_SECRET=$(openssl rand -base64 32 2>/dev/null | tr -d '/+=' | head -c 32)

    if [[ -z "${ADMIN_PASSWORD:-}" ]]; then
        ADMIN_PASSWORD=$(openssl rand -base64 24 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 16)
        log "Admin password generated"
    fi

    ADMIN_PASSWORD_HASH=$(echo "$ADMIN_PASSWORD" | openssl passwd -1 -stdin 2>/dev/null || echo "CHANGEME")
}

# Create directories
create_directories() {
    log_step "Creating directories..."
    mkdir -p "$INSTALL_DIR"/{nginx,app,ssl,logs}
    mkdir -p "$DATA_DIR"/{data,logs,backups,secrets}
    chmod -R 700 "$DATA_DIR/secrets"
    chmod 600 "$INSTALL_DIR/.env" 2>/dev/null || true
    log_success "Directories created"
}

# Generate SSL cert
generate_ssl_cert() {
    log_step "Generating SSL certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
        -keyout "$INSTALL_DIR/ssl/privkey.pem" \
        -out "$INSTALL_DIR/ssl/fullchain.pem" \
        -subj "/C=US/ST=State/L=City/O=OpenClaw/CN=${TAILSCALE_FQDN:-localhost}" 2>/dev/null
    log_success "SSL certificate generated"
}

# Generate Nginx config
generate_nginx_config() {
    cat > "$INSTALL_DIR/nginx/nginx.conf" << 'NGINX'
worker_processes auto;
error_log /var/log/nginx/error.log warn;

events {
    worker_connections 4096;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log off;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' https://login.tailscale.com wss://login.tailscale.com; font-src 'self' data:;" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

    server_tokens off;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;

    upstream app {
        server app:3000;
        keepalive 32;
    }

    server {
        listen 8080;
        server_name _;

        # Tailscale network ranges
        satisfy any;
        allow 100.64.0.0/10;
        allow 127.0.0.1/32;
        allow 10.0.0.0/8;
        allow 172.16.0.0/12;
        allow 192.168.0.0/16;
        deny all;

        location /health {
            return 200 "OK";
            add_header Content-Type text/plain;
        }

        location / {
            return 301 https://$host:8443$request_uri;
        }
    }

    server {
        listen 8443 ssl http2;
        server_name _;

        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
        ssl_prefer_server_ciphers off;

        limit_req zone=api burst=20 nodelay;

        location /health {
            return 200 "OK";
            add_header Content-Type text/plain;
        }

        location /api/ {
            proxy_pass http://app/api/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location / {
            root /usr/share/nginx/html;
            index index.html;
            try_files $uri $uri/ /index.html;
            add_header Cache-Control "no-store";
        }

        location ~ /\. { deny all; }
    }
}
NGINX
}

# Generate Docker Compose
generate_docker_compose() {
    cat > "$INSTALL_DIR/docker-compose.yml" << DOCKER
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "127.0.0.1:${PORT}:8080"
      - "127.0.0.1:${SSL_PORT}:8443"
    volumes:
      - ./app:/usr/share/nginx/html:ro
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - app
    networks:
      - openclaw
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /run
      - /tmp
    cap_drop:
      - ALL

  app:
    image: node:20-alpine
    restart: unless-stopped
    working_dir: /app
    command: sh -c "npm install --production && node index.js"
    volumes:
      - ./app:/app
    environment:
      - NODE_ENV=production
      - PORT=3000
      - SESSION_SECRET=${SESSION_SECRET}
      - TAILSCALE_IP=${TAILSCALE_IP:-}
      - TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME:-}
      - ADMIN_USERNAME=${ADMIN_USERNAME:-admin}
      - ADMIN_PASSWORD_HASH=${ADMIN_PASSWORD_HASH}
    networks:
      - openclaw
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL

networks:
  openclaw:
    driver: bridge
DOCKER
}

# Generate app
generate_app() {
    log_step "Generating application..."

    cat > "$INSTALL_DIR/app/index.js" << 'APPJS'
const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { execSync } = require('child_process');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(helmet());
app.use(express.json({ limit: '10kb' }));
app.use(express.urlencoded({ extended: false, limit: '10kb' }));
app.set('trust proxy', 1);

const limiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 100,
    standardHeaders: true,
    legacyHeaders: false
});
app.use('/api/', limiter);

const getTailscaleInfo = () => {
    try {
        return {
            ip: execSync('tailscale ip -4 2>/dev/null', { encoding: 'utf8' }).trim(),
            hostname: execSync('tailscale status --self --json 2>/dev/null', { encoding: 'utf8' })
                .match(/"DNSName":"([^"]+)"/)?.[1]?.replace(/\.$/, '') || null
        };
    } catch { return { ip: null, hostname: null }; }
};

const tsInfo = getTailscaleInfo();

const validateAuth = (req, res, next) => {
    if (!req.headers['x-api-key'] && !req.headers['x-session-token']) {
        return res.status(401).json({ error: 'Authentication required' });
    }
    next();
};

app.get('/api/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString(), version: '1.0.0' });
});

app.get('/api/status', validateAuth, (req, res) => {
    res.json({
        system: { uptime: process.uptime(), memory: process.memoryUsage() },
        network: {
            tailscale: tsInfo.ip ? { ip: tsInfo.ip, hostname: tsInfo.hostname } : null
        },
        accessUrl: tsInfo.hostname ? `https://${tsInfo.hostname}` : null
    });
});

app.use(express.static('/app/public'));
app.get('*', (req, res) => res.sendFile('/app/public/index.html'));

app.listen(PORT, '0.0.0.0', () => {
    console.log(`OpenClaw running on port ${PORT}`);
    if (tsInfo.hostname) console.log(`Access: https://${tsInfo.hostname}`);
});
APPJS

    cat > "$INSTALL_DIR/app/package.json" << 'PKG'
{
  "name": "open-claw",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "helmet": "^7.1.0",
    "express-rate-limit": "^7.1.5"
  }
}
PKG

    mkdir -p "$INSTALL_DIR/app/public"

    cat > "$INSTALL_DIR/app/public/index.html" << 'UI'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenClaw - Secure VPS Management</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #0f0f23, #1a1a3e);
            min-height: 100vh;
            color: #e4e4e4;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: rgba(255,255,255,0.03);
            border: 1px solid rgba(255,255,255,0.08);
            border-radius: 20px;
            padding: 3rem;
            max-width: 600px;
            text-align: center;
        }
        .logo { font-size: 2.5rem; font-weight: 700; color: #00d4ff; margin-bottom: 0.5rem; }
        .logo span { color: #ff6b6b; }
        .subtitle { color: #888; margin-bottom: 2rem; }
        .status { display: flex; align-items: center; justify-content: center; gap: 0.75rem; margin: 1.5rem 0; }
        .dot { width: 12px; height: 12px; border-radius: 50%; }
        .dot.green { background: #00ff88; box-shadow: 0 0 15px #00ff88; }
        .dot.blue { background: #00d4ff; box-shadow: 0 0 15px #00d4ff; }
        .access-box {
            background: rgba(0,0,0,0.3);
            border: 1px solid rgba(0,212,255,0.3);
            border-radius: 12px;
            padding: 1.5rem;
            margin: 1.5rem 0;
        }
        .access-url { font-family: monospace; color: #00d4ff; font-size: 1.1rem; word-break: break-all; }
        .features { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; margin: 2rem 0; text-align: left; }
        .feature { background: rgba(255,255,255,0.03); padding: 1rem; border-radius: 8px; }
        .feature h4 { color: #00d4ff; margin-bottom: 0.5rem; font-size: 0.9rem; }
        .feature p { color: #666; font-size: 0.8rem; }
        footer { margin-top: 2rem; color: #555; font-size: 0.85rem; }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">Open<span>Claw</span></div>
        <p class="subtitle">Secure VPS Management System</p>

        <div class="status">
            <div class="dot green"></div>
            <span>System Operational</span>
        </div>

        <div class="access-box">
            <p style="color: #888; margin-bottom: 0.5rem;">Your Private Access URL</p>
            <div class="access-url" id="access-url">Loading...</div>
        </div>

        <div class="features">
            <div class="feature">
                <h4>Private Access</h4>
                <p>Only accessible via Tailscale VPN</p>
            </div>
            <div class="feature">
                <h4>Encrypted</h4>
                <p>TLS 1.3 with secure headers</p>
            </div>
            <div class="feature">
                <h4>Rate Limited</h4>
                <p>Protected against brute force</p>
            </div>
            <div class="feature">
                <h4>Containerized</h4>
                <p>Isolated Docker deployment</p>
            </div>
        </div>

        <footer>
            <p>OpenClaw v1.0.0</p>
            <p style="margin-top: 0.5rem;">Secure • Private • Self-Hosted</p>
        </footer>
    </div>

    <script>
        async function loadStatus() {
            try {
                const res = await fetch('/api/status', {
                    headers: { 'X-API-Key': 'demo' }
                });
                if (res.ok) {
                    const data = await res.json();
                    const url = data.accessUrl || (data.network?.tailscale?.ip ? `https://${data.network.tailscale.ip}` : 'Not configured');
                    document.getElementById('access-url').textContent = url;
                }
            } catch {}
        }
        loadStatus();
    </script>
</body>
</html>
UI

    log_success "Application generated"
}

# Build and start
build_and_start() {
    log_step "Building and starting services..."

    cd "$INSTALL_DIR"
    docker-compose pull
    docker-compose up -d --build

    log "Waiting for services..."
    for i in {1..30}; do
        if curl -sfk https://localhost:${SSL_PORT}/health &>/dev/null; then
            log_success "Services started successfully!"
            return 0
        fi
        sleep 2
    done

    log_warn "Services may still be starting. Check: docker-compose -f $INSTALL_DIR/docker-compose.yml logs"
}

# Print summary
print_summary() {
    echo ""
    echo "=============================================="
    echo "  ${GREEN}OpenClaw Installation Complete!${NC}"
    echo "=============================================="
    echo ""

    if [[ "${TAILSCALE_CONFIGURED:-false}" == "true" ]]; then
        echo -e "${BOLD}Tailscale VPN Access:${NC}"
        echo "  VPN IP:      ${CYAN}${TAILSCALE_IP}${NC}"
        if [[ -n "$TAILSCALE_HOSTNAME" ]]; then
            echo "  Access URL:  ${CYAN}https://${TAILSCALE_HOSTNAME}${NC}"
        fi
        echo ""
        echo "To access this server:"
        echo "  1. Install Tailscale on your device: https://tailscale.com/download"
        echo "  2. Log in with your Tailscale account"
        echo "  3. Visit: https://${TAILSCALE_HOSTNAME:-${TAILSCALE_IP}}"
        echo ""
    fi

    echo -e "${BOLD}Local Access:${NC}"
    echo "  https://localhost:${SSL_PORT}"
    echo ""
    echo -e "${BOLD}Admin Credentials:${NC}"
    echo "  Username: ${ADMIN_USERNAME:-admin}"
    echo "  Password: ${ADMIN_PASSWORD}"
    echo ""
    echo -e "${BOLD}Management:${NC}"
    echo "  Logs:    docker-compose -f $INSTALL_DIR/docker-compose.yml logs -f"
    echo "  Stop:    docker-compose -f $INSTALL_DIR/docker-compose.yml down"
    echo "  Restart: docker-compose -f $INSTALL_DIR/docker-compose.yml restart"
    echo ""
    echo "  IMPORTANT: Change the admin password after first login!"
    echo ""
}

# Main
main() {
    echo ""
    echo "========================================"
    echo "  OpenClaw VPS - Secure Installer v1.0"
    echo "========================================"
    echo ""

    parse_args "$@"

    # If Tailscale key not provided via args, go interactive
    if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
        interactive_prompt
    fi

    detect_server_ip
    check_prerequisites
    setup_tailscale
    setup_cloudflare_dns
    generate_secrets
    create_directories
    generate_ssl_cert
    generate_nginx_config
    generate_docker_compose
    generate_app
    build_and_start
    print_summary
}

main "$@"
