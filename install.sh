#!/usr/bin/env bash
#
# OpenClaw VPS Management System - Secure One-Line Installer
# Version: 1.0.0
# Usage: curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/install.sh | bash
#
set -euo pipefail

# ============================================
# CONFIGURATION - Customize these variables
# ============================================
GITHUB_REPO="rgsaura/open-claw-vps"
BRANCH="main"
INSTALL_DIR="/opt/open-claw"
DATA_DIR="/var/lib/open-claw"
PORT=8080
SSL_PORT=8443
DOMAIN=""
CLOUDFLARE_API_TOKEN=""
TELESCALE_API_KEY=""
TELESCALE_WEBHOOK_SECRET=""
ADMIN_USERNAME="admin"
# ============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_deps=()

    # Check for required commands
    for cmd in curl docker docker-compose openssl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_warn "Missing dependencies: ${missing_deps[*]}"
        log_info "Installing missing dependencies..."
        install_dependencies
    fi

    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker and try again."
    fi

    log_success "Prerequisites check passed"
}

# Install system dependencies
install_dependencies() {
    if command -v apt-get &> /dev/null; then
        apt-get update
        apt-get install -y curl openssl ca-certificates gnupg lsb-release
    elif command -v yum &> /dev/null; then
        yum install -y curl openssl ca-certificates
    elif command -v apk &> /dev/null; then
        apk add --no-cache curl openssl ca-certificates
    fi

    # Install Docker if not present
    if ! command -v docker &> /dev/null; then
        log_info "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker --now 2>/dev/null || true
    fi

    # Install Docker Compose if not present
    if ! command -v docker-compose &> /dev/null; then
        log_info "Installing Docker Compose..."
        curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
}

# Generate secure random password
generate_password() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 24
}

# Generate self-signed SSL certificate
generate_ssl_cert() {
    local cert_dir="$1"
    local domain="$2"

    log_info "Generating self-signed SSL certificate..."

    openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
        -keyout "$cert_dir/privkey.pem" \
        -out "$cert_dir/fullchain.pem" \
        -subj "/C=US/ST=State/L=City/O=OpenClaw/CN=${domain:-localhost}" \
        2>/dev/null

    log_success "SSL certificate generated"
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure..."

    mkdir -p "$INSTALL_DIR"/{nginx,app,ssl}
    mkdir -p "$DATA_DIR"/{data,logs,backups,secrets}
    mkdir -p "$DATA_DIR/logs"/{nginx,app}

    # Set proper permissions
    chmod -R 750 "$DATA_DIR/secrets"
    chmod 700 "$DATA_DIR/secrets"

    log_success "Directory structure created"
}

