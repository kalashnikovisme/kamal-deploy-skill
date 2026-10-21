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
  secret:
    # DATABASE_URL is a derived secret value, not an independent one - it is built
    # in .kamal/secrets from POSTGRES_PASSWORD plus the accessory topology below.
    # It must live under env.secret (it contains the password), never env.clear -
    # deploy.yml is parsed as YAML/ERB, not shell, so a literal "${POSTGRES_PASSWORD}"
    # placed in env.clear would reach the container unexpanded.
    - POSTGRES_PASSWORD
    - DATABASE_URL

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

`.kamal/secrets` (not committed unless every line is command substitution from a committed encrypted backend - see `agents/patterns/secrets-backend.md`):

```sh
POSTGRES_PASSWORD=<primitive from the selected secrets backend>
DATABASE_URL="postgresql://app:$(urlencode "$POSTGRES_PASSWORD")@myapp-postgres:5432/myapp_production"
```

Notes:
- **`DATABASE_URL` is a derived secret value (see `agents/patterns/derived-deployment-values.md`), not an independent secret.** The user/backend supplies only `POSTGRES_PASSWORD`; `DATABASE_URL` is constructed in `.kamal/secrets` from that primitive plus the topology below, at secret-resolution time - never stored as its own independent backend entry, and never written to disk as plaintext outside that resolution step.
- The password component must be **percent-encoded** before interpolation (shown above via `urlencode`, illustrative of the requirement, not a specific tool mandate) - a generated or user-supplied password containing `@ : / ? # %` would otherwise break the URL or get misparsed. Don't work around this by restricting generated passwords to a weak character set; fix the encoding.
- **`DATABASE_URL` must point at the accessory's container-network hostname (`<service>-postgres`, Kamal's default accessory container name), not the server's public IP or `127.0.0.1`.** The app container and the Postgres accessory both attach to Kamal's shared `kamal` Docker network by default, and resolve each other there by container name on the accessory's *internal* port (`5432`) — this is how the app container actually reaches it.
- `port: "127.0.0.1:5432:5432"` is a **separate, host-level** binding — it controls whether something outside Docker on that same machine (an admin's local `psql`, a monitoring agent) can reach Postgres via the host's loopback interface. It has no effect on container-to-container traffic on the `kamal` network and must never be changed to the host's public IP/`0.0.0.0` to "let the app reach it" — the app doesn't need it loosened at all, and doing so exposes Postgres publicly instead.
- `directories:` maps a named Docker volume so data survives accessory restarts/redeploys. Without it, `kamal accessory reboot postgres` would wipe the database.
- `POSTGRES_PASSWORD` must be in the selected secrets backend, never hardcoded in `deploy.yml`.
- If the app and Postgres accessory are configured to run on **different** hosts, the `kamal` network no longer spans them and container-name resolution doesn't apply — this needs the same private-networking decision as cross-service communication between separately configured units (see `agents/patterns/multi-service-repo.md`'s "Inter-service communication" section). Don't default back to the public IP in that case either; resolve the private-networking question first.
- If `DATABASE_URL` instead points at an externally-managed database (Supabase, Neon, RDS, etc.), none of the derivation above applies - store the provider-supplied `DATABASE_URL` as a single opaque secret primitive and don't attempt to decompose or reconstruct it (see `agents/patterns/derived-deployment-values.md`'s external-database exception).

**Regression protection:** `agents/patterns/multi-service-repo.md`'s shared-accessory section and SKILL.md Step 4b #6 both point here as the authoritative reachable-hostname form; a generated `DATABASE_URL` using the server's public IP alongside a `127.0.0.1`-bound accessory port is inconsistent and must be treated as a defect, not a project-specific choice. An independently-stored `DATABASE_URL` sitting alongside `POSTGRES_PASSWORD` in the secrets backend, when the former is demonstrably derivable from the latter, is likewise a defect (`DUPLICATED_DERIVED_SECRET`) - see `agents/patterns/derived-deployment-values.md`.
