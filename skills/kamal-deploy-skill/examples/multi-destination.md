# Example: Staging + Production Destinations

Kamal's `-d`/`--destination` flag merges `config/deploy.<destination>.yml` on top of `config/deploy.yml`. This is a single Deployable Unit with two environments — not to be confused with multiple Deployable Units (see `examples/multi-service-repo.md`), which uses `-c`/`--config-file` instead.

`config/deploy.yml` (shared defaults):

```yaml
service: myapp
image: myuser/myapp

registry:
  username: myuser
  password:
    - KAMAL_REGISTRY_PASSWORD

builder:
  arch: amd64

env:
  clear:
    RAILS_ENV: production
  secret:
    - SECRET_KEY_BASE
```

`config/deploy.staging.yml` (overrides merged in for `-d staging`):

```yaml
servers:
  web:
    hosts:
      - 192.0.2.20
    proxy:
      ssl: true
      host: staging.myapp.example.com
      app_port: 3000

env:
  clear:
    RAILS_ENV: staging
```

`config/deploy.production.yml` (overrides merged in for `-d production`):

```yaml
servers:
  web:
    hosts:
      - 192.0.2.10
    proxy:
      ssl: true
      host: myapp.example.com
      app_port: 3000
```

Usage:

```bash
kamal deploy -d staging
kamal deploy -d production
```

Notes:
- Secrets can also be split per destination: `.kamal/secrets-staging` / `.kamal/secrets-production`, loaded automatically when `-d` is passed, alongside the shared `.kamal/secrets-common` if present.
- Don't put `servers:` in the base `deploy.yml` if every destination needs different hosts — leave it only in the per-destination files, as shown here, to avoid an unused default that could be deployed by accident.
- Any `bin/deploy` wrapper must forward `-d`/`--destination` untouched, the same way it forwards `-q`/`--quiet` (see `references/kamal-commands.md`).
