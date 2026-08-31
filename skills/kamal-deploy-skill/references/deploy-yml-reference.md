# deploy.yml Structure Reference

Configuration is read from `config/deploy.yml`. Destination-specific overrides are merged from `config/deploy.<destination>.yml`.

## Required Settings

```yaml
service: myapp          # Container name prefix; must be unique per server
image: user/myapp       # Docker registry image path (without tag)
```

## Servers

```yaml
servers:
  # Simple form — all servers are the primary web role:
  - 192.168.1.1
  - 192.168.1.2

  # Or role-based form:
  web:
    hosts:
      - 192.168.1.1
    proxy:
      ssl: true
      host: example.com
      app_port: 3000
      healthcheck:
        path: /health
        interval: 3
        timeout: 3
      response_timeout: 30
      forward_headers: true
  worker:
    hosts:
      - 192.168.1.2
    cmd: bundle exec sidekiq
    proxy: false       # Workers don't need the proxy
```

## Registry

```yaml
registry:
  server: ghcr.io           # Optional; defaults to Docker Hub
  username: myuser           # Or use an env var reference
  password:
    - KAMAL_REGISTRY_PASSWORD   # Loaded from .kamal/secrets
```

## Environment Variables

```yaml
env:
  clear:
    DATABASE_HOST: db.internal
    PORT: "3000"
  secret:
    - DATABASE_PASSWORD    # Loaded from .kamal/secrets; stored in encrypted env file on host
    - SECRET_KEY
```

## Accessories

```yaml
accessories:
  postgres:
    image: postgres:16
    host: 192.168.1.1          # Or hosts: [..] or role: web
    port: "127.0.0.1:5432:5432"
    env:
      clear:
        POSTGRES_USER: app
        POSTGRES_DB: myapp_production
      secret:
        - POSTGRES_PASSWORD
    directories:
      - postgres-data:/var/lib/postgresql/data
    files:
      - config/postgres.conf:/etc/postgresql/postgresql.conf
    options:
      restart: always

  redis:
    image: redis:7-alpine
    host: 192.168.1.1
    port: "127.0.0.1:6379:6379"
    directories:
      - redis-data:/data
    cmd: redis-server --appendonly yes
```

## Proxy

```yaml
proxy:
  ssl: true                   # Enable Let's Encrypt TLS
  host: example.com           # Domain name
  app_port: 3000              # Port the app container listens on
  healthcheck:
    path: /up
    interval: 3               # Seconds between checks
    timeout: 3                # Per-request timeout
  response_timeout: 30        # Request completion window (seconds)
  forward_headers: true       # Forward X-Forwarded-For, X-Forwarded-Proto
  ssl_redirect: true          # Redirect HTTP to HTTPS (default: true when ssl: true)
  # Custom SSL certificates (for multi-host or existing CA):
  # ssl:
  #   certificate_pem: CERTIFICATE_PEM
  #   private_key_pem: PRIVATE_KEY_PEM
```

## Builder

```yaml
builder:
  arch: amd64                 # amd64, arm64, or [amd64, arm64] for multi-arch
  dockerfile: Dockerfile      # Path to Dockerfile (default: Dockerfile)
  target: runner              # Multi-stage build target
  context: .                  # Build context (default: clean Git clone)
  args:
    BUILD_VERSION: 1.0.0
  secrets:
    - BUILD_SECRET            # Loaded from .kamal/secrets for build
  cache:
    type: registry            # or gha (GitHub Actions)
    options: mode=max
  remote: ssh://builder@build-server.example.com   # Remote builder
```

## SSH

```yaml
ssh:
  user: deploy               # SSH user (default: root)
  keys:
    - ~/.ssh/id_rsa           # SSH key paths
  keys_only: true
  proxy: ssh://bastion.example.com   # SSH proxy/jump host
```

## Volumes

```yaml
volumes:
  - myapp-storage:/app/storage
  - /host/path:/container/path
```

## Boot Behavior

```yaml
readiness_delay: 7           # Seconds to wait after container starts (default: 7)
deploy_timeout: 30           # Maximum deploy duration in seconds (default: 30)
drain_timeout: 30            # Graceful shutdown period in seconds (default: 30)
retain_containers: 5         # Old images to keep (default: 5)
```

## Logging

```yaml
logging:
  driver: json-file
  options:
    max-size: 100m
    max-file: "10"
```

## Aliases

```yaml
aliases:
  console: app exec -i --reuse 'bin/console'
  shell: app exec -i --reuse bash
  logs: app logs --follow
  migrate: app exec --reuse 'bin/rails db:migrate'
```

Use aliases via the wrapper-oriented operator flow in this skill when writing operator docs; when editing deploy.yml itself, keep the underlying Kamal alias semantics in mind.

## Hooks Path

```yaml
hooks_path: .kamal/hooks     # Default path for hooks
```

## Multi-Destination Example

`config/deploy.yml` (production defaults):

```yaml
service: myapp
image: user/myapp
servers:
  web:
    hosts:
      - 10.0.1.10
    proxy:
      ssl: true
      host: myapp.com
      app_port: 3000
```

`config/deploy.staging.yml` (staging overrides):

```yaml
servers:
  web:
    hosts:
      - 10.0.2.10
    proxy:
      ssl: true
      host: staging.myapp.com
      app_port: 3000
env:
  clear:
    APP_ENV: staging
```

Deploy to staging: `bin/deploy -d staging`
Deploy to production: `bin/deploy` (no `-d` flag uses `deploy.yml` defaults)

## .kamal/secrets Format

```bash
# Reference a shell environment variable:
KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD

# Run a command to get the value:
RAILS_MASTER_KEY=$(cat config/master.key)

# For destination-specific secrets, use .kamal/secrets.staging:
# .kamal/secrets-common — shared across all destinations
```

All secrets listed under `env.secret` in `deploy.yml` must have matching entries in `.kamal/secrets`.
