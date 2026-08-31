---
name: kamal-deploy-skill
description: 'Configure Kamal deployment for any non-Rails technology stack. Use when the user asks to implement, set up, or configure deployment via Kamal, deploy.yml, or Docker-based deployment in a non-Rails project. Covers Node.js / Next.js, Python, Go, PHP / Laravel, Java / Spring Boot, .NET, Elixir / Phoenix, Terraform / infrastructure provisioning, and unknown-stack fallback. If the project is Ruby on Rails, this skill redirects to tramway-skill instead.'
---

# Kamal Deploy Skill

Use this skill as a stack-driven playbook for configuring Kamal deployment on non-Rails projects.
Prefer small, safe, verifiable changes. Do not assume a Node.js-only workflow: recipe selection stays stack-driven, and repository-specific wrapper scripts are an operational layer on top of the stack recipe, not a replacement for it. At every stage the user can skip any proposed step; respect skips, note risks briefly, and continue.

## Runtime and File Loading

This skill runs in two environments. Behavior differs for file loading:

**Codex** - `agents/*.md` files are loaded natively by the Codex agents system. The "load `agents/X.md`" instructions work without extra steps.

**Claude Code** - `agents/*.md` files are NOT auto-loaded. Whenever this document says "load `agents/X.md`", you MUST use the Read tool to read that file before continuing. Use the following path:

```text
~/.claude/skills/kamal-deploy-skill/agents/X.md
```

If that path does not resolve, fall back to a project-local path:

```text
skills/kamal-deploy-skill/agents/X.md
```

Do NOT skip loading agent files. They contain mandatory rules for the active surface area. If a file cannot be read, report the error to the user instead of silently continuing.

Version policy:

1. The skill version is stored in `VERSION` at the root of this skill directory.
2. **MANDATORY: When this skill is loaded, immediately read the `VERSION` file and show the version to the user** as the first output, before any other response. Format: `kamal-deploy-skill v<version>`. Try `~/.claude/skills/kamal-deploy-skill/VERSION`, then `~/.codex/skills/kamal-deploy-skill/VERSION`, then any repository-local `skills/kamal-deploy-skill/VERSION`.
3. If the user asks for the skill version, read and report that `VERSION` value.

## Step 0: Rails Guard

**Before any other action**, check whether the current project is a Ruby on Rails application by looking for ALL of these signals:

- `Gemfile` exists
- `config/application.rb` exists
- `config/routes.rb` exists

Do not scan all project files for this step. Check only those three paths.

If the project IS a Rails application:
- Tell the user: "This project is a Ruby on Rails application. The kamal-deploy-skill does not cover Rails - use **tramway-skill** instead: https://github.com/Purple-Magic/tramway-skill/"
- Stop. Do not proceed with any Kamal configuration.

If the project is NOT a Rails application, continue to Step 1.

## Step 1: Detect Technology Stack

Detect the project stack by checking for these files in order. Stop at the first match:

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

Announce the detected stack to the user before loading any recipe. For example: "Detected: **Next.js (Node.js)**. Loading Node.js deployment recipe."

If no stack is detected, announce: "Could not detect the technology stack automatically." Then load `agents/recipes/unknown-stack.md`.

## Step 2: Load Recipe

Load **only** the recipe matching the detected stack. Do not load multiple recipes.

- Node.js (Next.js) -> load `agents/recipes/nextjs.md`
- Node.js (other) -> load `agents/recipes/nodejs.md`
- Python -> load `agents/recipes/python.md`
- Go -> load `agents/recipes/go.md`
- PHP / Laravel -> load `agents/recipes/php-laravel.md`
- Java / Spring Boot -> load `agents/recipes/java-spring.md`
- .NET -> load `agents/recipes/dotnet.md`
- Elixir / Phoenix -> load `agents/recipes/elixir-phoenix.md`
- Unknown -> load `agents/recipes/unknown-stack.md`

**Claude Code file paths for each recipe:**

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

