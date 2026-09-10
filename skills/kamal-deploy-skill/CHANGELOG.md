# Changelog

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
