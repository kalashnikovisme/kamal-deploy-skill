# Additional Runtime Dependencies

Applies when a unit's runtime needs more than its primary language's own ecosystem — most commonly a secondary language runtime invoked as a subprocess (e.g. a Node service that shells out to a Python script), or native system libraries/CLI tools that aren't pulled in by the primary package manager.

This is a generalization: do not create a dedicated pattern for any specific combination (e.g. "Node + Python"). The reusable concern is always the same regardless of which two ecosystems are involved.

## Detection

While reading the primary stack's manifest and source (already happening in the stack recipe), watch for:

- A subprocess call to an interpreter/binary not part of the primary language (`child_process.spawn('python3', ...)`, `exec("ffmpeg ...")`, `os/exec` shelling out to a CLI tool, etc.)
- A `requirements.txt`/`Pipfile`/`go.mod`-style manifest for a *second* language sitting next to the primary one's manifest
- References in the Dockerfile (existing or about to be written) to `apt-get install`/`apk add`/`pip install` packages that aren't part of the primary runtime's own base image

If found, ask the user to confirm the dependency is required at **runtime** (not just in a dev/test script) before adding anything to the production Dockerfile — a dependency only used by a test script or a dev-only tool does not belong in the runtime image.

## Deployment decision

1. The runtime stage of the Dockerfile must install the secondary runtime/toolchain explicitly — it will not appear by inheriting from the primary language's base image.
2. Prefer installing the secondary runtime in the **same stage** that will run (not just build) the application, since `child_process`/`exec` calls need the binary present at container-run time, not only at build time.
3. If the secondary runtime has its own package manager (pip, apt), pin versions the same way the primary manifest is pinned, and run its install non-interactively with cache cleanup (`--no-cache-dir` for pip, `rm -rf /var/lib/apt/lists/*` after `apt-get install`) to avoid bloating the image — see `agents/patterns/large-build-artifacts.md` if the secondary runtime pulls in a large model/asset on top of the interpreter itself.
4. Health checks and startup diagnostics (SKILL.md Step 5) should account for the secondary runtime: if the subprocess fails to start because its interpreter or a required package is missing, that should surface as a clear startup failure, not a silent fallback.

## Example Dockerfile fragment (illustrative, not stack-specific)

```dockerfile
FROM node:22-bookworm-slim AS runner
# Primary runtime's own install steps...

# Secondary runtime required at process run time, not just build time:
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip \
    && pip3 install --no-cache-dir -r requirements.txt \
    && rm -rf /var/lib/apt/lists/*
```

## Validation

- `docker build` (Step 4's build-validation step) will catch a missing install command if the Dockerfile tries to `COPY` a secondary-language manifest that was never installed.
- It will **not** catch a missing runtime binary that's only invoked by application code at request time — note this limitation to the user and recommend a smoke test (hit the endpoint that triggers the subprocess) after first deploy.

## Caveats

- Running as non-root still applies: if the secondary runtime needs to write temp files (e.g. a Python script writing to `/tmp`), ensure the non-root user has write access to the paths it needs, rather than reverting to root to work around a permissions error.
- Don't let a secondary runtime's presence change the primary stack recipe's own Dockerfile structure beyond adding the install step and any env vars the subprocess needs — this pattern adds to a recipe's Dockerfile, it does not replace it.
