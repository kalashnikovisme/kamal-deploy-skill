# Example: Web + Background Worker Role

Two roles from the same image: a `web` role behind the proxy, and a `workers` role running a background job processor with no proxy exposure.

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
      healthcheck:
        path: /health
        interval: 3
        timeout: 3
  workers:
    hosts:
      - 192.0.2.11
    cmd: bundle exec sidekiq   # or: npm run worker, python -m app.worker, etc.
    proxy: false               # workers don't serve HTTP traffic

registry:
  username: myuser
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    RAILS_ENV: production
  secret:
    - SECRET_KEY_BASE
    - REDIS_URL

builder:
  arch: amd64
```

Notes:
- `cmd:` overrides the image's default `CMD` for that role only — the Dockerfile's `CMD` is still what runs for `web`.
- `proxy: false` is required on any role that doesn't serve HTTP; otherwise kamal-proxy will try (and fail) to health-check it.
- Both roles share one `env` block here because they need the same secrets. Give a role its own `env` block if its configuration diverges.
- The worker can run on the same host as `web` (just list the same IP) if a second server isn't available — the role separation still applies.