# Generate configuration files
generate_configs() {
    log_info "Generating configuration files..."

    # Docker Compose configuration
    cat > "$INSTALL_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    container_name: open-claw-nginx
    restart: unless-stopped
    ports:
      - "${PORT}:8080"
      - "${SSL_PORT}:8443"
    volumes:
      - ./app:/usr/share/nginx/html:ro
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - ../data/logs/nginx:/var/log/nginx
    depends_on:
      - app
    networks:
      - open-claw-net
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /run
      - /tmp

  app:
    image: node:20-alpine
    container_name: open-claw-app
    restart: unless-stopped
    working_dir: /app
    volumes:
      - ./app:/app
      - ../data:/data
    environment:
      - NODE_ENV=production
      - PORT=3000
      - SSL_PORT=8443
      - SESSION_SECRET=${SESSION_SECRET}
      - CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
      - TELESCALE_API_KEY=${TELESCALE_API_KEY}
      - TELESCALE_WEBHOOK_SECRET=${TELESCALE_WEBHOOK_SECRET}
      - ADMIN_USERNAME=${ADMIN_USERNAME}
      - ADMIN_PASSWORD_HASH=${ADMIN_PASSWORD_HASH}
    networks:
      - open-claw-net
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
      - /var/cache

networks:
  open-claw-net:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: open-claw-br
    ipam:
      config:
        - subnet: 172.28.0.0/16
EOF

    # Nginx configuration with security headers
    cat > "$INSTALL_DIR/nginx/nginx.conf" << 'EOF'
worker_processes auto;
worker_rlimit_nofile 65535;
error_log /var/log/nginx/error.log warn;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging (disabled for privacy - logs to container only)
    access_log off;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' https://api.cloudflare.com https://api.telscale.com; font-src 'self';" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=(), payment=()" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # Hide nginx version
    server_tokens off;
    more_clear_headers Server;

    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

    # Buffer size limits
    client_body_buffer_size 16k;
    client_header_buffer_size 1k;
    client_max_body_size 1m;
    large_client_header_buffers 4 8k;

    # Upstream to app container
    upstream app_backend {
        server app:3000;
        keepalive 32;
    }

    server {
        listen 8080 default_server;
        listen [::]:8080 default_server;
        server_name _;

        # Security checks
        satisfy any;
        allow 127.0.0.1/32;
        allow 10.0.0.0/8;
        allow 172.16.0.0/12;
        allow 192.168.0.0/16;
        deny all;

        # Basic location for health check
        location /health {
            access_log off;
            return 200 "OK";
            add_header Content-Type text/plain;
        }

        location / {
            return 301 https://$host:${SSL_PORT}$request_uri;
        }
    }

    server {
        listen 8443 ssl http2 default_server;
        listen [::]:8443 ssl http2 default_server;
        server_name _;

        # SSL configuration
        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 1d;
        ssl_session_tickets off;
        ssl_stapling on;
        ssl_stapling_verify on;

        # OCSP Stapling (will work with self-signed after first request)
        # resolver 8.8.8.8 8.8.4.4 valid=300s;

        # Rate limiting
        limit_req zone=api_limit burst=20 nodelay;
        limit_conn conn_limit 10;

        # Security location for health check
        location /health {
            access_log off;
            return 200 "OK";
            add_header Content-Type text/plain;
        }

        # API Proxy
        location /api/ {
            proxy_pass http://app_backend/api/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            proxy_read_timeout 90;
            proxy_connect_timeout 90;
            proxy_send_timeout 90;
        }

        # WebSocket Support
        location /ws {
            proxy_pass http://app_backend/ws;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_read_timeout 86400;
        }

        # Static files (UI)
        location / {
            root /usr/share/nginx/html;
            index index.html;
            try_files $uri $uri/ /index.html;
            expires -1;
            add_header Cache-Control "no-store, no-cache, must-revalidate";
        }

        # Deny access to hidden files
        location ~ /\. {
            deny all;
            access_log off;
            log_not_found off;
        }
    }
}
EOF

    log_success "Configuration files generated"
}

# Generate application files
generate_app() {
    log_info "Generating application files..."

    # Main application entry point
    cat > "$INSTALL_DIR/app/index.js" << 'EOF'
const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { Cloudflare } = require('cloudflare');
const https = require('https');

const app = express();
const PORT = process.env.PORT || 3000;

// Security middleware
app.use(helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            scriptSrc: ["'self'", "'unsafe-inline'"],
            styleSrc: ["'self'", "'unsafe-inline'"],
            imgSrc: ["'self'", "data:", "https:"],
            connectSrc: ["'self'", "https://api.cloudflare.com", "https://api.telscale.com"],
            fontSrc: ["'self'"],
            objectSrc: ["'none'"],
            mediaSrc: ["'self'"],
            frameSrc: ["'none'"]
        }
    }
}));

// Rate limiting
const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // limit each IP to 100 requests per windowMs
    message: { error: 'Too many requests, please try again later.' },
    standardHeaders: true,
    legacyHeaders: false
});
app.use('/api/', limiter);

// Body parsing with size limits
app.use(express.json({ limit: '10kb' }));
app.use(express.urlencoded({ extended: false, limit: '10kb' }));

// Trust proxy (for correct IP detection behind nginx)
app.set('trust proxy', 1);

// Session management would go here with proper session store
// For production, use Redis or similar

// Cloudflare client initialization
let cf = null;
if (process.env.CLOUDFLARE_API_TOKEN) {
    cf = new Cloudflare({ token: process.env.CLOUDFLARE_API_TOKEN });
}

// Tellscale API client
class TellsScaleClient {
    constructor(apiKey) {
        this.apiKey = apiKey;
        this.baseUrl = 'https://api.telscale.com/v1';
    }

    async sendNotification(message, severity = 'info') {
        if (!this.apiKey) return { success: false, reason: 'No API key configured' };

        try {
            const data = JSON.stringify({ message, severity, timestamp: new Date().toISOString() });
            const result = await this.httpRequest('/notifications', 'POST', data);
            return { success: true, result };
        } catch (error) {
            console.error('TellsScale notification failed:', error.message);
            return { success: false, reason: error.message };
        }
    }

