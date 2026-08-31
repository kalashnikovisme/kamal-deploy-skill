# Wrapper Command Reference

This reference documents the operational wrappers used by the Arie repo and similar Kamal-enabled projects that ship a `bin/` layer. Prefer these wrapper names in docs and operator handoffs instead of raw `kamal` commands when a matching wrapper exists.

## Routing Model

- `bin/_bws_env` selects the Bitwarden project from `-d/--destination`
- Staging and production use different Bitwarden project IDs
- All wrapper commands execute through `bws run --project-id ... --`

## Main App Wrappers

| Wrapper | Purpose |
|---------|---------|
| `bin/setup` | Provision and deploy staging; cannot target production |
| `bin/deploy` | Deploy the main app to the selected destination |
| `bin/status` | Show the current deployment state |
| `bin/logs` | View app logs |
| `bin/console` | Open the app console |
| `bin/app` | Run app-level Kamal operations such as `restart`, `details`, `start`, and `stop` |
| `bin/accessory` | Run accessory-level Kamal operations |
| `bin/remove` | Remove the main app deployment |
| `bin/lock` | Inspect, acquire, or release the deploy lock |
| `bin/boot` | Pass through to the underlying Kamal command layer |

## Staging Secrets

When targeting staging, these wrappers source `.kamal/staging-secrets` before execution:

- `bin/setup`
- `bin/deploy`
- `bin/console`
- `bin/app`
- `bin/accessory`

That file is generated and managed by the wrapper flow. It exports:

- `LOCAL_JWT_SECRET`
- `LOCAL_PGRST_JWT_SECRET`
- `LOCAL_SUPABASE_SERVICE_ROLE_KEY`
- `LOCAL_SUPABASE_SERVICE_KEY`

## Setup and Restore

| Wrapper | Purpose |
|---------|---------|
| `bin/setup --snapshot <file>` | Provision, deploy, and restore snapshot data into staging |
| `bin/setup --snapshot <file> --migration <path>` | Provision, deploy, restore, and rebuild the schema through the specified migration slice first |
| `bin/restore --snapshot <file>` | Restore snapshot data into an already-existing destination |
| `bin/restore --migration <path>` | Re-run restore using previously uploaded snapshot chunks and rebuild through the specified migration slice |
| `bin/dump` | Produce a destination snapshot for later restore |

## Admin Wrappers

These operate from `admin/`, strip destination flags before invoking Kamal, and still run through `bws run`:

- `bin/deploy-admin`
- `bin/setup-admin`
- `bin/console-admin`
- `bin/logs-admin`
- `bin/boot-admin`

## Auxiliary Wrappers

| Wrapper | Purpose |
|---------|---------|
| `bin/psql` | Open `psql` against the selected destination |
| `bin/authorize` | Mint a short-lived authorize link for a user email |
| `bin/regsys-build` | Build and push `recsys/Dockerfile.regsys` and `recsys/Dockerfile.jobs` |
| `bin/regsys-registry-boot` | Boot the local registry container used by the RegSys image flow |
| `bin/run-data-migration` | Run an explicit staging-only data migration script through the app console |

## Usage Guidance

- Prefer wrapper names in README instructions, runbooks, and skill-generated documentation
- Mention raw Kamal only when explaining what the wrapper ultimately invokes
- Use destination-based examples such as `bin/deploy -d staging` or `bin/setup --snapshot <file>`
