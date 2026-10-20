# Multi-Service Repo: Running Several Kamal-Managed Units From One Repository

This pattern applies only when `agents/patterns/deployable-units.md` step 5 produced a **Kamal-managed subset with more than one unit**. If only one unit was selected, ignore this file entirely — use the plain single-app flow (`config/deploy.yml`, no `-c` flag, no suffixed paths).

## Mechanism (verified against Kamal's source, not just its public docs)

Kamal's CLI exposes a global option, independent of destinations:

```
-c, --config-file   Path to config file   (default: "config/deploy.yml")
```

This is distinct from `-d`/`--destination`, which selects a `config/deploy.<destination>.yml` override **merged into** whatever `--config-file` points at. The two compose: `-c config/deploy.api.yml -d staging` reads `config/deploy.api.yml` merged with `config/deploy.api.staging.yml`.

Each `deploy.yml` also accepts its own `secrets_path` and `hooks_path` keys (defaulting to `.kamal/secrets` and `.kamal/hooks`, resolved relative to the current working directory — **not** relative to `--config-file`'s location). Because the defaults are shared repo-wide regardless of which `-c` file is active, **every additional Kamal-managed unit beyond the first must set its own `secrets_path`/`hooks_path`**, or two units' secrets/hooks will collide on disk.

Source: `lib/kamal/cli/base.rb` and `lib/kamal/configuration.rb` in basecamp/kamal (verified during Phase 4 of the `learn_from_project` workflow; the public docs site documents destinations but not `-c`/`--config-file` as of this check — re-verify if Kamal's CLI changes).

## Layout

For each Kamal-managed unit, generate:

```
<unit-root>/Dockerfile
config/deploy.<unit>.yml          # NOT config/deploy.yml — avoids the first unit silently becoming "the default"
.kamal/secrets-<unit>
.kamal/hooks-<unit>/               # only if the unit needs pre-deploy/post-deploy hooks
```

In `config/deploy.<unit>.yml`:

```yaml
service: <unit>                    # must be unique across units sharing a server
image: <REGISTRY_USER>/<unit>

secrets_path: .kamal/secrets-<unit>
hooks_path: .kamal/hooks-<unit>    # omit if the unit has no hooks

servers:
  web:
    hosts:
      - <SERVER_IP>
    proxy:
      ssl: true
      host: <UNIT_DOMAIN_OR_SUBDOMAIN>
      app_port: <UNIT_PORT>
# ...the rest of the file follows the unit's own stack recipe exactly as it would for a single-app repo.
```

`builder.context` defaults to the directory containing the config file's build context, which for a unit living at `<unit-root>` inside the repo means the Dockerfile and build context must be generated **inside `<unit-root>`**, same as a single-app repo rooted there — do not generate a Dockerfile at the repo root for a sub-unit.

## bin/ wrappers in a multi-unit repo

If SKILL.md Step 5.5 creates wrapper scripts, each unit gets its own wrapper set or a single wrapper set gains a required unit argument — pick one explicitly with the user rather than guessing:

- **Per-unit wrappers** (`bin/deploy-api`, `bin/deploy-worker`): each wrapper hardcodes its own `-c config/deploy.<unit>.yml` and still forwards every other flag (`-q`/`--quiet` etc.) via `"$@"`, per the wrapper rules in SKILL.md Step 5.5.
- **Single wrapper with a required first positional argument** (`bin/deploy api ...`): the wrapper maps the first argument to the right `-c` value, then forwards the rest of `"$@"` unmodified. Only do this if the user explicitly prefers one entrypoint; it adds a parsing step that per-unit wrappers avoid.

Either way, the wrapper-forwarding contract in SKILL.md Step 5.5 is non-negotiable: once the `-c` value (and any destination) is resolved, every remaining argument — `-q`/`--quiet` included — must still reach `kamal` verbatim.

## Documenting the Kamal-managed subset (SKILL.md Step 6)

When more than one Deployable Unit was discovered (regardless of how many ended up Kamal-managed), the deployment documentation must include a short table listing **every discovered unit**, not just the Kamal-managed ones, so the setup is legible as a whole:

```markdown
## Deployable Units

| Unit | Path | Managed by Kamal | Notes |
|---|---|---|---|
| api | `api/` | Yes — `config/deploy.api.yml` | |
| worker | `worker/` | Yes — `config/deploy.worker.yml` | shares server with `api` |
| frontend | `frontend/` | No | already deployed on Vercel; untouched by this setup |
```

This table is the representation of "a Kamal-managed subset" — it must always show the units that were *not* selected, marked as not managed here, rather than omitting them and implying they don't exist.

## Shared accessories (Postgres/Redis) across units

If two Kamal-managed units in the same repo both need the same accessory (e.g. both `api` and `worker` need Postgres), do not define the accessory twice. Define it once, in whichever unit's `deploy.yml` is deployed first / considered primary, and point the other unit's `secret`/`clear` env at the same connection details. Note this explicitly in the documentation table above so it's clear which unit "owns" the accessory's lifecycle (`kamal accessory boot/reboot/remove` should be run against that unit's config file only).

## When NOT to use this pattern

- Exactly one Kamal-managed unit, regardless of how many total Deployable Units were discovered — use the plain single-app flow.
- Staging vs. production variants of the *same* unit — that's `-d`/`--destination` (see `examples/multi-destination.md`), not this pattern.
