# Changelog

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
