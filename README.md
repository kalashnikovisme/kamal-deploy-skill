# kamal-deploy-skill

A Claude Code / Codex skill for configuring [Kamal](https://kamal-deploy.org/) deployment on any technology stack — except Ruby on Rails (use [tramway-skill](https://github.com/Purple-Magic/tramway-skill/) for Rails).

## What it does

- Detects if the project is Ruby on Rails → redirects to tramway-skill
- Detects the technology stack automatically
- Generates a `Dockerfile`, `config/deploy.yml`, and `.kamal/secrets` template suited to the stack
- Configures accessories (PostgreSQL, Redis) as needed
- Creates multi-destination configs (staging + production)
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
| Unknown | Fetches latest Kamal docs and guides interactively |

## Installation

### Claude Code

```bash
# From the skill repo directory:
cp -R ./skills/kamal-deploy-skill ~/.claude/skills/kamal-deploy-skill
```

Or if installing from a published version, clone and copy:

```bash
git clone https://github.com/Purple-Magic/kamal-deploy-skill.git
cp -R kamal-deploy-skill/skills/kamal-deploy-skill ~/.claude/skills/kamal-deploy-skill
```

Then add to your Claude Code project settings (`.claude/settings.json`):

```json
{
  "skills": ["kamal-deploy-skill"]
}
```

### Codex

```bash
cp -R ./skills/kamal-deploy-skill ~/.codex/skills/kamal-deploy-skill
```

## Usage

In any non-Rails project directory, trigger the skill:

```
/kamal-deploy-skill
```

Or just describe what you want:

> "Set up Kamal deployment for this project"
> "Configure deploy.yml for my Next.js app"
> "Implement deployment with Kamal"

## Development

### Sync skill locally after changes

```bash
rm -rf ~/.claude/skills/kamal-deploy-skill
cp -R ./skills/kamal-deploy-skill ~/.claude/skills/kamal-deploy-skill
rm -rf ~/.codex/skills/kamal-deploy-skill
cp -R ./skills/kamal-deploy-skill ~/.codex/skills/kamal-deploy-skill
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
