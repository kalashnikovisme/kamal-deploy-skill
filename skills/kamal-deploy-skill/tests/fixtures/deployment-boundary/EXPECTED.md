# Fixture: Deployment Boundary (Deployable Unit ≠ Kamal Deployment)

Regression coverage for `agents/patterns/deployment-boundary.md`. Each variant below shares a base scenario: a monorepo with `apps/web` (frontend, same product as the API, normally released together), `apps/api` (backend/API for that product), `apps/stt` (an auxiliary HTTP speech-to-text service), PostgreSQL, and Redis — all intended for one server. The user selects `apps/web`, `apps/api`, `apps/stt`, PostgreSQL, and Redis into the Kamal-managed subset.

## Variant: default case — consolidate where the architecture supports it

Expected behavior, per `agents/patterns/deployment-boundary.md`'s decision hierarchy:

- The agent must run and show the eight boundary questions before generating any Kamal file, not just reason about them silently.
- The agent must **not** generate three independent `config/deploy.*.yml` files (one per `apps/web`, `apps/api`, `apps/stt`) merely because three Deployable Units were discovered and selected — an agent that defaults to one file per unit without first attempting consolidation fails this fixture, even if the resulting container graph would technically work.
- `apps/web` and `apps/api` belong to one product, target the same server, and are normally released together — the agent must investigate whether they can be built into one release image and proposed as **one Kamal application with separate roles** (e.g. `web` and `api` roles, each with its own `cmd`/`proxy`/health check) sharing one `config/deploy.yml`, one `service:`, and one release lifecycle. If the agent finds a concrete reason they can't share an image (e.g. truly incompatible runtimes), it must state that reason explicitly rather than silently keeping them separate.
- `apps/stt` must be evaluated against the accessory-lifecycle checklist (update frequency, zero-downtime needs, statefulness, startup dependencies, whether it needs `kamal-proxy`, whether accessory DNS suffices, whether manual restart semantics are acceptable) before any classification — an agent that classifies it as an accessory, or as a role, without running this evaluation and stating the answers fails this fixture.
- PostgreSQL and Redis should be proposed as accessories (`accessories: postgres`, `accessories: redis`) in the same deployment — this part is unchanged from existing accessory guidance.
- The proposed end state is: one `config/deploy.yml`, one server, one `service:`/release lifecycle, one `kamal-proxy` — with `apps/stt` placed as either a role or an accessory depending on what the evaluation above actually concludes (see the two variants below for the two concrete outcomes), not left unresolved.
- The agent must **not** introduce Traefik, nginx, Caddy, HAProxy, or any other reverse proxy anywhere in this scenario — `kamal-proxy` remains the only reverse proxy regardless of topology.

## Variant: `apps/stt` tolerates accessory lifecycle

Extend the scenario: the user confirms `apps/stt` does not need zero-downtime rolling releases, does not need to be called over HTTP through `kamal-proxy` (only reached directly by `apps/api` via a lightweight internal protocol / is fine behind manual restarts), and stable accessory DNS (`<service>-stt`) is sufficient for how `apps/api` reaches it. Expected behavior:

- The agent may classify `apps/stt` as an accessory and should state the specific checklist answers that justified it (not just "it's auxiliary, so it's an accessory").
- The agent must note, explicitly, that `apps/stt` as an accessory will **not** receive Kamal's normal rolling zero-downtime deploy lifecycle, and that updates require `kamal accessory reboot`/equivalent rather than `kamal deploy` — omitting this tradeoff note fails this sub-variant even if the YAML itself is correct.
- The agent must not register a `proxy:` block for the `apps/stt` accessory — Kamal's accessory schema has no such key; if the agent's generated config includes one, or implies `kamal-proxy` routes to it, that fails this sub-variant.
- `apps/api` reaching `apps/stt` uses the accessory's stable `service_name` directly (same mechanism as the Postgres/Redis guidance) — not `kamal-proxy`, not a guessed hostname.

## Variant: `apps/stt` requires zero-downtime rolling deployment (lifecycle conflict)

Extend the scenario differently: the user states `apps/stt` ships frequently and must use Kamal's normal rolling deploy so it never drops a request mid-transcription. Expected behavior:

- The agent must **not** silently classify `apps/stt` as an accessory merely because that would simplify the file count or the networking story — doing so fails this sub-variant outright, regardless of any caveat comment attached.
- The agent must surface the lifecycle conflict explicitly: accessory lifecycle cannot provide the stated zero-downtime rolling requirement, so `apps/stt` needs to be modeled as a Kamal role instead (either as a third role in the consolidated `apps/web`/`apps/api` deployment if it can share that release image, or — only with a stated concrete reason — its own separate Level 3 deployment).
- The agent must ask the user or state its own reasoned choice between "fold `apps/stt` in as a third role of the consolidated deployment" and "give `apps/stt` its own deployment," rather than picking silently with no justification shown.
- Having chosen "role," any `apps/web` ↔ `apps/stt` or `apps/api` ↔ `apps/stt` traffic still follows `agents/patterns/multi-service-repo.md`'s tier 1/2/3 model (no stable Docker DNS between role containers; route through `kamal-proxy`; stop at tier 3 for a stated internal-only requirement `kamal-proxy` can't satisfy) — consolidating into one deployment does not create a shortcut hostname between roles.

## Variant: a genuine Level 3 split is justified

Extend the scenario once more: `apps/api` is owned and released by a different team on an independent, faster release cadence that the user explicitly wants decoupled from `apps/web`'s release process, and the user confirms this is intentional, not incidental. Expected behavior:

- Multiple independent Kamal deployments remain allowed here — the agent must not force everything into one `config/deploy.yml` just because consolidation is the general preference.
- The agent must state the concrete reason (independent release lifecycle requirement, explicitly confirmed by the user) rather than a generic one ("they're different apps") — an agent that proposes separate deployments without naming a reason from `deployment-boundary.md`'s Level 3 list fails this sub-variant, even though the end topology (separate deploys) is the same as what a naive agent might produce by default.
- Once Level 3 is justified for `apps/web`/`apps/api`, `agents/patterns/multi-service-repo.md`'s `-c`/`--config-file`, `secrets_path`/`hooks_path`, and inter-service networking tiers apply to them as normal.
- This does not retroactively justify separating `apps/stt`, PostgreSQL, or Redis from whichever deployment they ended up in — each unit's boundary is evaluated on its own stated reason, not inherited from a sibling's.

## Explicitly out of scope for this fixture

- The exact stack recipe and Dockerfile content for `apps/web`/`apps/api`/`apps/stt` — covered by the relevant stack recipes, not this pattern.
- Multi-destination (staging/production) mechanics — see `examples/multi-destination.md`.
