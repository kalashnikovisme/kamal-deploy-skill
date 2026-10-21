# Example: Two Kamal-Managed Units From One Repo (genuinely separate deployments)

**Before reaching for this pattern, run `agents/patterns/deployment-boundary.md`'s boundary step.** `api/` and `worker/` sharing one release image as two roles in a single `config/deploy.yml` (see `examples/web-with-worker.md`) is the preferred default when they're part of one product, run on the same infrastructure, and are released together — that is not this example. This file shows the case where the boundary step found a genuine Level 3 reason to keep two Deployable Units as **separate** Kamal deployments instead — for example, `api/` and `worker/` are independently owned, ship on unrelated release cadences the team wants decoupled, or can't reasonably share a build. State that concrete reason before generating this layout; "they're in different directories" is not one. Mechanics are detailed in `agents/patterns/multi-service-repo.md`; this file shows the resulting files.

Layout:

```
api/Dockerfile
worker/Dockerfile
config/deploy.api.yml
config/deploy.worker.yml
.kamal/secrets-api
.kamal/secrets-worker
```

`config/deploy.api.yml`:

```yaml
service: myapp-api
image: myuser/myapp-api

servers:
  web:
    hosts:
      - 192.0.2.10
    proxy:
      ssl: true
      host: api.myapp.example.com
      app_port: 3001

registry:
  username: myuser
  password:
    - KAMAL_REGISTRY_PASSWORD

secrets_path: .kamal/secrets-api
hooks_path: .kamal/hooks-api   # only if this unit needs its own hooks

env:
  secret:
    - DATABASE_URL

builder:
  arch: amd64
```

`config/deploy.worker.yml`:

```yaml
service: myapp-worker
image: myuser/myapp-worker

servers:
  workers:
    hosts:
      - 192.0.2.10
    proxy: false

registry:
  username: myuser
  password:
    - KAMAL_REGISTRY_PASSWORD

secrets_path: .kamal/secrets-worker

env:
  secret:
    - DATABASE_URL
    - REDIS_URL

builder:
  arch: amd64
```

Usage — every command needs `-c`/`--config-file` to pick the unit:

```bash
kamal deploy -c config/deploy.api.yml
kamal deploy -c config/deploy.worker.yml
```

Notes:
- `-c`/`--config-file` is real in Kamal's source (`lib/kamal/cli/base.rb` in `basecamp/kamal`) but not documented on the public docs site as of this writing — don't assume a future Kamal version keeps it without re-checking the source if something looks off.
- `secrets_path`/`hooks_path` default to plain `.kamal/secrets`/`.kamal/hooks` resolved from the current working directory, **not** relative to the `-c` path — every unit beyond the first MUST set these explicitly, or it will silently read/write the other unit's secrets/hooks files.
- `service:` and `image:` must also differ per unit (`myapp-api` vs. `myapp-worker` here) — Kamal uses `service` as the container name prefix, and two units sharing one would collide on the same server.
- This pattern only applies once `agents/patterns/deployment-boundary.md` has placed a unit in a genuinely separate ("Level 3") deployment — a repo that merely contains multiple directories, with only one selected for Kamal or multiple consolidated into one deployment's roles, stays on the plain `config/deploy.yml` path (see `tests/fixtures/multi-deployable-unit/EXPECTED.md` and `tests/fixtures/deployment-boundary/EXPECTED.md` for worked cases).
