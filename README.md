# OpenClaw VPS Management System

A secure, self-hosted VPS management system designed for **private access only**. Built for teams that need to manage multiple VPS instances across different projects while keeping them completely private and secure.

## Key Features

- **Private by Design** - Only accessible via Tailscale VPN. No ports exposed to the public internet.
- **Tailscale Integration** - Automatic VPN connection with HTTPS certificates via Funnel
- **Production Ready** - TLS 1.3, security headers, rate limiting, container isolation
- **One-Line Install** - Deploy on any server with a single curl command

## Quick Start

### 1. Get a Tailscale Auth Key

1. Go to [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys)
2. Click "Generate auth key"
3. Copy the key (starts with `tskey-auth-`)

### 2. Install on Your Server

```bash
curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/install.sh | bash -s -- \
  --tailscale-key tskey-auth-xxxxx
```

The script will:
- Install Docker if needed
- Set up Tailscale VPN
- Configure HTTPS
- Deploy the application

### 3. Access Your Instance

After installation, you'll get a private URL like:
```
https://your-server.tail1234.ts.net
```

Only users logged into your Tailscale network can access it.

## With Custom Domain

```bash
curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/install.sh | bash -s -- \
  --tailscale-key tskey-auth-xxxxx \
  --tailscale-fqdn openclaw.yourdomain.com \
  --domain yourdomain.com \
  --cloudflare-token cf_token \
  --cloudflare-zone-id cf_zone_id
```

## All Options

| Option | Description |
|--------|-------------|
| `--tailscale-key` | Tailscale auth key (required) |
| `--tailscale-fqdn` | Custom hostname (e.g., openclaw.example.com) |
| `--cloudflare-token` | Cloudflare API token for DNS |
| `--cloudflare-zone-id` | Cloudflare Zone ID |
| `--domain` | Your domain name |
| `--admin-user` | Admin username (default: admin) |
| `--admin-pass` | Admin password (auto-generated if not set) |
| `--skip-dns` | Skip Cloudflare DNS setup |
| `--help` | Show help |

## Architecture

```
User (Tailscale) ── VPN ──► Server (OpenClaw)
                              │
                              ├── Nginx (TLS termination, security headers)
                              │     └── Port 8443 (localhost only)
                              │
                              └── Node.js (API)
                                    └── Port 3000 (internal)
```

**Security:**
- No ports exposed to public internet
- TLS 1.3 with secure cipher suites
- Helmet.js security headers
- Rate limiting (100 req/15min per IP)
- Container isolation (read-only, dropped capabilities)
- Access logging disabled

## Multi-Instance Setup

For managing multiple VPS instances:

```bash
# Instance 1 - Project A
curl -fsSL https://.../install.sh | bash -s -- \
  --tailscale-key tskey-auth-projA \
  --admin-pass ProjectA_Secure123!

# Instance 2 - Project B
curl -fsSL https://.../install.sh | bash -s -- \
  --tailscale-key tskey-auth-projB \
  --admin-pass ProjectB_Secure456!
```

Each instance gets its own Tailscale identity and can be accessed via:
- `https://projA.tailXXXX.ts.net`
- `https://projB.tailXXXX.ts.net`

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check |
| `/api/status` | GET | System status (auth required) |

Example:
```bash
curl -H "X-API-Key: your-password" https://localhost:8443/api/status
```

## Management Commands

```bash
# View logs
docker-compose -f /opt/open-claw/docker-compose.yml logs -f

# Stop services
docker-compose -f /opt/open-claw/docker-compose.yml down

# Restart services
docker-compose -f /opt/open-claw/docker-compose.yml restart
```

## Requirements

- Ubuntu/Debian/CentOS/Rocky Linux or Alpine
- Docker and Docker Compose
- Tailscale account (free at tailscale.com)

## License

MIT