## Step 3: Gather Required Information

### 3a. Infrastructure Check

Ask these two questions separately, one at a time:

1. > "Do you already have a server with SSH access (you have the IP and can SSH in)?"

2. > "Do you already have a DNS provider configured for your domain (the domain is registered and you can manage its DNS records)?"

Based on the answers:

| Has server? | Has DNS? | Action |
|---|---|---|
| Yes | Yes | Collect IP + domain. Proceed directly to Step 3b. |
| Yes | No | Load the Terraform recipe - DNS-only provisioning. |
| No | Yes | Load the Terraform recipe - server-only provisioning. |
| No | No | Load the Terraform recipe - full provisioning. |

**Claude Code path for Terraform recipe:** `~/.claude/skills/kamal-deploy-skill/agents/recipes/terraform.md`
(fallback: `skills/kamal-deploy-skill/agents/recipes/terraform.md`)

After the Terraform recipe completes, resume at Step 3b with the confirmed server IP and domain.

### 3b. Remaining Configuration

Collect the following (ask only what is not already determinable from the project files or from the Terraform step):

1. **Server IP address(es)** - confirmed in 3a, or ask if not yet known
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

4. **Service name** - defaults to the directory name if not specified
5. **Domain / hostname** - confirmed in 3a, or ask if not yet known
6. **Accessories needed** - PostgreSQL? Redis? Both? Neither? (pre-fill based on stack detection)
7. **Destinations** - does the user want separate staging and production configs?

Do not ask for secrets values in chat. Instruct the user to place secrets in `.kamal/secrets` and `.kamal/secrets-common` as instructed by the recipe. If the target repo provides wrapper-managed staging secrets, treat those values as generated or managed by the wrapper flow and do not ask for them ad hoc.

## Step 4: Apply Recipe

Follow the loaded recipe to:

1. Create or verify a `Dockerfile` suited to the stack
2. **Validate the Dockerfile** - immediately after writing it, run a test build:
   ```bash
   docker build --platform linux/amd64 -t kamal-skill-test:build-check . && docker rmi kamal-skill-test:build-check
   ```
   - If Docker is not available locally, skip this step and note it in the summary.
   - If the build succeeds: continue.
   - If the build fails: read the full error output, identify the root cause, fix the `Dockerfile`, and re-run the build. Repeat until the build passes. Do not proceed to the next step until the Dockerfile builds successfully.
   - Common fixable errors: missing base image tag, wrong `COPY` path, missing `RUN` dependency, incorrect `CMD` format, missing build argument.
   - If the error is caused by missing application source files (e.g. the project has no `src/` yet), note this in the summary and continue - the Dockerfile is structurally valid.
3. Create `config/deploy.yml` (and `config/deploy.staging.yml` / `config/deploy.production.yml` if multiple destinations)
4. Create `.kamal/secrets` template with placeholder instructions
5. Create `.kamal/hooks/` scripts if the recipe requires them
6. Add `.kamal/secrets` to `.gitignore`

## Step 5: Document the Workflow

After configuration is complete, update (or create) the project's documentation file with deployment operations. Target file priority:

1. `README.md` - if it exists, add a `## Deployment` section
2. `docs/deployment.md` - if a `docs/` directory exists but no README section is appropriate
3. `README.md` - create it if neither exists

If the target repository provides `bin/` wrappers for Kamal operations, document those wrappers instead of raw `kamal` commands. Use the destination-based flow and Bitwarden-backed execution model that the repository actually ships.

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

## Step 6: Summary

After completing all steps, provide a concise summary:

1. What files were created or modified
2. The exact commands the user needs to run next (setup secrets, then the appropriate wrapper command)
3. Any stack-specific caveats noted in the recipe
4. What to check if the health check fails

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

**Claude Code paths:**
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

**Claude Code paths:** `~/.claude/skills/kamal-deploy-skill/examples/<file>.md`
(fallback: `skills/kamal-deploy-skill/examples/<file>.md`)
