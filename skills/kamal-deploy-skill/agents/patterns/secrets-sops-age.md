# SOPS + age Secrets Integration

Loaded from `agents/patterns/secrets-backend.md` once SOPS + age is selected or detected as the established backend. Provides a Rails.credentials-like workflow for non-Rails Kamal projects: **encrypted configuration in Git + decryption key outside Git.**

## Conceptual model (not a literal Rails port)

| Rails | SOPS + age equivalent |
|---|---|
| `config/credentials/<env>.yml.enc` (per-environment credentials) | `config/secrets/<environment>.sops.yaml` (committed, encrypted, **one file per environment**) |
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

## Repository layout (default: one secrets file per environment)

An **environment** is a name such as `production`, `staging` or `development`. **Every environment gets its own encrypted file, and every environment's Kamal secrets live in a different file too.** This is the default layout for every project the Skill sets up or touches - never a single shared `config/secrets.sops.yaml`:

```text
.sops.yaml                          # committed - one creation rule per environment file, recipients only
config/
  secrets/
    production.sops.yaml            # committed - production values only
    development.sops.yaml           # committed - development values only (never deployed by Kamal)
  deploy.yml                        # shared Kamal config
  deploy.production.yml             # one per Kamal destination (may legitimately be `{}`, see below)
.kamal/
  secrets-common                    # committed - shared by EVERY destination, holds NO secret values
  secrets.production                # committed - the file Kamal reads for `-d production`
bin/
  secrets                           # `bin/secrets <environment> <command>`
```

Use a different location only when project conventions clearly call for it (an existing SOPS layout is extended, not replaced - see `agents/patterns/secrets-backend.md`).

### Environment rules

