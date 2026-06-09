# Changelog

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
