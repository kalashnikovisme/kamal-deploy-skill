# kamal-deploy-skill

A Claude Code / Codex skill for configuring [Kamal](https://kamal-deploy.org/) deployment on non-Rails projects across multiple stacks.

## Base features

1. Discover the repository's Deployable Units and determine which ones Kamal should manage
2. Configure Kamal deployment, independently per managed unit
3. Configure Terraform / infrastructure provisioning
4. Validate Dockerfiles
5. Document repository-specific wrapper workflows when present

## What it does

- Discovers every independently-deployable application/service in the repo first, instead of assuming one repo = one app. A root workspace/monorepo tool (npm/pnpm/yarn workspaces, Nx, Turborepo, Cargo workspaces) does not by itself imply either one unit or many — deployability is judged per candidate, not from directory count or tooling presence
- Asks which discovered units Kamal should manage; units left out (e.g. already deployed elsewhere, like a frontend on Vercel) are documented but otherwise untouched
- Migrates an existing Vercel-hosted unit to Kamal on request, or when the repo shows signs of it: inventories current Vercel behavior, classifies what carries over unchanged vs. needs a Kamal/server equivalent vs. needs an external service vs. needs a user decision, validates the Kamal target independently before any cutover, and gates production cutover and decommissioning behind explicit user approval — never touching Vercel's own config until asked
- Detects if a unit is Ruby on Rails → redirects to tramway-skill for that unit
- Detects each managed unit's technology stack automatically and loads the matching recipe
- Supports Node.js / Next.js, Python, Go, PHP / Laravel, Java / Spring Boot, .NET, Elixir / Phoenix, Terraform, and unknown-stack fallback
- Generates a `Dockerfile`, `config/deploy.yml`, and `.kamal/secrets` template suited to each unit's stack
- When more than one unit is Kamal-managed, first determines the Kamal deployment boundary separately from the Deployable Unit count: prefers consolidating units that share a product/server/release cadence into one `config/deploy.yml` as application roles and/or accessories, and only generates per-unit `config/deploy.<unit>.yml` files (invoked via Kamal's `-c`/`--config-file` flag, with distinct `secrets_path`/`hooks_path` per unit) when there's a concrete, stated reason the units can't share a deployment
- Applies cross-cutting patterns independently per unit as needed: a secondary runtime invoked as a subprocess, large build-time assets baked into the image, and database migration mechanics (pre-deploy hook vs. inline-at-boot)
- Checks an existing Dockerfile for Kamal-readiness (single identifiable port, foreground process, health-checkable path) before reusing it
- Configures accessories (PostgreSQL, Redis) only once the user (or clear repo evidence) confirms Kamal should own that dependency — a detected dependency on its own never implies Kamal should provision it; an externally-owned dependency gets its connection secret instead, with no accessory block
- Before writing any production secret, detects an established secrets backend (Rails credentials, SOPS, 1Password, Doppler, Bitwarden, a cloud secret manager) and preserves it; only when no backend exists yet does it present options — at minimum 1Password and SOPS + age — and persists the choice so future runs don't re-ask
- Never asks for a value it can derive: before generating a connection-string secret (e.g. `DATABASE_URL`, `REDIS_URL`) for a Kamal-managed accessory, it classifies the value as a secret primitive, a derived secret value, derived clear configuration, or genuine user-supplied input — storing only primitives and generating everything deterministic from them, rather than asking for both a password and a duplicated connection string built from it
- Generates secret primitives itself when it's safe to, using real cryptographic tooling (never model-invented randomness): classifies each primitive as locally generatable, protocol-generatable (e.g. a VAPID/SSH key pair, with private/public components stored separately), framework-generatable, Skill-owned infrastructure, provider-managed (rejected — directs you to the real provider), an existing value that must be preserved, or unknown (never guessed from the name alone) — then generates with an appropriate CSPRNG/tool, writes the result directly into your secrets backend, validates the write, and reports only success, never the value. Replacing an existing real secret is always treated as rotation, never a silent overwrite
- Creates multi-destination configs (staging + production)
- Prefers repository `bin/` wrappers over raw `kamal` commands when the project ships an operational layer like the Arie wrappers
- Generates a minimal `bin/deploy` wrapper (or per-unit wrappers, for multiple managed units) when the project has no Kamal `bin/` layer yet, guaranteed to forward `-q`/`--quiet`, `-c`/`--config-file`, and all other Kamal flags unmodified
- Updates the project's README with deployment operations documentation, including a Deployable Units table when more than one unit was discovered

## Supported stacks

| Stack | Frameworks |
|-------|-----------|
| Node.js | Next.js, NestJS, Express, Fastify, Nuxt, Remix |
| Python | Django, FastAPI, Flask |
| Go | Standard library, Gin, Echo, Chi, Fiber |
| PHP | Laravel, Symfony |
| Java | Spring Boot (Maven/Gradle), Quarkus, Micronaut |
| .NET | ASP.NET Core (Minimal API, MVC, Razor Pages, Blazor Server) |
| Elixir | Phoenix, plain OTP releases |
| Terraform | Server and DNS provisioning for existing or new infrastructure |
| Unknown | Fetches fresh Kamal docs and guides interactively |

## Secrets backends

The skill never invents a secrets backend on its own — it detects an established one and preserves it, or presents options when none exists yet (`agents/patterns/secrets-backend.md`). Only one native Kamal adapter exists among these; the rest integrate through `.kamal/secrets` command substitution:

| Backend | Storage | Decryption / access | Best fit | Native Kamal adapter? |
|---|---|---|---|---|
| Rails credentials | `config/credentials.yml.enc` committed | `RAILS_MASTER_KEY`/`config/master.key` kept outside Git | Existing Rails projects already using this model | No (Rails-level, not Kamal) |
| 1Password | Values live in an external vault, not in the repo | 1Password service account / Connect server | Teams already centralizing secrets in 1Password; want vault-level audit | Yes — `kamal secrets fetch --adapter 1password` |
| SOPS + age | Encrypted file (`config/secrets.sops.yaml`) committed to the repo | An age private identity held outside Git by whoever needs to decrypt | No external SaaS dependency; a Rails-credentials-like workflow for non-Rails projects | No — integrated via `.kamal/secrets` command substitution calling `sops` directly (see `agents/patterns/secrets-sops-age.md`) |

Neither 1Password nor SOPS + age is "more secure" in the abstract — they differ in ownership model: 1Password keeps secret values outside the repo entirely, under a vault service; SOPS + age keeps encrypted values inside the repo, with the decryption capability (the age private identity) held outside it.

## Versioning

`skills/kamal-deploy-skill/VERSION` is the human-readable semantic version of the skill's content, bumped on every change per `CHANGELOG.md`. It is not used as the plugin update identity — Claude Code's marketplace/plugin update mechanism tracks this repository's git history directly, so `claude plugin update` always pulls the latest commit regardless of the `VERSION` value.

## Installation

### Claude Code — recommended

This repository is both the source of truth and a Claude Code plugin marketplace. Add the marketplace once:

```text
/plugin marketplace add kalashnikovisme/kamal-deploy-skill
```

Then install the plugin:

```text
/plugin install kamal-deploy-skill@kamal-deploy-skill-marketplace
```

That's it — no `.claude/settings.json` edit needed, the plugin registers the skill automatically.

## Updating

Update on demand:

```bash
claude plugin update kamal-deploy-skill@kamal-deploy-skill-marketplace
```

Or turn on auto-update for the marketplace from Claude Code's plugin UI (`/plugin` → marketplace settings) so new releases are picked up without a manual step. Manual (`cp -R`) installs, below, do **not** get this — they stay frozen at whatever was copied until you re-sync them by hand.

### Manual installation (fallback)

Use this only if you can't add a plugin marketplace in your environment.

```bash
git clone https://github.com/kalashnikovisme/kamal-deploy-skill.git
cp -R kamal-deploy-skill/skills/kamal-deploy-skill ~/.claude/skills/kamal-deploy-skill
```

Then add to your Claude Code project settings (`.claude/settings.json`):

```json
{
  "skills": ["kamal-deploy-skill"]
}
```

To update a manual install, pull the latest source and re-copy over the installed directory:

```bash
cd kamal-deploy-skill && git pull
rm -rf ~/.claude/skills/kamal-deploy-skill
cp -R skills/kamal-deploy-skill ~/.claude/skills/kamal-deploy-skill
```

### Codex

Codex has no plugin marketplace mechanism, so installation is manual only:

```bash
git clone https://github.com/kalashnikovisme/kamal-deploy-skill.git
cp -R kamal-deploy-skill/skills/kamal-deploy-skill ~/.codex/skills/kamal-deploy-skill
```

Update the same way: `git pull`, then `rm -rf ~/.codex/skills/kamal-deploy-skill && cp -R skills/kamal-deploy-skill ~/.codex/skills/kamal-deploy-skill`.

## Usage

In any non-Rails project directory, trigger the skill:

```
/kamal-deploy-skill
```

Or just describe what you want:

> "Set up Kamal deployment for this project"
> "Configure deploy.yml for my Next.js app"
> "Implement deployment with Kamal"

If the target repository already exposes `bin/` wrappers, the generated documentation will use those wrapper names and the repository's destination-based flow instead of raw `kamal` commands. If it doesn't, the skill creates a minimal `bin/deploy` that forwards Kamal's own flags (including `-q`/`--quiet`) straight through, so `bin/deploy -q` behaves exactly like `kamal deploy -q`.

## Development

These steps are for people editing this repository, not for installing the skill — see [Installation](#installation) for that.

### Sync skill locally after changes

Local-only convenience for testing your working tree before pushing; it does not replace the marketplace update flow above.

```bash
rm -rf ~/.claude/skills/kamal-deploy-skill
cp -R ./skills/kamal-deploy-skill ~/.claude/skills/kamal-deploy-skill
rm -rf ~/.codex/skills/kamal-deploy-skill
cp -R ./skills/kamal-deploy-skill ~/.codex/skills/kamal-deploy-skill
```

### Validating the plugin/marketplace manifest

```bash
claude plugin validate . --strict
```

### Adding a new recipe

1. Create `skills/kamal-deploy-skill/agents/recipes/<stack>.md`
2. Add the detection signal to the stack detection table in `SKILL.md` (Step 2)
3. Add the recipe to the load table in `SKILL.md` (Step 3) with Claude Code file paths
4. Bump `MINOR` in `VERSION`
5. Add a CHANGELOG entry
6. Sync locally to test

### Validating the skill

```bash
python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py ./skills/kamal-deploy-skill
```

## License

MIT
