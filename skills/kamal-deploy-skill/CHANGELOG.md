# Changelog

## 1.0.0 — 2026-10-20

Patch discovered by the v0.11.0 acceptance test.

- Fix: dependency detection (e.g. a `pg`/`ioredis` package, a `psycopg2`/`redis` import) no longer implies Kamal should provision that dependency as an accessory. SKILL.md Step 4b #6 now splits this into two explicit questions - does the unit depend on the service, and separately, who owns/provisions it (Kamal accessory, existing managed service, external provider, or infra provisioned elsewhere) - and asks the user whenever repo evidence doesn't already establish ownership. Updated the stack recipes' commented-out accessory blocks (`nodejs.md`, `nextjs.md`, `python.md`, `go.md`), `unknown-stack.md`'s dependency-gathering step, `agents/patterns/multi-service-repo.md`'s shared-accessory section, and `examples/with-postgres.md`/`with-redis.md` to make clear the accessory path is something the user (or clear repo evidence) confirms, never a default triggered by detecting the dependency.
- Clarify in `agents/patterns/deployable-units.md` that Deployable Unit status is an architectural/deployment-lifecycle classification, decided independently of whether a candidate already has a `Dockerfile`, Kamal config, health endpoint, or other Kamal-readiness artifact - those are a later concern (Step 5). Added a regression case to `tests/fixtures/multi-deployable-unit/EXPECTED.md` protecting against describing the Dockerfile-less `apps/web` candidate as only "conditionally" a Deployable Unit.

## 0.11.0 — 2026-10-20

- Add the **Deployable Unit** abstraction: the Skill no longer assumes one repository = one application. New Step 1 (`agents/patterns/deployable-units.md`) discovers every independently-deployable candidate in a repo and asks which ones Kamal should manage, before any stack detection happens. A root workspace/monorepo build tool (npm/pnpm/yarn workspaces, Nx, Turborepo, Cargo workspaces) is explicitly **not** treated as evidence of unit count either way - deployability is judged per candidate (own runnable process/port/image vs. a purely-imported library), not from directory count or tooling presence.
- Add multi-service support (`agents/patterns/multi-service-repo.md` + `examples/multi-service-repo.md`): when the Kamal-managed subset has more than one unit, each gets its own `config/deploy.<unit>.yml`, invoked via Kamal's `-c`/`--config-file` flag, with its own `secrets_path`/`hooks_path` to avoid collisions. Verified directly against `basecamp/kamal`'s source (`lib/kamal/cli/base.rb`, `lib/kamal/configuration.rb`) since the public kamal-deploy.org docs site does not document `-c`/`--config-file`. This convention only triggers once the *selected* subset has more than one unit - never merely because the repo contains more than one candidate.
- Add three new cross-cutting patterns, generalized rather than stack-specific: `agents/patterns/additional-runtime-dependencies.md` (a secondary language runtime invoked as a subprocess), `agents/patterns/large-build-artifacts.md` (large baked-in assets like ML model weights), and `agents/patterns/database-migrations.md` (pre-deploy-hook vs. inline-at-boot tradeoffs; stack recipes keep their own exact migration commands and now point here for the reasoning).
- Add an existing-Dockerfile Kamal-readiness check and a fail-fast-diagnostics note to Step 5 (Apply Recipe): before reusing a repo's own Dockerfile, check for a single identifiable port, a foreground process (no daemonizing - PID 1 must stay running), and a health-checkable path.
- Renumbered `SKILL.md`'s steps (old Step 0-6 is now Step 0-7) to make room for the new Discover Deployable Units step; updated every cross-reference in recipes, patterns, and reference files accordingly.
- Add `agents/recipes/nodejs.md` Database Migrations section (previously had none) and a unit-root path clarification to every stack recipe, so each recipe operates relative to the current Deployable Unit's own root rather than implicitly assuming the repo root.
- Add regression fixture `tests/fixtures/multi-deployable-unit/` + `EXPECTED.md`: a synthetic workspaces-style monorepo with one unit that should be selected for Kamal and one that should surface as already-hosted-elsewhere (Vercel), plus a pure-library package that must NOT be counted as a Deployable Unit - exercises both discovery and selection without exercising multi-Kamal-unit mechanics (out of scope for this fixture; see `examples/multi-service-repo.md` instead).
- Fix pre-existing broken example references (unrelated to the above): `SKILL.md`'s Examples table referenced eight `examples/*.md` files that never existed - only a dead, empty `examples/nextjs.yml` stub was present. Created all eight (`web-only.md`, `web-with-worker.md`, `with-postgres.md`, `with-redis.md`, `multi-destination.md`, `local-registry.md`, `remote-builder.md`, plus the new `multi-service-repo.md`) and removed the stub.

## 0.10.1 — 2026-09-09

- Fix: `/plugin install` failed with "conflicting manifests: both plugin.json and marketplace entry specify components" - removed `.claude-plugin/plugin.json`, which was never required by the plugin spec and conflicted with `marketplace.json`'s own `"skills"` array (its mere presence next to a `skills/` directory triggers component auto-discovery, colliding with the explicit list). `marketplace.json` is now the sole component-spec source for this plugin.

## 0.10.0 — 2026-09-09

