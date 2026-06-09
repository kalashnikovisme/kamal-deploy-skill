# .NET Deployment Recipe

This recipe covers deployment of .NET web applications via Kamal. Applies to: ASP.NET Core (minimal APIs, MVC, Razor Pages, Blazor Server).

## 1. Inspect the Project

Find `*.csproj` or `*.sln` to determine:
- .NET version: `<TargetFramework>net8.0</TargetFramework>`
- Project type: `Microsoft.NET.Sdk.Web` → ASP.NET Core web app
- Key packages: `Microsoft.AspNetCore.*`, `EntityFrameworkCore`, etc.

Also check:
- Is there an existing `Dockerfile`? Inspect before creating.
- Does the project define a health check? Check `program.cs` for `app.MapHealthChecks`.
- Port: check `launchSettings.json` `applicationUrl`, or environment variable `ASPNETCORE_URLS`.

## 2. Determine Health Check Path

ASP.NET Core has built-in health check middleware. Check `Program.cs` for:

```csharp
app.MapHealthChecks("/health");
```

If no health check is wired up, instruct the user to add it:

```csharp
// In Program.cs
builder.Services.AddHealthChecks();
// ...
app.MapHealthChecks("/health");
```

Minimal API alternative:

```csharp
app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
```

## 3. Determine Port

ASP.NET Core defaults to port `8080` in containers (since .NET 8). Older versions defaulted to `80`. Check:
- `ASPNETCORE_URLS` environment variable pattern
- `launchSettings.json` `applicationUrl`
- For .NET 8+: default is `http://+:8080`

## 4. Create Dockerfile

Check for an existing `Dockerfile` first.

### ASP.NET Core (.NET 8+)

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS builder
WORKDIR /src
COPY *.csproj ./
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine AS runner
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app/publish .
USER appuser
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "<APP_NAME>.dll"]
```

Replace `<APP_NAME>` with the actual project DLL name (matches the `<AssemblyName>` in `.csproj` or the project name).

### Solution with multiple projects

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS builder
WORKDIR /src
COPY *.sln ./
COPY src/Web/*.csproj ./src/Web/
COPY src/Core/*.csproj ./src/Core/
RUN dotnet restore
COPY . .
RUN dotnet publish src/Web/<APP_NAME>.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine AS runner
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app/publish .
USER appuser
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "<APP_NAME>.dll"]
```

### .NET 6 / .NET 7

Change `8.0` to `6.0` or `7.0` in FROM lines, and adjust the default port to `80`:

```dockerfile
ENV ASPNETCORE_URLS=http://+:80
EXPOSE 80
```

And update `deploy.yml` `app_port` to `80`.

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
        timeout: 5

registry:
  username: <REGISTRY_USER>
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    ASPNETCORE_ENVIRONMENT: Production
    ASPNETCORE_URLS: http://+:8080
  secret:
    - ConnectionStrings__DefaultConnection
    - JWT_SECRET

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
#         POSTGRES_DB: <APP_NAME>_production
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

Note: .NET environment variable names use `__` as a separator for nested config (e.g., `ConnectionStrings__DefaultConnection` maps to `ConnectionStrings:DefaultConnection` in `appsettings.json`).

## 6. Create .kamal/secrets

```bash
# .kamal/secrets
# Load from environment. NEVER commit actual values.

KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
ConnectionStrings__DefaultConnection=$ConnectionStrings__DefaultConnection
# JWT_SECRET=$JWT_SECRET
# POSTGRES_PASSWORD=$POSTGRES_PASSWORD
```

Add to `.gitignore`:

```
.kamal/secrets
.kamal/secrets-common
.kamal/secrets.*
```

## 7. Database Migrations (Entity Framework Core)

Create `.kamal/hooks/pre-deploy`:

```bash
#!/bin/bash
set -e
kamal app exec --reuse "dotnet ef database update"
```

Make executable: `chmod +x .kamal/hooks/pre-deploy`

Alternatively, run migrations programmatically at startup by adding to `Program.cs`:

```csharp
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
}
```

The startup approach is simpler for small projects but adds startup time. The hook approach is safer for production with large migration sets.

## 8. Stack-Specific Caveats

- **DLL name**: The entry point in the Dockerfile must match the compiled DLL name. Check `<AssemblyName>` in `.csproj` or use `$(ProjectName).dll` as the default.
- **Alpine vs Debian**: Alpine images are smaller. If the app uses P/Invoke or native libraries (e.g., SkiaSharp, ImageSharp with native codecs), use Debian-based images (`mcr.microsoft.com/dotnet/aspnet:8.0`) instead.
- **Port (older .NET)**: .NET 6/7 containers default to port 80. .NET 8+ defaults to 8080. Match the `ASPNETCORE_URLS` and `app_port` accordingly.
- **`appsettings.json`**: Do not put production secrets in `appsettings.Production.json`. Use environment variables (which override `appsettings.json` values in ASP.NET Core automatically).
- **Blazor Server**: Blazor Server requires persistent connections (WebSockets/SignalR). Ensure the proxy does not have a very short response timeout; increase `proxy.response_timeout` if needed.
- **Blazor WebAssembly**: Static files only — Kamal is not ideal for pure WASM apps. Consider a CDN. If combined with an API backend, deploy only the API through Kamal and serve WASM separately.
- **`--self-contained`**: Publishing self-contained (`dotnet publish --self-contained true`) produces a larger image but removes the need for the ASP.NET Core runtime base image. Only use it if needed.
