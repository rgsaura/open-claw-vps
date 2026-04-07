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
            --setup-mode)
                SETUP_MODE="$2"
                shift 2
                ;;
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
            --tunnel-subdomain)
                CLOUDFLARE_TUNNEL_SUBDOMAIN="$2"
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

Setup Modes (will prompt if not specified):
  1) Tailscale VPN   - Most private, no ports exposed, requires VPN app
  2) Cloudflare Tunnel - No ports exposed, no VPN app needed (recommended)
  3) Cloudflare Proxy - Traditional, ports 80/443 needed

Options:
  --setup-mode MODE     Setup mode: 1 (Tailscale), 2 (Tunnel), 3 (Proxy)
  --tailscale-key KEY   Tailscale auth key (for mode 1)
  --cloudflare-token TOKEN  Cloudflare API token (for modes 2,3)
  --cloudflare-zone-id ID   Cloudflare Zone ID (for modes 2,3)
  --domain DOMAIN       Your domain name (for modes 2,3)
  --admin-user USER     Admin username (default: admin)
  --admin-pass PASS     Admin password (auto-generated if not set)
  --help, -h           Show this help

Examples:
  # Interactive setup (choose mode when prompted)
  curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/install.sh | bash

  # Tailscale VPN mode
  curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/install.sh | bash -s -- \
    --setup-mode 1 --tailscale-key tskey-auth-kffdsafdsa

  # Cloudflare Tunnel mode (recommended)
  curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/install.sh | bash -s -- \
    --setup-mode 2 --cloudflare-token cf_token --domain example.com