- Add Claude Code plugin marketplace support: `.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json` at the repo root, pointing at `./skills/kamal-deploy-skill`. `claude plugin validate . --strict` passes.
- Marketplace installation (`/plugin marketplace add` + `/plugin install`) is now the recommended Claude Code install path, with `claude plugin update` / marketplace auto-update as the update mechanism. Manual `cp -R` install is now documented as an explicit fallback that does not auto-update.
- `marketplace.json` intentionally has no static `version` field - plugin update identity is the marketplace repo's git history, not a duplicated semver. `VERSION` remains the skill's own human-readable semantic version.
- Removed `agents/reinstall.md` from the shipped skill: it was a dev-only file with a hardcoded personal absolute path, shipped inside the plugin package where Codex's native `agents/*.md` auto-load could pick it up and instruct self-reinstall as part of normal skill use. The equivalent dev-only sync workflow already lives in the repo root `AGENTS.md`/`CLAUDE.md` (not shipped as part of the installed skill).
- `SKILL.md`'s "Runtime and File Loading" section now resolves `agents/`, `references/`, `examples/`, and `VERSION` paths relative to the skill's own announced base directory first, falling back to the hardcoded `~/.claude/skills/kamal-deploy-skill/...` path only for legacy manual installs - this keeps recipe/reference/example loading correct regardless of where the plugin marketplace installs the skill.
- Fixed stale `Purple-Magic/kamal-deploy-skill` GitHub URL in README to the actual repo owner (`kalashnikovisme/kamal-deploy-skill`, per `git remote`).

## 0.9.0 — 2026-09-09

- Add Step 4.5: generate a minimal `bin/deploy` wrapper when the target repo has no Kamal `bin/` layer yet, instead of documenting a `bin/deploy` command that was never created
- Fix: wrapper generation now guarantees `-q`/`--quiet` (and every other Kamal flag) reaches `kamal deploy` unmodified - no consuming unrecognized flags, no piping/capturing kamal's output, no log tail chained after deploy
- Document the flag-passthrough contract in `references/kamal-commands.md` and SKILL.md Step 5's example commands

## 0.8.0 — 2026-08-31

- Make the skill explicitly multi-stack and repository-aware for the Arie wrapper flow
- Prefer `bin/` wrappers over raw `kamal` commands in generated documentation and operator guidance
- Document Bitwarden-backed destination routing, staging secret hydration, setup/restore sequencing, admin wrappers, and auxiliary `regsys` / `psql` / `authorize` flows
- Update README, references, and local reinstall paths to match the current repository layout

## 0.7.1 — 2026-06-09

- Step 4 now validates the Dockerfile with a test build immediately after writing it; fixes errors and retries until the build passes before continuing

## 0.7.0 — 2026-06-09

- Add examples/ directory with 7 annotated deploy.yml snippets
- SKILL.md references the examples table so the AI loads relevant files when generating configs

## 0.6.5 — 2026-06-09

- Fix: local Kamal registry no longer generates a registry accessory; it simply sets registry.server: localhost:<port> in deploy.yml
- Asks for the port (default 5555) instead of hardcoding 4443

## 0.6.4 — 2026-06-09

- Remote builder is no longer added automatically; a dedicated question now asks local vs remote with a plain-language explanation of the trade-offs
- Local Kamal registry + local builder combination is flagged as invalid with a clear warning

## 0.6.3 — 2026-06-09

- DigitalOcean SSH key question now offers two options: use an existing key already in the DO profile (asks for key name, uses data source) or upload a new key from a local file (asks for path, uses resource)

## 0.6.2 — 2026-06-09

- Fix: app_name is now derived automatically from the project directory name (lowercased, non-alphanumeric chars replaced with hyphens); removed from terraform.tfvars.example across all three server provider sections

## 0.6.1 — 2026-06-09

- Fix: terraform recipe no longer shows all providers' region/size options at once; follow-up questions are now scoped to the chosen hosting provider only

## 0.6.0 — 2026-06-09

- Split terraform recipe scenario detection into two independent questions (hosting and DNS)
- Recipe now handles four scenarios: full, server-only, DNS-only, and neither (skip)
- Terraform configs reorganised into composable server + DNS sections instead of fixed provider combos
- SKILL.md Step 3a updated with a decision matrix for the four scenarios

## 0.5.0 — 2026-06-09

- Add local Kamal registry option to the Docker registry question in SKILL.md Step 3b
- Includes exact deploy.yml modifications (localhost:4443 image, remote builder, registry accessory) and first-deploy boot instructions

## 0.4.0 — 2026-06-09

- Add Terraform infrastructure recipe (`agents/recipes/terraform.md`) covering DigitalOcean+Cloudflare, Hetzner+Cloudflare, and AWS+Route53
- Update SKILL.md Step 3 to detect whether the user has existing infrastructure; loads terraform recipe when they don't

## 0.3.0 — 2026-06-09

- Add dedicated Next.js recipe (`agents/recipes/nextjs.md`) for long-running server + background worker deployment
- Update SKILL.md to route Next.js projects to the new recipe instead of the generic Node.js recipe

## 0.2.0 — 2026-06-09

- Add AGENTS.md (Codex entry point)
- Add CLAUDE.md (Claude Code entry point)
- Add agents/openai.yaml (Codex interface definition)
- Add agents/reinstall.md (local reinstall instructions)

## 0.1.0 — 2026-06-09

Initial release.

- Rails guard: detects Ruby on Rails projects and redirects to tramway-skill
- Stack detection for Node.js, Python, Go, PHP/Laravel, Java/Spring Boot, .NET, and Elixir/Phoenix
- Dedicated deployment recipes for each detected stack with Dockerfile templates, deploy.yml, and .kamal/secrets
- Unknown-stack recipe with mandatory fresh Kamal docs fetch
- References: kamal-commands.md and deploy-yml-reference.md
- README documentation update step after every configuration
- Works in both Claude Code and Codex
