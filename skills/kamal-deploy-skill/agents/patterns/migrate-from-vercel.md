# Migrating a Deployable Unit from Vercel to Kamal

This is a cross-cutting pattern, like `agents/patterns/multi-service-repo.md` and `agents/patterns/database-migrations.md`. It does not replace or duplicate any part of the normal Skill workflow — it sequences and wraps the existing workflow with migration-specific discovery, safety gates, and cutover/rollback handling. Everything this pattern does not explicitly own (stack detection, recipes, Dockerfile generation, multi-service mechanics, accessory ownership, wrapper generation, documentation) stays exactly as SKILL.md and the other patterns already define it.

## When this pattern loads

- **Explicit user request** — the user says a project or unit is currently on Vercel and should move to Kamal (e.g. "This project is currently deployed on Vercel. Migrate it to Kamal."). This always triggers the flow, regardless of what repository evidence does or doesn't show.
- **Repository evidence that suggests Vercel relevance** — `vercel.json`, a `.vercel/` directory, `@vercel/*` packages, `VERCEL`/`VERCEL_ENV`/`VERCEL_URL` references in code, CI steps invoking the `vercel` CLI, or similar. Evidence only **suggests** a unit may be migration-relevant — it never **proves** the unit is currently deployed there. A `vercel.json` can be stale, copied from a template, or left over from a platform switch that already happened. When evidence exists but the user hasn't said anything, confirm before treating the unit as part of a migration: "`<unit>` has `vercel.json` / uses `@vercel/*` packages — is it currently deployed on Vercel and part of this migration?" An explicit user statement always overrides uncertainty from repository evidence — never argue with the user's own account of their infrastructure, and never insist a unit is Vercel-hosted (or isn't) purely from repo signals once the user has said otherwise.

## Core model: per-Deployable-Unit, never per-repo

Run `agents/patterns/deployable-units.md`'s discovery and selection **first, unchanged**. This pattern only activates for units that already exist in that output. Do not let "the repository is associated with Vercel" collapse into any of these false equivalences:

- The repository is **one** Deployable Unit. (A monorepo may have several; only some may touch Vercel at all.)
- **Every** Deployable Unit is hosted on Vercel. (One unit's `vercel.json` says nothing about its siblings.)
- **Every** Vercel-related unit should be migrated. (The user may want to migrate one unit and leave another on Vercel deliberately — that is a valid outcome, not a gap.)

For each unit discovered with Vercel evidence or named in an explicit request, confirm with the user which of those units are actually in scope for this migration before doing any inventory work on them. A unit not in scope is left alone — same as any unit the user doesn't select for Kamal management in the base workflow.

Migration work on one unit must never read, write, or infer anything about a sibling unit's root, Dockerfile, `deploy.yml`, secrets, or accessories. This is the same per-unit isolation `agents/patterns/deployable-units.md` and `agents/patterns/multi-service-repo.md` already require generally — migration does not relax it.

## Three things to keep distinguishable, per in-scope unit

1. **Current state (Vercel)** — what Vercel currently provides for this unit, as inventoried in Phase 1 below. A record of what's being left behind; never edited by anything this pattern does.
2. **Target state (Kamal)** — exactly what the normal SKILL.md Steps 2–6 produce for this unit, via its stack recipe and whatever cross-cutting patterns already apply. This pattern does not add to or restate that output — it only feeds it inputs (see Phase 4).
3. **Migration decisions** — the per-item resolution: kept as-is / replicated by an existing Kamal/Skill feature / replaced by an external service / intentionally dropped with the user's sign-off / still unknown and needs user input.

When reporting findings to the user, keep the **source** of each item visible too: repository evidence, user-provided information, or (if available) authenticated external tooling/account access. These are different kinds of evidence with different reliability, and conflating them is how a migration ends up guessing. Do not assume access to the user's Vercel account. If authenticated Vercel CLI/API access happens to be available in the environment, it may be used **read-only** during discovery (e.g. listing current env var names/scopes, domains) — never to make changes during discovery, and never to invent a value that tool access didn't actually return.

## Phase 1: Inventory current Vercel state

Bounded to what's actually present — do not write up every possible Vercel feature regardless of relevance. For the in-scope unit, check what applies from:

- `vercel.json` (if present): `rewrites`, `redirects`, `headers`, `crons`, `functions`/`builds`, `env`, `regions`
- Framework/project configuration and build/install/output behavior (framework auto-detection, build command, install command, output directory/mode — e.g. Next.js `output: 'standalone'` vs default vs `'export'`, already checked by `agents/recipes/nextjs.md`)
- Vercel-related environment references in code (`VERCEL`, `VERCEL_ENV`, `VERCEL_URL`, `VERCEL_REGION`, `NEXT_PUBLIC_VERCEL_*`)
- API routes / serverless functions, including a loose `api/` directory with no framework (plain Vercel Functions)
- Middleware / Edge runtime usage (`middleware.ts`/`.js` at the project root, `export const runtime = 'edge'`)
- Cron / scheduled behavior (`vercel.json`'s `crons`, or a dashboard-only schedule the user mentions)
- ISR / revalidation / caching assumptions (`revalidate` options, `next/cache` usage)
- Image optimization (`next/image`, `images.remotePatterns`/`domains`)
- Static assets / filesystem assumptions (anything assuming a read-only or ephemeral filesystem, or Vercel's CDN for static files)
- Vercel-specific packages/services (`@vercel/kv`, `@vercel/blob`, `@vercel/postgres`, `@vercel/og`, `@vercel/analytics`, `@vercel/speed-insights`, `@vercel/edge-config`)
- Domains/aliases (rarely in-repo now; usually dashboard-only — note as unknown rather than skipping)
- Preview-deployment assumptions (branch/PR workflows, docs, or CI referencing preview URLs)
- Vercel-related CI/deploy commands (`.github/workflows/*.yml` invoking `vercel deploy`/`vercel --prod`, `amondnet/vercel-action`, etc.)

Record each finding with its evidence (file + line, or "no repo evidence — ask") so the inventory stays auditable.

## Phase 2: Classify each finding

Use this fixed set of buckets — do not invent per-feature categories:

| Bucket | Meaning |
|---|---|
| Works unchanged | Behaves the same under Kamal with no action needed |
| Already handled by existing Kamal Skill | Covered by a Step/recipe/pattern that already runs — point to it, don't restate it |
| Requires container/runtime configuration | Needs a Dockerfile/runtime adjustment within the normal recipe (e.g. install a missing runtime dependency, adjust `CMD`) |
| Requires Kamal/server equivalent | The Vercel-platform mechanism needs a server-side stand-in (cron → hook/system cron/external scheduler; `vercel.json` redirects/headers → framework config or proxy rule) |
| Requires external service | Needs a managed service decision (Vercel KV/Blob/Postgres/Edge Config → keep as external, or replace) — same shape as the existing dependency-ownership question in SKILL.md Step 4b #6, not a new mechanism |
| Requires application change | The app's own code assumes Vercel-specific behavior (Edge-runtime-only APIs, `VERCEL_URL` branching, `waitUntil`) and needs a code change outside this Skill's scope to implement here |
| Vercel-specific behavior no longer needed | Platform-only convenience (preview-deploy env wiring, `@vercel/analytics` snippet) that can simply be dropped |
| Unknown / requires user input | Not resolvable from repository evidence — see Phase 3 |

A representative signal → bucket mapping (illustrative, not exhaustive — classify what's actually found, don't pad the inventory with hypothetical features):

| Signal | Usual bucket |
|---|---|
| `redirects`/`headers`/`rewrites` in `vercel.json` | Works unchanged (move into the framework's own config) or requires Kamal/server equivalent (proxy rule) for a non-framework project |
| `functions`/`builds` (generic serverless) | Requires Kamal/server equivalent — each function becomes a route in the containerized server |
| `crons` | Requires Kamal/server equivalent — see `agents/patterns/database-migrations.md`'s hook-vs-inline reasoning for how pre/post-deploy hooks work, or an external scheduler |
| Edge Middleware / `runtime: 'edge'` | Requires application change in most cases — Edge runtime's API surface is narrower than Node's |
| `@vercel/kv`/`blob`/`postgres`/Edge Config | Requires external service — route through SKILL.md Step 4b #6's ownership question |
| ISR / `revalidate` | Works unchanged in most cases (Next's standalone server supports on-disk ISR) — flag the lost multi-region edge cache as a behavior change, not a blocker |
| `next/image` optimization | Works unchanged for most traffic levels; requires external service only if the user was relying on Vercel's global image CDN at real scale |
| `@vercel/analytics` / Speed Insights | Vercel-specific behavior no longer needed |
| `VERCEL`/`VERCEL_ENV`/`VERCEL_URL` in app code | Requires application change — needs an equivalent env var under Kamal |
| Preview deployments relied on by the team | Unknown / requires user input — Kamal has no automatic per-branch equivalent; a staging destination is the closest analog, not a replacement |
| Domains/aliases | Unknown / requires user input — not reliably in-repo |

## Phase 3: Identify unknowns — ask, never guess

Never invent a secret or environment variable value that isn't actually available from the repo, the user, or (read-only) authenticated tooling. Repository evidence can show that a variable is *referenced*; it essentially never shows its *value* or its per-environment scope. Things that routinely cannot be discovered from the repo and must be asked:

- Actual secret/env values and which Vercel environment (production/preview/development) each belongs to
- Current custom domains/aliases
- DNS registrar/provider and who controls it (reuse the question `agents/recipes/terraform.md` already asks — don't ask it a second way)
- Whether preview deployments are workflow-critical or an acceptable gap
- Dashboard-only cron schedules not reflected in `vercel.json`
- Whether Vercel-managed storage should be kept (as an external service) or replaced
- Observability/analytics expectations that should carry over

## Gate: Phase 4 cannot start until Phases 1–3 are shown complete

This gate is **operational, not implied by phase ordering**. For every migrating Deployable Unit, before any target file (Dockerfile, `deploy.yml`, secrets template, or application code) is generated or changed, the agent must output all three of the following, explicitly, for that unit:

```
CURRENT STATE
<Phase 1 inventory — what Vercel currently provides, with evidence/source per item>

TARGET-RELEVANT MIGRATION DELTA
<Phase 2 classification, limited to findings that affect what Step 2–5 would generate —
 i.e. everything except items classified "Unknown / requires user input" that are purely
 cutover-relevant (domains, preview-deploy workflow, dashboard-only schedules)>

UNRESOLVED BLOCKERS
<Phase 3 unknowns that materially affect target generation, and their resolution status>
```

A blocker is **target-relevant** (must be resolved before Phase 4) if leaving it unresolved would force the agent to invent, guess, or omit something in the generated Dockerfile/`deploy.yml`/secrets/application code. A blocker is **cutover-only** (may stay open past Phase 4) if it only matters for Phase 6–12 — e.g. the exact current DNS record value, or whether preview deployments are workflow-critical. When classifying an unknown, say explicitly which bucket it's in and why; do not default everything to "cutover-only" to skip the gate.

If any target-relevant blocker is still unresolved, Phase 4 does not start for that unit: no Dockerfile, `deploy.yml`, secrets template, or application-code change may be written. Ask the user to resolve it, or ask whether they want to proceed with an explicit, stated gap (which itself becomes a recorded migration decision, not a silent skip).

**Regression protection:** `tests/fixtures/vercel-migration/EXPECTED.md` requires that no target file exists for `apps/web` until this three-part report has been produced for it, and specifically that the `KV_REST_API_URL` unknown (Phase 3) is resolved or explicitly deferred-with-sign-off before `config/deploy.yml`/Dockerfile generation — not silently dropped.

## Phase 4: Build the Kamal target using the existing Skill, unchanged

Resume the normal SKILL.md flow for this unit exactly as it runs for a greenfield unit: Step 2 (stack detection), Step 3 (recipe + cross-cutting patterns), Step 4 (gather info — informed by Phase 3's answers, not re-asked differently), Step 5 (Dockerfile/`deploy.yml`/secrets), Step 5.5 (wrappers), Step 6 (docs). This pattern supplies **inputs** to that flow (e.g. "this env var's value isn't in git — collect it as a real secret, don't template a placeholder value that looks real") — it never generates its own Dockerfile, `deploy.yml`, or accessory block.

**Do not remove, rewrite, or disable any Vercel configuration (`vercel.json`, `.vercel/`, Vercel-specific CI steps) while building the target.** The old platform's configuration stays exactly as it is through this entire phase — target generation is additive, not a replacement operation.

### 4a. Current-service vs. target-service for stateful dependencies (integrates with SKILL.md Step 4b #6)

SKILL.md Step 4b #6 asks whether a detected database/cache dependency should be a Kamal accessory or an external service. During a migration, answering "Kamal-managed accessory" is **not sufficient by itself** — it does not yet say what happens to the data/service the unit currently uses in production. Before proposing or creating a Kamal accessory for a migrating unit, determine, as part of Phase 1/2 above:

- **CURRENT**: what production actually uses today — an external managed provider (Neon, Supabase, PlanetScale, Upstash, Vercel KV/Postgres, etc.), a separately provisioned instance, or something not yet determined. Look for connection strings/env references, `@vercel/kv`/`@vercel/postgres`/`@vercel/blob` usage, and any infra-as-code pointing elsewhere.
- **TARGET**: what Step 4b #6 resolves to for the new Kamal deployment.

If CURRENT cannot be determined from the repo, ask — do not assume "no evidence of an external service" means "there isn't one." Never treat "the user wants Kamal-managed accessories going forward" as approval to discard or replace an existing production database/cache. If CURRENT and TARGET differ for a stateful service (e.g. current = managed Postgres provider, target = Kamal accessory), this is a **data/state migration**, not just a config choice: it requires its own explicit decision from the user (migrate data now, run both temporarily, accept data loss on a non-critical dataset, etc.) before Phase 4 generates the accessory block. This unknown is target-relevant under the gate above whenever the target would create or point at a *different* service than CURRENT — it blocks Phase 4 for that dependency until resolved.

### 4b. Vercel-live application-code compatibility check

Per the "What this pattern does not own" section, Vercel keeps serving production through cutover (Phase 6–11). Any application-code change made as part of target generation can be committed to the same branch Vercel auto-builds, **before** cutover — so "don't delete Vercel config" is not enough; code changes made for Kamal must not silently break the still-live Vercel deployment. Before applying any application-code change (as opposed to purely deployment-side files like `Dockerfile`/`deploy.yml`/`.kamal/*`, which Vercel never builds), classify it:

| Classification | Meaning |
|---|---|
| Deployment-only, invisible to Vercel | `Dockerfile`, `deploy.yml`, `.kamal/*`, CI steps scoped to Kamal — Vercel's build never touches these |
| Application change compatible with current Vercel deployment | e.g. adding a `/api/health` route that Vercel will happily also serve |
| Application change with uncertain Vercel impact | e.g. a runtime/version bump, a dependency change — verify against current Vercel/framework behavior before assuming it's safe, rather than asserting it's harmless |
| Application change incompatible with current Vercel deployment | e.g. Next.js `output: 'standalone'` (changes what Vercel's own build pipeline expects), removing/altering middleware Vercel still relies on, changing a runtime Vercel's build targets |

Never assume `output: 'standalone'`, middleware changes, or runtime changes are harmless to a live Vercel deployment by default — verify current Vercel behavior for that specific change when possible; otherwise treat it as "uncertain" rather than "compatible." Any change classified **uncertain** or **incompatible** requires a migration strategy — e.g. a feature flag/env-gated code path, a separate branch Vercel doesn't auto-build from, or scheduling the change for immediately before cutover — before it is merged or deployed to the branch Vercel builds. This check is scoped to code changes Phase 4 is about to make; it does not reopen or re-litigate Phase 1–3 findings already classified "Works unchanged."

**Regression protection:** `tests/fixtures/vercel-migration/EXPECTED.md` requires this classification to be shown for `apps/web/next.config.js`'s `output` setting and `apps/web/middleware.ts` specifically, since Kamal's standalone-server target plausibly wants `output: 'standalone'` while `apps/web` is still Vercel's live deployment target.

## Phase 5: Validate the Kamal target independently

Before any cutover planning starts, confirm the new Kamal deployment actually works **while Vercel is still serving production** — deploy it behind a non-production domain/subdomain or a staging destination (`agents/patterns/multi-service-repo.md`'s separation of destinations, or a simple `staging.<domain>` per `examples/multi-destination.md`). A passing `docker build` (SKILL.md Step 5) proves the image builds — it does not prove behavioral equivalence. Spot-check the Phase 2 findings that aren't "works unchanged," especially anything classified as "requires Kamal/server equivalent" or "requires application change" (cron actually fires, middleware-equivalent behaves correctly, image optimization renders).

## Phase 6: Prepare cutover and a concrete rollback plan

Keeping the Vercel deployment alive is necessary but is **not by itself** a rollback plan. Before proposing cutover, record the literal pre-cutover state needed to reverse it — the current DNS record type/value/TTL at the domain in question, or the current alias/domain assignment on the Vercel project — so there is an exact, written path back, not just "Vercel is still there." Do not perform an actual rollback test against production to produce this plan; the plan must exist and be concrete, but exercising it against live traffic is not required.

## Phase 7: Explicit approval gate

**Never perform a production cutover without the user's explicit approval of that specific action.** This is a dedicated confirmation, not something inferred from the user having agreed to the migration in general or to earlier steps.

Once the user explicitly approves cutover:

- If the agent has the necessary access and tooling already available and authorized in this session/environment (e.g. an authenticated DNS provider API/CLI, an authenticated Vercel CLI/API), it **may execute the cutover itself**.
- If it does not have that access or tooling, it must give the user the **exact** required action instead — the specific record type, name, and value to change, at which provider, not a generic "update your DNS."

The same two-path principle (execute if able, otherwise give exact steps) applies to rollback.

Approval for cutover should also cover whether rollback may proceed automatically if production verification fails, since that is frequently time-sensitive. If the user didn't say either way, ask immediately when verification fails rather than guessing or leaving a failed cutover unresolved.

## Phase 8: Cutover

Execute (or hand off, per Phase 7) the domain/traffic switch recorded in Phase 6.

## Phase 9: Production verification

Confirm the Kamal deployment is correctly serving real traffic post-cutover: health checks, and a spot-check of the same Phase 2 items validated in Phase 5, now against production.

## Phase 10: Rollback, if verification fails

Execute the Phase 6 rollback route — agent-executed if the access/tooling and prior approval (Phase 7) cover it, otherwise the exact user steps. Do not leave a failed verification unresolved while waiting on an approval round-trip the user already granted.

## Phase 11: Rollback window

After a successful cutover and verification, keep the Vercel deployment and the concrete rollback route (Phase 6) intact and valid for an explicit, user-agreed bake period. This window exists independently of whether rollback was ever triggered — it is the safety margin, not a sign that something went wrong.

## Phase 12: Decommission (separate, later, explicit approval)

Removing or disabling the old Vercel deployment/configuration is **never** implied by a successful cutover, a passed verification, or the end of the rollback window. It requires its own distinct, explicit user request, made separately from cutover approval. Until that request happens, leave Vercel's configuration and project exactly as they are.

## Scope discipline: unrelated cleanup/hardening is surfaced, not applied

Migration work routinely surfaces unrelated issues in the unit being migrated (an insecure Dockerfile `USER root`, an outdated dependency, a missing `.dockerignore`). Fixing these is not this pattern's job, and bundling them into migration changes makes the Vercel-live compatibility check (4b) and the migration diff harder to reason about. Only make a change outside of what Phase 1–4 above actually require when:

- it's required for deployment correctness (the recipe/Dockerfile won't run or pass its health check without it), or
- the user explicitly approved it as a separate, named change.

Otherwise, note the finding in the migration summary and leave it alone. This mirrors a general Skill rule, not a migration-specific one — see SKILL.md Step 5 item 9 ("Scope discipline").

## What this pattern does not own

Everything below stays exactly as the rest of the Skill already defines it — this pattern references these, it never restates or duplicates them:

- Deployable Unit discovery and selection (`agents/patterns/deployable-units.md`)
- Stack detection and recipe selection (SKILL.md Steps 2–3)
- Dockerfile generation and validation (SKILL.md Step 5)
- Multi-service-repo mechanics — `-c`/`--config-file`, per-unit `secrets_path`/`hooks_path` (`agents/patterns/multi-service-repo.md`)
- Database/cache dependency ownership and accessories (SKILL.md Step 4b #6)
- `deploy.yml` generation (stack recipes, `references/deploy-yml-reference.md`)
- Normal Dockerfile/build validation (SKILL.md Step 5)
- `bin/` wrapper generation (SKILL.md Step 5.5)
- Deployment documentation, including the Deployable Units table (SKILL.md Step 6)

## Resuming the base workflow

After Phase 4, resume exactly at SKILL.md's normal Step 5.5/Step 6 for this unit. After Step 6, continue with Phases 5–12 above for this unit before SKILL.md Step 7's summary is written for the run.
