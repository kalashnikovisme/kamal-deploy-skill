# Deployable Unit Discovery and Selection

This pattern runs **first**, before stack detection (SKILL.md Step 1 delegates to it immediately). It replaces any assumption that a repository is a single application with a repeatable discovery-and-selection process.

## Definition

A **Deployable Unit** is an application or service that can reasonably have its own deployment lifecycle, image/process, runtime configuration, or hosting target.

A repository can contain zero, one, or many Deployable Units. Kamal may end up managing all of them, some of them, or (rarely, if the user is just asking about an internal library) none of them.

## What does NOT determine Deployable Unit-hood

Do not use these signals, alone or together, to decide how many units exist:

- **Directory count.** A repo with many top-level directories (`app/`, `lib/`, `packages/`, `modules/`) is not automatically multi-unit. A Rails app with `app/`, `lib/`, and `packages/` is typically still **one** Deployable Unit if those directories are internal code organization for a single running process.
- **Presence of a root workspace/monorepo tool.** `package.json` `"workspaces"`, `pnpm-workspace.yaml`, Nx, Turborepo, a Cargo workspace, etc. are **build/dependency-management tooling**, not deployment topology. Their presence proves nothing about how many units exist — a workspace repo can be one unit (e.g. a single app that happens to use workspaces for internal packages) or many (e.g. a frontend, an API, and a worker that each publish independently).
- **Absence of a workspace tool.** Likewise, multiple independently-run apps living side by side in plain directories (no shared tooling at all) are still multiple units.
- **Existing Kamal-readiness artifacts.** Whether a candidate already has a `Dockerfile`, a `config/deploy.yml`, a health-check endpoint, a production-mode framework setting, or any other sign that it's already set up for Kamal specifically. Deployable Unit status is an architectural/deployment-lifecycle classification - "can this run and be deployed as its own process" - decided entirely by Step 3's independent-deployability test. Kamal-readiness is a separate, later concern (SKILL.md Step 5, Apply Recipe), where the Skill checks for and creates whatever is missing. A candidate that passes Step 3's test is a Deployable Unit full stop, even if it has no Dockerfile, no health endpoint, and no existing Kamal config - it is a Deployable Unit that needs additional work before Kamal can deploy it, never a unit whose status is "conditional" on already having that work done.

Repository/build structure and deployment topology are separate concepts. Evaluate them separately.

## Discovery and Selection Flow

### 1. Inspect repository structure

Survey the repo for signals of running processes and existing deployment setups:

- Top-level and nested directories containing their own manifest/build file (`package.json`, `go.mod`, `requirements.txt`/`pyproject.toml`, `pom.xml`/`build.gradle`, `*.csproj`, `mix.exs`, `composer.json`, etc.)
- `Dockerfile`s anywhere in the tree (each is a strong signal of an independently buildable image)
- `docker-compose.yml` / `compose.yml` service lists (each service is a discovery lead, not an automatic unit)
- Existing non-Kamal deployment config that signals a candidate is *already* deployed somewhere: `vercel.json`, `netlify.toml`, `railway.json`/`railway.toml`, `fly.toml`, `Procfile`, `app.yaml` (App Engine/Heroku-style), `.github/workflows/*.yml` with deploy steps referencing a specific app path
- A root-level workspace/monorepo tool, if present — note it, but per the rule above, do not use it to conclude anything about unit count on its own

### 2. Discover candidate applications/services

A candidate is any subtree (including the repo root itself, for a non-monorepo project) that has its own manifest/build file. List every candidate before judging any of them — do not stop at the first match the way stack detection does.

### 3. For each candidate, determine independent deployability

Ask, for each candidate:

- Does it have an identifiable way to run as a standalone process — a start/serve/run script, a framework entrypoint (`main.go`, `main.ts`/`main.js` behind a server, `manage.py runserver`-equivalent, a Rails/Phoenix/Spring Boot boot command), or its own `Dockerfile`/`CMD`?
- Does it listen on its own port, or run as its own long-lived worker/daemon/scheduled job?
- Could it reasonably be deployed, restarted, rolled back, or scaled on its own, without redeploying its siblings?

