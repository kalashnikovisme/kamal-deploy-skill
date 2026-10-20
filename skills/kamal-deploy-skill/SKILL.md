---
name: kamal-deploy-skill
description: 'Configure Kamal deployment for any non-Rails technology stack. Use when the user asks to implement, set up, or configure deployment via Kamal, deploy.yml, or Docker-based deployment in a non-Rails project. Covers Node.js / Next.js, Python, Go, PHP / Laravel, Java / Spring Boot, .NET, Elixir / Phoenix, Terraform / infrastructure provisioning, and unknown-stack fallback. Handles both single-application repos and repos containing multiple independently deployable services. If the project is Ruby on Rails, this skill redirects to tramway-skill instead.'
---

# Kamal Deploy Skill

Use this skill as a stack-driven playbook for configuring Kamal deployment on non-Rails projects.
Prefer small, safe, verifiable changes. Do not assume a Node.js-only workflow: recipe selection stays stack-driven, and repository-specific wrapper scripts are an operational layer on top of the stack recipe, not a replacement for it. Do not assume a repository contains exactly one application — some repos contain several independently deployable services, of which Kamal may end up managing one, several, or all. At every stage the user can skip any proposed step; respect skips, note risks briefly, and continue.

## Runtime and File Loading

This skill runs in two environments. Behavior differs for file loading:

**Codex** - `agents/*.md` files are loaded natively by the Codex agents system. The "load `agents/X.md`" instructions work without extra steps.

**Claude Code** - `agents/*.md` files are NOT auto-loaded. Whenever this document says "load `agents/X.md`", you MUST use the Read tool to read that file before continuing.

Resolve every relative path in this document (`agents/X.md`, `references/X.md`, `examples/X.md`, `VERSION`, ...) in this order - this applies everywhere below, including the explicit path lists in Step 3 and the References/Examples sections:

1. **Preferred (portable, works for any install method):** join the relative path onto this skill's own base directory, as announced when the skill was invoked (for example a line such as "Base directory for this skill: `<path>`"). This is correct regardless of whether the skill was installed manually, via a Claude Code plugin marketplace, or via Codex, since it always points at wherever this specific copy actually lives.
2. **Fallback (legacy manual install):** `~/.claude/skills/kamal-deploy-skill/<relative-path>`
3. **Fallback (running from inside the source repo):** `skills/kamal-deploy-skill/<relative-path>`

Do NOT skip loading agent files. They contain mandatory rules for the active surface area. If a file cannot be read, report the error to the user instead of silently continuing.

Version policy:

1. The skill version is stored in `VERSION` at the root of this skill directory.
2. **MANDATORY: When this skill is loaded, immediately read the `VERSION` file and show the version to the user** as the first output, before any other response. Format: `kamal-deploy-skill v<version>`. Resolve the path using the same order as above: this skill's own base directory first, then `~/.claude/skills/kamal-deploy-skill/VERSION`, then `~/.codex/skills/kamal-deploy-skill/VERSION`, then any repository-local `skills/kamal-deploy-skill/VERSION`.
3. If the user asks for the skill version, read and report that `VERSION` value.

## Step 0: Rails Guard (repo root)

**Before any other action**, check whether the **repository root** is itself a Ruby on Rails application by looking for ALL of these signals:

- `Gemfile` exists
- `config/application.rb` exists
- `config/routes.rb` exists

Do not scan all project files for this step. Check only those three paths, at the repo root only.

If the repo root IS a Rails application:
- Tell the user: "This project is a Ruby on Rails application. The kamal-deploy-skill does not cover Rails - use **tramway-skill** instead: https://github.com/Purple-Magic/tramway-skill/"
- Stop. Do not proceed with any Kamal configuration.

If the repo root is NOT a Rails application, continue to Step 1. Note: this only rules out the repo root being a single top-level Rails app. A sub-unit discovered in Step 1 may still turn out to be Rails - that is checked per-unit in Step 1, not here.

## Step 1: Discover Deployable Units

Load `agents/patterns/deployable-units.md` and follow it in full before doing anything else. It defines:

- The **Deployable Unit** abstraction: an application/service that can reasonably have its own deployment lifecycle, image/process, runtime configuration, or hosting target.
- Why directory count and the presence/absence of a root workspace/monorepo tool (npm/pnpm/yarn workspaces, Nx, Turborepo, Cargo workspaces, etc.) must **not** be used to infer how many units exist.
- The discovery flow: inspect repository structure -> discover candidate applications/services -> judge each candidate's independent deployability -> build the Deployable Unit list -> select which units Kamal should manage -> apply the rest of this skill independently per selected unit.