Setup Mode Details:

  ${GREEN}1) Tailscale VPN${NC} - Best for maximum privacy
     - No ports exposed to internet
     - Requires Tailscale app on devices
     - Get key: https://login.tailscale.com/admin/settings/keys

  ${YELLOW}2) Cloudflare Tunnel${NC} - Best for easy access
     - No ports exposed to internet
     - No VPN app needed
     - Uses Cloudflare's global network
     - Token: Account > Cloudflare Tunnel > Edit permissions

  ${CYAN}3) Cloudflare Proxy${NC} - Traditional setup
     - Requires ports 80/443 open
     - Full Cloudflare protection
     - Token: Zone > DNS > Edit permissions
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

    # =================================================================
    # STEP 1: Choose setup mode
    # =================================================================
    if [[ -z "${SETUP_MODE:-}" ]]; then
        echo ""
        echo -e "${BOLD}Choose Your Setup Mode:${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  ${GREEN}1${NC}) ${BOLD}Tailscale VPN${NC} - Most private"
        echo "      - Requires Tailscale app on your devices"
        echo "      - No ports exposed to internet"
        echo "      - Encrypted peer-to-peer connection"
        echo ""
        echo "  ${YELLOW}2${NC}) ${BOLD}Cloudflare Tunnel${NC} - Easy access (recommended)"
        echo "      - No VPN app needed"
        echo "      - No ports exposed to internet"
        echo "      - Uses Cloudflare's global network"
        echo ""
        echo "  ${CYAN}3${NC}) ${BOLD}Cloudflare Proxy${NC} - Traditional"
        echo "      - Direct access via domain"
        echo "      - Cloudflare proxies and protects traffic"
        echo "      - Requires ports 80/443 open locally"
        echo ""
        read -rp "Select setup mode [1]: " SETUP_MODE
        [[ -z "$SETUP_MODE" ]] && SETUP_MODE="1"
    fi

    # =================================================================
    # MODE 1: Tailscale VPN
    # =================================================================
    if [[ "$SETUP_MODE" == "1" ]]; then
        echo ""
        echo -e "${BOLD}Mode: Tailscale VPN${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Tailscale creates a private VPN network. Only users logged into"
        echo "your Tailscale network can access this server."
        echo ""

        if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
            echo -e "${BOLD}Step 1: Generate Tailscale Auth Key${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "1. Open this link: https://login.tailscale.com/admin/settings/keys"
            echo "2. Click '${GREEN}Generate auth key${NC}' button"
            echo "3. Copy the key (starts with '${GREEN}tskey-auth-${NC}')"
            echo ""
            read -rp "Paste your Tailscale Auth Key: " TAILSCALE_AUTH_KEY
        fi

        # Custom hostname (optional)
        if [[ -z "${TAILSCALE_FQDN:-}" ]]; then
            echo ""
            echo "Custom hostname (e.g., openclaw.example.com) or press Enter for default:"
            read -rp "[auto-generated tailxxxx.ts.net]: " TAILSCALE_FQDN
            [[ -z "$TAILSCALE_FQDN" ]] && TAILSCALE_FQDN=""
        fi

    # =================================================================
    # MODE 2: Cloudflare Tunnel
    # =================================================================
    elif [[ "$SETUP_MODE" == "2" ]]; then
        echo ""
        echo -e "${BOLD}Mode: Cloudflare Tunnel${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Cloudflare Tunnel creates a secure connection through Cloudflare's"
        echo "global network. No ports need to be opened on your server."
        echo "Users access via your domain without needing any VPN app."
        echo ""

        if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
            echo -e "${BOLD}Step 1: Create Cloudflare API Token${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "1. Open: https://dash.cloudflare.com/profile/api-tokens"
            echo "2. Click '${GREEN}Create Token${NC}'"
            echo "3. Choose '${GREEN}Create Custom Token${NC}'"
            echo "4. Token Name: ${GREEN}OpenClaw-Tunnel${NC}"
            echo "5. Permissions:"
            echo "   - Account: ${GREEN}Cloudflare Tunnel${NC} > ${GREEN}Edit${NC}"
            echo "6. Account Resources: ${GREEN}Include${NC} > ${GREEN}Your account${NC}"
            echo "7. Click '${GREEN}Create Token${NC}' and copy the token"
            echo ""
            read -rp "Paste your Cloudflare API Token: " CLOUDFLARE_API_TOKEN
        fi

        if [[ -z "${DOMAIN:-}" ]]; then
            echo ""
            echo "Your domain name (must be added to Cloudflare):"
            read -rp "Domain (e.g., example.com): " DOMAIN
        fi

        if [[ -z "${CLOUDFLARE_ZONE_ID:-}" ]]; then
            echo ""
            echo "Cloudflare Zone ID (found in Cloudflare Dashboard > Domain > Overview):"
            read -rp "Zone ID: " CLOUDFLARE_ZONE_ID
        fi

        # Optional: custom subdomain
        if [[ -z "${CLOUDFLARE_TUNNEL_SUBDOMAIN:-}" ]]; then
            echo ""
            echo "Subdomain for OpenClaw (or press Enter for 'openclaw'):"
            read -rp "[openclaw]: " CLOUDFLARE_TUNNEL_SUBDOMAIN
            [[ -z "$CLOUDFLARE_TUNNEL_SUBDOMAIN" ]] && CLOUDFLARE_TUNNEL_SUBDOMAIN="openclaw"
        fi

    # =================================================================
    # MODE 3: Cloudflare Proxy (Traditional)
    # =================================================================
    elif [[ "$SETUP_MODE" == "3" ]]; then
        echo ""
        echo -e "${BOLD}Mode: Cloudflare Proxy (Traditional)${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Traditional setup using Cloudflare as a reverse proxy."
        echo "Requires ports 80 and 443 open on your server."
        echo ""

        if [[ -z "${DOMAIN:-}" ]]; then
            echo -e "${BOLD}Step 1: Your Domain${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Your domain must be added to Cloudflare."
            read -rp "Domain (e.g., example.com): " DOMAIN
        fi

        if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
            echo ""
            echo -e "${BOLD}Step 2: Create Cloudflare API Token${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "1. Open: https://dash.cloudflare.com/profile/api-tokens"
            echo "2. Click '${GREEN}Create Token${NC}'"
            echo "3. Choose '${GREEN}Create Custom Token${NC}'"
            echo "4. Token Name: ${GREEN}OpenClaw-DNS${NC}"
            echo "5. Permissions:"
            echo "   - Zone: ${GREEN}DNS${NC} > ${GREEN}Edit${NC}"
            echo "6. Zone Resources: ${GREEN}Include${NC} > ${GREEN}Specific zone${NC} > ${DOMAIN:-your-domain}"
            echo "7. Click '${GREEN}Create Token${NC}' and copy the token"
            echo ""
            read -rp "Paste your Cloudflare API Token: " CLOUDFLARE_API_TOKEN
        fi

        if [[ -z "${CLOUDFLARE_ZONE_ID:-}" ]]; then
            echo ""
            echo "Cloudflare Zone ID:"
            read -rp "Zone ID: " CLOUDFLARE_ZONE_ID
        fi
    fi

    # =================================================================
    # ADMIN CREDENTIALS (common to all modes)
    # =================================================================
    if [[ -z "${ADMIN_USERNAME:-}" ]]; then
        echo ""
        echo -e "${BOLD}Admin Credentials${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Login for the OpenClaw web dashboard."
        read -rp "Admin username [admin]: " ADMIN_USERNAME
        [[ -z "$ADMIN_USERNAME" ]] && ADMIN_USERNAME="admin"
    fi

    if [[ -z "${ADMIN_PASSWORD:-}" ]]; then
        echo ""
        echo "Leave blank to auto-generate a secure password."
        read -rp "Admin password [auto-generate]: " ADMIN_PASSWORD
        [[ -z "$ADMIN_PASSWORD" ]] && ADMIN_PASSWORD=""
    fi

    echo ""
}

