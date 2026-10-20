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

**Core principle: sharing the `kamal` Docker network is not the same as having stable service discovery on it.** Every app container, accessory container, and the proxy container join the same `kamal` network on a host - that was never the gap. The gap is that an *application-role* container's name on that network rotates every deploy, so network membership alone gives a caller nothing stable to target. Accessories are the one case where network membership *does* equal a stable hostname, because their container name isn't versioned (see below). Never reason "both containers are on the `kamal` network, so `<service>:<port>` must resolve" - that confuses accessory naming with application-role naming. Treat a bare `<service>:<port>` or `<role>:<port>` hostname for an application-role target exactly the same as a guessed `<service>-web-1` hostname: **both are unverified application-role hostnames and neither is acceptable**, with or without a disclaimer comment.

### Verified mechanics (`lib/kamal/commands/{docker,app,proxy,accessory}.rb`, `lib/kamal/configuration/proxy/boot.rb` in basecamp/kamal)

- `kamal setup` creates exactly **one** Docker network per host, literally named `kamal` (`docker network create kamal`). Every Kamal-managed app container, accessory container, and the proxy container join this same network via `--network kamal` - regardless of which `deploy.yml`/`service:` they belong to. Separately configured services sharing a host **do** end up on the same Docker network by default; the gap is not "do they share a network" but "what stable name can they call each other by on it."
- **App containers are not stably named, and no bare alias is provisioned for them either.** An app container's `--name` is `<service>-<role>-<destination>-<version>` (`Kamal::Configuration::Role#container_name`) - the version segment changes on every deploy, and the old container is kept briefly (`retain_containers`) then removed during cutover, so old and new containers briefly coexist with different names. Docker's embedded per-network DNS resolves containers by their current name (and any `--network-alias` that was actually applied), so a name that includes the version cannot be a stable target. Kamal does not configure a bare, unversioned `--network-alias` equal to the service/role name for app containers on the default `kamal` network - a role's own `network-alias` option only reaches a *custom* network the role explicitly joins, not the default `kamal` network every container already shares (this is a documented Kamal limitation, not a configuration you can simply turn on - treat `<service>`/`<role>` alone as never resolving for an app-role target on `kamal` unless you have independently verified a specific deploy actually configured and proved this). This confirms the existing rule, stated generally: **never** infer or hardcode *any* application-role hostname that isn't `kamal-proxy` itself - not a guessed versioned name like `api-web-1`/`<service>-web-1`, and not a bare unversioned name like `stt`/`api` either. Both fail for the same underlying reason: Kamal provides no stable Docker DNS identity for an application role by default, versioned or not.
- **Accessory containers are stably named.** An accessory's `--name` is just its `service_name` (defaults to `<service>-<accessory>`, from `Kamal::Configuration::Accessory`) - never versioned, never rotated by an app deploy. This is why the accessory-reachability guidance in `examples/with-postgres.md`/`with-redis.md` (connect via `<service>-postgres`/`<service>-redis` on the `kamal` network) is correct and unaffected by this section.
- **`kamal-proxy` itself is stably named.** Exactly one `kamal-proxy` container runs per host, with the fixed container name `kamal-proxy` (`Kamal::Configuration::Proxy::Boot#container_name` - literally returns the string `"kamal-proxy"`, never versioned), also on the `kamal` network. It already tracks which app container is currently live for each configured `proxy.host` and routes by the `Host` header - the exact same mechanism that serves public traffic.

### Decision model: does a stable endpoint actually exist, not "internal preferred by default"

The policy is **not** "prefer internal, otherwise fall back to public." It is: establish whether a stable supported endpoint exists for this specific call, and only then decide where it lives. Internal routing is preferred *when it is actually stable* - correctness and verified stability take precedence over avoiding a public hop. Evaluate in this order when Deployable Unit A needs to call Deployable Unit B - do not pick a level merely because it's the easiest to identify, and do not stop at Level 1 unless its endpoint genuinely survives rolling deploys:

**Level 1 - Stable internal application routing.** The only verified mechanism that qualifies here, same host only, is routing through the host's own `kamal-proxy` container over the internal `kamal` network: target `http://kamal-proxy` (container name, resolvable on the shared network, port 80 - `kamal-proxy`'s internal listener) with the `Host` header set to B's configured `proxy.host` value. This qualifies because `kamal-proxy` itself is stably named and already tracks B's currently-live container through every rolling deploy (old/new coexistence included) - that's its job. It does **not** qualify to target B's app container name directly, a bare `<service>`/`<role>` alias, or any Docker DNS name that isn't `kamal-proxy` - none of those survive a redeploy (see above). This also only works for HTTP(S) traffic that `kamal-proxy` can Host-header-route; if B's protocol isn't HTTP(S) (a raw TCP/gRPC port, for example), Level 1 does not apply and you must drop to Level 2.

