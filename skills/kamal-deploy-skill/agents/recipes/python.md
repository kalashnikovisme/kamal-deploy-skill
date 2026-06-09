# Python Deployment Recipe

This recipe covers deployment of Python web applications via Kamal. Applies to: Django, FastAPI, Flask, and any WSGI/ASGI Python server.

## 1. Inspect the Project

Read `pyproject.toml`, `requirements.txt`, or `Pipfile` to determine:
- Framework: `django`, `fastapi`, `flask`, `starlette`, etc.
- Python version: check `.python-version`, `pyproject.toml` `[tool.poetry.dependencies] python`, or `Pipfile [requires] python_version`
- ASGI vs WSGI: FastAPI/Starlette → ASGI (use `uvicorn`); Django/Flask → WSGI (use `gunicorn`) or ASGI if configured

Also check:
- Is there an existing `Dockerfile`? Inspect before creating a new one.
- `manage.py` → Django project
- `app.py` / `main.py` / `wsgi.py` / `asgi.py` → entry point

## 2. Determine Health Check Path

| Framework | Default health path | Notes |
|-----------|-------------------|-------|
| Django | `/up/` or `/health/` | Create a minimal view if none exists |
| FastAPI | `/health` | Add `@app.get("/health")` if missing |
| Flask | `/health` | Add `@app.route("/health")` if missing |

If no health endpoint exists, instruct the user to add one.

**Django minimal health view** — add to `urls.py`:

```python
from django.http import JsonResponse
from django.urls import path

def health(request):
    return JsonResponse({"status": "ok"})

urlpatterns = [
    path("up/", health),
    # ... existing patterns
]
```

**FastAPI health endpoint**:

```python
@app.get("/health")
async def health():
    return {"status": "ok"}
```

**Flask health endpoint**:

```python
@app.route("/health")
def health():
    return {"status": "ok"}
```

## 3. Determine Port and Entry Point

| Framework | Server | Default port | Entry point |
|-----------|--------|-------------|-------------|
| Django (WSGI) | gunicorn | 8000 | `<project>.wsgi:application` |
| Django (ASGI) | uvicorn | 8000 | `<project>.asgi:application` |
| FastAPI | uvicorn | 8000 | `main:app` |
| Flask | gunicorn | 8000 | `app:app` or `wsgi:app` |

Identify the Django project name from `manage.py` (the `DJANGO_SETTINGS_MODULE` default value).

## 4. Create Dockerfile

Check for an existing `Dockerfile` first.

### Django (gunicorn / WSGI)

```dockerfile
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

FROM base AS builder
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM base AS runner
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 && rm -rf /var/lib/apt/lists/*
COPY --from=builder /install /usr/local
COPY . .
RUN addgroup --system --gid 1001 appgroup && adduser --system --uid 1001 --gid 1001 appuser
USER appuser
EXPOSE 8000
CMD ["gunicorn", "<PROJECT_NAME>.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "2"]
```

Replace `<PROJECT_NAME>` with the actual Django project name.

If using `pyproject.toml` with Poetry:

```dockerfile
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app

FROM base AS builder
RUN pip install poetry==1.8.3
COPY pyproject.toml poetry.lock ./
RUN poetry config virtualenvs.create false && poetry install --no-dev --no-root

FROM base AS runner
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 && rm -rf /var/lib/apt/lists/*
COPY --from=builder /usr/local /usr/local
COPY . .
RUN addgroup --system --gid 1001 appgroup && adduser --system --uid 1001 --gid 1001 appuser
USER appuser
EXPOSE 8000
CMD ["gunicorn", "<PROJECT_NAME>.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "2"]
```

### FastAPI (uvicorn)

```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
RUN pip install --no-cache-dir --prefix=/install uvicorn[standard] fastapi
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim AS runner
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .
RUN addgroup --system --gid 1001 appgroup && adduser --system --uid 1001 --gid 1001 appuser
USER appuser
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
```

### Flask (gunicorn)

```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim AS runner
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .
RUN addgroup --system --gid 1001 appgroup && adduser --system --uid 1001 --gid 1001 appuser
USER appuser
EXPOSE 8000
CMD ["gunicorn", "app:app", "--bind", "0.0.0.0:8000", "--workers", "2"]
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
      app_port: 8000
      healthcheck:
        path: /up/
        interval: 3
        timeout: 5

registry:
  username: <REGISTRY_USER>
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    DJANGO_SETTINGS_MODULE: <PROJECT_NAME>.settings.production
    PORT: "8000"
  secret:
    - SECRET_KEY
    - DATABASE_URL
    - ALLOWED_HOSTS

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

Adjust `healthcheck.path` to the actual health endpoint added in Step 2.
For FastAPI/Flask, set `DJANGO_SETTINGS_MODULE` to the relevant env var or remove it.

## 6. Create .kamal/secrets

```bash
# .kamal/secrets
# Load from environment. NEVER commit actual values.

KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
SECRET_KEY=$SECRET_KEY
DATABASE_URL=$DATABASE_URL
# POSTGRES_PASSWORD=$POSTGRES_PASSWORD
# REDIS_URL=$REDIS_URL
# ALLOWED_HOSTS=$ALLOWED_HOSTS
```

Add to `.gitignore`:

```
.kamal/secrets
.kamal/secrets-common
.kamal/secrets.*
```

## 7. Django-Specific: Static Files and Migrations

**Static files**: Kamal does not run `collectstatic` automatically. Add a deploy hook to run it, or configure static files to be served from a CDN/object storage.

Create `.kamal/hooks/pre-deploy`:

```bash
#!/bin/bash
set -e
kamal app exec --reuse "python manage.py collectstatic --no-input"
kamal app exec --reuse "python manage.py migrate --no-input"
```

Make it executable: `chmod +x .kamal/hooks/pre-deploy`

If running migrations in a hook is not appropriate for your team's workflow, document the manual migration step in the deployment README section instead.

**Static file serving**: For production, configure Django to serve static files via WhiteNoise or a CDN:

```python
# settings/production.py
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    # ...
]
STATICFILES_STORAGE = "whitenoise.storage.CompressedManifestStaticFilesStorage"
```

## 8. Stack-Specific Caveats

- **Python version**: Pin the Python version in the Dockerfile to match `.python-version` or `pyproject.toml`.
- **libpq-dev**: Required for `psycopg2`. Use `psycopg2-binary` for simpler builds (not recommended for production on amd64) or compile from source.
- **Gunicorn workers**: Start with `(2 * CPU_COUNT) + 1`. Adjust based on server size.
- **Django `ALLOWED_HOSTS`**: Must include the server IP and domain. Pass as a secret or clear env var.
- **Database migrations**: Decide on the migration strategy before first deploy. Running migrations in a hook is simple but may cause downtime on large tables.
- **Celery workers**: If the project uses Celery, add a separate `worker` role in `servers` section pointing to the same or a different host, with a different CMD.
