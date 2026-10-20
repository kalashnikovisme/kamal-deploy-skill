# Multi-Service Repo: Running Several Kamal-Managed Units From One Repository

This pattern applies only when `agents/patterns/deployable-units.md` step 5 produced a **Kamal-managed subset with more than one unit**. If only one unit was selected, ignore this file entirely — use the plain single-app flow (`config/deploy.yml`, no `-c` flag, no suffixed paths).

## Mechanism (verified against Kamal's source, not just its public docs)

Kamal's CLI exposes a global option, independent of destinations:

```
-c, --config-file   Path to config file   (default: "config/deploy.yml")
```

This is distinct from `-d`/`--destination`, which selects a `config/deploy.<destination>.yml` override **merged into** whatever `--config-file` points at. The two compose: `-c config/deploy.api.yml -d staging` reads `config/deploy.api.yml` merged with `config/deploy.api.staging.yml`.

Each `deploy.yml` also accepts its own `secrets_path` and `hooks_path` keys (defaulting to `.kamal/secrets` and `.kamal/hooks`, resolved relative to the current working directory — **not** relative to `--config-file`'s location). Because the defaults are shared repo-wide regardless of which `-c` file is active, **every additional Kamal-managed unit beyond the first must set its own `secrets_path`/`hooks_path`**, or two units' secrets/hooks will collide on disk.

Source: `lib/kamal/cli/base.rb` and `lib/kamal/configuration.rb` in basecamp/kamal (verified during Phase 4 of the `learn_from_project` workflow; the public docs site documents destinations but not `-c`/`--config-file` as of this check — re-verify if Kamal's CLI changes).

## Layout

For each Kamal-managed unit, generate:

```
<unit-root>/Dockerfile
config/deploy.<unit>.yml          # NOT config/deploy.yml — avoids the first unit silently becoming "the default"
.kamal/secrets-<unit>
.kamal/hooks-<unit>/               # only if the unit needs pre-deploy/post-deploy hooks
```

In `config/deploy.<unit>.yml`:

```yaml
service: <unit>                    # must be unique across units sharing a server
image: <REGISTRY_USER>/<unit>

secrets_path: .kamal/secrets-<unit>
hooks_path: .kamal/hooks-<unit>    # omit if the unit has no hooks

servers:
  web:
    hosts:
      - <SERVER_IP>
    proxy:
      ssl: true
      host: <UNIT_DOMAIN_OR_SUBDOMAIN>
      app_port: <UNIT_PORT>
# ...the rest of the file follows the unit's own stack recipe exactly as it would for a single-app repo.
```

`builder.context` defaults to the directory containing the config file's build context, which for a unit living at `<unit-root>` inside the repo means the Dockerfile and build context must be generated **inside `<unit-root>`**, same as a single-app repo rooted there — do not generate a Dockerfile at the repo root for a sub-unit.

## bin/ wrappers in a multi-unit repo

If SKILL.md Step 5.5 creates wrapper scripts, each unit gets its own wrapper set or a single wrapper set gains a required unit argument — pick one explicitly with the user rather than guessing:

- **Per-unit wrappers** (`bin/deploy-api`, `bin/deploy-worker`): each wrapper hardcodes its own `-c config/deploy.<unit>.yml` and still forwards every other flag (`-q`/`--quiet` etc.) via `"$@"`, per the wrapper rules in SKILL.md Step 5.5.
- **Single wrapper with a required first positional argument** (`bin/deploy api ...`): the wrapper maps the first argument to the right `-c` value, then forwards the rest of `"$@"` unmodified. Only do this if the user explicitly prefers one entrypoint; it adds a parsing step that per-unit wrappers avoid.

Either way, the wrapper-forwarding contract in SKILL.md Step 5.5 is non-negotiable: once the `-c` value (and any destination) is resolved, every remaining argument — `-q`/`--quiet` included — must still reach `kamal` verbatim.

## Documenting the Kamal-managed subset (SKILL.md Step 6)

When more than one Deployable Unit was discovered (regardless of how many ended up Kamal-managed), the deployment documentation must include a short table listing **every discovered unit**, not just the Kamal-managed ones, so the setup is legible as a whole:

```markdown
## Deployable Units

| Unit | Path | Managed by Kamal | Notes |
|---|---|---|---|
| api | `api/` | Yes — `config/deploy.api.yml` | |
| worker | `worker/` | Yes — `config/deploy.worker.yml` | shares server with `api` |
| frontend | `frontend/` | No | already deployed on Vercel; untouched by this setup |
```

This table is the representation of "a Kamal-managed subset" — it must always show the units that were *not* selected, marked as not managed here, rather than omitting them and implying they don't exist.

## Shared accessories (Postgres/Redis) across units

This section assumes the ownership question (SKILL.md Step 4b #6) has already resolved to "Kamal-managed accessory" for the dependency in question - both units merely depending on Postgres is not by itself a reason to create one. Once that's established: if two Kamal-managed units in the same repo both depend on the same Kamal-managed accessory (e.g. both `api` and `worker` use Postgres), do not define the accessory twice. Define it once, in whichever unit's `deploy.yml` is deployed first / considered primary, and point the other unit's `secret`/`clear` env at the same connection details. Note this explicitly in the documentation table above so it's clear which unit "owns" the accessory's lifecycle (`kamal accessory boot/reboot/remove` should be run against that unit's config file only). If instead the dependency is owned externally, there's nothing to share here - each unit just points at the same external connection string.

## Inter-service communication (verified against current Kamal docs/behavior)

This section applies whenever one Kamal-managed unit's app code or config needs to reach another **separately configured** Kamal service - a different `deploy.yml`/`service:` name, whether on the same server or a different one. It does not apply to app-container-to-accessory reachability within one unit's own `deploy.yml` - see SKILL.md Step 4b #6 for that.

**Never invent a container hostname from a naming convention** (e.g. assuming a sibling service's container is reachable as `api-web-1`, `<service>-web-1`, or similar). Kamal does not document a stable discovery mechanism for resolving one separately-configured service's current container from another service's config or code, and container names/versions are rotated on every rolling deploy (old containers are retained briefly for rollback, then removed - see `retain_containers`). A guessed hostname that happens to work today is not a supported mechanism and will silently break on the next deploy, a host rebuild, or a `kamal-proxy` change. Do not emit a guessed hostname even with an `UNVERIFIED`/`TODO` comment attached - a comment does not stop it from being wired into working code that will be deployed and relied on.

**Default, supported mechanism - go through `kamal-proxy` like any other client:** each Kamal service already has a stable, documented public entry point - its `proxy.host` domain, served over HTTPS by `kamal-proxy`, which always routes to the current healthy container regardless of rolling deploys. Unless a faster or private channel is specifically required and solved below, one service should call another the same way a browser would: `https://<other-service's-proxy-host>/...`. This is stable across deploys by construction (it's the same mechanism load balancing production traffic) and works whether the two services are on the same host or different hosts.

**Distinguish the communication shapes before picking anything:**

- **Browser/client → service**: always the public `proxy.host` domain over HTTPS. Not in question here.
- **Server/container → another service, same or different host, both publicly routable**: the public `proxy.host` domain over HTTPS is the default answer above - simplest, documented, stable. The cost is an extra hop through the proxy/TLS versus a theoretical direct path; that cost is usually acceptable and should be the default unless measured otherwise.
- **Server/container → another service, where exposing it publicly is undesirable** (an internal API that shouldn't be reachable from the internet at all): Kamal itself does not provide a documented private stable cross-service discovery mechanism for this case. Do not invent one (no guessed container names, no assumed shared Docker network across separately-configured services). This requires its own explicit infrastructure decision - e.g. a private network/VPN/overlay (Tailscale, WireGuard, a cloud provider's private networking) between the hosts, or a firewall rule restricting the proxy's port to known source IPs plus a dedicated non-public port/host binding. Treat the choice of mechanism as a blocker: ask the user, or escalate to `agents/recipes/terraform.md` if private networking needs to be provisioned, rather than falling back to a guessed hostname to "make it work for now."

**If a target-relevant blocker from this section can't be resolved**, do not generate the dependent config/code with a guessed value. State the gap and what's needed to resolve it (which mechanism, what access/credentials) instead of shipping something that looks complete but isn't verified.

**Regression protection:** `tests/fixtures/multi-deployable-unit/EXPECTED.md`'s "Variant: both units Kamal-managed" section requires an agent asked to wire `apps/web` → `apps/api` communication to propose the public `proxy.host` URL (or explicitly escalate the private-networking question) and to reject any `apps/api-web-1`-style guessed hostname, even with a disclaimer comment attached.

## When NOT to use this pattern

- Exactly one Kamal-managed unit, regardless of how many total Deployable Units were discovered — use the plain single-app flow.
- Staging vs. production variants of the *same* unit — that's `-d`/`--destination` (see `examples/multi-destination.md`), not this pattern.
