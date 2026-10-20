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

## Inter-service communication (verified against Kamal's source, not just its public docs)

This section applies whenever one Kamal-managed unit's app code or config needs to reach another **separately configured** Kamal service - a different `deploy.yml`/`service:` name, whether on the same server or a different one. It does not apply to app-container-to-accessory reachability within one unit's own `deploy.yml` - see SKILL.md Step 4b #6 for that (accessories already have a genuinely stable identity, unlike app containers - see below).

### Verified mechanics (`lib/kamal/commands/{docker,app,proxy,accessory}.rb`, `lib/kamal/configuration/proxy/boot.rb` in basecamp/kamal)

- `kamal setup` creates exactly **one** Docker network per host, literally named `kamal` (`docker network create kamal`). Every Kamal-managed app container, accessory container, and the proxy container join this same network via `--network kamal` - regardless of which `deploy.yml`/`service:` they belong to. Separately configured services sharing a host **do** end up on the same Docker network by default; the gap is not "do they share a network" but "what stable name can they call each other by on it."
- **App containers are not stably named.** An app container's `--name` is `<service>-<role>-<destination>-<version>` (`Kamal::Configuration::Role#container_name`) - the version segment changes on every deploy, and the old container is kept briefly (`retain_containers`) then removed. Docker's embedded per-network DNS resolves containers by their current name, so a name that includes the version cannot be a stable target. This confirms the existing rule: **never** infer or hardcode a hostname like `api-web-1`/`<service>-web-1` - even disregarding where the convention came from, that name is guaranteed to stop resolving on the next deploy.
- **Accessory containers are stably named.** An accessory's `--name` is just its `service_name` (defaults to `<service>-<accessory>`, from `Kamal::Configuration::Accessory`) - never versioned, never rotated by an app deploy. This is why the accessory-reachability guidance in `examples/with-postgres.md`/`with-redis.md` (connect via `<service>-postgres`/`<service>-redis` on the `kamal` network) is correct and unaffected by this section.
- **`kamal-proxy` itself is stably named.** Exactly one `kamal-proxy` container runs per host, with the fixed container name `kamal-proxy` (`Kamal::Configuration::Proxy::Boot#container_name` - literally returns the string `"kamal-proxy"`, never versioned), also on the `kamal` network. It already tracks which app container is currently live for each configured `proxy.host` and routes by the `Host` header - the exact same mechanism that serves public traffic.

### Default networking policy: private internally, public only at required ingress boundaries

Given the above, when Deployable Unit A needs to call Deployable Unit B, evaluate in this order - do not pick a tier merely because it's the easiest to identify:

**1. Same-host internal Docker network - default when both units are on the same server.** Call through the host's own `kamal-proxy` container over the internal `kamal` network, not the public domain: target `http://kamal-proxy` (container name, resolvable on the shared network, port 80 - `kamal-proxy`'s internal listener) with the `Host` header set to B's configured `proxy.host` value. This is the verified stable mechanism: it never requires guessing B's rotating container name, it automatically tracks B's currently-live container (that's `kamal-proxy`'s whole job), and it never leaves the host or touches the public internet/TLS. Do not target B's app container name directly - it isn't stable (see above).

**2. Different hosts with private connectivity - when A and B are on separate servers that already have, or are given, a private network path.** Prefer that private path over the public internet when one exists or is explicitly provisioned (a VPN/overlay such as Tailscale/WireGuard, a cloud provider's private networking, a firewalled port restricted to known source IPs). Do not invent this infrastructure automatically - if it doesn't already exist, surface it as an explicit decision/provisioning step (escalate to `agents/recipes/terraform.md` if infrastructure needs to be created), not a thing to silently assume.

**3. Public `proxy.host` + HTTPS - fallback, used only when internal/private communication isn't the right fit:**
   - the caller cannot reach the internal/private network at all (a browser, a mobile app, a third-party webhook provider, another host with no private connectivity to this one);
   - the architecture genuinely requires the traffic to leave the internal network;
   - internal/private discovery can't be made stable or supported here for some documented reason;
   - or the user explicitly asks for public/external inter-service communication.

   When this tier is chosen, say why tiers 1-2 weren't used - don't default to it just because it's the most obviously documented route.

**Never emit a guessed/unverified hostname as a placeholder, in any tier** - "UNVERIFIED" comments do not make a guessed container name acceptable; if the right tier's exact value isn't known yet (e.g. a private network hasn't been provisioned), say so and block that piece of config/code rather than filling in something that looks complete.

### Exposure and inter-service communication are separate decisions

Determine both, independently, per Deployable Unit - never infer one from the other:

- **Exposure**: public (reachable from the internet via `proxy.host`), private/internal-only (no public `proxy.host` at all), or mixed (some routes public - e.g. a webhook endpoint - while the service is still called internally by other units for everything else).
- **Inter-service communication**: which of the three tiers above each *caller* actually uses to reach this unit.

A unit having a public endpoint (e.g. an API that receives third-party webhooks) does not mean other internal callers should go through that public endpoint - they should still use tier 1/2 above. Conversely, a unit with no public exposure at all can still be called internally via tier 1.

### Browser/client vs. server/container callers (critical for frontends)

Browser JavaScript cannot resolve `kamal-proxy` or any other Docker-network-internal name - it only ever sees whatever URL is baked into the client bundle or returned over the wire. So:

- Code that runs **in the browser** (client components, `NEXT_PUBLIC_*`-driven fetches, any URL shipped to the client) must always use a browser-reachable address - tier 3, the public `proxy.host` domain. Never bake a `kamal-proxy`/internal container address into anything browser-visible, including `NEXT_PUBLIC_*` build args (see `agents/recipes/nextjs.md`'s caveats section).
- Code that runs **on the server** inside the frontend's own container (API routes, `getServerSideProps`/server actions, a backend-for-frontend/proxy layer) is a normal server/container caller and should prefer tier 1 (or tier 2) exactly like any other inter-service call, even though the same logical "frontend calls API" relationship also has a browser-facing side elsewhere.
- Do not force a browser → frontend-server → internal-API proxy architecture onto an app that doesn't already have one, and do not avoid it when the app's own request model already does this (e.g. Next.js API routes/server actions fronting a backend) - inspect the actual code path per unit rather than assuming either shape.

### If a target-relevant blocker from this section can't be resolved

Do not generate the dependent config/code with a guessed value. State the gap and what's needed to resolve it (which tier, what access/credentials/infra) instead of shipping something that looks complete but isn't verified.

**Regression protection:** `tests/fixtures/multi-deployable-unit/EXPECTED.md`'s "Variant: both units Kamal-managed" section requires an agent asked to wire `apps/web`'s server-side code → `apps/api` to default to the internal `kamal-proxy` route (tier 1) rather than `apps/api`'s public `proxy.host`, to reject any `apps/api-web-1`-style guessed hostname even with a disclaimer comment, and to keep any browser-visible config pointed at a public URL instead of an internal one.

## When NOT to use this pattern

- Exactly one Kamal-managed unit, regardless of how many total Deployable Units were discovered — use the plain single-app flow.
- Staging vs. production variants of the *same* unit — that's `-d`/`--destination` (see `examples/multi-destination.md`), not this pattern.
