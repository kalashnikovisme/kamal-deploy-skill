# Kamal Deploy Skill

Deploy non-Rails products across multiple stacks with Kamal.

## When to Use

Trigger when the user asks about implementation, deployment setup, `deploy.yml`, Docker-based deployment, Terraform/infrastructure provisioning, or repository-specific Kamal wrappers.

## Behavior

Read `SKILL.md` for the full step-by-step instructions. This file is the primary playbook.

1. Check if the project is a Ruby on Rails app (Step 0 in `SKILL.md`) - redirect to tramway-skill if so.
2. Detect the technology stack (Step 1).
3. Load the matching recipe from `agents/recipes/` (Step 2).
4. Gather required server/registry/domain info (Step 3).
5. Apply the recipe - create Dockerfile, deploy.yml, secrets template (Step 4).
6. Create `bin/deploy` (and companion wrappers as needed) if the repo has no Kamal `bin/` layer yet, forwarding Kamal's own flags unmodified (Step 4.5).
7. Update project documentation with deployment commands and wrapper guidance (Step 5).
8. Summarise what was created and next steps (Step 6).

## Rules

- Never ask for secrets values in chat. Always use `.kamal/secrets`.
- Always add `.kamal/secrets` to `.gitignore` before any other step.
- Do not cover Ruby on Rails projects - redirect to tramway-skill.
- When the target repo exposes `bin/` wrappers, prefer them over raw `kamal` commands.
- Any `bin/deploy` wrapper (generated or pre-existing) must forward `-q`/`--quiet` and all other Kamal flags to `kamal` unmodified - no piping/capturing kamal's output, and no log tail chained after deploy (see SKILL.md Step 4.5).

## Supporting Files

Load `agents/*.md` and `agents/recipes/*.md` files as needed. They are available natively.
