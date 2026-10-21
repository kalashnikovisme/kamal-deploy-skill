# Deployment Boundary: Deployable Unit ≠ Kamal Deployment

This pattern runs **after** `agents/patterns/deployable-units.md` has produced the Kamal-managed subset, and **before** Step 2 (stack detection) runs for any unit in that subset. It applies whenever the Kamal-managed subset has **more than one unit** - with exactly one unit there is nothing to decide, proceed with the plain single-app flow.

## Core principle

**A Deployable Unit is not automatically a separate Kamal deployment.** Discovery (`deployable-units.md`) answers "what independently-runnable things exist in this repo." This pattern answers a different question: "how many Kamal deployment configurations should represent them." Those are not the same number, and the Skill must stop assuming they are.

For components that belong to the same product, deploy to the same server or server group, and are operationally managed together, the Skill must **first attempt** to represent the complete product as one Kamal deployment: one `service:`, one `config/deploy.yml`, one server/server set, one registry/builder configuration, one `kamal-proxy`, with application roles and accessories used where each fits. Multiple `config/deploy.*.yml` files must not be generated merely because the repository contains multiple Deployable Units, multiple directories, multiple Dockerfiles, or multiple frameworks - none of those are, by themselves, a deployment-boundary justification.

## Four concepts that are not equivalent

Keep these distinct. Conflating any two of them is the mistake this pattern exists to prevent.

