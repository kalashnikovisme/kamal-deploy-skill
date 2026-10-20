# Large Build Artifacts / Large Runtime Assets

Applies when a unit's image ends up large because of something baked in at build time — a ML model file, a large static dataset, bundled media, or any other asset well beyond typical source-code size (rough guideline: anything that noticeably slows `docker build`/`docker push` or pushes the image into the hundreds of MB to multi-GB range).

This is a generalization: do not create a dedicated pattern for "large ML model" or any other specific asset type. The reusable concern is the same regardless of what the large asset actually is.

## Detection

Watch for, while inspecting the Dockerfile (existing or about to be written) and build scripts:

- A `RUN` step that downloads a file during the build (a model weights file, a dataset, a large binary) and the result is `COPY`'d or left in a layer that ships in the final image
- A build script invoked from the Dockerfile (e.g. `scripts/download-model.sh`) whose purpose is fetching something large
- An existing image that is unusually large for its stack when inspected with `docker images` after a build-validation run

Ask the user to confirm roughly how large the asset is and whether it changes often (a model that's updated every release behaves differently than one that's effectively static).

## Deployment decision

There are two supportable approaches — pick based on how often the asset changes and whether the hosting provider's registry/bandwidth can absorb a large image:

1. **Bake into the image (default for static or rarely-changing assets).** Simplest, no extra moving parts, but every deploy re-pushes/re-pulls the full image even if only application code changed. Mitigate with Docker layer ordering: put the large-asset-fetching `RUN` step **before** `COPY`-ing application source, so code-only changes don't invalidate the asset layer's cache and don't force a re-download during build (they still require a re-push/re-pull of the full image on the server, since Kamal transfers images as a whole — this is a Kamal/Docker registry mechanic, not something layer ordering fixes).
2. **Fetch at container start, persisted to a Kamal volume.** Add a `volumes` entry in `deploy.yml` mapping a path to persistent storage, and have the container's startup command check whether the asset already exists at that path before fetching it. This keeps the image itself small and the asset downloads once per server (not once per deploy), at the cost of a slower first boot and an extra failure mode (the fetch itself can fail at startup — make sure it fails loudly, not silently, per `agents/patterns/database-migrations.md`'s fail-fast principle applied here to asset fetching).

Default to option 1 unless the user indicates the asset is large enough, or changes rarely enough relative to deploys, that image bloat is a real operational cost — don't introduce the extra moving parts of option 2 speculatively.

## Boot-behavior implications

A large image or a startup-time fetch both push out how long a container takes to become healthy. Set `readiness_delay` generously in `deploy.yml` to match:

```yaml
boot:
  readiness_delay: 10   # seconds kamal-proxy waits before starting healthchecks
```

Increase further if option 2 (fetch-at-start) is used and the asset is large enough that the fetch itself takes more than a few seconds.

## Validation

- The build-validation step in SKILL.md Step 5 will complete even with a large asset, but note to the user that build/push time will be noticeably longer than a typical deploy of that stack — this is expected, not a sign of a broken Dockerfile.
- For option 2, after first deploy, confirm the asset only downloads once across repeated deploys (check container logs for the fetch step on a second deploy) rather than assuming the volume persisted correctly.

## Caveats

- Registries with per-layer or total-image size limits (some free-tier registries) may reject a sufficiently large image — if the user is on such a registry, option 2 avoids the problem entirely.
- A remote builder (see `references/deploy-yml-reference.md`) can help when the local machine is too slow/low-bandwidth to build and push a large image, but does not reduce the image's actual size.
