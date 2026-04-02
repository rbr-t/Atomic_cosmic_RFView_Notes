# Deployment Guide

## Pre-Deployment Checklist

- [ ] All tests passing (`npm test` || `Rscript -e "testthat::test_dir()"`)
- [ ] Environment variables configured (`.env.production`)
- [ ] Database backups scheduled
- [ ] Monitoring & alerting enabled
- [ ] Documentation updated
- [ ] Changelog updated

---

## Environments

### Development
- **Host**: localhost
- **Database**: PostgreSQL (local)
- **Auth**: Disabled
- **Features**: All flags enabled
- **Deploy**: Manual (docker-compose up)

### Staging
- **Host**: staging.example.com
- **Database**: PostgreSQL (managed)
- **Auth**: Enabled with test users
- **Features**: Production config
- **Deploy**: Automated on develop branch

### Production
- **Host**: app.example.com
- **Database**: PostgreSQL (highly available, replicated)
- **Auth**: Enabled with RBAC
- **Features**: Feature flags per deployment config
- **Deploy**: Automated on main branch (tag required)

---

## Docker Deployment

### Prerequisites
```bash
# Verify Docker & Compose
docker --version
docker-compose --version

# Check available disk space (≥10GB recommended)
df -h /var/lib/docker

# Verify network connectivity
ping postgres.example.com
ping chroma.example.com
```

### Deploy to Staging

```bash
# 1. SSH to staging server
ssh deploy@staging.example.com

# 2. Clone/update code
cd /opt/pa-design-app
git fetch origin
git checkout develop
git pull origin develop

# 3. Load environment
source .env.staging

# 4. Build & start services
docker-compose -f infra/docker/docker-compose.yml build
docker-compose -f infra/docker/docker-compose.yml up -d

# 5. Run database migrations
docker-compose exec app Rscript -e "
  source('src/utils/db_migrate.R')
  run_migrations()
"

# 6. Health check
sleep 10
curl -f http://localhost:3838 || exit 1

# 7. Smoke tests
docker-compose exec app Rscript -e "testthat::test_dir('tests/smoke')"
```

### Deploy to Production

```bash
# 1. Create release tag (locally)
git tag -a v1.1.0 -m "Release v1.1.0"
git push origin main v1.1.0

# GitHub Actions triggers automatically:
# - Runs full test suite
# - Builds Docker image
# - Stores image in Docker Hub
# - SSH deploys to production

# 2. Monitor deployment (optional)
ssh deploy@prod.example.com
docker-compose -f infra/docker/docker-compose.yml logs -f app
```

---

## Manual Deployment (Non-Docker)

### Prerequisites
```bash
# R 4.3+
R --version

# PostgreSQL 14+
psql --version

# Node.js 16+ (optional, for asset pipeline)
node --version
```

### Install & Start

```bash
# 1. Install R dependencies
cd "PA design App"
Rscript -e "renv::restore()"

# 2. Database setup
psql -U postgres -c "CREATE DATABASE pa_design_app"
psql -U postgres -d pa_design_app -f database/01_schema.sql

# 3. Load initial data
psql -U postgres -d pa_design_app -f database/seeds/01_init.sql

# 4. Start application (foreground)
Rscript -e "shiny::runApp('src/app.R', port=3838, host='0.0.0.0')"

# OR with systemd (background)
# Create /etc/systemd/system/pa-design-app.service
# See systemd-unit.service example below
```

### Systemd Unit File

```ini
# /etc/systemd/system/pa-design-app.service
[Unit]
Description=PA Design App
After=network.target postgresql.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=10
User=www-data
WorkingDirectory=/opt/pa-design-app
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
EnvironmentFile=/etc/pa-design-app/.env.production
ExecStart=/usr/bin/Rscript -e "shiny::runApp('src/app.R', port=3838, host='0.0.0.0')"

[Install]
WantedBy=multi-user.target
```

**Start service**:
```bash
sudo systemctl enable pa-design-app
sudo systemctl start pa-design-app
sudo systemctl status pa-design-app
```

---

## Reverse Proxy Setup

### Nginx

```nginx
# /etc/nginx/sites-available/pa-design-app
upstream shiny_backend {
  server 127.0.0.1:3838;
}

server {
  listen 80;
  listen [::]:80;
  server_name app.example.com;

  # Redirect HTTP → HTTPS
  return 301 https://$server_name$request_uri;
}

server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name app.example.com;

  ssl_certificate /etc/letsencrypt/live/app.example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/app.example.com/privkey.pem;

  # Security headers
  add_header Strict-Transport-Security "max-age=31536000" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-Frame-Options "SAMEORIGIN" always;

  # Compression
  gzip on;
  gzip_vary on;
  gzip_min_length 1024;
  gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss;

  # Proxy
  location / {
    proxy_pass http://shiny_backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 86400;
  }

  # Static assets (optional, if served separately)
  location /assets {
    alias /opt/pa-design-app/assets;
    expires 1y;
    add_header Cache-Control "public, immutable";
  }
}
```

