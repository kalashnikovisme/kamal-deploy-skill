# Reinstall Instructions

Follow these steps **before marking any skill task complete**. They sync the locally installed plugin with the repository source.

## 1. Validate (optional)

```bash
claude plugins validate /home/kalashnikovisme/projects/kamal-deploy-skill
```

## 2. Reinstall for Claude Code

```bash
rm -rf ~/.claude/skills/kamal-deploy-skill
cp -R /home/kalashnikovisme/projects/kamal-deploy-skill/skills/kamal-deploy-skill ~/.claude/skills/kamal-deploy-skill
```

## 3. Reinstall for Codex

```bash
rm -rf ~/.codex/skills/kamal-deploy-skill
cp -R /home/kalashnikovisme/projects/kamal-deploy-skill/skills/kamal-deploy-skill ~/.codex/skills/kamal-deploy-skill
```

## 4. Verify

```bash
ls ~/.claude/skills/kamal-deploy-skill/
ls ~/.codex/skills/kamal-deploy-skill/ 2>/dev/null || echo "Codex not installed"
```

Expected output includes: `AGENTS.md`, `CLAUDE.md`, `SKILL.md`, `agents/`, `references/`

---

## Notes

- Run from the repository root: `/home/kalashnikovisme/projects/kamal-deploy-skill`
- Skip step 3 if `~/.codex/skills/` does not exist