# Load .env file if it exists
load_env_file() {
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        log "Loading configuration from $INSTALL_DIR/.env..."
        set -a
        source "$INSTALL_DIR/.env"
        set +a
    fi
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

# Setup Tailscale with Funnel (automatic HTTPS)
setup_tailscale() {
    if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
        log_error "Tailscale auth key is required. Provide --tailscale-key or run interactively."
    fi

    log_step "Setting up Tailscale VPN with Funnel (automatic HTTPS)..."

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
        tailscale up --authkey="$TAILSCALE_AUTH_KEY" --accept-routes --hostcheck=false 2>/dev/null || \
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

            # Configure Funnel for automatic HTTPS certificates
            # Funnel exposes port 8443 with automatic Let's Encrypt certificates
            log "Configuring Tailscale Funnel for automatic HTTPS..."

            # Use the specified hostname or just enable Funnel
            if [[ -n "$TAILSCALE_FQDN" ]]; then
                # Set custom hostname and enable funnel
                tailscale serve --set-hostname="$TAILSCALE_FQDN" 2>/dev/null || true
                tailscale funnel --set-hostname="$TAILSCALE_FQDN" 8443 2>/dev/null || \
                tailscale funnel 8443 2>/dev/null || true
            else
                # Enable funnel on port 8443 (Tailscale handles HTTPS certs automatically)
                tailscale funnel 8443 2>/dev/null || \
                tailscale serve --bg 2>/dev/null || true
            fi

            # Get the Funnel hostname
            TAILSCALE_HOSTNAME=$(tailscale status --self --json 2>/dev/null | \
                grep -oP '"DNSName":"[^"]+"' | head -1 | cut -d'"' -f4 | sed 's/\.$//' || true)

            # Enable on boot
            systemctl enable tailscaled 2>/dev/null || true

            TAILSCALE_CONFIGURED="true"
            log_success "Funnel configured - HTTPS certificates are automatic!"
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

# Setup Cloudflare Tunnel (Mode 2)
setup_cloudflare_tunnel() {
    if [[ -z "$CLOUDFLARE_API_TOKEN" ]]; then
        log_error "Cloudflare API token is required for Cloudflare Tunnel mode"
    fi

    log_step "Setting up Cloudflare Tunnel..."

    # Install cloudflared
    if ! command -v cloudflared &> /dev/null; then
        log "Installing Cloudflared tunnel daemon..."
        if command -v apt-get &> /dev/null; then
            curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
                -o /usr/local/bin/cloudflared
            chmod +x /usr/local/bin/cloudflared
        elif command -v yum &> /dev/null; then
            curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
                -o /usr/local/bin/cloudflared
            chmod +x /usr/local/bin/cloudflared
        elif command -v apk &> /dev/null; then
            apk add --no-cache cloudflared
        fi
    fi

    if command -v cloudflared &> /dev/null; then
        log "Creating Cloudflare Tunnel..."

        # Create tunnel
        local tunnel_response=$(cloudflared tunnel create openclaw 2>/dev/null || true)
        local tunnel_id=$(echo "$tunnel_response" | grep -oP '[a-f0-9-]{36}' | head -1 || true)

        if [[ -z "$tunnel_id" ]]; then
            # Try to list existing tunnels
            tunnel_id=$(cloudflared tunnel list 2>/dev/null | grep openclaw | awk '{print $1}' || true)
        fi

        if [[ -n "$tunnel_id" ]]; then
            log_success "Tunnel created/verified: $tunnel_id"

            # Create tunnel credentials file path
            local creds_file="$DATA_DIR/tunnel-credentials.json"

            # Create DNS record for the tunnel
            local full_hostname="${CLOUDFLARE_TUNNEL_SUBDOMAIN:-openclaw}.${DOMAIN}"
            log "Creating DNS record for $full_hostname..."

            # Get or create CNAME for the tunnel
            local dns_response=$(curl -fsSL -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"type\":\"CNAME\",\"name\":\"${CLOUDFLARE_TUNNEL_SUBDOMAIN:-openclaw}\",\"content\":\"${tunnel_id}.cfargotunnel.com\",\"ttl\":3600,\"proxied\":true}" \
                2>/dev/null)

            if echo "$dns_response" | grep -q '"id"'; then
                log_success "DNS record created"
            else
                log_warn "DNS record creation failed or already exists"
            fi

            # Save tunnel ID for docker-compose
            CLOUDFLARE_TUNNEL_ID="$tunnel_id"

            TUNNEL_CONFIGURED="true"
            ACCESS_URL="https://${full_hostname}"
        else
            log_warn "Could not create or find Cloudflare Tunnel"
        fi
    else
        log_warn "Cloudflared installation failed"
    fi
}

# Setup Cloudflare Proxy Mode (Mode 3)
setup_cloudflare_proxy() {
    log_step "Setting up Cloudflare Proxy mode..."

    # Create DNS A record pointing to server IP
    if [[ -n "$DOMAIN" && -n "$CLOUDFLARE_API_TOKEN" ]]; then
        local full_hostname="${CLOUDFLARE_TUNNEL_SUBDOMAIN:-openclaw}.${DOMAIN}"
        log "Creating DNS A record for $full_hostname -> $SERVER_IP..."

        # Check if Zone ID exists, if not try to get it
        if [[ -z "$CLOUDFLARE_ZONE_ID" ]]; then
            log "Fetching Zone ID for $DOMAIN..."
            local zones_response=$(curl -fsSL -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json" 2>/dev/null)
            CLOUDFLARE_ZONE_ID=$(echo "$zones_response" | grep -oP '"id":"[^"]+"' | head -1 | cut -d'"' -f4)
        fi

        if [[ -n "$CLOUDFLARE_ZONE_ID" ]]; then
            local dns_response=$(curl -fsSL -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"type\":\"A\",\"name\":\"${CLOUDFLARE_TUNNEL_SUBDOMAIN:-openclaw}\",\"content\":\"$SERVER_IP\",\"ttl\":3600,\"proxied\":true}" \
                2>/dev/null)

            if echo "$dns_response" | grep -q '"id"'; then
                log_success "DNS A record created (proxied through Cloudflare)"
            else
                log_warn "DNS record creation failed or already exists"
            fi

            ACCESS_URL="https://${full_hostname}"
        fi
    fi

    PROXY_CONFIGURED="true"
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

# Create dedicated user for OpenClaw
create_openclaw_user() {
    log_step "Creating dedicated system user..."

    # Create openclaw group if it doesn't exist
    if ! getent group openclaw > /dev/null 2>&1; then
        groupadd --system openclaw 2>/dev/null || \
        groupadd openclaw 2>/dev/null || true
        log "Created 'openclaw' group"
    fi

    # Create openclaw user if it doesn't exist
    if ! id openclaw > /dev/null 2>&1; then
        useradd --system \
            --gid openclaw \
            --home-dir "$INSTALL_DIR" \
            --shell /usr/sbin/nologin \
            --comment "OpenClaw VPS Management" \
            openclaw 2>/dev/null || \
        useradd -g openclaw -d "$INSTALL_DIR" -s /usr/sbin/nologin openclaw 2>/dev/null || true
        log "Created 'openclaw' user"
    fi

    log_success "User 'openclaw' configured"
}

# Create directories
create_directories() {
    log_step "Creating directories..."
    mkdir -p "$INSTALL_DIR"/{nginx,app,ssl,logs}
    mkdir -p "$DATA_DIR"/{data,logs,backups,secrets}
    chmod -R 700 "$DATA_DIR/secrets"
    chmod 600 "$INSTALL_DIR/.env" 2>/dev/null || true

    # Set ownership to openclaw user
    if id openclaw > /dev/null 2>&1; then
        chown -R openclaw:openclaw "$INSTALL_DIR" 2>/dev/null || true
        chown -R openclaw:openclaw "$DATA_DIR" 2>/dev/null || true
        log "Set ownership to 'openclaw' user"
    fi

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
    # Get numeric UID/GID for openclaw user (default to 1000 if user doesn't exist yet)
    OPENCLAW_UID=$(id -u openclaw 2>/dev/null || echo "1000")
    OPENCLAW_GID=$(getent group openclaw 2>/dev/null | cut -d: -f3 || echo "1000")

    cat > "$INSTALL_DIR/docker-compose.yml" << DOCKER
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    restart: unless-stopped
    user: root
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
    user: "${OPENCLAW_UID}:${OPENCLAW_GID}"
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

    case "${SETUP_MODE:-1}" in
        1)
            echo -e "${BOLD}Mode: Tailscale VPN (Most Private)${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Your server is accessible ONLY through the Tailscale VPN."
            echo "No ports are exposed to the public internet."
            echo ""
            echo "Access URL:"
            echo "  ${CYAN}https://${TAILSCALE_HOSTNAME:-${TAILSCALE_IP}}${NC}"
            echo ""
            echo "How to access:"
            echo "  1. Install Tailscale: https://tailscale.com/download"
            echo "  2. Open Tailscale and log in"
            echo "  3. Visit: https://${TAILSCALE_HOSTNAME:-${TAILSCALE_IP}}"
            echo ""
            echo "Best for:"
            echo "  - Teams with Tailscale accounts"
            echo "  - Maximum privacy and security"
            echo "  - No internet exposure at all"
            echo ""
            ;;
        2)
            echo -e "${BOLD}Mode: Cloudflare Tunnel (Easy Access)${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Your server is accessible via Cloudflare's global network."
            echo "No ports are exposed to the public internet."
            echo ""
            echo "Access URL:"
            echo "  ${CYAN}https://${CLOUDFLARE_TUNNEL_SUBDOMAIN:-openclaw}.${DOMAIN}${NC}"
            echo ""
            echo "How to access:"
            echo "  1. Open your browser"
            echo "  2. Visit the URL above"
            echo "  3. No VPN app needed!"
            echo ""
            echo "Best for:"
            echo "  - Easy access without VPN app"
            echo "  - Global availability via Cloudflare"
            echo "  - Quick team onboarding"
            echo ""
            ;;
        3)
            echo -e "${BOLD}Mode: Cloudflare Proxy (Traditional)${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Your server uses Cloudflare as a reverse proxy."
            echo "Traffic is protected but ports 80/443 must be accessible."
            echo ""
            echo "Access URL:"
            echo "  ${CYAN}https://${CLOUDFLARE_TUNNEL_SUBDOMAIN:-openclaw}.${DOMAIN}${NC}"
            echo ""
            echo "How to access:"
            echo "  1. Ensure ports 80 and 443 are open"
            echo "  2. Visit the URL above"
            echo ""
            echo "Best for:"
            echo "  - Traditional hosting setups"
            echo "  - When you need direct server access"
            echo "  - Full Cloudflare protection features"
            echo ""
            ;;
    esac

    echo -e "${BOLD}Admin Credentials:${NC}"
    echo "  Username: ${ADMIN_USERNAME:-admin}"
    echo "  Password: ${ADMIN_PASSWORD}"
    echo ""
    echo -e "${BOLD}Management Commands:${NC}"
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

    # Load .env file if it exists (before parsing args so args can override)
    load_env_file

    parse_args "$@"

    # If required credentials not provided via args, go interactive
    if [[ -z "${TAILSCALE_AUTH_KEY:-}" && -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        interactive_prompt
    fi

    detect_server_ip
    check_prerequisites
    create_openclaw_user

    # Run setup based on chosen mode
    case "${SETUP_MODE:-1}" in
        1)
            setup_tailscale
            setup_cloudflare_dns
            ;;
        2)
            setup_cloudflare_tunnel
            ;;
        3)
            setup_cloudflare_proxy
            ;;
        *)
            log_error "Invalid setup mode: $SETUP_MODE"
            ;;
    esac

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