**Enable**:
```bash
sudo ln -s /etc/nginx/sites-available/pa-design-app /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Apache2

```apache
# /etc/apache2/sites-available/pa-design-app.conf
<VirtualHost *:443>
  ServerName app.example.com

  SSLEngine on
  SSLCertificateFile /etc/letsencrypt/live/app.example.com/fullchain.pem
  SSLCertificateKeyFile /etc/letsencrypt/live/app.example.com/privkey.pem

  <IfModule mod_proxy.c>
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:3838/ timeout=600
    ProxyPassReverse / http://127.0.0.1:3838/

    # WebSocket support
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/?(.*) "ws://127.0.0.1:3838/$1" [P,L]
  </IfModule>

  Header set Strict-Transport-Security "max-age=31536000"
  Header set X-Content-Type-Options "nosniff"
</VirtualHost>

<VirtualHost *:80>
  ServerName app.example.com
  Redirect permanent / https://app.example.com/
</VirtualHost>
```

**Enable**:
```bash
sudo a2ensite pa-design-app
sudo a2enmod proxy proxy_http rewrite headers
sudo apache2ctl configtest
sudo systemctl reload apache2
```

---

## Database Management

### Backup

```bash
# Full backup
pg_dump -U postgres pa_design_app > backup_$(date +%Y%m%d_%H%M%S).sql

# Compressed backup
pg_dump -U postgres pa_design_app | gzip > backup_$(date +%Y%m%d_%H%M%S).sql.gz

# With Docker
docker-compose exec postgres pg_dump -U postgres pa_design_app > backup.sql
```

### Restore

```bash
# From SQL file
psql -U postgres pa_design_app < backup.sql

# From compressed file
gunzip -c backup.sql.gz | psql -U postgres pa_design_app

# With Docker
docker-compose exec -T postgres psql -U postgres pa_design_app < backup.sql
```

### Maintenance

```bash
# Connect to DB
psql -U postgres pa_design_app

# List tables
\dt

# Analyze performance
ANALYZE;

# Vacuum (cleanup)
VACUUM ANALYZE;

# Check table sizes
SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

---

## Monitoring & Logging

### Docker Logs

```bash
# Stream app logs
docker-compose logs -f app

# View database logs
docker-compose logs -f postgres

# View specific lines
docker-compose logs --tail=100 app

# Timestamp filters
docker-compose logs --since 2024-01-01 --until 2024-01-02 app
```

### Application Logs

```bash
# Real-time
tail -f logs/app.log

# Search for errors
grep ERROR logs/app.log

# By date
sed -n '/2026-04-02/,/2026-04-03/p' logs/app.log | less
```

### Health Checks

```bash
# HTTP endpoint
curl http://localhost:3838

# Database connectivity
psql -U postgres -d pa_design_app -c "SELECT version();"

# Chroma vector DB
curl http://localhost:8000/api/v1/collections

# Check system resources
docker stats pa-design-app-app-1
```

---

## Troubleshooting

| Issue | Solution |
|---|---|
| App won't start | `docker-compose logs app`; check `.env` file |
| Database connection timeout | Verify `DB_HOST`, `DB_PORT` in `.env`; check firewall |
| Slow response times | Check database query logs; profile JavaScript canvas |
| WebSocket errors | Ensure proxy supports WebSocket upgrade; check nginx/Apache config |
| Out of disk space | Clean Docker images (`docker system prune`); archive old logs |
| High memory usage | Restart app; check for memory leaks in R code |

---

## Rollback Procedure

```bash
# If deployment fails

# 1. Identify last stable version
git log --oneline | head -5

# 2. Rollback Docker containers
git checkout v1.0.1
docker-compose build
docker-compose up -d

# 3. Verify health
curl http://localhost:3838

# 4. Restore database (if needed)
psql -U postgres pa_design_app < backup_stable.sql
```

---

## Post-Deployment Validation

```bash
# 1. Health check
curl -f http://app.example.com/

# 2. Database connectivity
# (check app logs for DB errors)

# 3. UI functional test
# - Login (if auth enabled)
# - Load PA lineup
# - Run calculation
# - Export PDF

# 4. Performance baseline
# - API response time (p95 < 500ms)
# - Database query time (p95 < 200ms)

# 5. Error monitoring
# - Check application error logs
# - Verify alerting system notifications
```

---

**Last Updated**: 2026-04-02
