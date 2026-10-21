# Expected Behavior: multi-deployable-unit fixture

This fixture is a synthetic pnpm/npm-workspaces-style monorepo. It exists to verify the discovery-and-selection flow in `agents/patterns/deployable-units.md`, not any particular stack recipe's Dockerfile output.

## Structure under test

```
package.json                  # "workspaces": ["apps/*", "packages/*"]
apps/api/package.json         # scripts.start, express dependency, no existing hosting config
apps/api/src/index.js         # listens on a port, serves /health
apps/web/package.json         # scripts.start ("next start"), but...
apps/web/vercel.json          # ...already configured for Vercel hosting
apps/web/pages/index.js
packages/shared-utils/package.json  # no start script, no port, pure library
packages/shared-utils/index.js
```

## Expected discovery (Step 1 of SKILL.md / `agents/patterns/deployable-units.md`)

The root `package.json`'s `workspaces` array is **not** evidence of a single deployable unit, and it is also not, by itself, evidence of three deployable units. It only tells the discovery step where to look for candidates (`apps/*`, `packages/*`).

Candidates discovered: `apps/api`, `apps/web`, `packages/shared-utils` — three candidate directories.

Per-candidate independent-deployability judgment:

| Candidate | Has own runnable process/port? | Verdict | Why |
|---|---|---|---|
| `apps/api` | Yes — `scripts.start` runs `node src/index.js`, which calls `app.listen(port)` | **Deployable Unit** | Own process, own port, no existing hosting config — a plausible Kamal candidate |
| `apps/web` | Yes — `scripts.start` runs `next start` | **Deployable Unit** | Has its own runnable process, but also carries `vercel.json` — existing-hosting evidence that must be surfaced during selection, not used to disqualify it from being a unit in the first place |
| `packages/shared-utils` | No — no `scripts.start`, no port, `main` points at a plain export, only consumed via `workspace:*` from `apps/api` | **Not a Deployable Unit** | Purely an imported library; directory presence and `package.json` presence alone do not create a unit |

### Regression protection: `apps/web` has no `Dockerfile`, and that must not make its status conditional

`apps/web` has no `Dockerfile` anywhere in its subtree — only `vercel.json` and a `package.json` with `scripts.start`. An agent running this fixture must still classify `apps/web` as an unconditional Deployable Unit, exactly as the table above states, and must **not** describe it with hedging language like "conditionally a deployable unit," "deployable if a Dockerfile is added," or "not yet a deployable unit until Kamal-ready." The missing `Dockerfile` is Kamal-readiness information that belongs to Step 5 (Apply Recipe) — it is a later concern about *how* Kamal would deploy `apps/web` if selected, never a qualifier on *whether* `apps/web` is a Deployable Unit. `apps/web` already satisfies the Step 3 independent-deployability test (own runnable process via `next start`) on that basis alone; the `vercel.json` existing-hosting evidence affects only the Step 5 *selection* question ("should Kamal manage it"), not the discovery classification. See `agents/patterns/deployable-units.md`'s "What does NOT determine Deployable Unit-hood" section.

Expected Deployable Unit list: **2** (`apps/api`, `apps/web`). `packages/shared-utils` is excluded — this is the test that directory count/workspace-glob matches alone don't inflate the unit count.

## Expected selection (Step 1, selection sub-step)

The agent should ask the user which discovered units Kamal should manage, surfacing `apps/web`'s `vercel.json` as relevant context (already hosted elsewhere) rather than silently excluding or silently including it.

Expected answer for this fixture: **`apps/api` only**.

- `apps/api`: selected — no existing hosting config, has a port and a start script, a reasonable Kamal target.
- `apps/web`: not selected — already deployed on Vercel per `vercel.json`; documented as out of scope, not deleted or ignored.

Resulting **Kamal-managed subset**: `{apps/api}` — size 1.

## Expected downstream behavior (Steps 2–6)

Because the Kamal-managed subset has exactly **one** unit, despite the repo containing multiple deployable-unit candidates:

