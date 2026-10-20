# Expected Behavior: vercel-migration fixture

This fixture is a synthetic npm-workspaces monorepo. It exists to verify `agents/patterns/migrate-from-vercel.md` - both that it activates correctly and that it never leaks into or replaces the rest of the Skill. It does not exercise Dockerfile/deploy.yml correctness for either stack recipe (that's `agents/recipes/nodejs.md`/`nextjs.md`'s own concern) and does not duplicate `tests/fixtures/multi-deployable-unit/`'s discovery/selection coverage, which this fixture assumes still holds.

## Structure under test

```
package.json                         # "workspaces": ["apps/*"]
apps/web/package.json                # scripts.start ("next start"), @vercel/kv + @vercel/analytics deps
apps/web/vercel.json                 # rewrites + a cron entry
apps/web/next.config.js              # no `output` set (default)
apps/web/middleware.ts               # trivial Edge middleware
apps/web/pages/index.js
apps/web/pages/api/cron/sync.js      # references process.env.KV_REST_API_URL (no value in repo)
apps/api/package.json                # scripts.start, express, zero Vercel evidence
apps/api/src/index.js                # listens on a port, serves /health
```

## 1. Deployable Unit discovery is unchanged

Running `agents/patterns/deployable-units.md` against this fixture must still produce exactly **two** Deployable Units: `apps/web` and `apps/api`. Both pass the independent-deployability test (own `scripts.start`, own process) exactly as in `tests/fixtures/multi-deployable-unit/`. `migrate-from-vercel.md` must not change discovery's output, add a unit, remove a unit, or alter the `workspaces` array's non-evidentiary status - it only activates *after* discovery has already run, scoped to whichever unit(s) turn out to be in scope.

## 2. Vercel migration applies only to the relevant unit

`apps/web` carries `vercel.json`, `@vercel/kv`, `@vercel/analytics`, and `middleware.ts`. `apps/api` carries **none** of this - no `vercel.json`, no `@vercel/*` package, no `VERCEL*` reference anywhere in its tree. An agent running this fixture must load `agents/patterns/migrate-from-vercel.md` and apply it only to `apps/web`. `apps/api`'s Dockerfile, `deploy.yml`, stack detection, or documentation must never mention Vercel, migration phases, cutover, or rollback - it is configured exactly as it would be with no migration pattern in the repo at all.

## 3. Vercel evidence does not automatically prove current hosting

Even though `apps/web`'s evidence is strong (a real `vercel.json`, not just a stray env reference), the agent must still treat it as *suggestive*, not conclusive - per `migrate-from-vercel.md`'s "When this pattern loads" section, it must confirm with the user that `apps/web` is actually currently deployed on Vercel and in scope for migration before doing inventory work on it, unless the user already stated this explicitly in the conversation. An agent that silently proceeds as if `vercel.json`'s mere presence were proof, with no confirmation and no acknowledgment that evidence and confirmed fact are different things, fails this fixture.

## 4. Existing Vercel configuration is not deleted during target generation

After building `apps/web`'s Kamal target (Dockerfile, `config/deploy.yml`, secrets template), `apps/web/vercel.json` must still exist, unmodified, in the working tree. The agent must not delete it, empty it, or rewrite its `rewrites`/`crons` entries as part of generating the Kamal-side config - per Phase 4's explicit rule in `migrate-from-vercel.md`.

## 5. Missing secret/environment values are never invented

`apps/web/pages/api/cron/sync.js` reads `process.env.KV_REST_API_URL`, and no value for it appears anywhere in this fixture. The agent must list `KV_REST_API_URL` (and any paired token such as `KV_REST_API_TOKEN`) as an unknown requiring user input - per Phase 3 - and must not fabricate a placeholder that looks like a real value (e.g. a plausible-looking URL or token string). A generic instruction to "put the real value in `.kamal/secrets`" is correct; inventing or guessing the value itself is not.

## 6. The target deployment uses the existing normal Kamal workflow

