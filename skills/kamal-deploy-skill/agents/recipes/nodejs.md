# Node.js Deployment Recipe

This recipe covers deployment of Node.js applications via Kamal. Applies to: Next.js, NestJS, Express, Fastify, Nuxt, Remix, and any other Node.js server.

## 1. Inspect the Project

Read `package.json` to determine:
- `name` field → use as the default service name
- `scripts.start` or `scripts.serve` → the production start command
- Key dependencies: `next`, `nuxt`, `@nestjs/core`, `express`, `fastify`, `remix`, etc.
- Node version: check `.nvmrc`, `.node-version`, or `engines.node` in `package.json`

Also check:
- Is there an existing `Dockerfile`? If yes, inspect it before creating a new one.
- Does the app expose a health check endpoint? Common paths: `/`, `/health`, `/api/health`, `/up`.

## 2. Determine Health Check Path

| Framework | Default health path |
|-----------|-------------------|
| Next.js | `/api/health` (create if missing) or `/` |
| NestJS | `/health` (if `@nestjs/terminus` is used) or `/` |
| Express / Fastify | `/health` or `/` |
| Nuxt | `/` |
| Remix | `/` |

If no health endpoint exists, instruct the user to add a minimal one before deployment. For Next.js, create `app/api/health/route.ts` (App Router) or `pages/api/health.ts` (Pages Router):

```typescript
// app/api/health/route.ts
export async function GET() {
  return Response.json({ status: 'ok' })
}
```

## 3. Determine Port

| Framework | Default port |
|-----------|-------------|
| Next.js | 3000 |
| NestJS | 3000 |
| Express | 3000 (check `app.listen()`) |
| Fastify | 3000 |
| Nuxt | 3000 |
| Remix | 3000 |

Read the source to confirm. The port must match `proxy.app_port` in `deploy.yml`.

## 4. Create Dockerfile

Check if a `Dockerfile` already exists. If it does, review it for:
- Multi-stage build (builder → runner)
- Non-root user
- Correct CMD/ENTRYPOINT

If no `Dockerfile` exists, create one appropriate for the framework.

### Next.js (standalone output)

First, verify `next.config.js`/`next.config.ts` has `output: 'standalone'`. Add it if missing:

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
}
module.exports = nextConfig
```

Then create `Dockerfile`:

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

### NestJS

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json* yarn.lock* ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nestjs
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY package.json ./
USER nestjs
EXPOSE 3000
CMD ["node", "dist/main.js"]
```

### Express / Fastify (generic Node.js server)

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json* yarn.lock* ./
RUN npm ci --omit=dev
COPY . .

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nodeapp
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app ./
USER nodeapp
EXPOSE 3000
CMD ["node", "src/index.js"]
```

Adapt `CMD` to match the actual entry point from `scripts.start`.

## 5. Create config/deploy.yml

Substitute `<APP_NAME>`, `<REGISTRY_USER>`, `<SERVER_IP>`, `<DOMAIN>`, and `<PORT>` with actual values gathered in Step 3 of SKILL.md.

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
        path: /health
        interval: 3
        timeout: 3

registry:
  username: <REGISTRY_USER>
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    NODE_ENV: production
    PORT: "<PORT>"
  secret:
    - NODE_ENV_SECRET  # Add any secrets your app needs

builder:
  arch: amd64

# Uncomment and configure accessories as needed:
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

If the user confirmed they need PostgreSQL and/or Redis, uncomment and populate the relevant accessory blocks.

If staging and production destinations are requested, create `config/deploy.staging.yml`:

```yaml
servers:
  web:
    hosts:
      - <STAGING_SERVER_IP>
    proxy:
      ssl: true
      host: staging.<DOMAIN>
      app_port: <PORT>

env:
  clear:
    NODE_ENV: staging
```

## 6. Create .kamal/secrets

Create `.kamal/secrets` with the following template. Never populate actual secret values.

```bash
# .kamal/secrets
# All secrets are loaded from your shell environment.
# Set these in your CI/CD system and on your local machine.
# NEVER commit actual secret values to this file.

KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD

# Add app-specific secrets below:
# DATABASE_URL=$DATABASE_URL
# REDIS_URL=$REDIS_URL
# SECRET_KEY=$SECRET_KEY
```

Create `.kamal/secrets-common` if sharing secrets across destinations:

```bash
# .kamal/secrets-common
# Secrets shared across all destinations.
KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
```

Add to `.gitignore`:

```
.kamal/secrets
.kamal/secrets-common
.kamal/secrets.*
```

## 7. Stack-Specific Caveats

- **Next.js**: `output: 'standalone'` is required for the Dockerfile above. Without it, the image will be very large.
- **Next.js image optimization**: If using `next/image` with external domains, configure `images.remotePatterns` in `next.config.js`.
- **Environment variables at build time**: Next.js bakes `NEXT_PUBLIC_*` variables at build time. Pass them as Docker build args if needed.
- **NestJS**: Adjust `dist/main.js` to the actual compiled entry point from `tsconfig.json` `outDir`.
- **Node version**: Match the Node version in the Dockerfile to the project's `.nvmrc` or `engines.node`.
- **Package manager**: Adjust `npm ci`/`yarn --frozen-lockfile`/`pnpm i --frozen-lockfile` based on which lockfile is present.
