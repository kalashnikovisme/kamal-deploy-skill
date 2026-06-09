# Changelog

## 0.1.0 — 2026-06-09

Initial release.

- Rails guard: detects Ruby on Rails projects and redirects to tramway-skill
- Stack detection for Node.js, Python, Go, PHP/Laravel, Java/Spring Boot, .NET, and Elixir/Phoenix
- Dedicated deployment recipes for each detected stack with Dockerfile templates, deploy.yml, and .kamal/secrets
- Unknown-stack recipe with mandatory fresh Kamal docs fetch
- References: kamal-commands.md and deploy-yml-reference.md
- README documentation update step after every configuration
- Works in both Claude Code and Codex
