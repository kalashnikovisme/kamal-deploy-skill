# Next.js Deployment Recipe

This recipe covers deployment of Next.js as a long-running server (server-side rendering, API routes, App Router) via Kamal, including an optional background worker role. It does **not** apply to static exports (`output: 'export'`) — those are served from a CDN, not Kamal.

## 1. Inspect the Project

Read `package.json` to determine:
- `name` field → default service name
- `scripts.start` or `scripts.build` → confirm Next.js is present
- Node version: check `.nvmrc`, `.node-version`, or `engines.node`
- Package manager: check for `yarn.lock`, `pnpm-lock.yaml`, or `package-lock.json`
- Worker entry point: look for `workers/`, `src/workers/`, `jobs/`, `src/jobs/`, or a `scripts/worker.js` / `scripts/worker.ts`

Also check:
- `next.config.js` or `next.config.ts` → confirm `output` is NOT set to `'export'`
- Is there an existing `Dockerfile`? Review before creating.
- Router type: does the project use App Router (`app/`) or Pages Router (`pages/`)?

## 2. Verify Server Mode

Confirm the project is NOT a static export:

```bash
# Acceptable: no output key, or output: 'standalone'
# NOT acceptable for Kamal: output: 'export'
```

If `output: 'export'` is set, stop and tell the user: "Static exports are served from a CDN — Kamal is not the right tool for this. Remove `output: 'export'` and add `output: 'standalone'` to deploy a server."

Ensure `output: 'standalone'` is set in `next.config.js` / `next.config.ts`. Add it if missing:

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
}
module.exports = nextConfig
```

For TypeScript config:

```typescript
import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  output: 'standalone',
}

export default nextConfig
```

## 3. Determine Health Check Path

Add a health endpoint if one does not exist.

**App Router** — create `app/api/health/route.ts`:

```typescript
export async function GET() {
  return Response.json({ status: 'ok' })
}
```

**Pages Router** — create `pages/api/health.ts`:

```typescript
import type { NextApiRequest, NextApiResponse } from 'next'

export default function handler(_req: NextApiRequest, res: NextApiResponse) {
  res.status(200).json({ status: 'ok' })
}
```

Health path: `/api/health`. Port: `3000`.

## 4. Identify the Worker Entry Point

Ask the user: "Does your app have a background worker process (e.g., job queue, scheduled tasks)? If yes, what is the entry point file?"

Common patterns:
- `workers/index.js` / `workers/index.ts`
- `src/workers/index.ts`
- `scripts/worker.js`
- A BullMQ, Inngest, or pg-boss queue processor

If the worker is TypeScript, it must be compiled or run with `tsx` / `ts-node`. Confirm which:
- Compiled: `node dist/workers/index.js` (build step needed)
- Runtime: `npx tsx workers/index.ts` (add `tsx` as a dependency)

If the user has no worker, skip the worker role in Step 6 and note it in the summary.

## 5. Create Dockerfile

Check for an existing `Dockerfile`. If it exists, verify it uses standalone output and a non-root user. If not, create:

```dockerfile
FROM node:20-alpine AS base

FROM base AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json package-lock.json* yarn.lock* pnpm-lock.yaml* ./
RUN \
  if [ -f yarn.lock ]; then yarn --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm i --frozen-lockfile; \
  else echo "No lockfile found." && exit 1; \
  fi

FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN \
  if [ -f yarn.lock ]; then yarn build; \
  elif [ -f package-lock.json ]; then npm run build; \
  elif [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm build; \
  fi

FROM base AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"
CMD ["node", "server.js"]
```

**If the worker is TypeScript compiled in the build step**, add to the `builder` stage:

```dockerfile
# In the builder stage, after `npm run build`:
RUN npm run build:workers   # adjust to actual script name
```

And copy the compiled worker output into the `runner` stage:

```dockerfile
COPY --from=builder --chown=nextjs:nodejs /app/dist/workers ./dist/workers
```

**If the worker uses `tsx` at runtime**, add the `tsx` dev dependency and include it in the image:

```dockerfile
# After copying node_modules in runner stage:
COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/workers ./workers
```

The same Docker image is used for both the web server and the worker — Kamal overrides the CMD per role.

## 6. Create config/deploy.yml

Substitute `<APP_NAME>`, `<REGISTRY_USER>`, `<SERVER_IP>`, and `<DOMAIN>` with values gathered in SKILL.md Step 3.

### Web + Worker (standard)

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
      app_port: 3000
      healthcheck:
        path: /api/health
        interval: 3
        timeout: 5
  workers:
    hosts:
      - <SERVER_IP>
    cmd: node dist/workers/index.js
    # No proxy block — workers are not exposed via kamal-proxy

registry:
  username: <REGISTRY_USER>
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    NODE_ENV: production
    PORT: "3000"
  secret:
    - DATABASE_URL   # add app-specific secrets here

builder:
  arch: amd64

# Uncomment and configure as needed:
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

Replace `node dist/workers/index.js` with the actual worker entry point (e.g., `npx tsx workers/index.ts` if using tsx at runtime).

### Web only (no worker)

If the user has no worker process, omit the `workers` role entirely:

```yaml
servers:
  web:
    hosts:
      - <SERVER_IP>
    proxy:
      ssl: true
      host: <DOMAIN>
      app_port: 3000
      healthcheck:
        path: /api/health
        interval: 3
        timeout: 5
```

### Staging destination

If staging is requested, create `config/deploy.staging.yml`:

```yaml
servers:
  web:
    hosts:
      - <STAGING_SERVER_IP>
    proxy:
      ssl: true
      host: staging.<DOMAIN>
      app_port: 3000
  workers:
    hosts:
      - <STAGING_SERVER_IP>
    cmd: node dist/workers/index.js

env:
  clear:
    NODE_ENV: staging
```

## 7. Create .kamal/secrets

```bash
# .kamal/secrets
# Loaded from shell environment. NEVER commit actual values.

KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD

# App secrets — add what your app needs:
# DATABASE_URL=$DATABASE_URL
# REDIS_URL=$REDIS_URL
# NEXTAUTH_SECRET=$NEXTAUTH_SECRET
# NEXTAUTH_URL=$NEXTAUTH_URL
```

Add to `.gitignore`:

```
.kamal/secrets
.kamal/secrets-common
.kamal/secrets.*
```

## 8. Caveats

- **`output: 'standalone'`** is required. Without it, the Next.js build does not produce `server.js` and the CMD will fail.
- **`NEXT_PUBLIC_*` variables** are baked at build time. If these differ between staging and production, pass them as Docker build args via `builder.args` in `deploy.yml`:
  ```yaml
  builder:
    arch: amd64
    args:
      NEXT_PUBLIC_API_URL: https://api.example.com
  ```
- **Worker CMD**: the `workers` role overrides the image CMD at runtime — the Dockerfile `CMD` still applies to the `web` role.
- **Worker restarts**: Kamal restarts crashed containers automatically. Ensure the worker process exits with a non-zero code on fatal errors so Kamal can restart it.
- **Scaling workers**: to run the worker on a second server, add its IP to the `workers.hosts` list.
- **Node version**: match the base image (`node:20-alpine`) to `.nvmrc` or `engines.node` in `package.json`.
- **next/image**: if using external image domains, configure `images.remotePatterns` in `next.config.js`.
- **Database migrations**: Next.js has no built-in migration runner. Add a `.kamal/hooks/pre-deploy` script if you want migrations to run automatically:
  ```bash
  #!/bin/bash
  set -e
  kamal app exec --reuse "npx prisma migrate deploy"
  # or: kamal app exec --reuse "node scripts/migrate.js"
  ```
  Make executable: `chmod +x .kamal/hooks/pre-deploy`
