# Application console (`bin/console`) examples

Real transcripts of what the generated script provides. Business objects shown are illustrative; the console only exposes what the project actually has.

## Node.js (Express/plain, CommonJS or ESM)

```text
$ bin/console
my-api console (development, node v22.11.0)
  available: load(spec), require, await import(...), prisma, db
my-api(development)> 1 + 1
2
my-api(development)> const users = await db.user.findMany({ take: 2 })
my-api(development)> const { UsersService } = await load('./dist/users/users.service.js')
my-api(development)> .exit
```

## NestJS (application context, no HTTP listener)

```text
$ bin/console --remote -d staging
Launching interactive command with version abc123 via SSH from existing container on 203.0.113.10...
my-api console (production, node v22.11.0)
  context: NestJS application context (no HTTP listener)
  available: load(spec), require, await import(...), app, get
my-api(production)> const { UsersService } = await load('./dist/users/users.service.js')
my-api(production)> await get(UsersService).findById(42)
```

## Python (FastAPI / plain)

```text
$ bin/console
my-svc console (development, python 3.12.4)
  context: FastAPI app from app.main (no server started)
  available: import <module>, asyncio.run(...), app
In [1]: from app.services import billing
```

## Framework-native: Laravel

```text
$ bin/console --remote -d production -r web      # php artisan tinker inside the running container
> User::count()
```

## Rules

- Remote mode is `kamal app exec -i --reuse <your flags> "sh bin/console --local"`; it attaches to the running container and starts nothing else.
- A production console can change production data, exactly like `rails console`.
- Multi-unit repo: `apps/api/bin/console --remote -d staging` (the unit script carries its own `-c`/`-r` defaults).
