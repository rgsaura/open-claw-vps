# OpenClaw VPS Management System

A secure, self-hosted VPS management system with **flexible deployment options**. Choose between Tailscale VPN, Cloudflare Tunnel, or Cloudflare Proxy based on your security and accessibility needs.

## Choose Your Setup Mode

| Mode | Security | Accessibility | Best For |
|------|----------|---------------|----------|
| **1. Tailscale VPN** | Highest | Requires VPN app | Maximum privacy, team with Tailscale |
| **2. Cloudflare Tunnel** | High | No VPN app | Easy access, global availability |
| **3. Cloudflare Proxy** | High | No VPN app | Traditional hosting, full CF features |

All modes: **No ports exposed to public internet** (except Mode 3 which needs 80/443)

---

## Quick Start

### Interactive Setup (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/openclaw-installer.sh | bash
```

You'll be prompted to choose your setup mode and enter credentials.

---

## Setup Mode 1: Tailscale VPN

**Most private** - No internet exposure, requires Tailscale app on devices.

### 1. Get Tailscale Auth Key

1. Go to [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys)
2. Click "Generate auth key"
3. Copy the key (starts with `tskey-auth-`)

### 2. Install

```bash
curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/openclaw-installer.sh | bash -s -- \
  --setup-mode 1 \
  --tailscale-key tskey-auth-xxxxx
```

### 3. Access

Visit: `https://your-server.tail1234.ts.net`

Requires Tailscale app on your device.

---

## Setup Mode 2: Cloudflare Tunnel (Recommended)

**Easy access** - No VPN app needed, uses Cloudflare's global network.

### 1. Get Cloudflare API Token

1. Go to [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Click "Create Token" → "Create Custom Token"
3. Name: `OpenClaw Tunnel`
4. Permissions: Account > Cloudflare Tunnel > Edit
5. Account Resources: Include > Your account
6. Create and copy the token

### 2. Install

```bash
curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/openclaw-installer.sh | bash -s -- \
  --setup-mode 2 \
  --cloudflare-token cf_token \
  --domain yourdomain.com
```

### 3. Access

Visit: `https://openclaw.yourdomain.com`

No VPN app needed.

---

## Setup Mode 3: Cloudflare Proxy (Traditional)

**Traditional setup** - Requires ports 80/443 open.

### 1. Get Cloudflare API Token

1. Go to [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Click "Create Token" → "Create Custom Token"
3. Name: `OpenClaw`
4. Permissions: Zone > DNS > Edit
5. Zone Resources: Include > Specific zone > Your domain
6. Create and copy the token

### 2. Install

```bash
curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/openclaw-installer.sh | bash -s -- \
  --setup-mode 3 \
  --cloudflare-token cf_token \
  --cloudflare-zone-id cf_zone_id \
  --domain yourdomain.com
```

### 3. Access

Visit: `https://openclaw.yourdomain.com`

Ensure ports 80 and 443 are open on your server.

---

## All Options

| Option | Mode | Description |
|--------|------|-------------|
| `--setup-mode` | All | 1=Tailscale, 2=Tunnel, 3=Proxy |
| `--tailscale-key` | 1 | Tailscale auth key (`tskey-auth-...`) |
| `--cloudflare-token` | 2,3 | Cloudflare API token |
| `--cloudflare-zone-id` | 2,3 | Cloudflare Zone ID |
| `--domain` | 2,3 | Your domain name |
| `--tunnel-subdomain` | 2,3 | Subdomain prefix (default: openclaw) |
| `--admin-user` | All | Admin username (default: admin) |
| `--admin-pass` | All | Admin password (auto-generated if not set) |

---

## Using .env File

Create `.env` file for repeatable setups:

```bash
cp .env.example .env
# Edit .env with your values
curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/openclaw-installer.sh | bash
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        MODE 1: TAILSCALE                      │
│  User ──► Tailscale VPN ──► Server (no ports exposed)       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    MODE 2: CLOUDFLARE TUNNEL                  │
│  User ──► Cloudflare Network ──► Tunnel ──► Server          │
│                                          (no ports exposed)  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    MODE 3: CLOUDFLARE PROXY                  │
│  User ──► Cloudflare ──► Nginx:443 ──► Server              │
│                              (ports 80/443 must be open)    │
└─────────────────────────────────────────────────────────────┘
```

**Security (all modes):**
- TLS 1.3 with secure cipher suites
- Helmet.js security headers
- Rate limiting (100 req/15min per IP)
- Container isolation (read-only, dropped capabilities)
- Access logging disabled
- No secrets in environment variables

---

## Multi-Instance Setup

```bash
# Instance 1 - Project A (Tailscale)
curl -fsSL https://.../openclaw-installer.sh | bash -s -- \
  --setup-mode 1 --tailscale-key tskey-auth-projA --admin-pass ProjA_Pass123!

# Instance 2 - Project B (Cloudflare Tunnel)
curl -fsSL https://.../openclaw-installer.sh | bash -s -- \
  --setup-mode 2 --cloudflare-token cf_token --domain projB.com
```

---

## Management Commands

```bash
# View logs
docker-compose -f /opt/open-claw/docker-compose.yml logs -f

# Stop services
docker-compose -f /opt/open-claw/docker-compose.yml down

# Restart services
docker-compose -f /opt/open-claw/docker-compose.yml restart
```

---

## Requirements

- Ubuntu/Debian/CentOS/Rocky Linux or Alpine
- Docker and Docker Compose
- For Mode 1: Tailscale account ([tailscale.com](https://tailscale.com))
- For Mode 2/3: Cloudflare account with domain added ([cloudflare.com](https://cloudflare.com))

---

## License

MIT