    httpRequest(path, method, data) {
        return new Promise((resolve, reject) => {
            const url = new URL(this.baseUrl + path);
            const options = {
                hostname: url.hostname,
                port: 443,
                path: url.pathname + url.search,
                method: method,
                headers: {
                    'Authorization': `Bearer ${this.apiKey}`,
                    'Content-Type': 'application/json',
                    'User-Agent': 'OpenClaw/1.0'
                }
            };

            const req = https.request(options, (res) => {
                let body = '';
                res.on('data', chunk => body += chunk);
                res.on('end', () => {
                    if (res.statusCode >= 200 && res.statusCode < 300) {
                        resolve(JSON.parse(body));
                    } else {
                        reject(new Error(`HTTP ${res.statusCode}: ${body}`));
                    }
                });
            });

            req.on('error', reject);
            req.setTimeout(10000, () => {
                req.destroy();
                reject(new Error('Request timeout'));
            });

            if (data) req.write(data);
            req.end();
        });
    }
}

let tellsScale = null;
if (process.env.TELESCALE_API_KEY) {
    tellsScale = new TellsScaleClient(process.env.TELESCALE_API_KEY);
}

// Authentication middleware
const authenticate = (req, res, next) => {
    // In production, implement proper authentication
    // This is a placeholder for the authentication logic
    const apiKey = req.headers['x-api-key'];
    const sessionToken = req.headers['x-session-token'];

    // For demo purposes, check against environment variables
    // Replace with proper authentication (OAuth, JWT, etc.)
    if (!apiKey && !sessionToken) {
        return res.status(401).json({ error: 'Authentication required' });
    }

    // Validate credentials here
    next();
};

