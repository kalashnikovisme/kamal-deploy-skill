# Kamal Deploy Skill

Deploy non-Rails products across multiple stacks with Kamal.

## When to Use

Trigger when the user asks about implementation, deployment setup, `deploy.yml`, Docker-based deployment, Terraform/infrastructure provisioning, or repository-specific Kamal wrappers.

## Behavior

Read `SKILL.md` for the full step-by-step instructions. Load it with the Read tool:

```text
~/.claude/skills/kamal-deploy-skill/SKILL.md
```

Fallback:

```text
skills/kamal-deploy-skill/SKILL.md
```

1. Check if the project is a Ruby on Rails app (Step 0 in `SKILL.md`) - redirect to tramway-skill if so.
2. Detect the technology stack (Step 1).
3. Load the matching recipe from `agents/recipes/` (Step 2).
4. Gather required server/registry/domain info (Step 3).
5. Apply the recipe - create Dockerfile, deploy.yml, secrets template (Step 4).
6. Update project documentation with deployment commands and wrapper guidance (Step 5).
7. Summarise what was created and next steps (Step 6).

## Rules

- Never ask for secrets values in chat. Always use `.kamal/secrets`.
- Always add `.kamal/secrets` to `.gitignore` before any other step.
- Do not cover Ruby on Rails projects - redirect to tramway-skill.
- When the target repo exposes `bin/` wrappers, prefer them over raw `kamal` commands.

## Supporting Files

`agents/*.md` files are NOT auto-loaded in Claude Code. Use the Read tool to load them:

```text
~/.claude/skills/kamal-deploy-skill/agents/X.md
```
