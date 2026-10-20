# Example: Minimal Single Web Server

The simplest possible Kamal setup: one service, one role, no accessories. Use this as the baseline before layering on workers, accessories, or multiple destinations.

```yaml
service: myapp
image: myuser/myapp

servers:
  - 192.0.2.10

proxy:
  ssl: true
  host: myapp.example.com
  app_port: 3000
  healthcheck:
    path: /health
    interval: 3
    timeout: 3

registry:
  username: myuser
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    RAILS_ENV: production
  secret:
    - SECRET_KEY_BASE

builder:
  arch: amd64
```

Notes:
- The simple `servers:` list form (as opposed to role-based `servers.web.hosts`) is only valid when there is exactly one role. Switch to the role-based form the moment a worker or second role is introduced (see `examples/web-with-worker.md`).
- `app_port` must match the port the application actually listens on inside the container — confirm this from the stack recipe, don't assume 3000.