- Stack detection (Step 2) and recipe loading (Step 3) run once, scoped to `apps/api/`, using `agents/recipes/nodejs.md`.
- The generated config is a **plain** `config/deploy.yml` — NOT `config/deploy.api.yml`, and `agents/patterns/multi-service-repo.md`'s `-c`/`--config-file` convention must **not** be triggered. That pattern only applies once the Kamal-managed subset itself has more than one unit, never merely because the repo discovered more than one candidate.
- `secrets_path`/`hooks_path` are left at Kamal's defaults (`.kamal/secrets`, `.kamal/hooks`) — no per-unit suffix needed for a single-unit subset.
- The Step 6 documentation update must include the Deployable Units table (per `agents/patterns/multi-service-repo.md`'s format) even though only one unit is Kamal-managed, because more than one unit was discovered overall:

  | Unit | Path | Managed by Kamal | Notes |
  |---|---|---|---|
  | api | `apps/api/` | Yes — `config/deploy.yml` | |
  | web | `apps/web/` | No | already deployed on Vercel per `vercel.json`; untouched by this setup |

  (`packages/shared-utils` does not appear in this table — it was never a Deployable Unit.)

## Variant: both units Kamal-managed (cross-unit networking regression)

This variant changes only the selection answer, not discovery: suppose the user instead asks Kamal to manage **both** `apps/api` and `apps/web` (dropping the Vercel hosting for `apps/web`), both deployed to the **same server**, and `apps/web`'s server-side code (e.g. an API route, not browser JS) needs to call `apps/api`'s `/health` (or any) endpoint.

**With the Kamal-managed subset now at two units, `agents/patterns/deployment-boundary.md`'s boundary step runs before anything below.** `apps/web` and `apps/api` are one product, same server, no stated reason they can't share a release image or be released together — absent the user stating a genuine Level 3 reason (different teams/release cadences/incompatible builds), the expected proposal is **one Kamal deployment with `apps/web` and `apps/api` as two roles** (one `config/deploy.yml`, one `service:`), not two independent `config/deploy.api.yml`/`config/deploy.web.yml` files. An agent that jumps straight to `agents/patterns/multi-service-repo.md`'s `-c`/`--config-file` layout without first running the boundary step and finding (or asking for) a Level 3 justification fails this fixture now, even though that was the previously-expected shape of this fixture before the boundary step existed.

The networking-tier expectations below hold **regardless of which side of the boundary decision `apps/web`/`apps/api` land on** - whether they end up as two roles of one consolidated deployment or (only with a stated Level 3 reason) two separate deployments, there is still no stable Docker DNS name between their app containers, and the same tier 1/2/3 model governs the call. Per `agents/patterns/multi-service-repo.md`'s "Inter-service communication" section (native stable mechanism first, then `kamal-proxy`, stop only for an explicit internal-only conflict):

- The agent must **not** write a guessed container hostname such as `apps-api-web-1`, `api-web-1`, or any `<service>-web-N` pattern into `apps/web`'s code or config as the way to reach `apps/api`. This is true even if the guess is accompanied by an `UNVERIFIED`/`TODO` comment — a disclaimer does not make an invented hostname acceptable, and an agent that emits one (commented or not) fails this fixture.
- The agent must **not** write a bare, unversioned application-role hostname either — e.g. `http://api:3001` or `http://api/health` relying on Docker DNS resolving the service/role name directly — on the theory that both containers share the `kamal` network. Sharing that network does not give `apps/api`'s app container a stable alias; only `kamal-proxy` has one. An agent that emits `http://api:<port>` (commented or not) fails this fixture exactly like the guessed-container-name case above.
- The agent must **not** introduce Traefik, nginx, Caddy, HAProxy, or any other reverse proxy/ingress layer to solve this call — `kamal-proxy` is the only reverse proxy this Skill generates, and an agent that reaches for a second proxy layer (even framed as "more correct" internal routing) fails this fixture.
- Because both units share one server and the call is HTTP, the **expected answer is tier 2, same-host internal listener**: `apps/web`'s server-side code should call through the host's own `kamal-proxy` container over the internal Docker network (target `kamal-proxy`, `Host` header set to `apps/api`'s configured `proxy.host`), not `apps/api`'s public `proxy.host` domain over the public internet. An agent that defaults straight to the public HTTPS URL for this same-host server-to-server call, without explaining why the internal listener wasn't used, fails this fixture — the same-host internal route is preferred when available, though the public route would not itself be a defect if stated as the reason.
- The agent should be able to produce the generation gate's fields for this call (CALLER `apps/web`, CALLEE `apps/api`, CONTEXT server, REQUIRED EXPOSURE no stated internal-only requirement, MECHANISM tier 2 `kamal-proxy` same-host, ENDPOINT `kamal-proxy` + `Host: apps/api`'s `proxy.host`, STABILITY `kamal-proxy` tracks the live container across deploys, ROLLING-DEPLOY old container served until cutover completes) — an agent that cannot articulate why the endpoint is stable across a redeploy, yet still emits it, fails this fixture.
- Any value written into browser-visible configuration (e.g. a `NEXT_PUBLIC_*` build arg, if `apps/web` needs one for client-side calls to `apps/api`) must still be `apps/api`'s public `proxy.host` URL — the internal `kamal-proxy` route from the bullet above is only for `apps/web`'s own server-side code, never for anything shipped to the browser. An agent that leaks `kamal-proxy` or any internal container name into a `NEXT_PUBLIC_*` variable fails this fixture.
- This variant now exercises `agents/patterns/multi-service-repo.md`'s `-c`/`--config-file` mechanics (both units selected), which the base scenario above intentionally leaves out of scope.

### Sub-variant: `apps/api` also receives an external webhook

Extend the same two-unit scenario: `apps/api` additionally needs a public endpoint for a third-party webhook (e.g. a payment provider). Expected behavior:

- `apps/api` gets public exposure (its own `proxy.host`) for the webhook route — exposure is a per-unit, per-route decision, not an all-or-nothing switch.
- `apps/web`'s internal call to `apps/api` (from the bullet above) still uses the same-host internal route. `apps/api` having a public endpoint for the webhook must not be treated as a reason to route `apps/web`'s internal call through that public endpoint instead — an agent that does this (reasoning "it's public now anyway") fails this sub-variant. Exposure and inter-service communication are independent decisions.

### Sub-variant: internal routing unavailable

If the agent determines (or the user states) that `apps/api` and `apps/web` do *not* actually share a host/network — e.g. the user says they'll be on unrelated infrastructure with no private connectivity — using `apps/api`'s public `proxy.host`/HTTPS listener is correct and is not a defect to flag. The agent must state briefly why the same-host internal listener wasn't available (no shared host/network) rather than silently defaulting to public routing without explanation, and must not invent private connectivity that wasn't stated to exist, and must not introduce Traefik/nginx/Caddy/HAProxy as an alternative to simply using `kamal-proxy`'s public listener.

### Sub-variant: non-HTTP protocol, stated internal-only requirement (tier 3 stop)

Extend the scenario: instead of an HTTP `/health` call, `apps/web` needs to reach a third Kamal-managed unit, `stt`, over a raw TCP/gRPC port (`3002`), and the user has explicitly stated `stt` must be inaccessible from the Internet. Expected behavior:

- `kamal-proxy` only Host-header-routes HTTP(S) traffic, so tier 2 does not apply to this call — an agent that still targets `kamal-proxy` for a non-HTTP protocol fails this sub-variant.
- The agent must **not** emit `http://stt:3002`, `stt:3002`, or any other bare/guessed hostname for `stt` — with or without a disclaimer comment — on the theory that `apps/web` and `stt` share the `kamal` network.
- The agent must **not** introduce Traefik, nginx, Caddy, HAProxy, or any other reverse proxy as a way to route this non-HTTP traffic privately — that is out of scope for this Skill's target architecture, even to satisfy a stated internal-only requirement.
- Because `kamal-proxy` has no supported route for a non-HTTP protocol at all, and the user requires `stt` be inaccessible from the Internet, the agent must stop at tier 3: present the conflict (required communication `apps/web -> stt`, exposure requirement `stt` inaccessible from the Internet, constraint `kamal-proxy` can't route this protocol) and the Kamal-native options (serve `stt` through `kamal-proxy`'s public listener with application-layer auth instead, find some other Kamal-supported approach that doesn't depend on `kamal-proxy` enforcing the boundary, or relax the internal-only requirement) — rather than silently choosing one of those for the user, inventing a hostname, or adding a second proxy. An agent that proposes "just make `stt` speak HTTP so `kamal-proxy` can route it" as a complete fix, without noting that doing so still doesn't make `stt` inaccessible from the Internet (`kamal-proxy` publishes its ports by default), fails this sub-variant just as much as one that skips the stop entirely.
- An agent that silently exposes `stt` via `kamal-proxy`'s public `proxy.host` without surfacing this as a decision fails this sub-variant, as does one that proposes Traefik/nginx/etc. as the "proper" internal-only solution.

### Sub-variant: HTTP call with a stated internal-only requirement (tier 3 stop still applies)

Extend the scenario once more: `apps/web` needs to reach `stt` over HTTP (not the TCP/gRPC case above), and the user has stated `stt` must be inaccessible from the Internet. Expected behavior:

- `kamal-proxy` *can* Host-header-route this call technically (`apps/web` -> `kamal-proxy` over the internal Docker network -> `Host: stt`'s configured `proxy.host`), but routing `apps/web`'s call that way does not satisfy the stated requirement: registering `stt`'s `proxy.host` with `kamal-proxy` makes it reachable through `kamal-proxy`'s public listener by default, regardless of which path `apps/web` itself uses. An agent that treats "I used the internal route for my own call" as having satisfied "stt must be inaccessible from the Internet" fails this sub-variant — those are two different questions.
- The agent must still stop at tier 3 and present the same conflict/decision set as the non-HTTP sub-variant above (serve `stt` through `kamal-proxy`'s public listener with application-layer protection, find another approach that doesn't rely on `kamal-proxy` enforcing the boundary, or relax the requirement) — HTTP vs. non-HTTP changes whether tier 2 is technically *available*, not whether it satisfies a strict internal-only requirement.
- An agent that introduces Traefik/nginx/Caddy/HAProxy "to be safe" and keep `stt` private also fails this sub-variant — that architecture is out of scope regardless of how well-justified the internal-only requirement is.

### Sub-variant: user accepts application-level privacy for `stt` after the tier 3 stop

Continue the HTTP sub-variant above: after the agent presents the tier 3 conflict, the user responds that they're fine with `stt` being reachable through `kamal-proxy`'s public listener as long as its endpoints reject unauthorized callers — i.e. they accept application-level privacy in place of the network-level internal-only requirement they originally stated. Expected behavior:

- The agent must treat this as a distinct, explicit approval — it must not have assumed this outcome on its own at tier 3, and must not retroactively claim the original network-level requirement was already satisfied by tier 2 routing (see the HTTP sub-variant above).
- Having received approval, the agent proceeds to wire `apps/web` -> `stt` through `kamal-proxy`'s public `proxy.host`/HTTPS route (the same tier 2 mechanism, now accepted) and treats that reachability as resolved, not as an outstanding defect to keep flagging.
- The agent must add server-to-server authentication on `stt`'s sensitive functional endpoints (a shared secret/token/HMAC appropriate to the stack) and must reject unauthenticated callers on those endpoints; a health/readiness endpoint with no sensitive data may remain unauthenticated for `kamal-proxy`'s health checks.
- The credential must be stored via `.kamal/secrets` (or the unit's own `secrets_path`), never hardcoded into `deploy.yml` or source, and never exposed through `NEXT_PUBLIC_*`/any browser-bundled config.
- An agent that skips adding authentication on `stt` after this approval — reasoning that "the user said it's fine" removes the need for any protection at all — fails this sub-variant, as does one that still reaches for Traefik/nginx/Caddy/HAProxy instead of application-layer auth.

## Explicitly out of scope for this fixture

- Multi-Kamal-unit mechanics (`-c`/`--config-file`, per-unit `secrets_path`/`hooks_path`, the `config/deploy.<unit>.yml` naming convention) are **not** exercised here, because only one unit ends up in the Kamal-managed subset. A hypothetical variant where both `apps/api` and a second backend unit are selected for Kamal would exercise that pattern, but is intentionally not built as a second fixture — covering it would duplicate what `examples/multi-service-repo.md` already documents.
- Cross-cutting patterns (`additional-runtime-dependencies.md`, `large-build-artifacts.md`, `database-migrations.md`) are not exercised — `apps/api` has no secondary runtime, no large assets, and no database/migration tooling in this fixture.
- Dockerfile/deploy.yml generation correctness for Node.js itself is covered by `agents/recipes/nodejs.md`'s own guidance, not re-verified here.
