# kamal-deploy-skill

A Claude Code / Codex skill for configuring [Kamal](https://kamal-deploy.org/) deployment on non-Rails projects across multiple stacks.

## Base features

1. Configure Kamal deployment
2. Configure Terraform / infrastructure provisioning
3. Validate Dockerfiles
4. Document repository-specific wrapper workflows when present

## What it does

- Detects if the project is Ruby on Rails → redirects to tramway-skill
- Detects the technology stack automatically and loads the matching recipe
- Supports Node.js / Next.js, Python, Go, PHP / Laravel, Java / Spring Boot, .NET, Elixir / Phoenix, Terraform, and unknown-stack fallback
- Generates a `Dockerfile`, `config/deploy.yml`, and `.kamal/secrets` template suited to the stack
- Configures accessories (PostgreSQL, Redis) as needed
- Creates multi-destination configs (staging + production)
- Prefers repository `bin/` wrappers over raw `kamal` commands when the project ships an operational layer like the Arie wrappers
- Generates a minimal `bin/deploy` wrapper when the project has no Kamal `bin/` layer yet, guaranteed to forward `-q`/`--quiet` and all other Kamal flags unmodified
- Updates the project's README with deployment operations documentation

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
2. Add the detection signal to the stack detection table in `SKILL.md` (Step 1)
3. Add the recipe to the load table in `SKILL.md` (Step 2) with Claude Code file paths
4. Bump `MINOR` in `VERSION`
5. Add a CHANGELOG entry
6. Sync locally to test

### Validating the skill

```bash
python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py ./skills/kamal-deploy-skill
```

## License

MIT
