# Go Deployment Recipe

This recipe covers deployment of Go web applications via Kamal. Applies to any Go HTTP server (standard `net/http`, Gin, Echo, Chi, Fiber, etc.).

## 1. Inspect the Project

Read `go.mod` to determine:
- Module name (used to identify the main package path)
- Go version (`go 1.22` etc.)
- Key dependencies: `github.com/gin-gonic/gin`, `github.com/labstack/echo`, `github.com/go-chi/chi`, `github.com/gofiber/fiber`, etc.

Also check:
- Is there an existing `Dockerfile`? Inspect before creating a new one.
- Where is `main.go`? Check `./`, `./cmd/<app>/`, `./cmd/server/`, or `./cmd/api/`.
- What port does the server listen on? Grep for `ListenAndServe` or `Listen`.

## 2. Determine Health Check Path

| Framework | Default health path |
|-----------|-------------------|
| Standard net/http | `/health` (add if missing) |
| Gin | `/health` (add if missing) |
| Echo | `/health` (add if missing) |
| Chi | `/health` (add if missing) |
| Fiber | `/health` (add if missing) |

If no health endpoint exists, instruct the user to add one. Example for standard `net/http`:

```go
http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusOK)
    w.Write([]byte(`{"status":"ok"}`))
})
```

For Gin:

```go
r.GET("/health", func(c *gin.Context) {
    c.JSON(http.StatusOK, gin.H{"status": "ok"})
})
```

## 3. Determine Port

Default assumption: `8080`. Check `main.go` and any `PORT` env var usage. The port must match `proxy.app_port` in `deploy.yml`.

## 4. Create Dockerfile

Go produces a single static binary, making images very small. Check for an existing `Dockerfile` first.

### Standard Go Dockerfile (multi-stage)

```dockerfile
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app/server ./cmd/server

FROM scratch AS runner
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app/server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
```

Adjust `./cmd/server` to the actual main package path. If the project uses CGO (rare), switch `FROM scratch` to `FROM alpine:3.20` and set `CGO_ENABLED=1`.

If the binary needs to read files at runtime (templates, static assets), use `FROM alpine:3.20` instead of `FROM scratch` and copy those files:

```dockerfile
FROM alpine:3.20 AS runner
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app/server /server
COPY --chown=appuser:appgroup templates/ /templates/
USER appuser
EXPOSE 8080
ENTRYPOINT ["/server"]
```

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
      app_port: 8080
      healthcheck:
        path: /health
        interval: 3
        timeout: 3

registry:
  username: <REGISTRY_USER>
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    PORT: "8080"
    GIN_MODE: release  # Remove if not using Gin
  secret:
    - DATABASE_URL  # Remove if not using a database
    - SECRET_KEY    # Remove if not needed

builder:
  arch: amd64

# Uncomment if using PostgreSQL:
# accessories:
#   postgres:
#     image: postgres:16
#     host: <SERVER_IP>
#     port: "127.0.0.1:5432:5432"
#     env:
#       clear:
#         POSTGRES_USER: app
#         POSTGRES_DB: <APP_NAME>_production
#       secret:
#         - POSTGRES_PASSWORD
#     directories:
#       - postgres-data:/var/lib/postgresql/data
#
# Uncomment if using Redis:
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
# DATABASE_URL=$DATABASE_URL
# SECRET_KEY=$SECRET_KEY
# POSTGRES_PASSWORD=$POSTGRES_PASSWORD
```

Add to `.gitignore`:

```
.kamal/secrets
.kamal/secrets-common
.kamal/secrets.*
```

## 7. Database Migrations

Go does not have a built-in migration runner. If using migrations (e.g., `golang-migrate`, `goose`, `atlas`), add a deploy hook:

Create `.kamal/hooks/pre-deploy`:

```bash
#!/bin/bash
set -e
# Using golang-migrate:
kamal app exec --reuse "migrate -path /migrations -database \"$DATABASE_URL\" up"
# Or using goose:
# kamal app exec --reuse "goose -dir /migrations postgres \"$DATABASE_URL\" up"
```

Make executable: `chmod +x .kamal/hooks/pre-deploy`

Adapt the command to the actual migration tool used in the project. If no migration tooling is detected, omit this section.

## 8. Stack-Specific Caveats

- **Static binary**: Go compiles to a static binary by default — Docker images are very small (often under 20 MB with `FROM scratch`).
- **CGO**: If the project uses `cgo` (e.g., SQLite via `mattn/go-sqlite3`), the `FROM scratch` approach won't work. Use `FROM alpine` and set `CGO_ENABLED=1`.
- **Go version**: Match the Go version in the Dockerfile to `go.mod`. Alpine images use `golang:X.Y-alpine`.
- **Embedded files**: If using `//go:embed`, ensure the source files are present in the builder stage and properly addressed.
- **Air / hot reload**: Do not use Air or other hot-reload tools in the production Dockerfile. These are development-only tools.
- **`FROM scratch` and TLS**: Always copy CA certificates from the builder when using `FROM scratch`, or HTTPS calls from the app will fail.
