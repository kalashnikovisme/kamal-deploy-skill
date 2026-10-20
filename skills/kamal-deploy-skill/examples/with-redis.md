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
    REDIS_URL: redis://192.0.2.10:6379/0

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
- `directories:` persists Redis's data across restarts. Omit it only if Redis is used purely as an ephemeral cache where losing data on restart is acceptable.
- As with Postgres, `port: "127.0.0.1:6379:6379"` keeps Redis unreachable from outside the host. Never remove the `127.0.0.1:` prefix on a production accessory.
- If a background worker role (`examples/web-with-worker.md`) also needs `REDIS_URL`, add it to that role's own `env` block too — `env` is not automatically shared across roles unless defined at the top level as shown here.
