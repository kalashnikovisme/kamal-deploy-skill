# Secret Generation and Secure Storage

Runs whenever a secret primitive needs a value - automatically, during SKILL.md Step 4b/5 when deployment-owned infrastructure requires a new credential, or explicitly, whenever the user asks for a specific secret to be generated or rotated (e.g. "generate JWT_SECRET", "create a new VAPID key pair", "generate all missing locally-generatable secrets"). Requires the secrets backend to already be selected (`agents/patterns/secrets-backend.md`) and the four-category model (`agents/patterns/derived-deployment-values.md`) already applied to the value in question.

## Core security invariant

> **The model may decide how a secret should be generated, but the model must never generate cryptographic secret material itself.**

Secret material must always come from an actual cryptographically secure implementation available in the execution environment - never from the model composing a random-looking string.

**Acceptable sources** (select the one appropriate to the primitive's actual type, verifying current syntax against the installed tool/library's own documentation rather than relying on memory):

- OpenSSL's CSPRNG (`openssl rand`)
- the operating system's CSPRNG (e.g. `/dev/urandom` via a proper generator call, not read raw)
- language cryptographic APIs: Ruby `SecureRandom`, Python `secrets`, Node.js `crypto.randomBytes`, Go `crypto/rand`
- framework-native secret/key generators, when the framework actually provides one for this purpose
- protocol-specific official tooling: `ssh-keygen`, `age-keygen`, a VAPID-library's own key-pair generator, etc.

**Never acceptable, under any circumstance:**