Run this once per Skill invocation, before Steps 2+. Its output is:

- The full list of discovered Deployable Units (for documentation later, even the ones Kamal won't manage).
- The **Kamal-managed subset** - the units Steps 2-7 below actually configure.
- For each unit in that subset, re-run Step 0's Rails check against **that unit's own root** (not just the repo root). Redirect any Rails unit to tramway-skill individually and continue with the remaining non-Rails units rather than aborting the whole run.

If the Kamal-managed subset is empty (e.g. the user only wanted documentation of what exists, or every candidate turned out to be Rails or a non-deployable library), stop here and summarize what was found.

If the Kamal-managed subset has exactly one unit, everything below behaves exactly as a single-app repo always has - plain `config/deploy.yml`, no unit suffixes, no `-c` flag. **Steps 2-5.5 below run once per unit in the Kamal-managed subset.** If more than one unit was selected, also load `agents/patterns/multi-service-repo.md` - it defines the `config/deploy.<unit>.yml` naming, the `-c`/`--config-file` mechanism, and how `secrets_path`/`hooks_path` must be kept separate per unit.

## Step 2: Detect Technology Stack

For the current unit (its own root directory - the repo root if there is only one unit), detect the stack by checking for these files in order. Stop at the first match:

| Stack | Detection files |
|-------|------------------|
| Node.js | `package.json` |
| Python | `requirements.txt`, `pyproject.toml`, `Pipfile`, `setup.py` |
| Go | `go.mod` |
| PHP / Laravel | `composer.json` + `artisan` |
| PHP (generic) | `composer.json` |
| Java / Spring Boot | `pom.xml`, `build.gradle`, `build.gradle.kts` |
| .NET | `*.csproj`, `*.sln` |
| Elixir / Phoenix | `mix.exs` |

For Node.js, also read `package.json` to determine the framework (Next.js, NestJS, Express, Fastify, Nuxt, Remix, etc.) - this affects the Dockerfile and health check strategy. Also check `next.config.js`/`next.config.ts` for `output: 'standalone'` vs `output: 'export'` to confirm server mode.

For Python, also read `pyproject.toml` or `requirements.txt` to determine the framework (Django, FastAPI, Flask, etc.).

Announce the detected stack to the user before loading any recipe. For example: "Detected: **Next.js (Node.js)**. Loading Node.js deployment recipe." When there are multiple units, include the unit name: "Unit `api`: detected **Go**. Unit `worker`: detected **Node.js (NestJS)**."

If no stack is detected for a unit, announce: "Could not detect the technology stack automatically for `<unit>`." Then load `agents/recipes/unknown-stack.md` for that unit.

## Step 3: Load Recipe

Load **only** the recipe matching the detected stack for the current unit. Do not load multiple recipes for the same unit. (Different units in the same repo may legitimately load different recipes - that's expected, not an error.)

- Node.js (Next.js) -> load `agents/recipes/nextjs.md`
- Node.js (other) -> load `agents/recipes/nodejs.md`
- Python -> load `agents/recipes/python.md`
- Go -> load `agents/recipes/go.md`
- PHP / Laravel -> load `agents/recipes/php-laravel.md`
- Java / Spring Boot -> load `agents/recipes/java-spring.md`
- .NET -> load `agents/recipes/dotnet.md`
- Elixir / Phoenix -> load `agents/recipes/elixir-phoenix.md`
- Unknown -> load `agents/recipes/unknown-stack.md`

Every recipe operates relative to the **current unit's own root directory** - for a single-unit repo that's the repo root; for a multi-unit repo it's that unit's subdirectory. Do not let one unit's recipe read or write files under a sibling unit's root.

**Claude Code file paths for each recipe:** resolve using the order defined in "Runtime and File Loading" above (this skill's own base directory first); the paths below are the documented fallbacks.

- Node.js (Next.js): `~/.claude/skills/kamal-deploy-skill/agents/recipes/nextjs.md` (fallback: `skills/kamal-deploy-skill/agents/recipes/nextjs.md`)
- Node.js (other): `~/.claude/skills/kamal-deploy-skill/agents/recipes/nodejs.md` (fallback: `skills/kamal-deploy-skill/agents/recipes/nodejs.md`)
- Python: `~/.claude/skills/kamal-deploy-skill/agents/recipes/python.md` (fallback: `skills/kamal-deploy-skill/agents/recipes/python.md`)
- Go: `~/.claude/skills/kamal-deploy-skill/agents/recipes/go.md` (fallback: `skills/kamal-deploy-skill/agents/recipes/go.md`)
- PHP/Laravel: `~/.claude/skills/kamal-deploy-skill/agents/recipes/php-laravel.md` (fallback: `skills/kamal-deploy-skill/agents/recipes/php-laravel.md`)
- Java/Spring: `~/.claude/skills/kamal-deploy-skill/agents/recipes/java-spring.md` (fallback: `skills/kamal-deploy-skill/agents/recipes/java-spring.md`)
- .NET: `~/.claude/skills/kamal-deploy-skill/agents/recipes/dotnet.md` (fallback: `skills/kamal-deploy-skill/agents/recipes/dotnet.md`)
- Elixir/Phoenix: `~/.claude/skills/kamal-deploy-skill/agents/recipes/elixir-phoenix.md` (fallback: `skills/kamal-deploy-skill/agents/recipes/elixir-phoenix.md`)
- Unknown: `~/.claude/skills/kamal-deploy-skill/agents/recipes/unknown-stack.md` (fallback: `skills/kamal-deploy-skill/agents/recipes/unknown-stack.md`)
- Terraform (infrastructure): `~/.claude/skills/kamal-deploy-skill/agents/recipes/terraform.md` (fallback: `skills/kamal-deploy-skill/agents/recipes/terraform.md`)

Also check, for the current unit, whether its cross-cutting situation matches any of these patterns, and load the ones that apply (a unit can match more than one, or none):

- Shells out to a second language runtime, or needs native system packages beyond its primary ecosystem -> load `agents/patterns/additional-runtime-dependencies.md`
- Bakes a large model/dataset/media asset into the image at build time, or the image is unusually large for its stack -> load `agents/patterns/large-build-artifacts.md`
- Has a database and a migration tool -> load `agents/patterns/database-migrations.md` (the recipe's own migration section has the stack-specific command; this pattern has the mechanics and tradeoffs)

**Claude Code paths** for these patterns (resolve using the order in "Runtime and File Loading"): `~/.claude/skills/kamal-deploy-skill/agents/patterns/<file>.md` (fallback: `skills/kamal-deploy-skill/agents/patterns/<file>.md`)

## Step 4: Gather Required Information

### 4a. Infrastructure Check

Ask these two questions separately, one at a time. Ask them **once per repo**, not once per unit, unless the user indicates different units will live on different servers:

1. > "Do you already have a server with SSH access (you have the IP and can SSH in)?"

2. > "Do you already have a DNS provider configured for your domain (the domain is registered and you can manage its DNS records)?"

If there are multiple Kamal-managed units, clarify up front: "Will these units share the same server, or do any of them need their own?" Multiple units sharing one server is the common case and needs only one round of these questions; a unit with its own server/domain needs its own round.

Based on the answers:

| Has server? | Has DNS? | Action |
|---|---|---|
| Yes | Yes | Collect IP + domain. Proceed directly to Step 4b. |
| Yes | No | Load the Terraform recipe - DNS-only provisioning. |
| No | Yes | Load the Terraform recipe - server-only provisioning. |
| No | No | Load the Terraform recipe - full provisioning. |

**Claude Code path for Terraform recipe** (resolve using the order in "Runtime and File Loading"): `~/.claude/skills/kamal-deploy-skill/agents/recipes/terraform.md`
(fallback: `skills/kamal-deploy-skill/agents/recipes/terraform.md`)

After the Terraform recipe completes, resume at Step 4b with the confirmed server IP and domain.

### 4b. Remaining Configuration

Collect the following (ask only what is not already determinable from the project files or from the Terraform step). If there are multiple Kamal-managed units sharing a server/registry, ask these once and apply the shared answers to every unit; only ask per-unit where the answer plausibly differs (domain/subdomain, accessories, service name):

1. **Server IP address(es)** - confirmed in 4a, or ask if not yet known
2. **Docker registry** - ask which option the user wants:
   - **Docker Hub** - Docker Hub username (image: `<user>/<app>`)
   - **GitHub Container Registry** - `ghcr.io/<org-or-user>/<app>`
   - **Private registry** - full registry URL
   - **Local Kamal registry** - a registry running locally on the server (not managed by Kamal); no external registry account needed. Kamal is pointed at it via `registry.server: localhost:<port>`.

   If the user chooses **local Kamal registry**, ask for the port (default: `5555`), then apply these modifications to the `deploy.yml` generated by the stack recipe:

   ```yaml
   # image: reference the local registry
   image: localhost:5555/<APP_NAME>

   # registry: point to the local registry; no credentials needed
   registry:
     server: localhost:5555
   ```

   Remove `KAMAL_REGISTRY_PASSWORD` from `.kamal/secrets` - it is not needed.

3. **Remote builder** - ask:

   > "Where do you want Docker images to be built?
   >
   > - **Local** (default) - Kamal builds the image on this machine using your local Docker, then pushes it to the registry.
   > - **Remote** - Kamal SSHes into the server and builds the image there. Useful when you don't have Docker locally, when the server architecture differs from your machine (e.g. building arm64 images on an amd64 laptop), or when the server has more CPU/RAM than your local machine."

   - **Local** -> no `builder` block needed; omit it from `deploy.yml`.
   - **Remote** -> add to `deploy.yml`:
     ```yaml
     builder:
       remote: ssh://root@<SERVER_IP>
       arch: amd64
     ```

   **Note for local Kamal registry users**: the registry runs on the server and is bound to `127.0.0.1:4443`. A remote builder is required in this case because only the server can reach `localhost:4443`. If the user chose local registry and selects local builder, warn them: "A local builder cannot push to a localhost registry on a remote server. Switch to remote builder, or use an external registry instead."

4. **Service name** - defaults to the unit's directory name if not specified (repo name for a single-unit repo)
5. **Domain / hostname** - confirmed in 4a, or ask if not yet known; for multiple units sharing one server, ask whether each gets its own subdomain
6. **Database/cache dependencies and who owns them** - stack detection (Step 2) may show the unit *depends on* PostgreSQL/Redis/etc. (e.g. a `pg`/`ioredis` package, a `psycopg2`/`redis` import, a configured ORM adapter). That only answers whether the app needs the service - it never by itself answers who provisions/owns it. Treat these as two separate questions:
   - **A. Does the unit depend on this service?** - established by detection above.
   - **B. Who owns/provisions it?** - a Kamal accessory, an existing managed database/cache, an external provider, infra provisioned separately, or another platform's add-on.
   For each detected dependency, check the repo for ownership evidence first (a `DATABASE_URL`/`REDIS_URL` already pointing at a non-localhost managed host, Terraform/infra config provisioning it elsewhere, platform config like `fly.toml`/`render.yaml` attaching a managed instance). If that evidence clearly establishes ownership, state it to the user and move on - don't ask. Otherwise ask explicitly, per dependency:
   > "This project depends on \<PostgreSQL/Redis\>. Should Kamal provision and manage it as an accessory, or does it already connect to an existing/external \<service\>?"
   Only add an `accessories:` block (see `examples/with-postgres.md` / `examples/with-redis.md`) for a dependency the user confirms - or clear repo evidence establishes - should be Kamal-managed. For an externally-owned dependency, add its connection secret to `.kamal/secrets` and skip the accessory block entirely. Never default to creating an accessory merely because the dependency was detected.
7. **Destinations** - does the user want separate staging and production configs?

Do not ask for secrets values in chat. Instruct the user to place secrets in `.kamal/secrets` and `.kamal/secrets-common` as instructed by the recipe (or the unit-suffixed equivalents from `agents/patterns/multi-service-repo.md` when there are multiple Kamal-managed units). If the target repo provides wrapper-managed staging secrets, treat those values as generated or managed by the wrapper flow and do not ask for them ad hoc.

## Step 5: Apply Recipe

Follow the loaded recipe (and any loaded cross-cutting patterns) to, for the current unit:

1. **Check for an existing Dockerfile first.** If one exists, read it before deciding whether to create a new one, and run a quick Kamal-readiness check on it:
   - Does it `EXPOSE`/listen on a single, identifiable port that can be set as `proxy.app_port`?
   - Does the process it runs stay in the foreground (no `&` backgrounding, no daemonizing)? Kamal/Docker expects the main process to be PID 1 and stay running - a script that forks and exits looks like a crashed container.
   - Is there a health-check-able path, or does one need to be added per the recipe's health-check section?
   If any of these fail, note the specific problem to the user before proceeding - don't silently rewrite a working Dockerfile without saying why.
2. Create a `Dockerfile` suited to the stack if none exists, or adjust the existing one only as needed to fix a problem found above.
3. **Validate the Dockerfile** - immediately after writing or changing it, run a test build from the unit's own root:
   ```bash
   docker build --platform linux/amd64 -t kamal-skill-test:build-check . && docker rmi kamal-skill-test:build-check
   ```
   - If Docker is not available locally, skip this step and note it in the summary.
   - If the build succeeds: continue.
   - If the build fails: read the full error output, identify the root cause, fix the `Dockerfile`, and re-run the build. Repeat until the build passes. Do not proceed to the next step until the Dockerfile builds successfully.
   - Common fixable errors: missing base image tag, wrong `COPY` path, missing `RUN` dependency, incorrect `CMD` format, missing build argument.
   - If the error is caused by missing application source files (e.g. the project has no `src/` yet), note this in the summary and continue - the Dockerfile is structurally valid.
4. Create `config/deploy.yml` (or `config/deploy.<unit>.yml` per `agents/patterns/multi-service-repo.md` when there are multiple Kamal-managed units), and `config/deploy.staging.yml` / `config/deploy.production.yml` if multiple destinations.
5. Create `.kamal/secrets` template with placeholder instructions (or the unit-suffixed path from the multi-service pattern).
6. Create `.kamal/hooks/` scripts if the recipe or `agents/patterns/database-migrations.md` calls for them.
7. Add `.kamal/secrets` (or its unit-suffixed equivalents) to `.gitignore`.
8. **Fail-fast startup diagnostics.** If the stack already validates required configuration at boot (crashes immediately with a clear error on missing/invalid env vars, rather than degrading silently), leave it as-is and note it as a point in the unit's favor. If no such check exists and the recipe's env var list includes anything the app cannot run correctly without, do not add new validation code speculatively - just note to the user, in the summary, which env vars are load-bearing so a misconfigured deploy is easy to diagnose from the first boot log rather than from a mysterious runtime error later.

Repeat Steps 2-5 for every unit in the Kamal-managed subset before moving to Step 5.5.

## Step 5.5: Create bin/ Wrapper Scripts

Check whether the target repo already has a Kamal `bin/` layer (e.g. `bin/deploy`, `bin/setup`).

- **Wrappers already exist (Arie layout or similar)** - do not overwrite them. Skip script creation. In Step 6, document the existing wrappers as-is; do not assume they follow the rules below unless you've read them and confirmed it.
- **No `bin/` wrappers exist** - create at minimum `bin/deploy`. Create companion wrappers (`bin/setup`, `bin/logs`, `bin/console`, `bin/status`, `bin/remove`, `bin/app`) only if the user wants the fuller operational layer; otherwise document raw `kamal` commands for those in Step 6 instead of inventing wrappers nobody asked for.
- **Multiple Kamal-managed units** - follow the "bin/ wrappers in a multi-unit repo" section of `agents/patterns/multi-service-repo.md` to decide between per-unit wrappers and a single wrapper with a required unit argument. Either way, the forwarding rules below still apply without exception.

### Wrapper rules (mandatory)

Kamal has real flags that must reach the real `kamal` binary completely unmodified, most importantly `-q`/`--quiet` (mutes per-step output until the run finishes or errors - see https://kamal-deploy.org/docs/commands/deploy/) and `-c`/`--config-file` in multi-unit repos. A wrapper silently breaks these if it does any of the following. Avoid all of them:

1. **Never consume-and-drop unrecognized flags.** Only *read* flags the wrapper itself needs (e.g. peek `-d`/`--destination` to pick which secrets file to source, or peek a unit argument to resolve `-c`) - don't strip them out of the argument list. Every argument the wrapper doesn't specifically need to inspect, `-q`/`--quiet` included, must reach `kamal` verbatim via `"$@"`.
2. **Never pipe or capture kamal's output.** `kamal deploy "$@" | cat`, `| tee`, or `output=$(kamal deploy "$@")` changes kamal's TTY detection and can force it to print progress it would otherwise suppress. Invoke kamal as the last statement with `exec kamal deploy "$@"` so it talks to the real terminal directly.
3. **Never chain a log tail (or anything else) after deploy.** Do not append `&& kamal app logs --follow` or similar after the deploy call - that reintroduces exactly the log stream `--quiet` exists to suppress. A "watch logs after deploy" mode must be its own explicit opt-in flag, never on by default.
4. **Never hardcode `--verbose` or otherwise override the caller's flags.** If the wrapper adds its own flags (e.g. a config path), append them alongside the forwarded `"$@"`, never in place of it.

### Minimal bin/deploy template

Adapt destination/secrets sourcing to match the recipe and the registry chosen in Step 4b; the forwarding contract in the last line must stay intact:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Peek -d/--destination WITHOUT removing it from "$@" - kamal needs to see it too.
destination="production"
args=("$@")
for i in "${!args[@]}"; do
  if [[ "${args[$i]}" == "-d" || "${args[$i]}" == "--destination" ]]; then
    destination="${args[$((i + 1))]}"
  fi
done

if [[ -f ".kamal/secrets-${destination}" ]]; then
  set -a
  source ".kamal/secrets-${destination}"
  set +a
fi

exec kamal deploy "$@"
```

Make it executable: `chmod +x bin/deploy`.

After creating it, verify the contract holds: run `bin/deploy -q` (or `bin/deploy --quiet`) against a real or staging destination and confirm no per-step output prints unless the deploy fails. If output still appears, the fix is almost always rule 2 or rule 3 above - grep the wrapper for a pipe, a captured `$()`, or a trailing command after the `kamal deploy` call.

## Step 6: Document the Workflow

After configuration is complete, update (or create) the project's documentation file with deployment operations. Target file priority:

1. `README.md` - if it exists, add a `## Deployment` section
2. `docs/deployment.md` - if a `docs/` directory exists but no README section is appropriate
3. `README.md` - create it if neither exists

**If more than one Deployable Unit was discovered in Step 1** (regardless of how many Kamal manages), include a `## Deployable Units` table listing every discovered unit, which ones Kamal manages, and the config file or hosting note for each - see the "Documenting the Kamal-managed subset" section of `agents/patterns/multi-service-repo.md` for the exact format. Do not omit units Kamal doesn't manage; mark them explicitly as not managed here rather than leaving them undocumented.

If the target repository provides `bin/` wrappers for Kamal operations - whether pre-existing or just created in Step 5.5 - document those wrappers instead of raw `kamal` commands. Use the destination-based flow and Bitwarden-backed execution model that the repository actually ships.

The deployment section MUST include a concise, implementation-ready wrapper-oriented workflow. Use the project-specific destinations and secret names, but prefer these command forms:

### First-time Setup

```bash
bin/setup
```

### Deploy

```bash
bin/deploy
```

### Staging Deploy

```bash
bin/deploy -d staging
```

### Silent Deploy

`bin/deploy` forwards Kamal's own flags untouched, so `-q`/`--quiet` works exactly as it does with raw `kamal deploy`: no per-step output unless the deploy errors.

```bash
bin/deploy -q
bin/deploy -d staging --quiet
```

### Setup + Snapshot Restore

```bash
bin/setup --snapshot <dump-file>
bin/setup --snapshot <dump-file> --migration <migration-folder-or-file>
```

### Restore Only

```bash
bin/restore --snapshot <dump-file>
bin/restore --migration <migration-folder-or-file>
```

### Logs and Status

```bash
bin/status
bin/logs
bin/logs --follow
```

### Console and App Ops

```bash
bin/console
bin/app restart
bin/app details
```

### Accessories

```bash
bin/accessory boot all
bin/accessory boot postgres
bin/accessory logs postgres
```

### Locking and Removal

```bash
bin/lock status
bin/lock acquire
bin/lock release
bin/remove
```

### Operational Extras

```bash
bin/dump
bin/boot
bin/psql
bin/authorize --email <email>
bin/regsys-registry-boot -d staging
bin/regsys-build -d staging
```

If the repo has admin-only wrappers, document those separately:

```bash
bin/deploy-admin
bin/setup-admin
bin/console-admin
bin/logs-admin
bin/boot-admin
```

Adapt the section to match the actual accessories and environments configured. Remove sections that do not apply.

## Arie Operational Layer

If the target repository uses the Arie wrapper layout under `bin/`, treat those wrappers as the authoritative operator interface for Kamal-driven actions. Prefer these command names in docs, examples, and handoff notes:

- Main app operations: `bin/deploy`, `bin/setup`, `bin/status`, `bin/logs`, `bin/console`, `bin/app`, `bin/accessory`, `bin/remove`, `bin/lock`, `bin/dump`, `bin/restore`
- Staging and production routing: `bin/_bws_env` selects the Bitwarden project from `-d/--destination`, and all wrappers execute through `bws run --project-id ... --`
- Staging secret hydration: `bin/setup`, `bin/deploy`, `bin/console`, `bin/app`, and `bin/accessory` source `.kamal/staging-secrets` when targeting staging. That file exports `LOCAL_JWT_SECRET`, `LOCAL_PGRST_JWT_SECRET`, `LOCAL_SUPABASE_SERVICE_ROLE_KEY`, and `LOCAL_SUPABASE_SERVICE_KEY`
- Secret management: staging secrets are generated and managed by the wrapper flow. Do not ask for those values in chat or treat them as ad hoc operator input
- Setup and restore: `bin/setup` cannot target production. `bin/setup --snapshot [--migration]` is the provisioning plus restore path. `bin/restore --snapshot [--migration]` is the restore-only path for an already-existing destination
- Migration slicing: the `--migration` target is the last migration that should exist before restoring snapshot data. The wrapper rebuilds the schema through that migration first, then restores the snapshot, then finishes the staged restart sequence
- Admin split: `bin/*-admin` wrappers operate from `admin/`, strip destination flags before invoking Kamal, and still flow through `bws run`, but they are a separate operational path from the main app wrappers
- Auxiliary flows: `bin/regsys-build` builds and pushes `recsys/Dockerfile.regsys` and `recsys/Dockerfile.jobs`; `bin/regsys-registry-boot` boots the local registry container used by that flow; `bin/psql` and `bin/authorize` are operational wrappers to mention for database and auth workflows; `bin/run-data-migration` is an explicit staging-only wrapper for data migration scripts

When documenting this repo, use the wrapper names above and the destination-based flow instead of raw `kamal` commands. Mention raw Kamal only when explaining what the wrapper ultimately executes.

## Step 7: Summary

After completing all steps, provide a concise summary:

1. What files were created or modified - grouped by Deployable Unit if there was more than one
2. The exact commands the user needs to run next (setup secrets, then the appropriate wrapper command) - per unit if there's more than one
3. Any stack-specific caveats noted in the recipe, and any cross-cutting pattern caveats (additional runtime dependencies, large build artifacts, migrations) that applied
4. Which env vars are load-fail-fast per unit (from Step 5's fail-fast diagnostics check), so a misconfigured deploy is easy to diagnose from the first boot log
5. What to check if the health check fails

## Secrets Policy

1. Never ask the user to paste secrets in chat (passwords, tokens, API keys, registry credentials).
2. Always instruct users to put secrets in `.kamal/secrets` locally and in their CI/CD secret storage.
3. Ask the user to confirm a secret is set ("done") rather than pasting its value.
4. If the user pastes a secret anyway, instruct immediate rotation and continue with the secure flow.
5. Ensure `.kamal/secrets` is added to `.gitignore` before any other step.

## References

Load only when needed:

- Wrapper command reference: `references/kamal-commands.md`
- deploy.yml structure reference: `references/deploy-yml-reference.md`

**Claude Code paths** (resolve using the order in "Runtime and File Loading"):
- `~/.claude/skills/kamal-deploy-skill/references/kamal-commands.md`
- `~/.claude/skills/kamal-deploy-skill/references/deploy-yml-reference.md`

## Examples

The `examples/` directory contains annotated deploy.yml snippets. Load the relevant file(s) when generating or explaining a configuration - they serve as authoritative patterns to follow.

| File | What it shows |
|---|---|
| `examples/web-only.md` | Minimal single web server |
| `examples/web-with-worker.md` | Web + background worker role |
| `examples/with-postgres.md` | Web + PostgreSQL accessory |
| `examples/with-redis.md` | Web + Redis accessory |
| `examples/multi-destination.md` | Staging + production destinations |
| `examples/local-registry.md` | Local registry (`registry.server: localhost:5555`) |
| `examples/remote-builder.md` | Remote builder (`builder.remote`) |
| `examples/multi-service-repo.md` | Two Kamal-managed units from one repo (`-c`/`--config-file`, per-unit `secrets_path`/`hooks_path`) |

**Claude Code paths** (resolve using the order in "Runtime and File Loading"): `~/.claude/skills/kamal-deploy-skill/examples/<file>.md`
(fallback: `skills/kamal-deploy-skill/examples/<file>.md`)
