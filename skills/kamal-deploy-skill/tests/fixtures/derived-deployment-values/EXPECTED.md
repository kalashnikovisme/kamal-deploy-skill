# Fixture: Derived Deployment Values

Regression coverage for `agents/patterns/derived-deployment-values.md`. Each case is an independent scenario against SKILL.md Step 4b #6, after accessory ownership has already been decided as Kamal-managed (unless stated otherwise).

## Case A: Skill-managed PostgreSQL, known topology

Scenario: a Kamal `postgres` accessory with known `POSTGRES_USER`, `POSTGRES_DB`, accessory hostname/port, and a `POSTGRES_PASSWORD` to be stored.

Expected behavior:

- `POSTGRES_PASSWORD` is the only value stored as an independent secret primitive.
- `DATABASE_URL` is generated at secret-resolution time from that primitive plus topology - it does not appear in the secrets backend as its own entry.
- No `DATABASE_URL` placeholder (`TODO_FILL_IN` or similar) is ever written.
- The password component of the generated `DATABASE_URL` is correctly percent-encoded, not raw-concatenated.
- `DATABASE_URL` is placed under `env.secret` in `deploy.yml`, never `env.clear` with unexpanded shell-style interpolation.

## Case B: Skill-managed unauthenticated Redis

Scenario: a Kamal `redis` accessory with no password configured.

Expected behavior:

- `REDIS_URL` is generated automatically as derived clear configuration, directly from accessory topology.
- `REDIS_URL` does not appear in the secrets backend at all.
- No placeholder is written for it - there is nothing for the user to supply.

## Case C: Skill-managed authenticated Redis

Scenario: a Kamal `redis` accessory configured with a password.

Expected behavior:

- `REDIS_PASSWORD` is stored as the independent secret primitive.
- `REDIS_URL` is derived from `REDIS_PASSWORD` plus topology at resolution time, with the password percent-encoded.
- `REDIS_URL` is not independently stored in the secrets backend alongside `REDIS_PASSWORD`.

## Case D: external/provider-managed PostgreSQL

Scenario: the application's `DATABASE_URL` points at a provider-managed database (Supabase/Neon/RDS/etc.) that the Skill does not control the topology of.

Expected behavior:

- `DATABASE_URL` is stored as a single opaque secret primitive, exactly as supplied.
- The agent does not attempt to decompose it into a password plus reconstructed topology, and does not attempt to reconcile or normalize it against any Kamal accessory.
- If a Kamal `postgres` accessory is also being added for a different purpose, the agent does not silently redirect the application to the new accessory's derived URL - that would be an unconfirmed production data-source migration.

## Case E: newly created PostgreSQL accessory, no existing credential

Scenario: a brand-new Kamal-managed PostgreSQL accessory is being created for a project that has no existing database/password to preserve.

Expected behavior:

- The agent may generate `POSTGRES_PASSWORD` itself, using cryptographically secure randomness.
- The generated value is written directly into the selected secrets backend and is never printed in chat, a report, a log, or a diff.
- `DATABASE_URL` is derived automatically from the generated primitive - no manual input is required for either value.

## Case F: existing PostgreSQL password must be preserved

Scenario: the project already has a `POSTGRES_PASSWORD` (or equivalent) in use by production.

Expected behavior:

- The agent preserves the existing value and does not regenerate it.
- `DATABASE_URL` is still derived from it (rather than asking for `DATABASE_URL` separately).

## Case G: URI-special-character password

Scenario: a generated or existing database password contains characters such as `@`, `:`, `/`, `?`, `#`, or `%`.

Expected behavior:

- The derived `DATABASE_URL` remains syntactically valid - the password component is correctly percent-encoded before interpolation.
- The agent does not work around this by constraining future generated passwords to a weak/simple character set.

## Case H: duplicated existing `DATABASE_URL`

Scenario: the Skill controls the PostgreSQL accessory's topology, and the project already has both `POSTGRES_PASSWORD` and an independently-stored `DATABASE_URL` in the secrets backend, where `DATABASE_URL` is demonstrably built from that same password plus the accessory's topology.

Expected behavior:

- The agent identifies this as duplicated derived state (conceptually, a `DUPLICATED_DERIVED_SECRET` finding) rather than treating it as two unrelated secrets.
- The agent offers to normalize: keep `POSTGRES_PASSWORD`, remove the independently-stored `DATABASE_URL` entry, and move `DATABASE_URL` construction into `.kamal/secrets`.
- Normalizing does not change the value of `POSTGRES_PASSWORD` itself.

## Case I: derived internal service URL

Scenario: a unit needs to reach a Kamal accessory (or another value with a known stable hostname and port under this Skill's control) via a constructed URL with no secret material involved.

Expected behavior:

- The URL is derived automatically from the known hostname/port - the agent does not ask the user to supply it.
- No unnecessary secret-backend placeholder is created for it.

## Explicitly out of scope for this fixture

- The exact shell/encoding tool used inside `.kamal/secrets` to percent-encode credential components - `agents/patterns/derived-deployment-values.md` states the requirement, not a mandated specific tool.
- Accessory ownership decisions themselves (Kamal-managed vs. external) - covered by SKILL.md Step 4b #6 directly, assumed already resolved as a precondition for each case above.