- **The environment is always the first argument of `bin/secrets`** (`bin/secrets production edit`, `bin/secrets development edit`). There is no default environment, so nobody edits or deploys production secrets by accident. A command without an environment is refused with a pointer to the right form.
- **An environment is a Kamal destination** iff `config/deploy.<environment>.yml` exists. Destinations additionally have a `.kamal/secrets.<environment>` file and are validated with `kamal config -d <environment>`. Other environments (`development`) only have the encrypted file; `bin/secrets <env> check` verifies they decrypt and reports missing primitives as `PENDING` (they are not required there), and skips the Kamal checks.
- **Name the environment even when there is only one.** A single-environment project uses `production`: `config/secrets/production.sops.yaml`, `.kamal/secrets.production`, `config/deploy.production.yml`, `bin/deploy -d production`. Adding `staging` or `development` later is then a new file, not a migration. A destination file with nothing to override must be written as `{}` - an all-comments YAML file parses to `nil` and Kamal crashes on it (`undefined method 'symbolize_keys'`).
- **Each environment has its own values.** Never copy production values into another environment's file; a secret that is missing in `development` is `PENDING` there, not borrowed from production. `bin/secrets <env> value NAME` only ever reads that environment's file, and `check` fails if `.kamal/secrets.<env>` reads from another environment.
- **`.kamal/secrets-common` never holds secret values** - it is loaded for every destination. `check` fails if one is added. Put secrets in the destination file.
- **Each environment can have its own readers.** Give every environment file its own rule in `.sops.yaml` (same recipients today if that is the reality) so production can later be limited to the people who deploy: edit only that rule and run `sops updatekeys config/secrets/<environment>.sops.yaml`. A new environment needs its rule before `bin/secrets <env> edit` can create the file.
- **Which file Kamal reads.** With `-d <destination>` Kamal loads `<secrets_path>-common` and `<secrets_path>.<destination>` (verified against Kamal 2.12's `Kamal::Secrets#secrets_filenames`); the plain `.kamal/secrets` is read **only when no destination is passed**, so it is never the right place for a destination's secrets. (With a unit-specific `secrets_path: .kamal/secrets-<unit>` the files become `.kamal/secrets-<unit>-common` and `.kamal/secrets-<unit>.<destination>`.)
- **Gitignore.** `.kamal/secrets*` stays ignored by default; un-ignore each committed destination file explicitly (`!.kamal/secrets-common`, `!.kamal/secrets.production`) once every line in it is a command substitution.

### Ownership rules

- `.sops.yaml` - **committed**. Contains only non-secret encryption configuration (age public recipients, path rules - one per environment file).
- `config/secrets/<environment>.sops.yaml` - **committed**. Values are encrypted; key names/structure remain visible per SOPS' normal format - that is expected, not a leak.
- age **private** identity - **never committed**, regardless of storage mechanism (file, env var, keychain). Only the **public** recipient derived from it ever goes into `.sops.yaml`/Git.
- `.kamal/secrets.<destination>` - may be committed **only if** every line resolves a value via command substitution from the encrypted backend (e.g. `DATABASE_PASSWORD=$(bin/secrets production value DATABASE_PASSWORD)`, or `$(sops --extract '["DATABASE_PASSWORD"]' -d config/secrets/production.sops.yaml)`) and contains no literal secret value itself. If any line still holds a plaintext value, it must stay gitignored like any other secrets file - judge this per-line, don't assume either way.

## Kamal integration

`.kamal/secrets.<destination>` entries use command substitution - no intermediate decrypted file, no extra dependency (`yq` etc.). The preferred form calls the project's `bin/secrets <environment> value NAME` (installed from `templates/bin/secrets`), which decrypts only that environment's file in memory, prints exactly one value and fails closed:

```sh
# .kamal/secrets.production
DATABASE_PASSWORD=$(bin/secrets production value DATABASE_PASSWORD)
JWT_SECRET=$(bin/secrets production value JWT_SECRET)
```

Without the helper, call `sops --extract` directly against that environment's file:

```sh
DATABASE_PASSWORD=$(sops --extract '["DATABASE_PASSWORD"]' -d config/secrets/production.sops.yaml)
```

Each line names its own environment, so a destination file can never silently read another environment's values. The `sops --extract` line is illustrative, not a syntax to copy blindly - validate `sops --extract`'s exact flag syntax against the installed SOPS version before generating it, since flag names/output format have changed across SOPS major versions.

Requirements this integration must satisfy:

- No decrypted file is ever written to disk as part of normal `kamal deploy`/`setup`/`accessory` usage.
- No secret values are committed, printed during normal deployment, or echoed into logs/reports.
- The developer does not manually export every secret before running Kamal - `.kamal/secrets.<destination>` resolves them automatically whenever an authorized age identity is available in the environment.
- A decryption failure (missing identity, unauthorized recipient, corrupted file) must **fail closed**: the `$(...)` substitution should produce a non-zero exit / empty value that surfaces as a clear Kamal error, never a silent empty secret deployed as if it were valid. Prefer wrapping each extraction so a `sops` failure aborts the secrets file (`set -e` at the top of `.kamal/secrets.<destination>`) rather than continuing with blank values (`bin/secrets <environment> value NAME` already exits non-zero on a missing or empty value).
- If multiple secrets are needed and decrypting the whole file once is both simpler and safe (no partial-value exposure concern), prefer that over N separate `--extract` calls - balance the number of `sops` invocations against complexity; don't default to either extreme without reason.

## Developer UX

Recommend project-level helpers if the repo doesn't already have an equivalent. Exact naming follows repo convention; the shape:

Every command takes the environment as its **first argument** (`bin/secrets <environment> <command>`), never a default - see "Repository layout".

- **`bin/secrets <environment> edit`** - runs `sops config/secrets/<environment>.sops.yaml`. Opens decrypted in `$EDITOR`, re-encrypts on save, never leaves a plaintext file on disk afterward. For a new environment it first creates the empty encrypted file (the matching rule must exist in `.sops.yaml`).
- **`bin/secrets <environment> show`** - runs `sops -d` on that environment's file. Must make clear in its own output/help text that it prints secret values to the terminal; never invoke this from another script or automatically.
- **`bin/secrets <environment> value NAME`** - prints exactly one value from that environment's file (what `.kamal/secrets.<environment>` lines call). Fails closed on a missing or empty value. Project-specific derived values (see `agents/patterns/derived-deployment-values.md`) are added as branches in the script's `cmd_value`.
- **`bin/secrets <environment> check`** - verifies, without printing values: `sops` is installed; an age identity is resolvable (`SOPS_AGE_KEY_FILE` set / default identity path present); `sops -d` on that environment's encrypted file succeeds; and, **only for an environment that is a Kamal destination** (`config/deploy.<environment>.yml` exists), that `.kamal/secrets.<environment>` has no literal values and reads only from this environment, `.kamal/secrets-common` holds no values, `kamal config -d <environment>` resolves, and every secret **primitive** referenced by `config/deploy.yml`'s `env.secret`/accessory `secret:` lists exists in the decrypted structure. A **derived** value (e.g. `DATABASE_URL`) is not checked for its own backend entry - it has none by design - its *dependencies* (the primitive(s) plus topology it derives from, per `agents/patterns/derived-deployment-values.md`) are checked instead, and derivation success is verified without printing the result. Non-deploy environments (e.g. `development`) only need to decrypt; missing primitives are `PENDING` there. If a safe "list key names only" SOPS invocation is available for the installed version, prefer it over a full decrypt-then-discard-values approach.
- **`bin/secrets <environment> generate <NAME>`** / **`generate --missing`** / **`policy`** / **`rotate <NAME>`** - generates a secret primitive using a trusted CSPRNG/tool and writes it directly into `config/secrets/<environment>.sops.yaml`, without ever printing the value. Don't reimplement this inline: install the Skill's own reusable, executable implementation at `templates/bin/secrets` as the project's `bin/secrets` (merging with any existing script rather than overwriting it), driven by the project-specific, commit-safe `config/secret-generation.yml` policy file (template at `templates/config/secret-generation.yml`). Full behavior (policy classification, the generator registry, rejecting provider-managed/unknown/preserve-only secrets, rotation gating on an existing real value, the safest available single-value SOPS update mechanism, post-write validation) is defined in `agents/patterns/secret-generation.md` - load it before installing or running this subcommand.
- **`bin/deploy`/`bin/setup`** (when the project has them) require `-d <destination>` and run `bin/secrets <destination> check` first, so the destination that is deployed is exactly the environment whose secrets were verified.

Also document the raw underlying commands (`sops config/secrets/<environment>.sops.yaml`, `sops -d config/secrets/<environment>.sops.yaml`, `sops --extract ... -d ...`, `sops updatekeys config/secrets/<environment>.sops.yaml`) so the workflow doesn't depend entirely on custom wrappers existing.

## Initial setup (new project, no existing age identity)

1. Explain what will be created before creating it: an age identity (private + public) and the SOPS/Kamal wiring around it.
2. Generate the identity with `age-keygen`, writing the **private** key directly to its storage location (a file outside the repo, or the current SOPS-supported default identity path) - never let it print to a terminal transcript or land in shell history. Do not overwrite an existing identity if one is already present; detect it first.
3. Capture the **public** recipient from the generated identity.
4. Create `.sops.yaml` with that recipient under `creation_rules` - one rule per environment file (`config/secrets/production\.sops\.yaml$`, plus one for each other environment the project uses, e.g. `development`).
5. Create `config/secrets/production.sops.yaml` (and one file per other environment) with the required secret names, encrypted via `sops`, with placeholder/empty values the user fills in through `bin/secrets <environment> edit` (or the raw `sops` command) - never ask for secret values in chat.
6. Create the destination (`config/deploy.production.yml`, `{}` if there is nothing to override) and wire `.kamal/secrets.production` to resolve from the production file per "Kamal integration" above; leave `.kamal/secrets-common` free of values.
7. If a filesystem decision can't be safely inferred (where to store the private identity on this particular machine/CI), ask before deciding.
8. Never print the private identity in any report, log, or commit. Never commit it.

## Reusing an existing age identity

If the operator already has a suitable age identity, prefer reusing it over generating a project-specific one, unless the user wants per-project keys. Detect via `SOPS_AGE_KEY_FILE` or the current default identity path; confirm its public recipient without ever displaying the private material. Only the public recipient goes into `.sops.yaml`.

## Multiple developers/operators

Support multiple age recipients in `.sops.yaml` - do not recommend one shared private identity for a whole team as the normal model; one identity is acceptable only for a genuinely solo operator.

- **Adding a recipient**: obtain their public age recipient, add it to the `.sops.yaml` rule of each environment they should read, run `sops updatekeys config/secrets/<environment>.sops.yaml` for each of those files, commit. No existing value needs to be re-entered.
- **Removing a recipient**: remove their public key from `.sops.yaml`, run `sops updatekeys` on every environment file they could read to re-encrypt the data key for the remaining recipients, commit. This revokes their ability to decrypt the file **going forward** - it does not erase secrets they already saw. See rotation semantics below.

## Key loss and recovery

If every age identity capable of decrypting an environment's `config/secrets/<environment>.sops.yaml` is lost, the encrypted secrets become unrecoverable - there is no backdoor. Recommend (don't automatically create) a recovery strategy appropriate to the project: a securely backed-up recovery identity, an additional trusted recipient, or a cloud KMS recipient where the project already has that infrastructure. Never automatically generate or upload a recovery key to a third-party system on the user's behalf.

