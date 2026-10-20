# Example: Local Registry

Use a self-hosted registry (e.g. for air-gapped deploys, or to avoid a third-party registry dependency) instead of Docker Hub/GHCR/ECR.

```yaml
service: myapp
image: myapp   # no registry-user prefix needed for a local registry

registry:
  server: localhost:5555
  username: registry-user
  password:
    - KAMAL_REGISTRY_PASSWORD

servers:
  web:
    hosts:
      - 192.0.2.10
    proxy:
      ssl: true
      host: myapp.example.com
      app_port: 3000

builder:
  arch: amd64
```

Notes:
- `registry.server` is the piece that changes — everything else in `deploy.yml` is unaffected by using a local registry.
- "Local" here means local **to the deploy process**, typically a registry container running on (or reachable from) the target server(s), not literally `localhost` on the operator's own machine — confirm with the user where the registry container actually runs before using `localhost` in this field.
- The registry container itself is usually run outside Kamal's management (e.g. via a separate `docker run registry:2` or a dedicated boot script) since Kamal doesn't manage the registry it pushes to.
- If the registry requires auth, `KAMAL_REGISTRY_PASSWORD` still goes through `.kamal/secrets` like any other registry credential — never hardcode it.
