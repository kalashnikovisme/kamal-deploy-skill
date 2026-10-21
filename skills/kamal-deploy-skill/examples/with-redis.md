# Example: Web + Redis Accessory

Redis as a Kamal-managed accessory, typically used for caching, job queues (Sidekiq, BullMQ, Celery), or session storage. This example demonstrates the Kamal-managed path once that ownership decision has been made (SKILL.md Step 4b #6) — depending on Redis does not by itself mean Kamal should provision it; an app connecting to an existing/external Redis instance instead just needs `REDIS_URL` as a secret, with no `accessories:` block at all.

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
    # myapp-redis is the accessory's container/service name on Kamal's shared
    # "kamal" Docker network - NOT the server's public IP. See notes below.
    REDIS_URL: redis://myapp-redis:6379/0

accessories:
  redis:
    image: redis:7-alpine
    host: 192.0.2.10
    port: "127.0.0.1:6379:6379"   # bind to loopback only
    directories:
      - redis-data:/data

builder:
  arch: amd64
```

Notes:
- **`REDIS_URL` here is derived clear configuration, not a secret** (see `agents/patterns/derived-deployment-values.md`) - this accessory has no password, so the URL contains no secret material and belongs in `env.clear`, generated directly from topology. It must never be placed in the secrets backend or left as a `TODO_FILL_IN` placeholder - there's nothing for the user to supply.
- **`REDIS_URL` must point at the accessory's container-network hostname (`<service>-redis`), not the server's public IP or `127.0.0.1`.** The app container and the Redis accessory share Kamal's `kamal` Docker network by default and resolve each other there by container name on Redis's internal port (`6379`).
- `port: "127.0.0.1:6379:6379"` is a separate, host-level binding for something outside Docker (e.g. a local `redis-cli` on the host) — it doesn't affect container-to-container traffic and must not be loosened to a public interface to make the app reachable; the app never needs it.
- `directories:` persists Redis's data across restarts. Omit it only if Redis is used purely as an ephemeral cache where losing data on restart is acceptable.
- If a background worker role (`examples/web-with-worker.md`) also needs `REDIS_URL`, add it to that role's own `env` block too — `env` is not automatically shared across roles unless defined at the top level as shown here.
- If the app and Redis accessory run on **different** hosts, see `with-postgres.md`'s note on the same issue — the `kamal` network doesn't span hosts, and this becomes the same private-networking decision as `agents/patterns/multi-service-repo.md`'s "Inter-service communication" section, not a reason to fall back to the public IP.

### Variant: authenticated Redis accessory

If the accessory is configured with a password (`requirepass`/`REDIS_PASSWORD` or equivalent), the category changes: only the password is a secret primitive, and `REDIS_URL` becomes a **derived secret value** built from it, the same way `DATABASE_URL` is derived in `examples/with-postgres.md`.

```yaml
env:
  secret:
    - REDIS_PASSWORD
    - REDIS_URL

accessories:
  redis:
    image: redis:7-alpine
    host: 192.0.2.10
    port: "127.0.0.1:6379:6379"
    cmd: redis-server --requirepass "$REDIS_PASSWORD"
    env:
      secret:
        - REDIS_PASSWORD
    directories:
      - redis-data:/data
```

`.kamal/secrets`:

```sh
REDIS_PASSWORD=<primitive from the selected secrets backend>
REDIS_URL="redis://default:$(urlencode "$REDIS_PASSWORD")@myapp-redis:6379/0"
```

Store only `REDIS_PASSWORD` in the secrets backend - never an independently-entered `REDIS_URL` alongside it. Percent-encode the password component exactly as described in `examples/with-postgres.md`.