**Level 2 - Stable private routing.** When Level 1 doesn't apply (different hosts, or a non-HTTP protocol that `kamal-proxy` can't route), check whether another *supported, already-configured* private mechanism exists: a deliberately configured internal reverse proxy, a private load balancer, private DNS, a VPN/overlay (Tailscale/WireGuard), a cloud provider's private networking, or a firewalled port restricted to known source IPs. Use it if it exists. Do **not** provision this speculatively - if it doesn't already exist and the architecture needs it, surface it as an explicit decision/provisioning step (escalate to `agents/recipes/terraform.md` if infrastructure needs to be created) rather than silently assuming or inventing it.

**Level 3 - `kamal-proxy`/public `proxy.host` + HTTPS.** If neither Level 1 nor Level 2 produces a stable endpoint, prefer this known, documented, stable Kamal routing mechanism over inventing Docker service discovery - even when both services live on the same server. This is a valid, correct fallback, not a failure: document it as "stable internal/private application service discovery is not available in the current topology," not as a workaround. Also use this level directly when:
   - the caller cannot reach any internal/private network at all (a browser, a mobile app, a third-party webhook provider);
   - the user explicitly asks for public/external inter-service communication;
   - the exposure decision below allows it.

**Level 4 - No stable mechanism available, and the user requires internal-only.** If the unit's required exposure is internal-only (see below) but Levels 1-2 produce no stable endpoint for this specific call, STOP. Do not silently fall through to Level 3 and expose the service publicly against a stated internal-only requirement, and do not invent a hostname to make Level 1 look satisfied. Present the architectural choices instead - for example:

   ```
   Desired exposure: internal-only
   Required communication: frontend-server -> stt
   Current topology: no verified stable internal/private routing (non-HTTP protocol, kamal-proxy cannot route it)
   Decision required:
     - configure a supported private routing/discovery mechanism (Level 2), or
     - restructure the deployment topology (e.g. put STT behind an HTTP wrapper so kamal-proxy can route it), or
     - allow STT to be routed through kamal-proxy/public HTTPS instead (Level 3), overriding the internal-only requirement
   ```

**Never emit a guessed/unverified hostname as a placeholder, at any level** - "UNVERIFIED" comments do not make a guessed or bare container/service name acceptable; if the right level's exact value isn't known yet (e.g. a private network hasn't been provisioned), say so and block that piece of config/code (Level 4) rather than filling in something that looks complete.

### Generation gate (mandatory before writing any inter-service URL)

Before generating any application-role -> application-role URL/hostname in config or code, answer all of the following explicitly. If `STABLE ENDPOINT` or its stability justification is unknown or unverified, generation for that dependency is **blocked** - do not emit a placeholder hostname instead:

```
CALLER:
CALLEE:
CALLER EXECUTION CONTEXT:        (browser, or which unit's server/container)
REQUIRED EXPOSURE:               (public / internal-only / mixed)
ROUTING MECHANISM:               (Level 1 kamal-proxy / Level 2 private path / Level 3 public proxy.host)
STABLE ENDPOINT:                 (the exact hostname:port to be used)
WHY ENDPOINT IS STABLE:          (why it survives container replacement)
ROLLING-DEPLOY BEHAVIOR:         (what happens to this endpoint while old/new containers coexist)
```

This gate applies per dependency, not once per unit - a unit calling two different application-role services answers it twice.

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

**Regression protection:** `tests/fixtures/multi-deployable-unit/EXPECTED.md`'s "Variant: both units Kamal-managed" section requires an agent asked to wire `apps/web`'s server-side code → `apps/api` to default to the internal `kamal-proxy` route (Level 1) rather than `apps/api`'s public `proxy.host`, to reject any `apps/api-web-1`-style guessed hostname *and* any bare `api`/`apps-api`-style unversioned hostname even with a disclaimer comment, and to keep any browser-visible config pointed at a public URL instead of an internal one. `localhost`/`127.0.0.1` inside one application container never refers to a different Deployable Unit's container/process namespace - only to the caller's own container - unless a specifically documented host-network mechanism changes that; never use it as a stand-in for another unit's address.

## When NOT to use this pattern

- Exactly one Kamal-managed unit, regardless of how many total Deployable Units were discovered — use the plain single-app flow.
- Staging vs. production variants of the *same* unit — that's `-d`/`--destination` (see `examples/multi-destination.md`), not this pattern.
