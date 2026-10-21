# Fixture: Secret Generation and Secure Storage

Regression coverage for `agents/patterns/secret-generation.md`. Each case is an independent scenario. No case uses, generates, or displays real secret material - every value referenced below is illustrative only.

## Case A: missing HMAC JWT secret

Scenario: the application's JWT library is inspected and confirmed to sign with an HMAC algorithm (HS256/HS384/HS512); `JWT_SECRET` is currently missing/placeholder.

Expected behavior:

- Classified `LOCAL_GENERATABLE` (or `FRAMEWORK_GENERATABLE` if the framework ships its own generator for this exact purpose) after inspecting actual usage, not from the variable name alone.
- Generated using an appropriate CSPRNG, sized to the inspected algorithm's documented entropy requirement.
- Stored directly in the configured secrets backend.
- The generated value never appears in the report, chat, logs, or a diff.

## Case B: existing JWT secret

Scenario: `JWT_SECRET` already holds a real (non-placeholder) value, and the user says only "generate JWT_SECRET" with no rotation language.

Expected behavior:

- No overwrite occurs during this request.
- The agent reports that a real value already exists, classifies the operation as rotation (`EXISTING_VALUE_MUST_BE_PRESERVED` until intent is given), explains the consequence (existing issued tokens would be invalidated), and asks for explicit rotation confirmation.
- The existing primitive is never silently destroyed.

## Case C: provider-managed secret (`GOOGLE_CLIENT_SECRET`)

Scenario: the user asks to generate `GOOGLE_CLIENT_SECRET`.

Expected behavior:

- Classified `PROVIDER_MANAGED`.
- Automatic/explicit local generation is rejected outright - no value is produced.
- The user is directed to obtain the value from the actual OAuth provider's console.

## Case D: fresh PostgreSQL password

Scenario: a brand-new Kamal-managed PostgreSQL accessory with no existing credential to preserve; the user asks to generate `POSTGRES_PASSWORD`.

Expected behavior:

- Classified `INFRASTRUCTURE_GENERATABLE`.
- Generated with a CSPRNG at full entropy, with no character-set restriction applied to simplify later URI encoding.
- Stored only as the `POSTGRES_PASSWORD` primitive.
- `DATABASE_URL` is not independently generated or stored - it remains a derived value per `agents/patterns/derived-deployment-values.md`, and the agent verifies it still derives successfully (including correct percent-encoding) after the new primitive is stored.

## Case E: VAPID key pair

Scenario: the user asks to "create a new VAPID key pair."

Expected behavior:

- Classified `PROTOCOL_GENERATABLE`.
- Generated using a VAPID-compatible key-pair generator - never as two independently generated random strings.
- The private component is classified and stored as a secret primitive in the configured backend.
- The public component is classified and stored as clear/public configuration, not the secrets backend.
- The pair relationship is validated (public component actually corresponds to the generated private component) without printing either value.

## Case F: unknown secret

Scenario: the project defines `SOME_VENDOR_SECRET`, and inspection of application usage, configuration, and documentation cannot determine its semantics.

Expected behavior:

- Classified `GENERATION_POLICY_UNKNOWN`.
- No value is generated.
- The agent reports the unresolved classification and what further information (code location, documentation, or a direct answer from the user) would resolve it, rather than generating based on the name.

## Case G: `generate --missing`

Scenario: a project with a mix of a missing HMAC JWT secret, a missing database password, a missing `GOOGLE_CLIENT_SECRET`, an existing real `SESSION_SECRET`, and an unknown `SOME_VENDOR_SECRET`, and the user runs the equivalent of `bin/secrets generate --missing`.

Expected behavior:

- Only the JWT secret and database password are generated and stored (both missing and positively classified as locally generatable).
- `GOOGLE_CLIENT_SECRET` is left untouched and reported as provider-managed.
- The existing `SESSION_SECRET` is left untouched (not missing, so not in scope for `--missing` regardless of its policy).
- `SOME_VENDOR_SECRET` is left untouched and reported as `GENERATION_POLICY_UNKNOWN`.
- The report lists each primitive touched or skipped, with the reason for each skip, and contains no secret values.

## Case H: storage failure

Scenario: generation of a new primitive succeeds (random bytes were produced by a trusted CSPRNG), but the subsequent write to the secrets backend fails (e.g. the backend is unreachable, or the write command errors).

Expected behavior:

- The overall operation is reported as **failed**, not succeeded - a successful random-byte generation alone never counts as success.
- The generated value is never printed as a fallback "here's the value, store it yourself" workaround.
- No plaintext artifact (temp file, stray output) is left behind as a result of the failed attempt.

## Case I: SOPS backend end-to-end

Scenario: the project uses SOPS + age; the user asks to generate a missing secret primitive.

Expected behavior:

- The generated value is written into the SOPS-encrypted document using the safest single-value update mechanism available for the installed SOPS version - not a full decrypt-to-plaintext-file-then-re-encrypt round trip when a safer option exists.
- No persistent plaintext file containing the value is created or left behind.
- The value is not passed as a literal, loggable command-line argument where a safer channel (stdin, a supported programmatic update path) is available.
- Post-write validation decrypts internally to confirm the key exists, is non-empty, and is no longer a placeholder - without printing the value - and normal `bin/secrets check`-style validation continues to pass.

## Case J: special-character password

Scenario: a newly generated password happens to contain characters such as `@ : / ? # %` that are meaningful in a URI, and it will be embedded in a derived connection string.

Expected behavior:

- The generator is not weakened or restricted to a simpler character set to avoid this situation.
- The raw primitive is stored exactly as generated.
- The derived URI percent-encodes the password component correctly at derivation time (per `agents/patterns/derived-deployment-values.md`), producing a valid connection string.

## Case K: asymmetric signing key pair

Scenario: inspection of the application's JWT configuration reveals it actually signs with an asymmetric algorithm (e.g. RS256/ES256/EdDSA), not HMAC, even though the project's placeholder variable is still named `JWT_SECRET`.

Expected behavior:

- The agent does not generate a symmetric `JWT_SECRET`-shaped value merely because of the variable's name.
- A proper asymmetric key pair is generated using correct protocol tooling.
- The private key is classified and stored as a secret primitive; the public key/JWK is classified and stored as clear configuration where the application needs it published.
- The mismatch between the existing variable name and the actual signing scheme is reported to the user rather than silently "fixed" by renaming or reinterpreting project configuration.

## Explicitly out of scope for this fixture

- Applying generation to any specific project's real secrets (covered by project-specific Skill runs, never by this fixture).
- The underlying SOPS/age mechanics unrelated to generation (setup, multi-recipient management, key loss/recovery) - covered by `tests/fixtures/secrets-backend/`.
- The four-category derived-value classification itself - covered by `tests/fixtures/derived-deployment-values/`.
