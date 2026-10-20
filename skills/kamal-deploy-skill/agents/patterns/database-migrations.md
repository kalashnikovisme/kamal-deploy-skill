# Database Migrations

Cross-cutting tradeoffs for running schema migrations as part of a Kamal deploy. Stack-specific recipes hold the exact commands (`npx prisma migrate deploy`, `php artisan migrate --force`, `dotnet ef database update`, etc.) — this file holds the mechanics and tradeoffs that are the same regardless of which migration tool is in use. A recipe's migration section should point here for the reasoning and keep only its own stack-specific command.

## The two supportable approaches

1. **Pre-deploy hook** (`.kamal/hooks/pre-deploy`, run via `kamal app exec --reuse "<migration command>"`). Runs once, before the new containers start serving traffic. This is the **default recommendation** for most stacks, because it keeps "did the migration succeed" as a distinct, visible step separate from "did the app boot" — a failed migration stops the deploy before any new container takes traffic, and the failure is attributable to the migration step specifically rather than buried in general boot logs.
2. **Inline at container boot** (the migration command is part of the image's `CMD`/entrypoint, e.g. `sh -c "migrate && start-app"`). Simpler — no separate hook file — but runs on **every container boot**, not once per deploy. For a single-replica deploy this is usually harmless (one container, one boot, one migration run). It becomes a correctness concern once there's more than one replica/host: if Kamal boots multiple containers for the same service, the migration command runs once per container, concurrently. Most migration tools are designed to be safe under concurrent execution (they take a lock or check "already applied" state), but this is a property of the specific migration tool, not something the Skill should assume blindly.

## Deployment decision

- **Single replica / single host**: either approach is fine. Prefer the pre-deploy hook when the recipe already lists it as the convention for that stack (keeps behavior consistent across projects); inline-at-boot is acceptable if that's what an existing Dockerfile already does and there's no reason to change it.
- **Multiple replicas / multiple hosts for the same service**: prefer the pre-deploy hook. Running migrations once, before any replica starts, avoids relying on the migration tool's own concurrency safety. If an existing Dockerfile already runs migrations inline and the project is multi-replica, flag this to the user as a reliability concern rather than silently leaving it — but don't rewrite an existing working Dockerfile without the user's go-ahead, since the migration tool in use may in fact handle concurrent runs safely.
- **Multi-service repos** (`agents/patterns/multi-service-repo.md`): each unit's migrations are its own concern. Don't run one unit's migration hook from another unit's deploy — if two units share a database, pick one unit as the migration owner (typically whichever unit owns the schema/ORM models) and document that choice.

## Fail-fast expectation

A migration failure (in either approach) must stop the deploy / stop the container from becoming healthy — never swallow the error and continue with a stale schema. Pre-deploy hooks already behave this way (`set -e` in the hook script, as the recipes already template). For inline-at-boot, ensure the migration command is chained with `&&`, not `;` or `||`, so a failed migration prevents the app process from starting at all.

## Validation

- After adding or changing migration handling, confirm the chosen approach actually blocks on failure: temporarily point the migration command at an invalid target (or review the hook/CMD chaining) and confirm the deploy halts rather than proceeding with a half-migrated database. This is a one-time sanity check during setup, not something to automate into the Skill's build-validation step.
- `kamal app exec --reuse` (used by the pre-deploy hook) runs inside an already-built, not-yet-started container image — confirm the migration tool's CLI is present in the **runtime** image, not only a build stage, or the hook will fail with a "command not found" error unrelated to the migration itself.
