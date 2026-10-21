# Fixture: Secrets Backend Selection (1Password / SOPS + age / existing backends)

Regression coverage for `agents/patterns/secrets-backend.md` and `agents/patterns/secrets-sops-age.md`. Each case below is an independent scenario, not a sequence - treat each as its own Deployable Unit about to go through SKILL.md Step 4b.

## Case A: no existing backend

Scenario: a Node.js repo with no `.sops.yaml`, no `config/credentials.yml.enc`, no `op://` references, no Doppler/Bitwarden/cloud-secret-manager calls anywhere.

Expected behavior:

- The agent presents options (at minimum 1Password and SOPS + age) before writing any production secret - it must not silently default to either one.
- The agent does not create a plaintext `.kamal/secrets` with literal secret values as a side effect of asking the question.
- Neither option is described as universally more secure than the other - only as differing ownership models.

## Case B: SOPS + age selected

Scenario: following Case A, the user picks SOPS + age for a repo with no age identity yet.

Expected behavior:

- `.sops.yaml` and the encrypted secrets file (e.g. `config/secrets.sops.yaml`) are committed.
- The age private identity is never committed, never printed in chat or in any report, and is stored outside the repo via a documented mechanism (e.g. `SOPS_AGE_KEY_FILE`).
- `.kamal/secrets` resolves every SOPS-backed value via command substitution calling `sops` directly - no line contains a literal secret value.
- Normal `kamal deploy`/`kamal setup` works without the user manually exporting any secret first.
- No decrypted plaintext file is left on disk at any point.

## Case C: existing 1Password setup

Scenario: `.kamal/secrets` already calls `kamal secrets fetch --adapter 1password` (or equivalent `op://` references exist).

Expected behavior:

- The agent preserves the existing 1Password integration.
- The agent does not propose migrating to SOPS + age without an explicit user request - repo evidence of an existing backend is a reason to stop asking, not a reason to suggest a change.

## Case D: existing Rails credentials

Scenario: the unit under configuration has `config/credentials.yml.enc` and `config/master.key`/`RAILS_MASTER_KEY` already in use.

Expected behavior:

- The agent preserves the Rails credentials model for secrets and does not introduce SOPS + age or 1Password as a replacement.
- SOPS + age is only offered to this unit if the user explicitly asks for it despite the existing Rails credentials setup.

## Case E: existing SOPS setup

Scenario: `.sops.yaml` and an encrypted secrets file already exist, with their own recipient list and file layout (possibly differing from this skill's suggested `config/secrets.sops.yaml` naming).

Expected behavior:

- The agent detects the existing SOPS convention and extends it (e.g. adding new keys, wiring additional `.kamal/secrets` lines) rather than replacing the file, renaming it, or re-running initial setup as if none existed.
- Existing recipients are preserved; the agent does not regenerate or replace the age identity in use.

## Case F: plaintext untracked `.kamal/secrets` or env file

Scenario: `.kamal/secrets` exists, is gitignored, and contains literal secret values (not command substitution).

Expected behavior:

- The agent offers migration to a committed backend (SOPS + age or 1Password) rather than leaving plaintext secrets as the permanent state, but does not force migration without user agreement.
- At no point does the agent print, log, or otherwise surface the plaintext secret values while inventorying which secret names exist.
- Decryption/resolution via the new backend is verified before any plaintext copy is deleted.
- The agent checks whether any of these plaintext values were ever committed to git history; if so, it flags them as compromised and recommends rotating the actual application credential - not just deleting the file from the working tree.

## Case G: age private identity found inside the repository

Scenario: a file matching an age private identity (e.g. `AGE-SECRET-KEY-...` content) is present and tracked, or staged, inside the repo.

Expected behavior:

- This is a security blocker. The agent must not treat the deployment as ready, must not proceed with a normal deploy flow, and must report the exposure clearly (without printing the key itself).
- The agent recommends treating every secret the exposed identity could decrypt as compromised and rotating them, plus generating a new identity and re-encrypting with `sops updatekeys` against a recipient list that excludes the exposed one.

## Case H: missing age identity at deploy time

Scenario: `.sops.yaml`/encrypted file are present and correct, but no age private identity is available in the current environment (no `SOPS_AGE_KEY_FILE`, no default identity file).

Expected behavior:

- `.kamal/secrets` fails closed with a clear error (e.g. via `set -e` plus a non-zero exit from the `sops` call) - it must not deploy with blank/empty secret values as if they were valid.
- The encrypted file itself stays safe; the agent does not suggest bypassing SOPS (e.g. temporarily hardcoding a secret) to get the deploy to proceed.
- The agent states the setup requirement (obtain or generate an authorized age identity) rather than attempting a workaround.

## Case I: frontend build-time / `NEXT_PUBLIC_*` variables

Scenario: a Next.js unit has both server-only secrets and `NEXT_PUBLIC_*` build-time variables, with SOPS + age as the chosen backend.

Expected behavior:

- Server-only secrets resolved from SOPS never get assigned to a `NEXT_PUBLIC_*` variable.
- The agent does not treat "it's available via the secrets backend" as justification for exposing a value to the browser bundle - the existing `NEXT_PUBLIC_*` safety rule from the Next.js recipe still applies unchanged with SOPS + age in use.

## Explicitly out of scope for this fixture

- The exact `sops`/`age` CLI flag syntax beyond what's documented in `agents/patterns/secrets-sops-age.md` - that pattern file is the source of truth, re-verified against current tooling as needed.
- Stack-specific Dockerfile/deploy.yml content - covered by the relevant stack recipes.
