# SOPS + age Secrets Integration

Loaded from `agents/patterns/secrets-backend.md` once SOPS + age is selected or detected as the established backend. Provides a Rails.credentials-like workflow for non-Rails Kamal projects: **encrypted configuration in Git + decryption key outside Git.**

## Conceptual model (not a literal Rails port)

| Rails | SOPS + age equivalent |
|---|---|
| `config/credentials.yml.enc` | `config/secrets.sops.yaml` (committed, encrypted) |
| `config/master.key` / `RAILS_MASTER_KEY` (never committed) | age private identity (never committed) |

Only the operational model carries over - encrypted file in Git, decryption key outside it. Do not otherwise copy Rails' implementation.

## Verified SOPS + age mechanics

Re-verify against current official SOPS documentation if behavior here looks off:

- SOPS encrypts values in-place in a structured file (YAML/JSON/ENV/etc.); keys/structure stay visible, only values are encrypted.
- `.sops.yaml` at the repo root declares `creation_rules` with an `age:` recipient list (comma-separated age **public** keys) per path pattern - it is non-secret configuration and is safe to commit.
- `sops <file>` opens the file decrypted in `$EDITOR`, then re-encrypts on save - no persistent plaintext file is created on disk as part of normal editing.
- `sops -d <file>` decrypts to stdout. `sops --extract '["key"]' -d <file>` decrypts and extracts a single value to stdout without dumping the whole file - prefer this for single-secret lookups over decrypting everything.
- age identity resolution: `SOPS_AGE_KEY_FILE` (path to a private key file), `SOPS_AGE_KEY` (the private key material directly, as an env var - avoid this one, it risks landing in shell history/process listings), or SOPS' default identity file location for the current SOPS version - confirm the current default path for the installed version rather than hardcoding one from memory.
- `sops updatekeys <file>` re-encrypts the file's data key for the recipient list currently in `.sops.yaml` - this is how a recipient is added or removed without decrypting/re-entering every value.
- age key generation: `age-keygen` prints a private identity plus its public recipient; redirect the private identity straight to its storage location, never let it print to a terminal that gets logged.

## Repository layout

```text
.sops.yaml                  # committed - recipients only, no secret values
config/
  secrets.sops.yaml         # committed - SOPS-encrypted values
.kamal/
  secrets                   # committed only if it contains no plaintext values (see below)
```

Use a different location only when project conventions clearly call for it.

### Ownership rules

- `.sops.yaml` - **committed**. Contains only non-secret encryption configuration (age public recipients, path rules).
- `config/secrets.sops.yaml` - **committed**. Values are encrypted; key names/structure remain visible per SOPS' normal format - that is expected, not a leak.
- age **private** identity - **never committed**, regardless of storage mechanism (file, env var, keychain). Only the **public** recipient derived from it ever goes into `.sops.yaml`/Git.
- `.kamal/secrets` - may be committed **only if** every line resolves a value via command substitution from the encrypted backend (e.g. `DATABASE_PASSWORD=$(sops --extract '["database_password"]' -d config/secrets.sops.yaml)`) and contains no literal secret value itself. If any line still holds a plaintext value, it must stay gitignored like any other secrets file - judge this per-line, don't assume either way.

## Kamal integration

`.kamal/secrets` entries use command substitution to call `sops --extract` directly - no intermediate decrypted file, no extra dependency (`yq` etc.) when `sops --extract` already does the job safely:

```sh
DATABASE_PASSWORD=$(sops --extract '["database_password"]' -d config/secrets.sops.yaml)
JWT_SECRET=$(sops --extract '["jwt_secret"]' -d config/secrets.sops.yaml)
```

This is illustrative, not a syntax to copy blindly - validate `sops --extract`'s exact flag syntax against the installed SOPS version before generating it, since flag names/output format have changed across SOPS major versions.

Requirements this integration must satisfy:

- No decrypted file is ever written to disk as part of normal `kamal deploy`/`setup`/`accessory` usage.
- No secret values are committed, printed during normal deployment, or echoed into logs/reports.
- The developer does not manually export every secret before running Kamal - `.kamal/secrets` resolves them automatically whenever an authorized age identity is available in the environment.
- A decryption failure (missing identity, unauthorized recipient, corrupted file) must **fail closed**: the `$(...)` substitution should produce a non-zero exit / empty value that surfaces as a clear Kamal error, never a silent empty secret deployed as if it were valid. Prefer wrapping each extraction so a `sops` failure aborts the secrets file (`set -e` at the top of `.kamal/secrets`) rather than continuing with blank values.
- If multiple secrets are needed and decrypting the whole file once is both simpler and safe (no partial-value exposure concern), prefer that over N separate `--extract` calls - balance the number of `sops` invocations against complexity; don't default to either extreme without reason.