If yes to these, the candidate is independently deployable. If a candidate exists only to be **imported** by other candidates (a shared UI component library, a shared types/utils package, an internal SDK with no entrypoint and no listener) and has no standalone run path of its own, it is **not** a Deployable Unit — it is a dependency of one or more units, and the Skill should not try to deploy it.

When genuinely ambiguous, ask the user directly rather than guessing: "I found `<path>` — does this run as its own service, or is it a library consumed by `<other candidate>`?"

### 4. Build the Deployable Unit list

For each candidate that passed step 3, record:

- Name (derived from directory name unless the user says otherwise)
- Root path within the repo
- Evidence used to classify it as independently deployable
- Any existing hosting-platform evidence found in step 1 (e.g. "has `vercel.json`") — this is a signal to surface to the user in step 5, never a final decision made on the Skill's behalf

Present the full list to the user, including units that are clearly not going to be Kamal-managed (e.g. a frontend already on Vercel). Discovery produces **all** units in the repo; selection (step 5) narrows to the Kamal-managed subset.

If exactly one Deployable Unit is found, state it plainly ("Found one deployable unit: `<name>`") and proceed without a selection question — there is nothing to select between.

### 5. Determine which Deployable Units should be managed by Kamal

If more than one Deployable Unit was found, list them with their stack (once detected — see step 6) and any existing-hosting evidence, then ask explicitly:

> "I found these deployable units: `<list>`. Which of these should this Kamal configuration manage? (You can select more than one. Units you don't select are left as-is — I won't assume they should move off their current platform.)"

Record the answer as the **Kamal-managed subset**. A unit that is not selected is not touched by any later step — no Dockerfile, no deploy.yml, nothing. It is still documented (see Step 6 of SKILL.md) so the resulting setup is legible as a whole, but it is otherwise out of scope.

Multiple units may be selected. A single repository may end up with more than one Kamal-managed unit — see `agents/patterns/multi-service-repo.md` for how that is represented in config.

### 6. Apply stack recipes and cross-cutting patterns independently, per selected unit

For each unit in the Kamal-managed subset, run SKILL.md Step 2's stack-detection table and Step 3's recipe loading **scoped to that unit's root path**, not the repo root. Each unit gets its own stack detection, its own recipe, its own Dockerfile check, its own `config/deploy.yml` (or `config/deploy.<unit>.yml` — see the multi-service pattern), and its own cross-cutting pattern checks (`agents/patterns/additional-runtime-dependencies.md`, `agents/patterns/large-build-artifacts.md`, `agents/patterns/database-migrations.md`), independently of its siblings. One unit using Postgres and another using none, or one unit on Go and another on Node, is normal and expected — do not let one unit's stack or needs bleed into another's generated config.

If the Kamal-managed subset has exactly one unit, the rest of the Skill behaves exactly as it did for a single-app repo: plain `config/deploy.yml`, no special naming, no `-c` flag needed anywhere. The multi-service naming/`-c` convention in `agents/patterns/multi-service-repo.md` only applies when the **Kamal-managed subset** has more than one unit — never merely because the repo *discovered* more than one.

## Worked Examples

- A pnpm/Turborepo repo with `apps/frontend`, `apps/api`, `apps/worker`: three candidates, all three pass the independent-deployability test (each has its own start command and process) → three Deployable Units, regardless of the shared Turborepo config at the root.
- A Rails repo with `app/`, `lib/`, `packages/`: one candidate at the repo root (the Rails app itself); `lib/` and `packages/` are internal code with no standalone entrypoint → one Deployable Unit.
- A repo with `frontend/` (has `vercel.json`, no Dockerfile) and `api/` (has a `Dockerfile`, no existing hosting config): two Deployable Units. The user may select only `api` for Kamal management — `frontend` stays documented but untouched.
- A repo with `api/` and `worker/`, both lacking any existing hosting config, both independently runnable: two Deployable Units, and the user may select both for Kamal management → triggers the multi-service pattern.

## Interaction with Step 0 (Rails Guard)

Run Step 0's Rails check against **each discovered candidate's root**, not just the repo root. A monorepo containing one Rails unit and one Node unit should redirect the Rails unit to tramway-skill while continuing to configure the Node unit through this skill. Note this to the user explicitly rather than aborting the whole run.
