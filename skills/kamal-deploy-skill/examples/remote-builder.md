# Example: Remote Builder

Build the image on a remote host instead of the operator's local machine — useful when the local machine can't build for the target architecture (e.g. building `amd64` images from an Apple Silicon laptop) or is too slow/low-bandwidth for a large build.

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

builder:
  arch: amd64
  remote: ssh://build-user@192.0.2.30
```

Notes:
- `builder.remote` points at a dedicated build host over SSH — it must have Docker installed and be reachable via the same SSH credentials Kamal already uses for deploys (`ssh.*` config, if customized).
- A remote builder changes **where** the build runs, not the resulting image's size — it does not help with a large image problem (see `agents/patterns/large-build-artifacts.md`), only with build speed/architecture mismatches.
- `builder.arch` can list multiple architectures (`arch: [amd64, arm64]`) for multi-arch images; this is independent of whether the build itself is local or remote.
- One of the actual deploy target servers can double as the build host if a separate build machine isn't available — just point `builder.remote` at that server's SSH address.
