# Example: Web + PostgreSQL Accessory

Kamal manages the database as an "accessory" — a long-running container Kamal deploys and restarts, but doesn't version/roll like the app image. This example demonstrates the Kamal-managed path once that ownership decision has been made (SKILL.md Step 4b #6) — depending on PostgreSQL does not by itself mean Kamal should provision it; an app connecting to an existing/external PostgreSQL instance instead just needs `DATABASE_URL` as a secret, with no `accessories:` block at all.

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
    # myapp-postgres is the accessory's container/service name on Kamal's shared
    # "kamal" Docker network - NOT the server's public IP. See notes below.
    DATABASE_URL: postgres://app:${POSTGRES_PASSWORD}@myapp-postgres:5432/myapp_production
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
- **`DATABASE_URL` must point at the accessory's container-network hostname (`<service>-postgres`, Kamal's default accessory container name), not the server's public IP or `127.0.0.1`.** The app container and the Postgres accessory both attach to Kamal's shared `kamal` Docker network by default, and resolve each other there by container name on the accessory's *internal* port (`5432`) — this is how the app container actually reaches it.
- `port: "127.0.0.1:5432:5432"` is a **separate, host-level** binding — it controls whether something outside Docker on that same machine (an admin's local `psql`, a monitoring agent) can reach Postgres via the host's loopback interface. It has no effect on container-to-container traffic on the `kamal` network and must never be changed to the host's public IP/`0.0.0.0` to "let the app reach it" — the app doesn't need it loosened at all, and doing so exposes Postgres publicly instead.
- `directories:` maps a named Docker volume so data survives accessory restarts/redeploys. Without it, `kamal accessory reboot postgres` would wipe the database.
- `POSTGRES_PASSWORD` must be in `.kamal/secrets`, never hardcoded in `deploy.yml`.
- If the app and Postgres accessory are configured to run on **different** hosts, the `kamal` network no longer spans them and container-name resolution doesn't apply — this needs the same private-networking decision as cross-service communication between separately configured units (see `agents/patterns/multi-service-repo.md`'s "Inter-service communication" section). Don't default back to the public IP in that case either; resolve the private-networking question first.

**Regression protection:** `agents/patterns/multi-service-repo.md`'s shared-accessory section and SKILL.md Step 4b #6 both point here as the authoritative reachable-hostname form; a generated `DATABASE_URL` using the server's public IP alongside a `127.0.0.1`-bound accessory port is inconsistent and must be treated as a defect, not a project-specific choice.
