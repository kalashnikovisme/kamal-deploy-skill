---
name: kamal-deploy-skill
description: 'Configure Kamal deployment for any technology stack except Ruby on Rails. Use when the user asks to implement, set up, or configure deployment via Kamal, deploy.yml, kamal setup, kamal deploy, or add Docker-based deployment to a non-Rails project. Covers Node.js, Python, Go, PHP, Java, .NET, Elixir, and any other stack. If the project is Ruby on Rails, this skill redirects to tramway-skill instead.'
---

# Kamal Deploy Skill

Use this skill as an operational playbook for configuring Kamal deployment on non-Rails projects.
Prefer small, safe, verifiable changes. At every stage the user can skip any proposed step; respect skips, note risks briefly, and continue.

## Runtime and File Loading

This skill runs in two environments. Behavior differs for file loading:

**Codex** — `agents/*.md` files are loaded natively by the Codex agents system. The "load `agents/X.md`" instructions work without extra steps.

**Claude Code** — `agents/*.md` files are NOT auto-loaded. Whenever this document says "load `agents/X.md`", you MUST use the Read tool to read that file before continuing. Use the following path:

```
~/.claude/skills/kamal-deploy-skill/agents/X.md
```

If that path does not resolve, fall back to a project-local path:

```
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
- Tell the user: "This project is a Ruby on Rails application. The kamal-deploy-skill does not cover Rails — use **tramway-skill** instead: https://github.com/Purple-Magic/tramway-skill/"
- Stop. Do not proceed with any Kamal configuration.

If the project is NOT a Rails application, continue to Step 1.

## Step 1: Detect Technology Stack

Detect the project stack by checking for these files in order. Stop at the first match:

| Stack | Detection files |
|-------|----------------|
| Node.js | `package.json` |
| Python | `requirements.txt`, `pyproject.toml`, `Pipfile`, `setup.py` |
| Go | `go.mod` |
| PHP / Laravel | `composer.json` + `artisan` |
| PHP (generic) | `composer.json` |
| Java / Spring Boot | `pom.xml`, `build.gradle`, `build.gradle.kts` |
| .NET | `*.csproj`, `*.sln` |
| Elixir / Phoenix | `mix.exs` |

For Node.js, also read `package.json` to determine the framework (Next.js, NestJS, Express, Fastify, Nuxt, Remix, etc.) — this affects the Dockerfile and health check strategy. Also check `next.config.js`/`next.config.ts` for `output: 'standalone'` vs `output: 'export'` to confirm server mode.

For Python, also read `pyproject.toml` or `requirements.txt` to determine the framework (Django, FastAPI, Flask, etc.).

Announce the detected stack to the user before loading any recipe. For example: "Detected: **Next.js (Node.js)**. Loading Node.js deployment recipe."

If no stack is detected, announce: "Could not detect the technology stack automatically." Then load `agents/recipes/unknown-stack.md`.

## Step 2: Load Recipe

Load **only** the recipe matching the detected stack. Do not load multiple recipes.

- Node.js (Next.js) → load `agents/recipes/nextjs.md`
- Node.js (other) → load `agents/recipes/nodejs.md`
- Python → load `agents/recipes/python.md`
- Go → load `agents/recipes/go.md`
- PHP / Laravel → load `agents/recipes/php-laravel.md`
- Java / Spring Boot → load `agents/recipes/java-spring.md`
- .NET → load `agents/recipes/dotnet.md`
- Elixir / Phoenix → load `agents/recipes/elixir-phoenix.md`
- Unknown → load `agents/recipes/unknown-stack.md`

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

## Step 3: Gather Required Information

Before generating any configuration, collect the following from the user (ask only what is not already determinable from the project files):

1. **Server IP address(es)** — one or more IPs for production; optionally a separate set for staging
2. **Docker registry** — Docker Hub username, GitHub Container Registry (ghcr.io), or a private registry URL
3. **Service name** — defaults to the directory name if not specified
4. **Domain / hostname** — for SSL and proxy configuration
5. **Accessories needed** — PostgreSQL? Redis? Both? Neither? (pre-fill based on stack detection)
6. **Destinations** — does the user want separate staging and production configs?

Do not ask for secrets values in chat. Instruct the user to place secrets in `.kamal/secrets` and `.kamal/secrets-common` as instructed by the recipe.

## Step 4: Apply Recipe

Follow the loaded recipe to:

1. Create or verify a `Dockerfile` suited to the stack
2. Create `config/deploy.yml` (and `config/deploy.staging.yml` / `config/deploy.production.yml` if multiple destinations)
3. Create `.kamal/secrets` template with placeholder instructions
4. Create `.kamal/hooks/` scripts if the recipe requires them
5. Add `.kamal/secrets` to `.gitignore`

## Step 5: Update Documentation

After configuration is complete, update (or create) the project's documentation file with deployment operations. Target file priority:

1. `README.md` — if it exists, add a `## Deployment` section
2. `docs/deployment.md` — if a `docs/` directory exists but no README section is appropriate
3. `README.md` — create it if neither exists

The deployment section MUST include:

```markdown
## Deployment

### Prerequisites

- Kamal installed: `gem install kamal`
- Docker installed on all target servers
- SSH access to all servers (key-based)
- Docker registry access configured in `.kamal/secrets`

### First-time Setup

Run once to provision servers and deploy the application:

\`\`\`bash
kamal setup
\`\`\`

### Deploy

Deploy a new version:

\`\`\`bash
kamal deploy
\`\`\`

### Staging Deploy

\`\`\`bash
kamal deploy -d staging
\`\`\`

### Rollback

Roll back to the previous version:

\`\`\`bash
kamal rollback
\`\`\`

Roll back to a specific version (use `kamal audit` to find version hash):

\`\`\`bash
kamal rollback <version>
\`\`\`

### Restart

Restart the application without deploying a new image:

\`\`\`bash
kamal app restart
\`\`\`

### Logs

\`\`\`bash
kamal app logs
kamal app logs --follow
\`\`\`

### Accessories

Boot accessories (databases, cache):

\`\`\`bash
kamal accessory boot all
kamal accessory boot postgres
\`\`\`

### Status

\`\`\`bash
kamal details
kamal app details
\`\`\`
```

Adapt the section to match the actual accessories and environments configured. Remove sections that do not apply (e.g. remove staging commands if no staging destination was configured).

## Step 6: Summary

After completing all steps, provide a concise summary:

1. What files were created or modified
2. The exact commands the user needs to run next (setup secrets, then `kamal setup`)
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

- Common Kamal command reference: `references/kamal-commands.md`
- deploy.yml structure reference: `references/deploy-yml-reference.md`

**Claude Code paths:**
- `~/.claude/skills/kamal-deploy-skill/references/kamal-commands.md`
- `~/.claude/skills/kamal-deploy-skill/references/deploy-yml-reference.md`