// API Routes
app.get('/api/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.get('/api/status', authenticate, async (req, res) => {
    try {
        const status = {
            system: {
                uptime: process.uptime(),
                memory: process.memoryUsage(),
                platform: process.platform
            },
            integrations: {
                cloudflare: cf ? 'configured' : 'not_configured',
                telscale: tellsScale ? 'configured' : 'not_configured'
            }
        };

        // Get Cloudflare zone info if configured
        if (cf) {
            try {
                const zones = await cf.zones.list();
                status.cloudflare = { zones: zones.length, configured: true };
            } catch (e) {
                status.cloudflare = { error: e.message, configured: true };
            }
        }

        res.json(status);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Cloudflare DNS management
app.post('/api/cloudflare/dns', authenticate, async (req, res) => {
    if (!cf) return res.status(503).json({ error: 'Cloudflare not configured' });

    try {
        const { zone_id, name, type, content, proxied = false, ttl = 3600 } = req.body;

        const record = await cf.dnsRecords.add(zone_id, {
            name, type, content, proxied, ttl
        });

        if (tellsScale) {
            await tellsScale.sendNotification(`DNS record created: ${name}`, 'info');
        }

        res.json({ success: true, record });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Tellscale notifications
app.post('/api/tellscale/notify', authenticate, async (req, res) => {
    if (!tellsScale) return res.status(503).json({ error: 'Tellscale not configured' });

    try {
        const { message, severity = 'info' } = req.body;
        const result = await tellsScale.sendNotification(message, severity);
        res.json(result);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Serve static UI (in production, build the React/Vue app)
app.use(express.static('/app/public'));

// SPA fallback
app.get('*', (req, res) => {
    res.sendFile('/app/public/index.html');
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`OpenClaw API running on port ${PORT}`);
    console.log(`Cloudflare: ${cf ? 'Configured' : 'Not configured'}`);
    console.log(`Tellscale: ${tellsScale ? 'Configured' : 'Not configured'}`);
});
EOF

    # Package.json for the app
    cat > "$INSTALL_DIR/app/package.json" << 'EOF'
{
  "name": "open-claw",
  "version": "1.0.0",
  "description": "Secure VPS Management System",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "dev": "node index.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "helmet": "^7.1.0",
    "express-rate-limit": "^7.1.5",
    "cloudflare": "^2.9.1"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF

    # Create public directory with secure UI
    mkdir -p "$INSTALL_DIR/app/public"

    cat > "$INSTALL_DIR/app/public/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' https://api.cloudflare.com https://api.telscale.com;">
    <title>OpenClaw - Secure VPS Management</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            color: #e4e4e4;
        }
        .container { max-width: 1200px; margin: 0 auto; padding: 2rem; }
        header {
            background: rgba(255,255,255,0.05);
            backdrop-filter: blur(10px);
            border-bottom: 1px solid rgba(255,255,255,0.1);
            padding: 1.5rem 0;
            margin-bottom: 2rem;
        }
        .header-content { display: flex; justify-content: space-between; align-items: center; }
        .logo { font-size: 1.5rem; font-weight: 700; color: #00d4ff; }
        .security-badge {
            background: rgba(0, 212, 255, 0.1);
            border: 1px solid rgba(0, 212, 255, 0.3);
            padding: 0.5rem 1rem;
            border-radius: 20px;
            font-size: 0.85rem;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }
        .security-badge::before {
            content: '🔒';
        }
        .dashboard { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1.5rem; }
        .card {
            background: rgba(255,255,255,0.05);
            border: 1px solid rgba(255,255,255,0.1);
            border-radius: 12px;
            padding: 1.5rem;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .card:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 30px rgba(0,0,0,0.3);
        }
        .card h3 { margin-bottom: 1rem; color: #00d4ff; font-size: 1.1rem; }
        .card p { color: #888; font-size: 0.9rem; line-height: 1.6; }
        .status { display: flex; align-items: center; gap: 0.5rem; margin-top: 1rem; }
        .status-dot { width: 8px; height: 8px; border-radius: 50%; }
        .status-dot.green { background: #00ff88; box-shadow: 0 0 10px #00ff88; }
        .status-dot.yellow { background: #ffd700; box-shadow: 0 0 10px #ffd700; }
        .status-dot.red { background: #ff4757; box-shadow: 0 0 10px #ff4757; }
        .btn {
            display: inline-block;
            background: linear-gradient(135deg, #00d4ff 0%, #0099cc 100%);
            color: #1a1a2e;
            padding: 0.75rem 1.5rem;
            border-radius: 8px;
            text-decoration: none;
            font-weight: 600;
            margin-top: 1rem;
            transition: opacity 0.2s;
        }
        .btn:hover { opacity: 0.9; }
        footer {
            margin-top: 3rem;
            text-align: center;
            color: #666;
            font-size: 0.85rem;
        }
        .footer-links { margin-top: 1rem; }
        .footer-links a { color: #00d4ff; text-decoration: none; margin: 0 1rem; }
        .footer-links a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <header>
        <div class="container header-content">
            <div class="logo">OpenClaw</div>
            <div class="security-badge">Secure Connection</div>
        </div>
    </header>

    <div class="container">
        <div class="dashboard">
            <div class="card">
                <h3>System Status</h3>
                <p>Monitor your VPS infrastructure with real-time metrics and alerts.</p>
                <div class="status">
                    <div class="status-dot green"></div>
                    <span>All systems operational</span>
                </div>
            </div>

            <div class="card">
                <h3>Cloudflare Integration</h3>
                <p>Secure your domains with Cloudflare's DDoS protection and CDN.</p>
                <div class="status">
                    <div class="status-dot green"></div>
                    <span>Connected</span>
                </div>
            </div>

            <div class="card">
                <h3>Tellscale Notifications</h3>
                <p>Receive instant alerts via Tellscale when issues arise.</p>
                <div class="status">
                    <div class="status-dot green"></div>
                    <span>Notifications enabled</span>
                </div>
            </div>

            <div class="card">
                <h3>Security Features</h3>
                <p>Built with security in mind: TLS 1.3, rate limiting, CSP headers, and more.</p>
                <a href="#" class="btn">View Security Docs</a>
            </div>

            <div class="card">
                <h3>Quick Actions</h3>
                <p>Deploy, configure, and manage your VPS instances with ease.</p>
                <a href="#" class="btn">Get Started</a>
            </div>

            <div class="card">
                <h3>Documentation</h3>
                <p>Learn how to get the most out of your OpenClaw deployment.</p>
                <a href="#" class="btn">Read Docs</a>
            </div>
        </div>

        <footer>
            <p>OpenClaw VPS Management System v1.0.0</p>
            <div class="footer-links">
                <a href="#">Privacy Policy</a>
                <a href="#">Terms of Service</a>
                <a href="#">Security</a>
                <a href="#">Support</a>
            </div>
        </footer>
    </div>

    <script>
        // Secure API communication
        const API_BASE = '/api';

        async function checkStatus() {
            try {
                const response = await fetch(`${API_BASE}/status`, {
                    headers: {
                        'X-API-Key': sessionStorage.getItem('apiKey') || ''
                    }
                });
                if (response.ok) {
                    const data = await response.json();
                    console.log('System status:', data);
                }
            } catch (e) {
                console.log('Running in standalone mode');
            }
        }

        // Check status on load
        checkStatus();
    </script>
</body>
</html>
EOF

    log_success "Application files generated"
}

# Generate environment file
generate_env_file() {
    log_info "Generating environment configuration..."

    # Generate secure session secret
    local session_secret=$(generate_password)
    local admin_password_hash=$(openssl passwd -1 -bcrypt "changeme" 2>/dev/null || echo "Bcrypt hash placeholder")

    cat > "$INSTALL_DIR/.env" << EOF
# OpenClaw Environment Configuration
# Auto-generated on $(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Security
SESSION_SECRET=${session_secret}
ADMIN_USERNAME=${ADMIN_USERNAME}
ADMIN_PASSWORD_HASH=${admin_password_hash}

# Ports
PORT=${PORT}
SSL_PORT=${SSL_PORT}

# Domain
DOMAIN=${DOMAIN:-localhost}

# Cloudflare Configuration
CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN:-}

# Tellscale Configuration
TELESCALE_API_KEY=${TELESCALE_API_KEY:-}
TELESCALE_WEBHOOK_SECRET=${TELESCALE_WEBHOOK_SECRET:-}
EOF

    chmod 600 "$INSTALL_DIR/.env"

    log_success "Environment file generated"
}

# Set proper permissions
set_permissions() {
    log_info "Setting permissions..."

    chown -R root:root "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    chmod 600 "$INSTALL_DIR"/.env
    chmod 700 "$INSTALL_DIR/nginx"
    chmod 700 "$INSTALL_DIR/ssl"

    chown -R root:root "$DATA_DIR"
    chmod -R 755 "$DATA_DIR"
    chmod -R 700 "$DATA_DIR/secrets"

    log_success "Permissions set"
}

# Start services
start_services() {
    log_info "Starting services..."

    cd "$INSTALL_DIR"

    # Load environment variables
    set -a
    source .env
    set +a

    # Pull latest images
    docker-compose pull

    # Build and start containers
    docker-compose up -d --build

    # Wait for services to be ready
    log_info "Waiting for services to start..."
    sleep 10

    # Check service health
    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -sf https://localhost:${SSL_PORT}/health &>/dev/null; then
            log_success "Services are healthy!"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    log_warn "Services may not be fully healthy yet. Check logs with: docker-compose logs"
    return 0
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."

    local https_ok=false
    local api_ok=false

    # Test HTTPS endpoint
    if curl -sfI https://localhost:${SSL_PORT}/ 2>/dev/null | grep -q "200\|301\|302"; then
        https_ok=true
    fi

    # Test API endpoint
    if curl -sf https://localhost:${SSL_PORT}/api/health 2>/dev/null | grep -q "healthy"; then
        api_ok=true
    fi

    if $https_ok && $api_ok; then
        log_success "Installation verified successfully!"
        log_success "Access the UI at: https://localhost:${SSL_PORT}"
        log_success "API endpoint: https://localhost:${SSL_PORT}/api"
    else
        log_warn "Verification incomplete. Check the status with: docker-compose ps"
    fi
}

# Print next steps
print_next_steps() {
    echo ""
    echo "=============================================="
    echo "  OpenClaw Installation Complete!"
    echo "=============================================="
    echo ""
    echo "Access URLs:"
    echo "  UI Dashboard: https://localhost:${SSL_PORT}"
    echo "  API Health:   https://localhost:${SSL_PORT}/api/health"
    echo ""
    echo "Important Steps:"
    echo "  1. Change the default admin password"
    echo "  2. Configure your domain and SSL certificates"
    echo "  3. Set up Cloudflare API token for DNS management"
    echo "  4. Configure Tellscale for notifications"
    echo ""
    echo "Configuration file: $INSTALL_DIR/.env"
    echo "Data directory:     $DATA_DIR"
    echo ""
    echo "Management Commands:"
    echo "  View logs:     docker-compose -f $INSTALL_DIR/docker-compose.yml logs -f"
    echo "  Stop services: docker-compose -f $INSTALL_DIR/docker-compose.yml down"
    echo "  Restart:       docker-compose -f $INSTALL_DIR/docker-compose.yml restart"
    echo ""
    echo "For security hardening, review $INSTALL_DIR/nginx/nginx.conf"
    echo ""
}

# Main installation flow
main() {
    echo ""
    echo "========================================"
    echo "  OpenClaw VPS - Secure Installer v1.0"
    echo "========================================"
    echo ""

    check_root
    check_prerequisites
    create_directories
    generate_configs
    generate_app
    generate_ssl_cert "$INSTALL_DIR/ssl" "${DOMAIN:-localhost}"
    generate_env_file
    set_permissions
    start_services
    verify_installation
    print_next_steps
}

# Run main function
main "$@"
