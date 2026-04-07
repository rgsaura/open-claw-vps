# OpenClaw VPS Management System

A secure, self-hosted VPS management system with Cloudflare and Tellscale integration. Designed for privacy-conscious deployments with enterprise-grade security.

## Features

- **Secure by Design**: TLS 1.3, Helmet.js security headers, rate limiting, CSP policies
- **Cloudflare Integration**: DNS management, DDoS protection, CDN
- **Tellscale Integration**: Real-time notifications and alerts
- **Privacy-First**: No external tracking, self-contained deployment
- **One-Line Installation**: Deploy with a single curl command

## Security Features

| Feature | Description |
|---------|-------------|
| TLS 1.3 | Modern cryptography with forward secrecy |
| HSTS | Strict Transport Security headers |
| CSP | Content Security Policy to prevent XSS |
| Rate Limiting | Protection against brute force and DoS |
| Container Isolation | Read-only filesystems, dropped capabilities |
| No Logging | Optional disable of access logs for privacy |

## Quick Start

### One-Line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/main/install.sh | bash
```

For a specific version:
```bash
curl -fsSL https://raw.githubusercontent.com/rgsaura/open-claw-vps/v1.0.0/install.sh | bash
```

### Manual Installation

```bash
# Clone the repository
git clone https://github.com/rgsaura/open-claw-vps.git
cd open-claw-vps

# Configure environment
cp .env.example .env
nano .env  # Edit with your configuration

# Generate SSL certificates (or use Let's Encrypt)
mkdir -p ssl
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
  -keyout ssl/privkey.pem -out ssl/fullchain.pem \
  -subj "/C=US/ST=State/L=City/O=OpenClaw/CN=yourdomain.com"

# Start services
docker-compose up -d

# Access the UI
open https://localhost:8443
```

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `SESSION_SECRET` | Secret for session encryption | Yes |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token | No |
| `TELESCALE_API_KEY` | Tellscale API key | No |
| `ADMIN_USERNAME` | Admin login username | Yes |
| `ADMIN_PASSWORD_HASH` | Bcrypt hash of admin password | Yes |

### Cloudflare Setup

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Go to Profile > API Tokens
3. Create a custom token with:
   - `Zone:DNS:Edit` permissions
   - `Account:User Details:Read` permission
4. Copy the token to `CLOUDFLARE_API_TOKEN` in `.env`

### Tellscale Setup

1. Sign up at [telscale.com](https://telscale.com)
2. Generate an API key from the dashboard
3. Copy to `TELESCALE_API_KEY` in `.env`

## Accessing the UI

After installation:

1. **Local Access**: `https://localhost:8443`
2. **Remote Access**: `https://your-domain.com:8443`

### First-Time Setup

1. Access the UI
2. Log in with admin credentials
3. Change the default password immediately
4. Configure Cloudflare and Tellscale integrations
5. Review and customize security settings

## API Usage

### Authentication

Include your API key in requests:

```bash
curl -H "X-API-Key: your-api-key" https://localhost:8443/api/status
```

### Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check |
| `/api/status` | GET | System status (authenticated) |
| `/api/cloudflare/dns` | POST | Create DNS record |
| `/api/tellscale/notify` | POST | Send notification |

## Deployment Options

### Behind Cloudflare Tunnel

```yaml
# docker-compose.override.yml
services:
  nginx:
    environment:
      - REAL_IP_HEADER=Cf-Connecting-IP
```

### With Let's Encrypt

```bash
# Use Certbot to get certificates
certbot certonly --nginx -d yourdomain.com

# Copy to ssl directory
cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem ssl/fullchain.pem
cp /etc/letsencrypt/live/yourdomain.com/privkey.pem ssl/privkey.pem
```

## Security Hardening

### For Production

1. **Use valid SSL certificates** (Let's Encrypt, commercial CA)
2. **Change default credentials** immediately
3. **Enable firewall**: `ufw allow 8443/tcp`
4. **Disable direct IP access**: Configure Cloudflare or nginx to only allow your domains
5. **Regular updates**: Keep Docker images updated
6. **Backup encryption**: Enable backup encryption with a strong key

### Firewall Configuration

```bash
# Only allow Cloudflare IPs (recommended)
for ip in $(curl -s https://www.cloudflare.com/ips-v4); do
  ufw allow from $ip to any port 8443
done

# Or for internal networks only
ufw allow from 10.0.0.0/8 to any port 8443
ufw allow from 172.16.0.0/12 to any port 8443
ufw allow from 192.168.0.0/16 to any port 8443
```

## Troubleshooting

### Check Service Status

```bash
docker-compose ps
docker-compose logs -f
```

### Restart Services

```bash
docker-compose restart
```

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f nginx
docker-compose logs -f app
```

### Reset to Factory Settings

```bash
docker-compose down -v
rm -rf data/*
docker-compose up -d
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Client                              │
│                    (Browser / BPS)                          │
└────────────────────────┬────────────────────────────────────┘
                         │ HTTPS :8443
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Nginx (Alpine)                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ • TLS 1.3 Termination                                │   │
│  │ • Security Headers (CSP, HSTS, etc.)                │   │
│  │ • Rate Limiting                                      │   │
│  │ • Reverse Proxy                                      │   │
│  └─────────────────────────────────────────────────────┘   │
└────────────────────────┬────────────────────────────────────┘
                         │ HTTP :3000
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Node.js App                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ • Express.js API                                     │   │
│  │ • Helmet.js Security                                 │   │
│  │ • Cloudflare SDK                                     │   │
│  │ • Tellscale Client                                   │   │
│  └─────────────────────────────────────────────────────┘   │
└────────────────────────┬────────────────────────────────────┘
                         │
            ┌────────────┴────────────┐
            │                         │
            ▼                         ▼
     ┌─────────────┐          ┌─────────────┐
     │ Cloudflare  │          │  Tellscale  │
     └─────────────┘          └─────────────┘
```

## License

MIT License - See LICENSE file for details.

## Support

- GitHub Issues: https://github.com/rgsaura/open-claw-vps/issues
- Security: Please report vulnerabilities via GitHub Security Advisories

---

**Remember**: Security is a continuous process. Always keep your system updated and monitor for suspicious activity.
