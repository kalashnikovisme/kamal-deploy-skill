# PHP / Laravel Deployment Recipe

This recipe covers deployment of PHP web applications via Kamal. Applies to: Laravel, Symfony, and generic PHP applications.

## 1. Inspect the Project

Read `composer.json` to determine:
- `name` field → service name candidate
- Key dependencies: `laravel/framework`, `symfony/framework-bundle`, etc.
- PHP version requirement: `require.php`

Also check:
- Is there an existing `Dockerfile`? Inspect before creating a new one.
- `artisan` exists → Laravel project
- `bin/console` exists → Symfony project
- PHP version: check `composer.json` `require.php`, `.php-version`

## 2. Determine Health Check Path

| Framework | Default health path | Notes |
|-----------|-------------------|-------|
| Laravel | `/up` | Laravel 11+ ships `/up` by default |
| Symfony | `/health` | Add via HealthCheckBundle or custom controller |
| Generic PHP | `/health.php` or `/` | Create a simple script |

For Laravel 10 and older, add a health route to `routes/web.php`:

```php
Route::get('/up', function () {
    return response()->json(['status' => 'ok']);
});
```

Laravel 11+ includes `/up` by default in `routes/web.php` via `Route::get('/up', ...)`.

## 3. Determine Port

PHP-FPM + nginx combination serves on port 80 inside the container. Default: `80`.

## 4. Create Dockerfile

### Laravel (PHP-FPM + nginx in one container)

This approach bundles PHP-FPM and nginx in one image for simplicity with Kamal's single-container model:

```dockerfile
FROM php:8.3-fpm-alpine AS base

RUN apk add --no-cache \
    nginx \
    libpng-dev \
    libzip-dev \
    zip \
    unzip \
    && docker-php-ext-install pdo_mysql pdo_pgsql zip gd opcache \
    && rm -rf /var/cache/apk/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

FROM base AS builder
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader
COPY . .
RUN php artisan config:cache \
    && php artisan route:cache \
    && php artisan view:cache

FROM base AS runner
WORKDIR /var/www/html

COPY --from=builder /app .

RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 80
CMD ["/start.sh"]
```

Create `docker/nginx.conf`:

```nginx
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /tmp/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access.log;
    sendfile on;
    keepalive_timeout 65;

    server {
        listen 80;
        root /var/www/html/public;
        index index.php index.html;

        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }

        location ~ \.php$ {
            fastcgi_pass 127.0.0.1:9000;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
            include fastcgi_params;
        }

        location ~ /\.(?!well-known).* {
            deny all;
        }
    }
}
```

Create `docker/start.sh`:

```bash
#!/bin/sh
set -e
php-fpm -D
nginx -g "daemon off;"
```

### Symfony

Adapt the above Dockerfile by:
- Replacing artisan cache commands with `php bin/console cache:warmup`
- Changing the document root to `public/`
- Adjusting PHP extensions to match `symfony/requirements-checker`

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
      app_port: 80
      healthcheck:
        path: /up
        interval: 3
        timeout: 5

registry:
  username: <REGISTRY_USER>
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    APP_ENV: production
    APP_DEBUG: "false"
    LOG_CHANNEL: stderr
  secret:
    - APP_KEY
    - DB_PASSWORD
    - DB_HOST
    - DB_DATABASE

builder:
  arch: amd64

volumes:
  - <APP_NAME>-storage:/var/www/html/storage/app

# accessories:
#   mysql:
#     image: mysql:8.0
#     host: <SERVER_IP>
#     port: "127.0.0.1:3306:3306"
#     env:
#       clear:
#         MYSQL_DATABASE: <APP_NAME>_production
#         MYSQL_USER: app
#       secret:
#         - MYSQL_ROOT_PASSWORD
#         - MYSQL_PASSWORD
#     directories:
#       - mysql-data:/var/lib/mysql
#
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

## 6. Create .kamal/secrets

```bash
# .kamal/secrets
# Load from environment. NEVER commit actual values.

KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
APP_KEY=$APP_KEY
DB_PASSWORD=$DB_PASSWORD
# DB_HOST=$DB_HOST
# DB_DATABASE=$DB_DATABASE
# MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
# MYSQL_PASSWORD=$MYSQL_PASSWORD
# POSTGRES_PASSWORD=$POSTGRES_PASSWORD
```

Add to `.gitignore`:

```
.kamal/secrets
.kamal/secrets-common
.kamal/secrets.*
.env
```

## 7. Database Migrations

Create `.kamal/hooks/pre-deploy`:

```bash
#!/bin/bash
set -e
kamal app exec --reuse "php artisan migrate --force"
```

Make executable: `chmod +x .kamal/hooks/pre-deploy`

For Symfony:

```bash
#!/bin/bash
set -e
kamal app exec --reuse "php bin/console doctrine:migrations:migrate --no-interaction"
```

## 8. Queue Workers

If the project uses Laravel queues, add a worker role:

```yaml
# In config/deploy.yml servers section:
servers:
  web:
    hosts:
      - <SERVER_IP>
    proxy:
      ssl: true
      host: <DOMAIN>
      app_port: 80
  worker:
    hosts:
      - <SERVER_IP>
    cmd: php artisan queue:work --tries=3 --timeout=60
    proxy: false
```

## 9. Stack-Specific Caveats

- **APP_KEY**: Laravel requires a unique `APP_KEY`. Generate with `php artisan key:generate --show` and store securely.
- **Storage volume**: The `volumes` config ensures `storage/app` persists across deployments. Without it, uploaded files are lost on each deploy.
- **File cache**: `php artisan config:cache`, `route:cache`, and `view:cache` run at build time. If any config depends on environment variables that differ per deployment, use `env()` calls consistently and don't cache config.
- **Opcache**: Enable opcache in production for significant performance gains. The Dockerfile above includes it.
- **Queue worker restart**: After deploy, restart queue workers: add `php artisan queue:restart` to the `pre-deploy` hook.
- **Scheduler**: Laravel's scheduler should run via a cron job on the server: `* * * * * cd /var/www/html && php artisan schedule:run >> /dev/null 2>&1`
- **Symfony**: Replace `php artisan` commands with `php bin/console` equivalents throughout.
