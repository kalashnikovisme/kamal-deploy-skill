# Repository Instructions

Follow all instructions in `AGENTS.md`.

## Cross-Platform Requirement

This skill must work correctly in both **Codex** and **Claude Code**. Instructions in `SKILL.md` must be readable and actionable for both AI systems. The key difference:

- **Codex** loads `agents/*.md` files natively via the Codex agents system.
- **Claude Code** does NOT auto-load `agents/*.md` files. The skill file must include explicit Read-tool guidance so Claude knows *how* and *from where* to load each file.

Every change to this skill must preserve this dual-platform compatibility. When in doubt, test the updated skill in both environments.

## README Updates

Before finishing any task that adds, removes, or materially changes a feature of this skill, update `README.md` to reflect the change. This includes:

- New recipes or stacks
- New configuration options or questions asked during setup
- New features (e.g. Terraform provisioning, Dockerfile validation, examples directory)
- Removed or renamed behavior

Do not update README.md for internal wording fixes, formatting, or refactors that don't affect what the skill does from a user's perspective.

## End-of-Task Skill Sync

At the end of every task that changes this repository, update `skills/kamal-deploy-skill/VERSION` and sync with:

```bash
rm -rf ~/.claude/skills/kamal-deploy-skill
cp -R ./skills/kamal-deploy-skill ~/.claude/skills/kamal-deploy-skill
rm -rf ~/.codex/skills/kamal-deploy-skill
cp -R ./skills/kamal-deploy-skill ~/.codex/skills/kamal-deploy-skill
```
