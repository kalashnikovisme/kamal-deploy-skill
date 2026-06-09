# Unknown Stack Recipe

This recipe is used when the technology stack cannot be automatically detected from the project files. It fetches the latest Kamal documentation and guides the user through a custom deployment configuration.

## Mandatory First Step: Fetch Latest Documentation

**BEFORE answering ANY Kamal question or generating ANY configuration**, fetch current documentation. Do not rely on training data for Kamal specifics — always fetch fresh docs.

Execute these WebFetch calls in parallel:

- `WebFetch(url: "https://kamal-deploy.org/docs/installation/", prompt: "Extract complete installation and setup guide")`
- `WebFetch(url: "https://kamal-deploy.org/docs/configuration/overview/", prompt: "Extract all configuration options and deploy.yml structure")`
- `WebFetch(url: "https://kamal-deploy.org/docs/configuration/proxy/", prompt: "Extract proxy, SSL, and health check configuration")`

Also fetch these based on what the user needs:

- Servers/roles: `WebFetch(url: "https://kamal-deploy.org/docs/configuration/servers/", prompt: "Extract server roles and configuration")`
- Accessories: `WebFetch(url: "https://kamal-deploy.org/docs/configuration/accessories/", prompt: "Extract accessories configuration for databases and Redis")`
- Environment variables: `WebFetch(url: "https://kamal-deploy.org/docs/configuration/environment-variables/", prompt: "Extract env vars and secrets configuration")`
- Docker build options: `WebFetch(url: "https://kamal-deploy.org/docs/configuration/builders/", prompt: "Extract Docker build configuration options")`
- Hooks: `WebFetch(url: "https://kamal-deploy.org/docs/hooks/overview/", prompt: "Extract deployment hooks overview")`

Only after fetching fresh docs, use the supplementary reference in `references/deploy-yml-reference.md` as additional context.

## Identify the Stack

Ask the user directly:

> "I could not automatically detect the technology stack from the project files. What language and framework does this project use? (For example: Rust/Actix, Ruby/Sinatra, Kotlin/Ktor, Swift/Vapor, etc.)"

## Gather Information

Once the user identifies the stack, collect:

1. How to build the application (build command, output binary/artifact path)
2. How to run the application in production (start command)
3. What port the server listens on
4. Whether there is an existing health check endpoint (path) — if not, instruct the user to add one
5. What dependencies are needed (database, cache, etc.)
6. What the Docker base image should be (language-specific official image or Alpine variant)

## Dockerfile Strategy

Guide the user through building a multi-stage Dockerfile:

**Stage 1 (builder)**: Compile or build the application.
**Stage 2 (runner)**: Minimal runtime image with only what's needed to run.

Principles to enforce:
- Use official language images for the builder stage
- Use minimal base images for the runner (Alpine or Distroless where possible)
- Create a non-root user in the runner stage
- Expose only the application port
- Set `ENTRYPOINT` and `CMD` appropriately

General multi-stage template to adapt:

```dockerfile
FROM <BUILDER_IMAGE> AS builder
WORKDIR /app
# Copy dependency files first for layer caching
COPY <dependency_files> ./
# Install dependencies
RUN <install_deps_command>
# Copy source
COPY . .
# Build
RUN <build_command>

FROM <RUNNER_IMAGE> AS runner
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
# Copy built artifact(s)
COPY --from=builder /app/<output_artifact> ./
USER appuser
EXPOSE <PORT>
ENTRYPOINT ["<start_command>"]
```

Fill in the placeholders based on the information gathered from the user.

## deploy.yml Template

After fetching the current Kamal docs, generate a `config/deploy.yml` based on the documented structure. Use this as a starting point and adapt to the current Kamal version as documented:

```yaml
service: <APP_NAME>
image: <REGISTRY_USER>/<APP_NAME>

servers:
  web:
    hosts:
      - <SERVER_IP>
    proxy:
      ssl: true
      host: <DOMAIN>
      app_port: <PORT>
      healthcheck:
        path: <HEALTH_PATH>
        interval: 3
        timeout: 5

registry:
  username: <REGISTRY_USER>
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    PORT: "<PORT>"
  secret:
    - APP_SECRET

builder:
  arch: amd64
```

Add accessories, volumes, and hooks as needed based on the fetched documentation and user requirements.

## .kamal/secrets Template

```bash
# .kamal/secrets
# Load from environment. NEVER commit actual values.

KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
# APP_SECRET=$APP_SECRET
```

Add to `.gitignore`:

```
.kamal/secrets
.kamal/secrets-common
.kamal/secrets.*
```

## Validation Steps

After generating the configuration:

1. Verify the `Dockerfile` builds locally if possible: `docker build -t <APP_NAME>-test .`
2. Confirm the health check path is correct by running the container locally: `docker run -p <PORT>:<PORT> <APP_NAME>-test`
3. Verify `config/deploy.yml` is syntactically valid YAML
4. Confirm `.kamal/secrets` is in `.gitignore`

## When to Suggest Adding to the Skill

If the stack identified by the user is a mainstream framework (e.g., Rust/Actix, Kotlin/Ktor, Swift/Vapor, Scala/Play), note to the user:

> "This stack doesn't have a dedicated recipe yet. The configuration above was created specifically for your project. If you'd like this to become a reusable recipe in the kamal-deploy-skill, consider opening a PR at the skill's repository."

Then proceed with the custom configuration.
