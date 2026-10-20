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

This variant changes only the selection answer, not discovery: suppose the user instead asks Kamal to manage **both** `apps/api` and `apps/web` (dropping the Vercel hosting for `apps/web`), and `apps/web`'s frontend code needs to call `apps/api`'s `/health` (or any) endpoint server-side.

Expected behavior, per `agents/patterns/multi-service-repo.md`'s "Inter-service communication" section:

- The agent must **not** write a guessed container hostname such as `apps-api-web-1`, `api-web-1`, or any `<service>-web-N` pattern into `apps/web`'s code or config as the way to reach `apps/api`. This is true even if the guess is accompanied by an `UNVERIFIED`/`TODO` comment — a disclaimer does not make an invented hostname acceptable, and an agent that emits one (commented or not) fails this fixture.
- The default, expected answer is for `apps/web` to call `apps/api` via `apps/api`'s own `proxy.host` domain over HTTPS, the same way any other client would — not a private Docker-network shortcut invented for the occasion.
- If the agent instead determines a private, non-publicly-routable channel is specifically required, it must say so explicitly and treat the choice of mechanism (private network/VPN, firewalled port, etc.) as an open question requiring the user's decision — not resolve it silently with a guess.
- This variant now exercises `agents/patterns/multi-service-repo.md`'s `-c`/`--config-file` mechanics (both units selected), which the base scenario above intentionally leaves out of scope.

## Explicitly out of scope for this fixture

- Multi-Kamal-unit mechanics (`-c`/`--config-file`, per-unit `secrets_path`/`hooks_path`, the `config/deploy.<unit>.yml` naming convention) are **not** exercised here, because only one unit ends up in the Kamal-managed subset. A hypothetical variant where both `apps/api` and a second backend unit are selected for Kamal would exercise that pattern, but is intentionally not built as a second fixture — covering it would duplicate what `examples/multi-service-repo.md` already documents.
- Cross-cutting patterns (`additional-runtime-dependencies.md`, `large-build-artifacts.md`, `database-migrations.md`) are not exercised — `apps/api` has no secondary runtime, no large assets, and no database/migration tooling in this fixture.
- Dockerfile/deploy.yml generation correctness for Node.js itself is covered by `agents/recipes/nodejs.md`'s own guidance, not re-verified here.
