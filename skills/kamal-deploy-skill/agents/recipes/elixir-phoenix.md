# Elixir / Phoenix Deployment Recipe

This recipe covers deployment of Elixir/Phoenix applications via Kamal.

## 1. Inspect the Project

Read `mix.exs` to determine:
- Application name: `app:` field in the project definition
- Elixir version: `elixir:` in `mix.exs` or `.tool-versions` (asdf)
- OTP version: `erlang:` in `.tool-versions`
- Key dependencies: `phoenix`, `phoenix_live_view`, `ecto_sql`, etc.

Also check:
- Is there an existing `Dockerfile`? Phoenix generates one with `mix phx.gen.release --docker`.
- `config/prod.exs` and `config/runtime.exs` → production configuration
- `priv/repo/migrations/` → Ecto migrations
- `assets/` → JavaScript/CSS assets (requires Node.js in the builder)

## 2. Determine Health Check Path

Phoenix applications don't have a default health endpoint. Add one in your router.

Add to `lib/<app_name>_web/router.ex`:

```elixir
scope "/", AppWeb do
  pipe_through :api
  get "/health", HealthController, :index
end
```

Create `lib/<app_name>_web/controllers/health_controller.ex`:

```elixir
defmodule AppWeb.HealthController do
  use AppWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
```

Alternatively use a simple `Plug`:

```elixir
# In router.ex, before other routes:
get "/health", fn conn, _ -> Plug.Conn.send_resp(conn, 200, ~s({"status":"ok"})) end
```

## 3. Determine Port

Phoenix defaults to port `4000`. Check `config/prod.exs` or `config/runtime.exs`:

```elixir
config :my_app, MyAppWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000]
```

## 4. Create Dockerfile

First, try `mix phx.gen.release --docker` if Phoenix 1.7+ is used — it generates a well-optimized Dockerfile. Inspect and adapt the generated file if it exists.

If no Dockerfile exists or generation is not available:

### Phoenix with Assets (Esbuild + Tailwind)

```dockerfile
FROM hexpm/elixir:1.17.3-erlang-27.1-alpine-3.20.3 AS builder

RUN apk add --no-cache build-base git nodejs npm

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY assets assets
RUN mix assets.deploy

COPY lib lib
RUN mix compile

COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM alpine:3.20 AS runner

RUN apk add --no-cache libstdc++ openssl ncurses-libs
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

COPY --from=builder --chown=appuser:appgroup /app/_build/prod/rel/my_app ./

USER appuser

EXPOSE 4000

ENV PHX_SERVER=true
ENTRYPOINT ["/app/bin/my_app"]
CMD ["start"]
```

Replace `my_app` with the actual OTP application name (lowercase, underscored) from `mix.exs`.

The Elixir and OTP version in `FROM hexpm/elixir:...` should match `.tool-versions` or `mix.exs`. Browse available tags at `https://hub.docker.com/r/hexpm/elixir/tags`.

## 5. Create config/deploy.yml

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
      app_port: 4000
      healthcheck:
        path: /health
        interval: 3
        timeout: 5

registry:
  username: <REGISTRY_USER>
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    PHX_HOST: <DOMAIN>
    PORT: "4000"
    MIX_ENV: prod
  secret:
    - SECRET_KEY_BASE
    - DATABASE_URL

builder:
  arch: amd64

# accessories:
#   postgres:
#     image: postgres:16
#     host: <SERVER_IP>
#     port: "127.0.0.1:5432:5432"
#     env:
#       clear:
#         POSTGRES_USER: app
#         POSTGRES_DB: <APP_NAME>_prod
#       secret:
#         - POSTGRES_PASSWORD
#     directories:
#       - postgres-data:/var/lib/postgresql/data
#
#   redis:
#     image: redis:7-alpine
#     host: <SERVER_IP>
#     port: "127.0.0.1:6379:6379"
#     directories:
#       - redis-data:/data
```

## 6. Create .kamal/secrets

```bash
# .kamal/secrets
# Load from environment. NEVER commit actual values.

KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
SECRET_KEY_BASE=$SECRET_KEY_BASE
DATABASE_URL=$DATABASE_URL
# POSTGRES_PASSWORD=$POSTGRES_PASSWORD
```

Generate `SECRET_KEY_BASE` with: `mix phx.gen.secret`

Add to `.gitignore`:

```
.kamal/secrets
.kamal/secrets-common
.kamal/secrets.*
```

## 7. Ecto Migrations

Create `.kamal/hooks/pre-deploy`:

```bash
#!/bin/bash
set -e
kamal app exec --reuse "/app/bin/my_app eval 'MyApp.Release.migrate()'"
```

Add a `Release` module to the application (this is standard Phoenix release practice):

```elixir
# lib/my_app/release.ex
defmodule MyApp.Release do
  @app :my_app

  def migrate do
    load_app()
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
```

Replace `MyApp` and `my_app` with the actual application module and atom.

Make the hook executable: `chmod +x .kamal/hooks/pre-deploy`

## 8. config/runtime.exs

Ensure `config/runtime.exs` reads configuration from environment variables:

```elixir
import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      """

  config :my_app, MyApp.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :my_app, MyAppWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
```

## 9. LiveView and WebSockets

If using Phoenix LiveView, kamal-proxy forwards WebSocket connections automatically. No additional proxy configuration is needed.

Ensure `config/prod.exs` does not have `check_origin: true` with a fixed list that excludes the production domain.

## 10. Stack-Specific Caveats

- **OTP application name**: The binary path in the Dockerfile (`/app/bin/my_app`) and CMD in `config/deploy.yml` must match the `app:` atom in `mix.exs` exactly.
- **Elixir version pinning**: Pin exact versions in the `FROM hexpm/elixir:...` line. The `alpine` suffix keeps images small.
- **Node.js**: Required only at build time for asset compilation. It should not be in the runner stage.
- **`mix phx.gen.release`**: Running this generates `rel/`, `Dockerfile`, and `config/runtime.exs` stubs. It is the recommended starting point for Phoenix 1.7+.
- **Erlang cookie**: Phoenix release clusters require a shared Erlang cookie. For single-node deploys, this is not needed.
- **Hot code upgrades**: Kamal deploys by replacing containers, not via Erlang hot code upgrades. This is the trade-off for simplicity.
- **BEAM memory**: Each BEAM process is lightweight, but the VM itself uses ~150-300MB baseline. Ensure the server has adequate RAM.
