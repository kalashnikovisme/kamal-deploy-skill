# Secrets Backend Selection

Runs once per repo, during SKILL.md Step 4b, before any production secret is written to `.kamal/secrets` or any accessory's `secret:` list.

## Verified Kamal mechanics

Verified against Kamal's current documented behavior - re-verify if it changes:

- `.kamal/secrets` is a shell script Kamal sources before `deploy`/`setup`/`accessory`/etc. Lines are `KEY=value` or `KEY=$(command)` - command substitution is fully supported, so any command that prints a value to stdout can populate a secret.
- `secrets_path` defaults to `.kamal/secrets`; Kamal also supports a shared `.kamal/secrets-common` plus a destination-specific `.kamal/secrets.<destination>` loaded and merged per destination.
- `kamal secrets fetch`/`kamal secrets extract` ship **native adapters** for a fixed set of providers (1Password among them) - these are adapters Kamal's own CLI knows how to call directly.
- **SOPS has no native `kamal secrets fetch --adapter` provider.** Do not describe it as one. SOPS is integrated the same way any non-native backend is: a command inside `.kamal/secrets` (command substitution) that calls `sops` directly and prints the decrypted value - there is no Kamal-side SOPS awareness beyond that.
- `env.secret` entries and accessory `secret:` entries both resolve by name from whatever `.kamal/secrets`/`secrets_path` ultimately exports - the backend behind that is invisible to Kamal past this point.

## Decision step

Before generating production secrets configuration for a project with no established backend, inspect the repo for an existing one and prefer it over asking:

| Signal | Established backend | Action |
|---|---|---|
| `config/credentials.yml.enc` + `config/master.key`/`RAILS_MASTER_KEY` | Rails credentials | Preserve it - see "Rails projects" below. Never propose replacing it. |
| `.sops.yaml` + an encrypted file (`*.sops.yaml`/`*.enc.yaml`/sops metadata inside a YAML/JSON/ENV file) | SOPS (age or otherwise) | Preserve its existing recipients/layout; extend rather than replace. |
| `op://` references, a 1Password Connect/Service Account setup, `.kamal/secrets` calling `kamal secrets fetch --adapter 1password` | 1Password | Preserve it. |
| Doppler/Bitwarden CLI calls, cloud KMS/secret-manager references in `.kamal/secrets` or CI config | That provider | Preserve it. |

**Never migrate an existing secure backend merely because another option exists.** Only change backends on an explicit user request.

If no established backend is found, present options rather than picking one silently. At minimum:

> "This project has no established secrets-management backend yet. Two good options for Kamal:
>
> - **1Password** - secret values live in an external vault; good if you already use 1Password, want centralized/team secret management, and are fine with an external service owning the vault. Kamal has a native 1Password integration.
> - **SOPS + age** - a Rails.credentials-like workflow: an encrypted file committed to Git, with the decryption key (an age identity) kept outside Git. No external SaaS dependency; cloning the repo plus an authorized private key is enough to operate the deployment. (Not a native Kamal adapter - integrated via `.kamal/secrets` command substitution.)
>
> Which fits this project?"

Mention other providers (Doppler, Bitwarden, a cloud secret manager) only if the user asks or repo evidence points at one specifically - don't pad the decision with options nobody asked about.

Do not describe either option as universally more secure - they differ in ownership model, not security tier:

- **1Password**: secret values live in an external vault; access/audit managed by that service.
- **SOPS + age**: encrypted secret values live in the repository itself; decryption capability lives entirely outside the repository, in whoever holds an authorized age private identity.

## Persisting the decision

Record which backend was chosen in the project's deployment documentation (SKILL.md Step 6) so future Skill invocations detect and continue using it without re-asking. If `.kamal/secrets` already resolves from a given backend, or the documentation already states one, treat that as the established backend for this repo going forward - the question above is only for a repo with no backend at all.

## Loading backend-specific detail

- **SOPS + age**: load `agents/patterns/secrets-sops-age.md` for setup, editing, multi-user recipients, rotation, migration, and validation.
- **1Password**: use Kamal's native `kamal secrets fetch --adapter 1password` integration per Kamal's own documentation; no dedicated pattern file exists for it in this Skill beyond the existing secrets guidance in SKILL.md Step 4b/Secrets Policy.
- **Other established backends found above**: follow the project's existing convention; do not invent new tooling for it.