## Developer UX

Recommend project-level helpers if the repo doesn't already have an equivalent. Exact naming follows repo convention; the shape:

- **`bin/secrets edit`** - runs `sops config/secrets.sops.yaml`. Opens decrypted in `$EDITOR`, re-encrypts on save, never leaves a plaintext file on disk afterward.
- **`bin/secrets show`** - runs `sops -d config/secrets.sops.yaml`. Must make clear in its own output/help text that it prints secret values to the terminal; never invoke this from another script or automatically.
- **`bin/secrets check`** - verifies, without printing values: `sops` is installed; an age identity is resolvable (`SOPS_AGE_KEY_FILE` set / default identity path present); `sops -d` on the encrypted file succeeds; every secret **primitive** referenced by `config/deploy.yml`'s `env.secret`/accessory `secret:` lists exists as a key in the decrypted structure; no plaintext secrets file (e.g. an untracked `.env` with real values, a non-SOPS `.kamal/secrets` with literal values) is tracked by git. A **derived** value (e.g. `DATABASE_URL`) is not checked for its own backend entry - it has none by design - its *dependencies* (the primitive(s) plus topology it derives from, per `agents/patterns/derived-deployment-values.md`) are checked instead, and derivation success is verified without printing the result. If a safe "list key names only" SOPS invocation is available for the installed version, prefer it over a full decrypt-then-discard-values approach.

Also document the raw underlying commands (`sops config/secrets.sops.yaml`, `sops -d config/secrets.sops.yaml`, `sops --extract ... -d ...`, `sops updatekeys config/secrets.sops.yaml`) so the workflow doesn't depend entirely on custom wrappers existing.

## Initial setup (new project, no existing age identity)

1. Explain what will be created before creating it: an age identity (private + public) and the SOPS/Kamal wiring around it.
2. Generate the identity with `age-keygen`, writing the **private** key directly to its storage location (a file outside the repo, or the current SOPS-supported default identity path) - never let it print to a terminal transcript or land in shell history. Do not overwrite an existing identity if one is already present; detect it first.
3. Capture the **public** recipient from the generated identity.
4. Create `.sops.yaml` with that recipient under `creation_rules`.
5. Create `config/secrets.sops.yaml` with the required secret names, encrypted via `sops`, with placeholder/empty values the user fills in through `bin/secrets edit` (or the raw `sops` command) - never ask for secret values in chat.
6. Wire `.kamal/secrets` to resolve from it per "Kamal integration" above.
7. If a filesystem decision can't be safely inferred (where to store the private identity on this particular machine/CI), ask before deciding.
8. Never print the private identity in any report, log, or commit. Never commit it.

## Reusing an existing age identity

If the operator already has a suitable age identity, prefer reusing it over generating a project-specific one, unless the user wants per-project keys. Detect via `SOPS_AGE_KEY_FILE` or the current default identity path; confirm its public recipient without ever displaying the private material. Only the public recipient goes into `.sops.yaml`.

## Multiple developers/operators

Support multiple age recipients in `.sops.yaml` - do not recommend one shared private identity for a whole team as the normal model; one identity is acceptable only for a genuinely solo operator.

- **Adding a recipient**: obtain their public age recipient, add it to `.sops.yaml`'s recipient list, run `sops updatekeys config/secrets.sops.yaml`, commit both files. No existing value needs to be re-entered.
- **Removing a recipient**: remove their public key from `.sops.yaml`, run `sops updatekeys` to re-encrypt the data key for the remaining recipients, commit. This revokes their ability to decrypt the file **going forward** - it does not erase secrets they already saw. See rotation semantics below.

## Key loss and recovery