## Rotation semantics (two different operations)

- **Encryption-key rotation**: changing which age identities can decrypt the file (`sops updatekeys` after editing `.sops.yaml`'s recipients). This changes *who can decrypt*, not the secret values themselves.
- **Application-secret rotation**: changing the actual values (database passwords, JWT secrets, API keys, registry credentials) via `bin/secrets <environment> edit`/`sops`.
- **Removing a recipient does not rotate the application secrets they could previously see.** If someone's access is revoked specifically because they left or were compromised, treat that as a prompt to also rotate the application secrets they had access to - state this explicitly rather than treating recipient removal alone as sufficient.
- For the generalized, risk-aware application-secret rotation workflow (identifying consumers/derived values/external systems, grace periods, obtaining explicit rotation intent, and safe retirement of the old value), see `agents/patterns/secret-generation.md`'s "Rotation" section - it applies on top of the mechanics above, not instead of them.

## Secret classification (don't encrypt everything)

Keep clear/non-secret configuration (hostnames, ports, public URLs, database names, non-secret feature flags) in `config/deploy.yml`'s normal clear configuration - do not move it into SOPS merely because SOPS is available. Only passwords, private API keys, signing secrets, private tokens, and registry credentials (where actually required - see below) belong in the encrypted backend.

`config/secrets/<environment>.sops.yaml` holds secret **primitives** only - never a derived composite value (a `DATABASE_URL` that just re-embeds a password already stored as `POSTGRES_PASSWORD`) and never a value with no secret material at all (an unauthenticated accessory's `REDIS_URL`). See `agents/patterns/derived-deployment-values.md` for the full category breakdown and how `.kamal/secrets.<destination>` constructs derived values at resolution time without ever writing them to disk.

## Browser/build-time variables

Preserve the existing `NEXT_PUBLIC_*`/build-time-variable rules from the stack recipes and `agents/patterns/multi-service-repo.md`: a value resolved from SOPS is still a server-side secret, and must never be wired into a browser-bundled/build-time-public variable. SOPS is a storage/transport mechanism for a secret - it does not change whether that value is safe to expose to a browser.

## Registry credentials

Evaluate independently of other secrets. If the registry is unauthenticated (e.g. a local Kamal registry) and no credential is needed, don't invent one just to have something in SOPS. If credentials are required, source them from SOPS the same way as any other Kamal secret.

## Migration from plaintext `.kamal/secrets` or a single shared secrets file

Two migrations lead to the per-environment layout:

- **Plaintext `.kamal/secrets` or env file -> SOPS** (steps below).
- **A single `config/secrets.sops.yaml` and/or `.kamal/secrets-common` full of values -> per-environment files.** `git mv config/secrets.sops.yaml config/secrets/<environment>.sops.yaml` (the file is for the environment it was holding - normally `production`; the MAC does not depend on the path, so no re-encryption is needed), update `.sops.yaml`'s rule to the new path, move the values from `.kamal/secrets-common` into `.kamal/secrets.<destination>` rewriting each line to `$(bin/secrets <environment> value NAME)`, leave `.kamal/secrets-common` value-free, make `bin/secrets` environment-first (merge `templates/bin/secrets` into the existing script, keeping project-specific extensions), require `-d` in `bin/deploy`/`bin/setup`, update `.gitignore` (`!.kamal/secrets.<destination>`) and every doc/comment that names the old paths, then run `bin/secrets <environment> check` and `kamal config -d <destination>`. If the project had no destination yet, add `config/deploy.<environment>.yml` (`{}`) first - without a destination Kamal never reads `.kamal/secrets.<destination>`.

When an existing project has plaintext secrets in an untracked `.kamal/secrets` or env file and SOPS + age is selected:

1. Identify the required secret **names** without printing or logging their values.
2. Set up the SOPS + age backend (`.sops.yaml`, `config/secrets/<environment>.sops.yaml`) per "Initial setup" above.
3. Migrate each value into the encrypted file via `sops`/`bin/secrets <environment> edit` - never passing values through a tool call, report, diff, or test fixture that would echo them.
4. Verify decryption succeeds (`sops -d`/`bin/secrets <environment> check`).
5. Update `.kamal/secrets.<destination>` to resolve from SOPS per "Kamal integration."
6. Verify `config/deploy.yml` still resolves (`kamal config -d <destination>` - see validation below).
7. Verify every secret name `config/deploy.yml` requires is present in the encrypted structure.
8. Confirm the plaintext file/values are no longer required for any Kamal command to succeed.
9. Only after that verification, delete the plaintext copy - don't delete it speculatively before confirming the SOPS path actually works.
10. Check git history/index for accidental prior commits of the plaintext file (`git log --all --full-history -- <path>` or equivalent). If a secret value was ever committed historically, flag it as **compromised** - require rotating the actual application credential, not just removing the file from the current tree (removing a file does not remove it from history, and even purging history doesn't un-expose a value others may have already fetched).

## Validation checklist (before deployment, when SOPS is selected)

- `sops` is installed and on `PATH`.
- A usable age identity is resolvable in the current environment.
- Each environment's `config/secrets/<environment>.sops.yaml` decrypts successfully (`bin/secrets <environment> check`).
- Every environment has its own file and its own `.sops.yaml` rule; `.kamal/secrets-common` holds no values and `.kamal/secrets.<destination>` reads only its own environment.
- Every secret name `config/deploy.yml`'s `env.secret` and accessory `secret:` lists require exists in the decrypted structure, and none resolve to an empty value.
- `.sops.yaml` contains only recipients/path rules - no secret values.
- No private age identity file is tracked by git.
- No plaintext secrets file is tracked by git.
- If `.kamal/secrets.<destination>` is committed, confirm every line is a command-substitution lookup, not a literal value.
- `kamal config -d <destination>` (which resolves secrets without printing them) succeeds. **Never use `kamal secrets print`/`sops -d`'s full output as a routine validation step** - both intentionally expose values; reserve them for deliberate, explicit inspection (`bin/secrets show`), never an automated check.

## Rails projects

If a Rails project already uses `config/credentials.yml.enc` + `RAILS_MASTER_KEY`, preserve that model - do not introduce SOPS alongside or in place of it unless the user explicitly asks for SOPS specifically. SOPS + age exists in this Skill for non-Rails projects (or a Rails project's non-Rails sibling units) that have no equivalent encrypted-in-repo workflow yet, not as a universal replacement.