- **Deployable Unit** - a component that can conceptually be deployed independently (from `deployable-units.md`'s discovery process). This is an architectural/lifecycle classification about the *repository*, decided before any Kamal config exists.
- **Runtime Unit** - a process/container that runs independently at runtime, regardless of which Kamal deployment (if any) manages it.
- **Kamal Role** - a runtime role (`servers.<role>`) of one Kamal application, sharing that application's release image, versioned and deployed together with every other role in the same `config/deploy.yml`.
- **Accessory** - a separately managed supporting container declared under `accessories:` in the same Kamal deployment configuration, with its own image/lifecycle, not updated by normal `kamal deploy` runs.
- **Kamal Deployment** - the complete deployment boundary described by one primary `config/deploy.yml` (or `config/deploy.<name>.yml` when more than one is genuinely required - see Level 3 below): one `service:`, one release lifecycle, one `kamal-proxy` on its target hosts.

A Deployable Unit can end up as a Kamal Role, an Accessory, or its own Kamal Deployment - which one is exactly what this pattern decides. **Deployable Unit ≠ Kamal Deployment** is the core invariant; nothing downstream of this pattern should assume one implies the other.

## Verified Kamal mechanics (roles and accessories)

Verified against Kamal's current documentation and configuration schema (`kamal-deploy.org/docs/configuration/`) - re-verify if Kamal's role/accessory model changes.

- **One application per deployment configuration.** A `config/deploy.yml` describes one application: one `service:` name, one `image:`, one release lifecycle. `kamal deploy` builds/pushes one image and rolls it out, versioned, across every role that application defines.
- **Roles share the release image, not its runtime behavior.** Under `servers:`, each role (e.g. `web`, `api`, `worker`) can set its own `cmd`, `env`, `proxy` block, and host list, while still being built from the same image and deployed together as one release. This is the mechanism for running multiple processes from one product as one Kamal deployment: different entrypoints into the same artifact, not different artifacts.
- **Accessories have their own image and a different lifecycle.** An `accessories:` entry can declare its own `image`, `env`, `secrets`, `volumes`, `files`, `directories`, `cmd`, and host, but it is **not** part of the application's rolling-deploy cycle. `kamal deploy` does not touch accessories; they are booted/rebooted/restarted independently via `kamal accessory boot/reboot/restart/remove`. An accessory update means manually re-running that command - there is no zero-downtime rolling replacement, no automatic "redeploy on image change," and no coordination with the main application's deploy unless a hook is written to do so explicitly.
- **Accessories are not routed by `kamal-proxy`.** The `proxy:` block that registers an HTTP route with `kamal-proxy` is a role-level (`servers.<role>.proxy`) concept; Kamal's accessory schema has no equivalent `proxy:` key. An accessory that needs to be called over HTTP through `kamal-proxy`'s routing cannot be declared as an accessory for that purpose - it needs to be a role (in this deployment or another) for `kamal-proxy` to route it at all. An accessory is reachable only via its stable Docker-network `service_name` (direct container-to-container connection) or via whatever port it binds on the host - never via a `kamal-proxy` `proxy.host` route. This is a hard constraint on the Level 2 "accessory" option below, not a style preference.
- **One `kamal-proxy` per host, shared across every Kamal deployment that targets it.** Multiple independent `config/deploy.yml` files targeting the same host still share that host's single `kamal-proxy` container - splitting into multiple deployments does not get you "more kamal-proxy," it gets you more deployment/release/secrets management overhead for configurations that then both register routes with the same proxy anyway.

## Mandatory step: Determine Kamal Deployment Boundary

Before generating any Kamal files for a Kamal-managed subset with more than one unit, answer all of the following explicitly (present the answers to the user, don't just reason about them silently):

```
1. Are these units part of one product?
2. Are they intended to run on the same server/server group?
3. Do they normally need to be deployed together?
4. Can multiple application units share one release image?
5. Can different commands/roles start the individual processes from that image?
6. Which units require Kamal's normal rolling application deployment lifecycle?
7. Which units are suitable for accessory lifecycle?
8. Is there any genuine reason for multiple independent Kamal configurations?
```

Then propose the simplest valid topology that answers those questions correctly - not the simplest topology in the abstract. "Simplest" means fewest deployment boundaries that are each individually justified, not fewest files for their own sake.

## Decision hierarchy

Evaluate in this order. Each level is a stronger claim than the last; only move to the next level when the current one is actually unsuitable for a given unit, not merely to avoid the analysis.

### Level 1 - One application image with roles

Prefer this when multiple application components belong to the same product, run on the same infrastructure, can reasonably be built into one image, benefit from being deployed as one release, and can be started using different role commands (`cmd`). Conceptual shape (do not copy blindly - generate from the actual discovered application):

```yaml
service: product
image: product

servers:
  web:
    hosts:
      - SERVER
    cmd: ...
    proxy:
      host: app.example.com
  api:
    hosts:
      - SERVER
    cmd: ...
    proxy:
      host: api.example.com

accessories:
  postgres:
    ...
  redis:
    ...
```

This keeps separate processes/containers while sharing one image, one release version, one `config/deploy.yml`, and one deployment lifecycle. The preferred consolidation is **one image / multiple Kamal roles**, not **one container / multiple unrelated processes** - do not combine unrelated processes into a single container merely to satisfy this rule, and do not force a unified image onto components whose build requirements genuinely conflict (see Level 3).

### Level 2 - Primary application + accessories

Use an accessory for a component that genuinely fits accessory lifecycle - PostgreSQL, Redis, and similar supporting infrastructure are the typical case. An application service (not just infrastructure) may also be modeled as an accessory when that is an explicit, evaluated architectural choice, never a default. Before making an application service an accessory, explicitly evaluate and state the answer to each of:

- Update frequency - how often does this component change relative to the main application?
- Zero-downtime requirements - can this component tolerate a restart-based update instead of a rolling one?
- Rolling deployment requirements - does it need Kamal's normal versioned rollout at all?
- Statefulness - does it hold state that a restart-based lifecycle handles safely?
- Startup dependencies - does anything depend on strict startup ordering that accessory lifecycle doesn't guarantee?
- Whether it needs `kamal-proxy` - if yes, it **cannot** be an accessory (see "Verified Kamal mechanics" above); it must be a role instead, in this deployment or a separate one.
- Whether stable accessory DNS (`<service>-<accessory>`) is useful and sufficient for how it's reached.
- Whether independent `kamal accessory` lifecycle (manual boot/restart, no rolling update) is actually acceptable to the user for this component.

**Do not blindly turn every secondary service into an accessory.** If the evaluation above shows the component needs HTTP routing through `kamal-proxy`, needs zero-downtime rolling releases, or has startup-ordering/statefulness needs accessory lifecycle doesn't satisfy, it belongs at Level 1 (as a role) instead - surface that tradeoff rather than quietly picking accessory lifecycle because it looked like the simpler networking answer.

### Level 3 - Multiple independent Kamal deployments

Only use multiple independent `config/deploy.*.yml` configurations when there is an actual deployment boundary, not merely multiple Deployable Units. Legitimate reasons include:

- Different server fleets - the components genuinely don't share target infrastructure.
- Genuinely independent products, not components of the same product.
- Independent release lifecycles that must remain independent (e.g. one component ships multiple times a day, another is released quarterly under a separate approval process, and the user wants that decoupling preserved).
- Incompatible build/release requirements that cannot reasonably share an application image (conflicting base images/runtimes that can't coexist in one image, or a build pipeline that genuinely cannot produce both artifacts together).
- Different infrastructure ownership (e.g. managed by different teams with separate deploy credentials/access).
- Another verified Kamal limitation requiring separation - cite the specific mechanic, don't assert this generically.

None of the following are sufficient justification on their own: the existence of multiple directories (`frontend/`, `api/`, `stt/`); different Dockerfiles; different frameworks; a monorepo containing several Deployable Units. If one of the above genuine reasons applies to only *some* units in the subset, split the boundary accordingly - e.g. two units consolidate at Level 1/2 while a third genuinely needs its own deployment at Level 3. Explain the concrete reason to the user when proposing Level 3 for any unit; "they're in different directories" is not an explanation.

## Same-server optimization

When the user says something like "everything should run on one server," treat that as a strong signal to investigate a single Kamal deployment - not as instruction to generate N independent deploy files that merely happen to list the same IP. Do not interpret "three applications on one server" as automatically meaning "three independent Kamal services with three deploy files." Ask instead: "Can these components be represented as one Kamal application with roles and accessories?" and prefer that topology when the Level 1/2 evaluation above supports it.

## One server means one declaration

When all application components and accessories intentionally live on the same physical server, avoid duplicating that server's address across multiple independent deployment files. The generated architecture should normally have one authoritative Kamal configuration describing the deployment, with one normal `config/deploy.yml` and one normal Kamal secrets layout (`.kamal/secrets`). Do not create separate secret files/configuration trees per Deployable Unit unless the resulting topology (per the hierarchy above) actually lands on Level 3 for that unit.

## Frontend + backend consolidation

For products containing a frontend and a backend/API that belong to the same product, live in the same repository or monorepo, deploy to the same server, and are normally released together: the Skill **must** evaluate whether they should be consolidated into one Kamal application/release before defaulting to separate deployments. Do not assume frontend and backend must stay separate merely because they use different frameworks.

Investigate whether a unified production Docker image can contain the runtime artifacts required by both. If so, consider `web` role → frontend process, `api` role → backend process, each with its own `cmd`, env, `proxy` block, and health check, sharing one image, one release version, one `config/deploy.yml`.

Also evaluate whether a separate publicly exposed backend hostname is actually necessary: for products where the frontend already has a server-side/BFF layer that can proxy `/api/*` to the backend, consider whether the public topology can be simplified to one public hostname. Do not rewrite application architecture automatically, and do not remove public API access when third parties, webhooks, or browser clients genuinely require direct access to it - surface the simplification as an option, let the user decide.

## Auxiliary application services (transcription, search, ML inference, document conversion, etc.)

Evaluate accessory lifecycle explicitly rather than defaulting to it. A service like this is a reasonable accessory candidate when it runs on the same server, stable internal DNS (the accessory's `service_name`) is useful for how it's reached, it does not require normal application rolling deployment, and explicit accessory restart/update semantics are acceptable to the user. If it requires zero-downtime rolling releases or `kamal-proxy` HTTP routing, do not silently make it an accessory merely to simplify networking or reduce file count - that is exactly the mistake this pattern exists to prevent. Explain the tradeoff and propose Level 1 (a role, in this deployment or a justified separate one) instead.

## kamal-proxy remains the only reverse proxy

This pattern does not change the constraint in `agents/patterns/multi-service-repo.md`: there must be no additional reverse proxy. Use only `kamal-proxy`. Do not introduce Traefik, nginx, Caddy, HAProxy, or custom ingress proxies to route to roles or to work around an accessory's lack of `proxy:` support - the resolution to "this needs HTTP routing but was going to be an accessory" is to make it a role (Level 1), never to add another proxy in front of it.

## Networking implications of this pattern

The inter-service networking lessons in `agents/patterns/multi-service-repo.md` remain valid, but reconsider whether some of that complexity disappears once components are correctly modeled as roles/accessories inside one deployment instead of as separate Kamal deployments:

- Two roles inside the **same** Kamal deployment still have no stable application-role Docker DNS name between them (role containers are versioned exactly like any other app container - see `multi-service-repo.md`'s "Verified mechanics"). Calls between roles still go through `kamal-proxy` (tier 2 of that pattern) unless one side is actually an accessory.
- Accessories have stable `service_name`s and already share the `kamal` Docker network by default - use that supported identity directly when a role needs to reach an accessory (see SKILL.md Step 4b #6); don't route accessory traffic through `kamal-proxy` or externally without a specific reason, since accessories aren't registered with `kamal-proxy` in the first place.
- Collapsing two Deployable Units into one Kamal deployment (Level 1) does not, by itself, create a stable hostname between their roles - it only removes the *build/release/secrets* duplication. The `multi-service-repo.md` decision model still governs how the roles actually call each other.

## Deployment lifecycle is part of topology

Do not treat topology only as "what containers exist." Topology also includes:

- **Build boundary** - what gets built together into one image.
- **Release boundary** - what gets versioned and rolled out together.
- **Deployment boundary** - what one `config/deploy.yml` describes (the subject of this pattern).
- **Rolling-deployment boundary** - which components get zero-downtime versioned replacement, and which don't (accessories don't).
- **Runtime process boundary** - what actually runs as its own process/container.
- **Accessory lifecycle** - manual boot/restart semantics, not coordinated with application deploys.
- **Network exposure boundary** - public vs. internal-only vs. application-level-private (`multi-service-repo.md`).

A correct container graph with the wrong deployment lifecycle is still an incorrect Kamal architecture - e.g. proposing an accessory for a component that actually needs rolling zero-downtime releases is wrong even if the resulting container topology "looks right."

## If the boundary can't be resolved cleanly

If answering the eight questions above produces a genuine split - some units consolidate, one doesn't, for a concrete Level 3 reason - propose that mixed topology explicitly rather than forcing everything into one deployment or defaulting back to one-file-per-unit. State which units consolidate, which stay separate, and the specific reason for the separation.