If every age identity capable of decrypting `config/secrets.sops.yaml` is lost, the encrypted secrets become unrecoverable - there is no backdoor. Recommend (don't automatically create) a recovery strategy appropriate to the project: a securely backed-up recovery identity, an additional trusted recipient, or a cloud KMS recipient where the project already has that infrastructure. Never automatically generate or upload a recovery key to a third-party system on the user's behalf.

## Rotation semantics (two different operations)

- **Encryption-key rotation**: changing which age identities can decrypt the file (`sops updatekeys` after editing `.sops.yaml`'s recipients). This changes *who can decrypt*, not the secret values themselves.
- **Application-secret rotation**: changing the actual values (database passwords, JWT secrets, API keys, registry credentials) via `bin/secrets edit`/`sops`.
- **Removing a recipient does not rotate the application secrets they could previously see.** If someone's access is revoked specifically because they left or were compromised, treat that as a prompt to also rotate the application secrets they had access to - state this explicitly rather than treating recipient removal alone as sufficient.

## Secret classification (don't encrypt everything)

Keep clear/non-secret configuration (hostnames, ports, public URLs, database names, non-secret feature flags) in `config/deploy.yml`'s normal clear configuration - do not move it into SOPS merely because SOPS is available. Only passwords, private API keys, signing secrets, private tokens, and registry credentials (where actually required - see below) belong in the encrypted backend.

`config/secrets.sops.yaml` holds secret **primitives** only - never a derived composite value (a `DATABASE_URL` that just re-embeds a password already stored as `POSTGRES_PASSWORD`) and never a value with no secret material at all (an unauthenticated accessory's `REDIS_URL`). See `agents/patterns/derived-deployment-values.md` for the full category breakdown and how `.kamal/secrets` constructs derived values at resolution time without ever writing them to disk.

## Browser/build-time variables

Preserve the existing `NEXT_PUBLIC_*`/build-time-variable rules from the stack recipes and `agents/patterns/multi-service-repo.md`: a value resolved from SOPS is still a server-side secret, and must never be wired into a browser-bundled/build-time-public variable. SOPS is a storage/transport mechanism for a secret - it does not change whether that value is safe to expose to a browser.

## Registry credentials

Evaluate independently of other secrets. If the registry is unauthenticated (e.g. a local Kamal registry) and no credential is needed, don't invent one just to have something in SOPS. If credentials are required, source them from SOPS the same way as any other Kamal secret.

## Migration from plaintext `.kamal/secrets`

When an existing project has plaintext secrets in an untracked `.kamal/secrets` or env file and SOPS + age is selected:

1. Identify the required secret **names** without printing or logging their values.
2. Set up the SOPS + age backend (`.sops.yaml`, `config/secrets.sops.yaml`) per "Initial setup" above.
3. Migrate each value into the encrypted file via `sops`/`bin/secrets edit` - never passing values through a tool call, report, diff, or test fixture that would echo them.
4. Verify decryption succeeds (`sops -d`/`bin/secrets check`).
5. Update `.kamal/secrets` to resolve from SOPS per "Kamal integration."
6. Verify `config/deploy.yml` still resolves (`kamal config` - see validation below).
7. Verify every secret name `config/deploy.yml` requires is present in the encrypted structure.
8. Confirm the plaintext file/values are no longer required for any Kamal command to succeed.
9. Only after that verification, delete the plaintext copy - don't delete it speculatively before confirming the SOPS path actually works.
10. Check git history/index for accidental prior commits of the plaintext file (`git log --all --full-history -- <path>` or equivalent). If a secret value was ever committed historically, flag it as **compromised** - require rotating the actual application credential, not just removing the file from the current tree (removing a file does not remove it from history, and even purging history doesn't un-expose a value others may have already fetched).

## Validation checklist (before deployment, when SOPS is selected)

- `sops` is installed and on `PATH`.
- A usable age identity is resolvable in the current environment.
- `config/secrets.sops.yaml` decrypts successfully.
- Every secret name `config/deploy.yml`'s `env.secret` and accessory `secret:` lists require exists in the decrypted structure, and none resolve to an empty value.
- `.sops.yaml` contains only recipients/path rules - no secret values.
- No private age identity file is tracked by git.
- No plaintext secrets file is tracked by git.
- If `.kamal/secrets` is committed, confirm every line is a command-substitution lookup, not a literal value.
- `kamal config` (which resolves secrets without printing them) succeeds. **Never use `kamal secrets print`/`sops -d`'s full output as a routine validation step** - both intentionally expose values; reserve them for deliberate, explicit inspection (`bin/secrets show`), never an automated check.

## Rails projects

If a Rails project already uses `config/credentials.yml.enc` + `RAILS_MASTER_KEY`, preserve that model - do not introduce SOPS alongside or in place of it unless the user explicitly asks for SOPS specifically. SOPS + age exists in this Skill for non-Rails projects (or a Rails project's non-Rails sibling units) that have no equivalent encrypted-in-repo workflow yet, not as a universal replacement.
