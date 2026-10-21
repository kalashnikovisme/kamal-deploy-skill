# Derived Deployment Values

Runs during SKILL.md Step 4b/Step 5, after the secrets backend is selected (`agents/patterns/secrets-backend.md`) and after accessory ownership is decided (SKILL.md Step 4b #6), before any secret placeholder or connection string is written.

**Core invariant:** never ask the user to provide a value the deployment configuration can deterministically derive, and never store a duplicated derived representation of a secret already stored as a primitive.

## The four value categories

Every environment variable the application needs falls into exactly one of these. Classify before writing anything:

| Category | Definition | Where it lives | Example |
|---|---|---|---|
| **1. Secret primitive** | Cannot be derived; must be supplied, generated, or preserved | Secrets backend (SOPS/1Password/etc.) | `POSTGRES_PASSWORD`, `JWT_SECRET`, a third-party API key |
| **2. Derived secret value** | Contains secret material, but is a deterministic function of one or more primitives plus known topology | Constructed at secret-resolution time; not stored as its own backend entry unless there's a concrete reason | `DATABASE_URL` built from `POSTGRES_PASSWORD` + accessory host/port/db/user |
| **3. Derived clear configuration** | Fully derivable from non-secret Kamal topology; contains no secret material | `config/deploy.yml`'s `env.clear`, generated directly | `REDIS_URL` for an unauthenticated Redis accessory |
| **4. User-supplied clear/public configuration** | Not secret, but not safely inferable | Asked from the user, stored as clear config | A public third-party identifier, an external callback URL |

Do not confuse category 3 with category 4: "derivable from topology this Skill controls" and "not inferable at all" are opposite ends, not the same bucket.

## Dependency analysis (run before writing any placeholder)

For every environment variable the application requires, ask in order:

1. Is this a genuine independent secret with no derivation path? -> category 1.
2. Is it fully derivable from clear Kamal/accessory configuration alone, with no secret material? -> category 3.
3. Is it derivable from clear configuration *plus* one or more category-1 primitives? -> category 2.
4. Is it public/clear configuration that still needs the user's input? -> category 4.

Only category 1 and category 4 require asking the user for anything. Categories 2 and 3 are generated automatically. **Derivation must be proven** from actual application usage, the project's own connection-string/driver conventions, Kamal's verified accessory-naming rule, and documented service semantics - never invented merely because a variable name looks familiar (e.g. don't assume every `*_URL` is derivable just because `DATABASE_URL` sometimes is). If deriving a given value is ambiguous, ask the user rather than guessing.

## Source of truth, by layer

- **Kamal topology/configuration** (accessory `service_name`, ports, server assignment) is the source of truth for hosts/ports/service names. Use the Skill's existing verified accessory-hostname rule (`<service>-<accessory>`, from SKILL.md Step 4b #6/`examples/with-postgres.md`) - never invent a Docker hostname independently of it.
- **The secrets backend** is the source of truth for primitive credential values.
- **Derived environment** (category 2 and 3 values) is generated from those two sources at resolution time - it is not a third independent store. Never duplicate a topology value inside the secrets backend, and never duplicate a primitive credential inside a separately-stored full connection string.

## PostgreSQL: `DATABASE_URL`

When PostgreSQL is a Kamal-managed accessory (ownership decided per SKILL.md Step 4b #6), inspect:

- the accessory's stable `service_name` (`<service>-postgres` by default - verify against the actual `service:`/accessory name in use, don't hardcode "postgres" if the accessory block uses a different key);
- its port (`5432` unless configured otherwise);
- `POSTGRES_USER`, `POSTGRES_DB`;
- `POSTGRES_PASSWORD` (or whatever the accessory's password env var is actually named);
- the application's actual expected connection-string format - inspect the project (ORM/driver config, existing `.env.example`, framework conventions) rather than assuming one universal PostgreSQL URL shape. Preserve any framework/driver-specific query parameters (e.g. `?sslmode=require`, `?schema=public`) the project already requires.

`DATABASE_URL` is then a **category 2** value: derive it at secret-resolution time from `POSTGRES_PASSWORD` plus the topology above. The user populates `POSTGRES_PASSWORD` only - never both `POSTGRES_PASSWORD` and `DATABASE_URL` as independently-entered values.

`config/deploy.yml` lists it under `env.secret` (it contains secret material, so it cannot live in `env.clear`):

```yaml
env:
  secret:
    - POSTGRES_PASSWORD
    - DATABASE_URL
```

`.kamal/secrets` resolves the primitive from the backend and derives the composite value:

```sh
POSTGRES_PASSWORD=$(sops --extract '["postgres_password"]' -d config/secrets.sops.yaml)
DATABASE_URL="postgresql://app:$(urlencode "$POSTGRES_PASSWORD")@myapp-postgres:5432/myapp_production"
```

This is illustrative of the shape, not literal syntax to copy - the backend lookup line follows whichever backend was selected (see "Backend-specific storage" below), and the URI-encoding helper must actually exist/be implemented (see next section). Do not write `DATABASE_URL` into `env.clear` with shell-style `${POSTGRES_PASSWORD}` interpolation - `deploy.yml` is parsed as YAML/ERB, not shell, so a literal `${POSTGRES_PASSWORD}` string would be passed to the container unexpanded. If a value contains secret material, it belongs in `env.secret`, resolved by `.kamal/secrets`, never assembled via unexpanded shell syntax sitting in committed YAML.

## URI encoding (mandatory, not optional)

Never concatenate a raw password into a connection string. Percent-encode the username/password components per the connection-string format's own encoding rules before interpolating them, so characters including `@ : / ? # %` can't break the URL or get misparsed as a delimiter.

- Do not solve this by restricting generated passwords to a weak/simple character set - fix the encoding, not the password.
- Implement (or call) an actual encoding routine appropriate to the shell/language available in `.kamal/secrets` (e.g. a small `jq -rn --arg v "$PASSWORD" '$v|@uri'` or an equivalent percent-encoding call, or a short helper script if the project already has a scripting runtime available) - do not hand-roll a partial character-substitution that only covers a few symbols.
- Verify the final constructed URL is syntactically valid for the target driver/format as part of validation (see below), not just "looks right."

## Redis: `REDIS_URL`

When Redis is a Kamal-managed accessory, first determine whether authentication is configured - this changes the category:

- **Unauthenticated accessory**: `REDIS_URL` is **category 3** - fully derivable from clear topology (`redis://<service>-redis:6379` or `redis://<service>-redis:6379/<db>` if a specific database number is used), contains no secret material. Generate it directly into `env.clear`. It must never become a secrets-backend entry and must never be left as a placeholder like `TODO_FILL_IN` - there is nothing for the user to supply.
- **Authenticated accessory**: only `REDIS_PASSWORD` (or the accessory's actual password variable) is a **category 1** primitive, stored in the backend. `REDIS_URL` is then **category 2**, derived from scheme, hostname, port, optional database number, optional username, and the password - URI-encoded per the rule above - and listed under `env.secret`, not `env.clear`. Do not store both `REDIS_PASSWORD` and an independently-entered `REDIS_URL`.

## Generalizing beyond Postgres/Redis

Apply the same four-category analysis to any other deterministic connection/configuration value the project needs - other database DSNs, internal accessory URLs, internal service URLs, authenticated internal endpoints, storage endpoints assembled from known topology plus a credential. The method generalizes; the examples above (PostgreSQL, Redis) are not an exhaustive hardcoded list. Do not derive a value just because its name resembles a known pattern - derivation must be justified by the actual application/driver/service semantics for that specific value, and ambiguity is resolved by asking the user, not by guessing.

## External / provider-managed databases and services

**This exception is critical and inverts the default.** If `DATABASE_URL` (or any similar connection string) points at a provider-managed service the Skill does not control the topology of - Supabase, Neon, RDS, Railway, another managed PostgreSQL/Redis/etc. - then the full connection string is itself the primitive credential the provider supplied. In that case:

- Store it as a **category 1 secret primitive**, in full, exactly as given.
- Do not attempt to decompose it into a password plus reconstructed topology, and do not attempt to reconstruct or "normalize" it against a Kamal accessory - the Skill has no authority over that topology.
- The derivation rule in this pattern applies only when the Skill has enough authoritative information (because it controls the accessory) to derive the value safely - not merely because the variable name matches one the Skill knows how to derive in the Kamal-managed case.

### Existing production migrations

Never replace an existing external/production connection string with a newly derived Kamal-accessory URL merely because a new accessory now exists in `deploy.yml`. This follows the Skill's existing stateful-migration rules (see `agents/patterns/migrate-from-vercel.md` Phase 4a and SKILL.md Step 4b #6): switching the application to a derived accessory URL is a data/topology migration decision that needs the user's explicit confirmation, not an automatic side effect of adding an accessory block.

## Generating new secret primitives

When a secret primitive belongs entirely to infrastructure the Skill is newly creating and fully owns both sides of - a brand-new PostgreSQL accessory's password, a brand-new authenticated Redis accessory's password, an internal service token created specifically for this deployment - the Skill MAY generate it automatically instead of leaving a placeholder.

The full generation policy - the safe/unsafe conditions for generating automatically, CSPRNG/tooling selection, asymmetric key pairs, provider-managed rejection, rotation, backend-specific write strategies, and leak-prevention rules - lives in `agents/patterns/secret-generation.md`. Load it before generating any primitive. In short: generation and secure persistence are one atomic operation, the model never invents secret material itself, an existing real value is never silently overwritten, and third-party/provider-managed credentials are never generated locally. A generated primitive is still stored as a plain category-1 primitive under this file's four-category model - generation never changes which category a value belongs to, and a derived value (category 2/3) is never independently generated.

## Placeholder policy

Before writing `TODO_FILL_IN` (or an equivalent placeholder) for any value, the Skill must first determine, in this order, whether the value is actually:

1. derivable from topology (category 3) - generate it, no placeholder;
2. derivable from topology plus another secret (category 2) - generate it at resolution time, no placeholder;
3. a primitive the Skill owns and can safely generate (see above) - generate it, no placeholder.

Only a value that genuinely requires external/user-supplied information (a real category 1 the Skill can't generate, or category 4) may remain as an explicit unresolved placeholder that the user is asked to fill in.

**Bad** (for a brand-new Skill-managed PostgreSQL + unauthenticated Redis):

```text
POSTGRES_PASSWORD=TODO_FILL_IN
DATABASE_URL=TODO_FILL_IN
REDIS_URL=TODO_FILL_IN
```

**Correct:**

```text
POSTGRES_PASSWORD=<securely generated primitive, stored in backend>
DATABASE_URL=<derived automatically at resolution time>
REDIS_URL=<generated directly as clear configuration>
```

No manual input is required for any of these three in this scenario.

## Backend-specific storage

This rule applies identically across every supported secrets backend - it is not SOPS-specific.

- **SOPS + age** (`agents/patterns/secrets-sops-age.md`): `config/secrets.sops.yaml` holds only genuine primitives (`POSTGRES_PASSWORD`, `JWT_SECRET`, etc.), never a duplicated `DATABASE_URL` containing the same password, and never a `REDIS_URL` that holds no secret material at all. `.kamal/secrets` resolves the primitive via `sops --extract` and derives the composite value in the same script, with no plaintext derived value ever written to disk.
- **1Password**: store `POSTGRES_PASSWORD` as the vault item; do not also store an independent `DATABASE_URL` item when it is deterministic from that password plus topology. Derive it in `.kamal/secrets` after `kamal secrets fetch`/`extract` resolves the primitive.
- **Any other backend**: same principle - the backend holds the minimal set of independent primitives needed to reconstruct the full deployment environment; everything derivable is generated, not independently stored.

## Drift and duplication detection (validation)

Treat an independently-stored derived value as a defect to flag and offer to fix, not a silent acceptable state:

- If both a secret primitive (e.g. `POSTGRES_PASSWORD`) and an independently-stored composite (e.g. `DATABASE_URL`) exist in the backend, and the composite is demonstrably derivable from that primitive plus Kamal-controlled topology, flag it as `DUPLICATED_DERIVED_SECRET` and offer to normalize: keep the primitive, remove the independent composite entry, move composite construction into `.kamal/secrets`.
- Apply the same check for `REDIS_PASSWORD` + an independently stored `REDIS_URL`.
- **Do not flag this for an externally-managed database/service** where the Skill does not control the topology (see "External / provider-managed databases and services" above) - an opaque provider-supplied `DATABASE_URL` is not a duplication defect, it's the actual primitive.
- Normalizing must never change the underlying primitive credential's value - only remove the redundant independently-stored derived copy.

## Validation checklist (derived values)

For every category 2/3 derived value, verify without printing the resolved value itself:

- All of its declared dependencies (primitives + topology) actually exist and resolve.
- Every required primitive is non-empty.
- No unresolved placeholder remains where a derivation or generation should have applied instead.
- The derivation/construction step itself succeeds (no error from the resolution script).
- The constructed URI is syntactically valid for its format.
- Credential components are correctly percent-encoded.
- The hostname used matches the actual Kamal accessory topology (not a guessed or stale name).
- The port matches the actual accessory configuration.
- The database name/user match the accessory's actual configuration.
- For Redis specifically, the derived value's authentication form (with/without password) matches whether the accessory actually has authentication configured - don't derive an authenticated-style URL for an unauthenticated accessory or vice versa.
- No independently-stored duplicate of this derived value exists elsewhere in the backend (see drift detection above).

Never use a full secret-dump command (`kamal secrets print`, an unscoped `sops -d`) as the mechanism for this validation - validate structurally (dependency presence, derivation success, syntactic validity) without surfacing the resolved value.

## `bin/secrets check` output (when SOPS is in use)

Extend the check to understand derived values rather than treating every `config/deploy.yml` secret name as requiring its own backend entry:

```text
POSTGRES_PASSWORD  OK (secret primitive)
DATABASE_URL       OK (derived: POSTGRES_PASSWORD + PostgreSQL accessory topology)
REDIS_URL          OK (derived clear configuration: Redis accessory topology)
JWT_SECRET         MISSING (external value required)
```

A derived value must not fail merely because it has no entry of its own in `config/secrets.sops.yaml` - its *dependencies* are what gets checked (the primitive it depends on, and the topology it depends on), never the derived name treated as a standalone required backend key. Never print resolved values, including derived ones.

## Secret inventory report format

Report the resolved set of deployment values grouped by category, not as one flat list, so the operator can see at a glance what they actually need to supply:

```text
SECRET PRIMITIVES
POSTGRES_PASSWORD → generated/stored
JWT_SECRET → user/provider required

DERIVED SECRET VALUES
DATABASE_URL → POSTGRES_PASSWORD + PostgreSQL accessory topology

DERIVED CLEAR CONFIGURATION
REDIS_URL → Redis accessory topology

PUBLIC/CLEAR USER CONFIGURATION
...
```

Never include a real resolved value in this report - only the category, the name, and (for derived values) what it's derived from.