- an LLM-generated random-looking string
- `rand()` or any other non-cryptographic PRNG
- timestamps
- UUIDs, unless the specific protocol explicitly treats a UUID as sufficient entropy for that exact purpose
- a hash of a predictable value (username, project name, hostname, etc.)
- `$RANDOM` (shell's non-cryptographic PRNG)
- a password derived from the username/project/service name
- any entropy the model invents, assembles, or "types out" itself

If no trusted generator is available in the execution environment for a given primitive type, do not fall back to inventing one - report that generation is blocked and explain what tooling is missing.

## Step 1: Determine semantics before generating

**Never generate a value based only on its environment-variable name.** Before generating anything, inspect:

- the application code that actually consumes the variable
- the framework/library involved (which algorithm, which encoding, which format)
- existing configuration and `.env.example`/documentation
- validation rules (e.g. a startup check that enforces a minimum length or specific encoding)
- the existing value's format, if a real value already exists
- authoritative documentation for the protocol/library where the above doesn't fully resolve it

A name is a hint, not a specification. `JWT_SECRET` could be an HMAC signing secret, a misnamed leftover no longer read anywhere, or something a newer asymmetric setup has already superseded - determine which from actual usage before choosing a generation strategy. If usage is genuinely ambiguous after inspection, ask the user rather than guessing.

## Step 2: Classify generation policy

Classify every secret primitive into exactly one policy before taking any action:

| Policy | Meaning | Example |
|---|---|---|
| `LOCAL_GENERATABLE` | A random symmetric value with no external dependency - entropy/format determined by actual usage | A session/cookie-signing secret, an internal service token |
| `PROTOCOL_GENERATABLE` | Must be produced by a specific protocol's key-generation mechanism, usually yielding related public/private components | VAPID key pair, SSH key pair, an asymmetric JWT key pair |
| `FRAMEWORK_GENERATABLE` | The project's framework ships an authoritative generator for this exact purpose - prefer it over a generic CSPRNG call when it genuinely applies | A framework-specific secret-key-generation command, when actually present and appropriate |
| `INFRASTRUCTURE_GENERATABLE` | A credential for infrastructure this Skill is newly creating and fully owns both sides of | A brand-new Kamal-managed `POSTGRES_PASSWORD`/`REDIS_PASSWORD` |
| `PROVIDER_MANAGED` | Issued by an external party; the Skill has no authority to mint it | `GOOGLE_CLIENT_SECRET`, `RESEND_API_KEY`, `PADDLE_API_KEY`, `SENTRY_AUTH_TOKEN`, `TELEGRAM_BOT_TOKEN`, an AWS access key |
| `EXISTING_VALUE_MUST_BE_PRESERVED` | A real (non-placeholder) value already exists for this primitive | Any of the above, once a real value is found in the backend |
| `GENERATION_POLICY_UNKNOWN` | Semantics could not be determined from inspection | An unfamiliar vendor-specific variable with no discoverable usage |

Only `LOCAL_GENERATABLE`, `PROTOCOL_GENERATABLE`, `FRAMEWORK_GENERATABLE`, and `INFRASTRUCTURE_GENERATABLE` may be generated automatically (subject to Step 4 below). `PROVIDER_MANAGED` is never generated - report that the value must come from its actual provider. `GENERATION_POLICY_UNKNOWN` is never generated either - naming alone is not authorization to invent a credential; investigate further or ask the user.

This policy is a classification, not a hardcoded table of secret names - it is re-derived per project from actual usage (Step 1), not assumed from a name matching a prior example.

## Step 3: Standards-aware generation by category

### Random application secret (symmetric)

Covers JWT HMAC secrets, session secrets, cookie-signing secrets, CSRF secrets, application-level encryption secrets, internal service tokens.

- Determine the actual algorithm/library in use (e.g. for JWT: is it HS256, HS384, HS512, or an asymmetric algorithm entirely? - inspect the signing configuration, don't assume).
- Use that algorithm/library's own documented minimum-entropy guidance to size the generated value - there is no single universal length; do not impose one.
- Generate with an appropriate CSPRNG (see "Core security invariant" above) and the encoding the consumer actually expects (raw bytes, base64, hex, etc. - verify from how the value is read, not assumed).

### Password

Covers a PostgreSQL/Redis accessory password, an internal Basic Auth credential, etc.

- Generate with a CSPRNG sized for adequate entropy; do not impose an arbitrary universal length divorced from the consumer's own constraints (if any).
- **If the password will be embedded in a URI later** (e.g. inside a derived `DATABASE_URL`/`REDIS_URL` per `agents/patterns/derived-deployment-values.md`), never narrow the character set to dodge encoding. The flow is always: generate the raw primitive -> store it -> percent-encode it correctly only at the point the derived URI is constructed. Encoding is the responsibility of the derivation step, never a constraint on the generator.

### Asymmetric key pair

Covers RSA, EC, Ed25519, SSH, VAPID, and other signing/encryption key pairs.

- Never generate these as two independent random strings - a key pair has a defined mathematical relationship that only the correct protocol/library/tool can produce.
- Use the protocol's own tooling (`ssh-keygen` for SSH, a VAPID-library's own key-pair generator for web push, a language crypto library's key-pair API for RSA/EC/Ed25519, etc.) - verify current invocation syntax against that tool/library's own documentation rather than from memory.
- Classify each resulting component independently once generated - do not default to storing both halves as secrets. The private component is a secret primitive; the public component is typically public/clear configuration (see "Key pairs" below) unless the specific protocol says otherwise.

### Framework-native secret

If the project's framework ships an authoritative, purpose-built generator for this exact kind of secret, prefer it over a generic CSPRNG call - but verify first that the framework actually provides one and that it actually applies to this variable; do not assume one exists just because the framework is popular.

### Provider-managed credential

Covers OAuth client secrets, third-party API keys, webhook signing secrets issued by a vendor's dashboard, platform access keys issued by a cloud provider, etc. **Never generate these locally.** Report that the value must be obtained from its authoritative provider, and leave an explicit unresolved placeholder (per the Placeholder Policy in `agents/patterns/derived-deployment-values.md`) rather than fabricating one.

## Step 4: Missing vs. existing vs. ambiguous

Before generating, resolve the destination's current state:

- **No value stored, or a placeholder** (e.g. `TODO_FILL_IN`): if the policy is one of the generatable categories, generate and store it. If the user explicitly requested the generation, no further confirmation is needed. If this is happening automatically (not on an explicit request), proceed only under the same conditions `agents/patterns/derived-deployment-values.md`'s "Generating new secret primitives" section already requires (no existing production value to preserve, no external system expecting a pre-existing value, the Skill owns both sides of the credential).
- **A real (non-placeholder) value already exists**: never silently overwrite it. Generating a value here is a **rotation**, not an initial generation - treat it under "Rotation" below, which requires explicit rotation intent. If the user's request was a plain "generate X" and a real value already exists, report that a real value exists, explain what rotating it would affect, and ask for explicit confirmation before replacing it - do not proceed and do not destroy the existing primitive while waiting for that confirmation.
- **Policy is `GENERATION_POLICY_UNKNOWN`**: never generate. Report the classification and what would be needed to resolve it (more context on usage, or the user's own answer).
- **Policy is `PROVIDER_MANAGED`**: never generate, regardless of current state. Report that the real provider must issue it.

## Step 5: Generate outside the model, then persist atomically

> **A generated production secret is not successfully generated until it has been safely persisted to its authoritative secret backend.**

The flow is always generate -> persist -> validate -> report success - never generate -> display -> ask the user to store it themselves. If persistence fails for any reason, the whole operation is a failure, even though random bytes were technically produced; never report success merely because generation succeeded in isolation, and never fall back to printing the value as a workaround for a failed write.

For every generated primitive, be able to state internally (not necessarily to the user, except per the audit-trail format below):

- which generator/tool was used
- its cryptographic source (CSPRNG class)
- the entropy/algorithm it targets
- the encoding applied
- why that satisfies the actual consumer's requirements (from Step 1's inspection)

The final user-facing report must never contain the generated value itself.

## Step 6: Safe command execution (never leak the value in transit)

Generation and storage must never expose the secret through: command output, shell history, process-argument listings (`ps`), logs, temporary files, a Git diff, exception/stack-trace output, or the final report.

- Prefer mechanisms that pipe or programmatically transfer the generated value directly from generator to backend without the value ever becoming a literal command-line argument (which can be visible via `ps`/process listings) or a value echoed to a terminal that gets captured in a tool-call transcript.
- Prefer, in order of preference as the backend's tooling allows: piping via stdin, passing via a file descriptor, a backend's native write API, or an in-process language-level transformation - over interpolating the value into a shell command string.
- Avoid the pattern "capture the value into a shell variable, then put that variable directly into another command's arguments" when the backend offers a stdin-accepting write path instead - prefer the stdin path.
- If a temporary file is genuinely unavoidable for a specific backend's tooling: create it with restrictive permissions, outside the repository, with a cleanup trap installed *before* it's written, remove it immediately after use, and verify the removal succeeded. Prefer a design that avoids ever creating a plaintext secret file over relying on cleanup to undo one.
- When composing a value from multiple pieces (e.g. deriving a URI from a generated password), keep every intermediate value in memory/in a shell variable - never write an intermediate plaintext composite to disk "just to check it."

## Step 7: Backend-specific write strategy

### SOPS + age

```text
trusted generator -> generated primitive -> SOPS-encrypted document -> key updated
```

- Do not decrypt the entire document to a persistent plaintext file merely to change one key. Use whatever the installed SOPS version's current safest supported single-value update mechanism is (e.g. a value-setting operation that accepts the new value without requiring a full plaintext round-trip to disk) - verify the exact current flag/command against the installed SOPS version's own documentation rather than assuming one from memory, since this has changed across SOPS versions.
- Feed the generated value to that mechanism via stdin/a non-logged channel, not as a literal command-line argument, when the installed version supports it.
- After writing, validate by decrypting internally and checking: the key exists, it is non-empty, and it no longer matches the placeholder pattern - all without printing the value anywhere, including in the validation step's own output.
- This is the same backend already documented in `agents/patterns/secrets-sops-age.md` - this pattern only adds the generation step in front of the existing write/validate mechanics there; it does not change how `.kamal/secrets` subsequently resolves the value.

### 1Password

```text
trusted generator -> generated primitive -> the appropriate 1Password item/field
```

- Use 1Password's own CLI/API write capability to set the field directly; do not route the value through an intermediate file or an unnecessary shell round-trip.
- Do not switch a 1Password-backed project to SOPS merely because generation feels easier there - use the backend the project has already selected (`agents/patterns/secrets-backend.md`'s "never migrate an existing secure backend" rule applies here too).
- Validate the field was set without printing it (e.g. a presence/length check, not a value dump).

### Other backends

Apply the same generate -> persist -> validate shape to any other backend the project has already established, using whatever write capability that backend's own tooling exposes.

**If a backend can be read but the Skill has no safe tooling available to write/update it:** do not generate the value and hold it only in memory, and do not fall back to printing it so the user can paste it in manually - that violates the atomic-generation principle. Instead, report plainly that secure automatic storage is unavailable for this backend and state what capability (CLI, API access, credential) would be needed to add it.

## Step 8: Integration with the derived-values model (v1.4.0)

Generation is entirely about secret **primitives** - it never touches a derived value directly, and a derived value is never independently (re)generated.

Example - `POSTGRES_PASSWORD`:

1. confirm it's safe to create/rotate (Step 4 above);
2. generate the raw password with a CSPRNG;
3. store only `POSTGRES_PASSWORD` in the backend;
4. do **not** store `DATABASE_URL` - it remains derived per `agents/patterns/derived-deployment-values.md`;
5. verify `DATABASE_URL` still derives successfully from the new primitive plus topology;
6. verify the derived URI's password component is still correctly percent-encoded;
7. report the dependency impact (what else re-resolves differently now that the primitive changed) without printing any resolved value.

The same shape applies to `REDIS_PASSWORD` -> derived `REDIS_URL`, and to any other primitive-plus-topology derivation this Skill already recognizes. Never regenerate a category-2/3 derived value as if it were itself a primitive.

## Step 9: Key pairs (multi-value generated credentials)

Some generation operations produce more than one related value (private + public). Preserve the relationship, but classify and store each component **independently**, per the four-category model:

```text
VAPID key pair
  private component -> secret backend (secret primitive)
  public component   -> clear/public configuration (category 4, or category 3 if purely derived from the pair with no independent entropy)
```

- Do not store both halves in the secret backend just because they were generated together - only the half that is actually confidential belongs there.
- Do not generate the two halves independently (e.g. two separate random strings pretending to be a "key pair") - they must come from one actual key-pair-generation call, so the mathematical relationship holds.
- Validate the pair relationship itself where the protocol allows a cheap check (e.g. that the public component is actually derivable from/matches the private component) as part of post-generation validation, without printing either component.

## Step 10: Rotation (distinct from initial generation)

Rotating an existing real primitive is a different, higher-stakes operation than filling in a missing one. For an existing value:

1. Identify every consumer of the primitive (application code, derived values, other roles).
2. Identify every derived value that depends on it (per `agents/patterns/derived-deployment-values.md`) - these will automatically pick up the new value at next resolution, not before.
3. Identify any external system that independently also needs the new value (e.g. a third-party dashboard holding the same shared secret) - the Skill can only update what it controls.
4. Determine whether a dual-value/grace-period rotation is required (the old and new value both need to validate for some window) rather than an instant cutover - this depends entirely on the specific primitive and its consumers; don't assume either model.
5. Determine user/session/data impact - e.g. rotating a JWT HMAC signing secret invalidates every token signed with the old one; rotating a database password requires the database user's password to actually be changed in step with the stored value, not just the stored value alone.
6. Where appropriate, ensure a backup/recovery path exists before destroying the old value (e.g. don't rotate the only credential capable of decrypting something else without confirming an alternative access path first).
7. Obtain explicit rotation intent from the user before proceeding - "generate X" alone, when a real X already exists, is not implicit rotation intent (see Step 4).
8. Generate the new primitive per Steps 3/5/6 above.
9. Update the authoritative backend.
10. Update any dependent external system the Skill actually controls - never silently leave an external system holding the stale value when the Skill could have updated it.
11. Validate per the checklist below.
12. Retire the old credential only once the above confirms it's safe to do so - don't delete/invalidate the old value as the very first step.

Primitives that typically need special care under this workflow: JWT signing keys/secrets, database passwords, encryption-at-rest keys, OAuth credentials, VAPID keys, webhook signing secrets. Not every secret can be rotated as a single atomic swap - say so explicitly per-primitive rather than treating rotation as uniformly safe.

## Step 11: JWT-specific pattern

Do not assume JWT always means a shared HMAC secret - inspect the actual signing configuration first.

- **HMAC JWT** (HS256/HS384/HS512 or equivalent): determine the configured algorithm, generate an appropriately-sized symmetric key with a CSPRNG, store only the primitive, never print it.
- **Asymmetric JWT** (RS*/ES*/EdDSA or equivalent): generate the correct key pair with suitable tooling per "Asymmetric key pair" above - private key to the secret backend, public key/JWK as clear configuration where the application actually needs it published. Never substitute a `JWT_SECRET`-shaped shared secret for an asymmetric setup that's actually in use.
- **An existing JWT secret/key of either kind**: any replacement is rotation (Step 10) - explicitly surface token-invalidation impact as part of obtaining rotation intent.

## Step 12: Secret-generation metadata (non-secret)

Record non-secret operational metadata about a generated primitive in the project's deployment documentation where useful, so a future Skill run (or a different operator) understands this value is Skill-managed rather than provider-issued:

```text
JWT_SECRET
type: generated symmetric signing secret
generator class: CSPRNG
managed by: SOPS
generated/rotated: 2026-10-21
```

Never record: the secret value itself, any reversible representation of it, a hash of it (unless there's a genuine, stated operational reason to), a seed, or private key material. Keep this metadata minimal - its only purpose is "this is Skill-managed," not a forensic record that creates its own fingerprinting risk.

## Step 13: Validation (after generation, before reporting success)

Without ever printing the generated value:

- the destination backend contains the primitive;
- the stored value is non-empty;
- the placeholder it replaced (if any) is actually gone;
- the value matches whatever format/length/entropy requirement Step 1's inspection established;
- for key pairs, the public/private components actually relate to each other correctly;
- every derived value depending on this primitive (per `agents/patterns/derived-deployment-values.md`) still resolves successfully;
- `kamal config` (or the project's equivalent resolution check) still succeeds;
- no plaintext copy of the value was left tracked anywhere (git status/diff checked structurally, not by printing contents);
- no secret value appears in generated/updated documentation;
- the value was not accidentally placed into `env.clear` (or any other non-secret config path);
- for a private component, it was not accidentally exposed as a public/`NEXT_PUBLIC_*`-style build variable.

Never use a full secret-dump command (`kamal secrets print`, an unscoped `sops -d`, a full 1Password item read) as the mechanism for any of this - validate structurally (presence, non-emptiness, placeholder-absence, derivation success) without ever surfacing the resolved value.

## Step 14: Audit trail / report format

Report generation results in this shape - status and method only, never the value:

```text
JWT_SECRET
status: generated
method: cryptographically secure symmetric key generation (<actual tool/API used>)
backend: SOPS + age
stored: yes
validation: passed
```

For a key pair:

```text
VAPID key pair
private component: generated -> SOPS
public component: generated -> clear configuration
pair validation: passed
```

Never produce a report resembling `JWT_SECRET=<value>` under any circumstance, including inside an error message, a "here's what would have been generated" preview, or a debug/verbose log shown to the user.

## Step 15: Explicit user requests

Support higher-level natural-language requests directly - the user should never need to specify the underlying mechanism themselves:

- "generate JWT_SECRET"
- "generate the database password"
- "create a new VAPID key pair"
- "generate all missing locally-generatable secrets" (see "`generate --missing` semantics" below)
- "rotate JWT_SECRET"

Translate each into: classify policy (Step 2) -> resolve current state (Step 4) -> generate via the correct category-specific mechanism (Step 3) -> persist per the selected backend (Step 7) -> validate (Step 13) -> report (Step 14). Reject (with a clear reason, never silently) any request that resolves to `PROVIDER_MANAGED` or `GENERATION_POLICY_UNKNOWN`, and any request to generate over an existing real value without explicit rotation intent.

## `generate --missing` semantics

When asked to generate "all missing" (or similar) locally-generatable secrets:

- Only generate primitives positively classified as `LOCAL_GENERATABLE`, `PROTOCOL_GENERATABLE`, `FRAMEWORK_GENERATABLE`, or `INFRASTRUCTURE_GENERATABLE` **and** currently missing or placeholder-only.
- Never generate a primitive classified `GENERATION_POLICY_UNKNOWN` - report it as unresolved instead, by name, with the reason it couldn't be classified.
- Never generate a `PROVIDER_MANAGED` primitive - report it as requiring the actual provider.
- Never overwrite any primitive that already holds a real (non-placeholder) value, even if its policy would otherwise allow generation - that would be an unrequested rotation.
- Report one line per primitive touched, using the Step 14 audit-trail format, plus one line per primitive explicitly skipped and why.

## The reusable `bin/secrets` implementation

This policy is not merely documentation - the Skill ships an actual, installable implementation at `templates/bin/secrets`, plus an example project policy file at `templates/config/secret-generation.yml`. Applying the Skill to a project installs/merges this script as the project's own `bin/secrets` (see "Applying this to a project" below) rather than the agent re-inventing the generation logic each time.

**The command generates secret material. The LLM does not.** When the user asks to generate a secret, the agent executes `bin/secrets generate <NAME>` and nothing else - it never computes, composes, or passes in a value itself (e.g. `bin/secrets generate JWT_SECRET "some-value"` is always wrong; `bin/secrets generate JWT_SECRET` is correct). The script invokes a real CSPRNG or protocol tool internally; the agent's only job is choosing which command to run and relaying its status output.

### Generator registry, not a generic fallback

**Do not implement "every `LOCAL_GENERATABLE` secret gets `openssl rand -base64 48`" as the architecture.** A generic CSPRNG call is one *registered generator type* among several - the project's own policy file explicitly selects it per secret, with its own entropy requirement, rather than the script defaulting every primitive to the same call. The dispatch shape is:

```text
policy (classification) -> generator (named function) -> generated primitive(s) -> backend adapter
```

`templates/bin/secrets` ships these generator functions, selected by the policy file's `generator` field, never inferred from the secret's name:

| Generator | Produces | Mechanism |
|---|---|---|
| `random_symmetric_key` | HMAC/signing/session secrets | CSPRNG (`openssl rand -base64`), entropy from the policy's `bytes` field, never a hardcoded size |
| `random_password` | Infrastructure-owned credentials (e.g. `POSTGRES_PASSWORD`) | CSPRNG at full entropy - never charset-restricted to simplify later URI encoding; percent-encoding stays the derived-value's job |
| `random_token` | Opaque bearer/service tokens | CSPRNG (`openssl rand -hex`), policy-defined entropy |
| `vapid_key_pair` | A VAPID-compatible EC key pair | Real EC (P-256) key generation via `openssl ecparam`/`openssl ec`, never two independent random strings |

A project with a different asymmetric need (SSH, an RS256/ES256 JWT key pair) gets its own protocol-specific generator function added to the installed copy, following the same registry shape - never bent into the symmetric generators above.

### Project policy file (`config/secret-generation.yml`)

**Secret-generation policy is commit-safe metadata; generated secret material belongs only in the configured secret backend.** The policy file records, per secret name, its policy and generator - never a value:

```yaml
JWT_SECRET:
  policy: local_generatable
  generator: random_symmetric_key
  bytes: 32  # sized from the project's actual HS256 usage, not a default

POSTGRES_PASSWORD:
  policy: infrastructure_generatable
  generator: random_password
  bytes: 24

GOOGLE_CLIENT_SECRET:
  policy: provider_managed
```

This file is generated/updated per project from actual inspection (Steps 1-2 above) when the Skill is applied - `templates/config/secret-generation.yml` is an illustrative template, never copied in verbatim as a project's real policy.

**A placeholder plus `local_generatable` (or another generatable policy) authorizes initial generation. A placeholder plus `existing_value_must_be_preserved` does not.** The latter policy exists specifically so a placeholder in a freshly migrated or partially-filled-in repository cannot be mistaken for permission to generate - e.g.:

```yaml
LEGACY_SIGNING_KEY:
  policy: existing_value_must_be_preserved  # production tokens depend on the current value, even though the backend may currently show a placeholder
```

### Supported commands

- `bin/secrets check` - validates required tools, backend access, policy-file syntax, that every secret has a known policy where required, that generators referenced by policy actually exist, policy/generator combination validity, derived-dependency resolution, and absence of any plaintext leak. Does not require a `provider_managed` secret to already be resolved.
- `bin/secrets edit` / `bin/secrets show` - the project's existing secret-inspection commands, unchanged by generation support.
- `bin/secrets policy` / `bin/secrets generate --list` - prints each secret's policy only, never a value, e.g.:
  ```text
  JWT_SECRET              LOCAL_GENERATABLE
  POSTGRES_PASSWORD       INFRASTRUCTURE_GENERATABLE
  VAPID_KEY_PAIR          PROTOCOL_GENERATABLE
  GOOGLE_CLIENT_SECRET    PROVIDER_MANAGED
  ```
- `bin/secrets generate <NAME>`:
  1. recognize `<NAME>` from the project's own policy file (not from the name alone);
  2. look up its generation policy;
  3. reject immediately (clear message, no generation attempted, non-zero exit) if the policy is `provider_managed`, `existing_value_must_be_preserved`, or has no recognized entry at all (`GENERATION_POLICY_UNKNOWN`);
  4. detect whether a real value already exists even under a generatable policy - if so, refuse (this is rotation, not generation) rather than proceeding;
  5. generate using the registered generator (Step 3/above);
  6. persist directly into the configured backend per Step 7's write strategy;
  7. validate per Step 13;
  8. print only status (Step 14's format) - never the value.
- `bin/secrets generate --missing`: apply the `generate --missing` semantics above, restricted to names the project's own policy file has positively classified - never attempt to generate an unrecognized name just because it appears somewhere in `config/deploy.yml`. A secret with no policy entry is reported skipped as unknown-policy, not silently ignored.
- `bin/secrets rotate <NAME>` - the only supported path for replacing an existing real value. Distinct from `generate`; requires interactive confirmation of rotation intent, refuses immediately for `provider_managed`/unknown policies, and never adds a casual force-overwrite flag to `generate` itself.

### Applying this to a project

When the Skill configures (or finds already configured) a secrets backend for a project, it also installs the reusable helper:

- **No existing `bin/secrets`:** install `templates/bin/secrets` as the project's `bin/secrets`, and generate `config/secret-generation.yml` from actual project analysis (Steps 1-2 above) rather than copying the template's illustrative entries.
- **An existing project `bin/secrets`:** never blindly overwrite it. Inspect its current commands/behavior first, preserve anything it already does correctly, and merge in only the generation capability it's missing - treat this the same as any other upgrade-in-place, not a replacement.

A Skill-managed secrets workflow's expected artifacts are now `bin/secrets`, `config/secret-generation.yml`, and the selected backend together - not the backend alone. Once installed, "generate JWT_SECRET" from the user means the agent runs `bin/secrets generate JWT_SECRET`, never a reimplementation of the generation logic inline.

## Regression coverage

See `tests/fixtures/secret-generation/EXPECTED.md` for the fixture cases this pattern must satisfy (missing HMAC JWT secret, existing JWT secret/rotation gating, provider-managed rejection, fresh PostgreSQL password plus derived-value integrity, VAPID key-pair classification, unknown-secret rejection, `--missing` selective generation, storage-failure handling, SOPS end-to-end, special-character password plus correct encoding, and asymmetric-signing key-pair generation).