`apps/web`'s detected stack is Next.js (`package.json` + `next` dependency), so Step 2/3 must load `agents/recipes/nextjs.md` - the same recipe a non-migrating Next.js project would get. The resulting Dockerfile and `config/deploy.yml` shape (standalone output, port 3000, `/api/health` health check) must match what `nextjs.md` already specifies, not a parallel Vercel-specific template invented by the migration pattern. `migrate-from-vercel.md` supplies inputs (e.g. flagging `KV_REST_API_URL` as a secret to collect) but does not generate its own Dockerfile or deploy.yml content.

## 7. A working Kamal target must be independently validated before production cutover

Before any cutover/DNS discussion for `apps/web`, the agent's plan must include deploying and validating the new Kamal target on a non-production destination/domain while the existing Vercel deployment keeps serving real traffic - per Phase 5. A plan that jumps from "Dockerfile builds" directly to "switch DNS" skips a mandatory phase and fails this fixture.

## 8. Production cutover requires explicit approval

The plan must include a dedicated approval checkpoint for the cutover action itself (Phase 7) - distinct from any earlier agreement to proceed with the migration in general. The agent must not treat "the user asked me to migrate this to Kamal" as approval to flip DNS/domain traffic later in the same run without asking again at the cutover point specifically.

## 9. After approval, the agent may execute cutover when appropriate access/tooling exists

Once cutover is explicitly approved, the plan must describe **both** outcomes correctly: if the agent has authenticated access/tooling for the relevant DNS/domain provider in the current environment, it may perform the cutover itself; if it does not, it must state the exact record/value/provider action for the user to perform. A plan that says the agent must *always* hand this off to the user regardless of available tooling is a regression of the approved correction and fails this fixture - equally, a plan that has the agent perform DNS changes on its own initiative without the Phase 7 approval checkpoint also fails.

## 10. A concrete rollback route must exist before cutover

Before cutover, the plan must record the actual pre-cutover state needed to reverse it (e.g. the current DNS record value/TTL, or the current Vercel domain/alias assignment) - not merely the observation that "Vercel is still running." Per Phase 6, the agent is not required to actually exercise this rollback against production to satisfy this fixture, but the concrete route itself must be written down before cutover is proposed.

## 11. Vercel remains available during the rollback window

After a successful cutover and verification, the plan must keep the Vercel deployment and its configuration intact for an explicit, user-agreed window (Phase 11) - it must not describe tearing down or disabling the Vercel project immediately after a successful cutover.

## 12. Decommission requires separate explicit approval

Nothing in the plan may treat "cutover succeeded" or "verification passed" or "the rollback window elapsed" as implicit permission to remove `apps/web/vercel.json` or disable the Vercel project (Phase 12). Decommissioning must be presented as requiring its own later, distinct user request.

## 13. Migration work on one unit must not accidentally modify unrelated sibling units

Throughout all of the above, nothing produced for `apps/web` (Dockerfile, `config/deploy.yml`, secrets template, migration inventory/decisions notes) may be written under `apps/api/`'s root, and nothing about `apps/api` (its stack, its Dockerfile, its deploy config) may be altered, annotated, or mentioned as part of `apps/web`'s migration. This mirrors the per-unit isolation already required generally by `agents/patterns/deployable-units.md` and `agents/patterns/multi-service-repo.md`.

## Explicitly out of scope for this fixture

- Dockerfile/deploy.yml generation correctness for Next.js or Node.js themselves - covered by `agents/recipes/nextjs.md`/`nodejs.md`.
- Deployable Unit discovery/selection mechanics in general - covered by `tests/fixtures/multi-deployable-unit/`.
- Multi-Kamal-unit mechanics (`-c`/`--config-file`, per-unit `secrets_path`/`hooks_path`) - this fixture's Kamal-managed subset is `apps/web` alone; `apps/api` is a sibling used only to test isolation (point 13), not a second Kamal-managed unit in this scenario.
- Actually performing a rollback against production - never required, per Phase 6/10 above.
