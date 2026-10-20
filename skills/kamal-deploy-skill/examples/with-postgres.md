# Example: Web + PostgreSQL Accessory

Kamal manages the database as an "accessory" — a long-running container Kamal deploys and restarts, but doesn't version/roll like the app image.

```yaml
service: myapp
image: myuser/myapp

servers:
  web:
    hosts:
      - 192.0.2.10
    proxy:
      ssl: true
      host: myapp.example.com
      app_port: 3000

registry:
  username: myuser
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    DATABASE_URL: postgres://app:${POSTGRES_PASSWORD}@192.0.2.10:5432/myapp_production
  secret:
    - POSTGRES_PASSWORD

accessories:
  postgres:
    image: postgres:16
    host: 192.0.2.10
    port: "127.0.0.1:5432:5432"   # bind to loopback only — never expose Postgres publicly
    env:
      clear:
        POSTGRES_USER: app
        POSTGRES_DB: myapp_production
      secret:
        - POSTGRES_PASSWORD
    directories:
      - postgres-data:/var/lib/postgresql/data

builder:
  arch: amd64
```

Notes:
- `port: "127.0.0.1:5432:5432"` binds Postgres to localhost on the host — only the app containers on that same server can reach it. Do not drop the `127.0.0.1:` prefix.
- `directories:` maps a named Docker volume so data survives accessory restarts/redeploys. Without it, `kamal accessory reboot postgres` would wipe the database.
- `POSTGRES_PASSWORD` must be in `.kamal/secrets`, never hardcoded in `deploy.yml`.
- If the app and Postgres run on different hosts, replace `192.0.2.10` in `DATABASE_URL` with the Postgres host's actual address and open the port between the two hosts instead of binding to loopback.
