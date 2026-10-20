# Kamal Deploy Skill

Deploy non-Rails products across multiple stacks with Kamal.

## When to Use

Trigger when the user asks about implementation, deployment setup, `deploy.yml`, Docker-based deployment, Terraform/infrastructure provisioning, or repository-specific Kamal wrappers.

## Behavior

Read `SKILL.md` for the full step-by-step instructions. This file is the primary playbook.

1. Check if the repo root is a Ruby on Rails app (Step 0 in `SKILL.md`) - redirect to tramway-skill if so.
2. Discover Deployable Units and select which ones Kamal should manage (Step 1) - do not assume one repo = one app; see `agents/patterns/deployable-units.md`.
3. For each selected unit: detect its technology stack (Step 2).
4. Load the matching recipe from `agents/recipes/`, plus any cross-cutting pattern files that apply (Step 3).
5. Gather required server/registry/domain info - once per repo unless units need different infra (Step 4).
6. Apply the recipe - create Dockerfile (checking an existing one for Kamal-readiness first), deploy.yml, secrets template (Step 5).
7. Create `bin/deploy` (and companion wrappers as needed) if the repo has no Kamal `bin/` layer yet, forwarding Kamal's own flags unmodified; use per-unit or unit-argument wrappers when there are multiple Kamal-managed units (Step 5.5).
8. Update project documentation with deployment commands, wrapper guidance, and (if more than one unit was discovered) the Deployable Units table (Step 6).
9. Summarise what was created and next steps (Step 7).

## Rules

- Never ask for secrets values in chat. Always use `.kamal/secrets`.
- Always add `.kamal/secrets` to `.gitignore` before any other step.
- Do not cover Ruby on Rails projects - redirect to tramway-skill (per-unit, not just at the repo root).
- Do not infer the number of deployable units from directory count or from the presence/absence of a root workspace tool (npm/pnpm/yarn workspaces, Nx, Turborepo, Cargo workspaces) - see `agents/patterns/deployable-units.md`.
- When the target repo exposes `bin/` wrappers, prefer them over raw `kamal` commands.
- Any `bin/deploy` wrapper (generated or pre-existing) must forward `-q`/`--quiet`, `-c`/`--config-file`, and all other Kamal flags to `kamal` unmodified - no piping/capturing kamal's output, and no log tail chained after deploy (see SKILL.md Step 5.5).

## Supporting Files

Load `agents/*.md` and `agents/recipes/*.md` files as needed. They are available natively.
