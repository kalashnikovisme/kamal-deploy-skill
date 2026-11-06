# Application Console Pattern (`bin/console`)

Every Kamal-managed unit gets a working `bin/console`: an **application-aware REPL** - the closest practical equivalent of `rails console` for the unit's stack. This is mandatory, not part of the optional wrapper layer (SKILL.md Step 5.5). A plain `sh`/`bash` is **not** a console and must never be generated as one.

The common behavior and acceptance criteria live here. Recipes only add stack-specific details (`## Application console` section).

## The reusable implementation

Install from `templates/bin/` (resolve paths per SKILL.md "Runtime and File Loading"):

| Template | Install as | Used for |
|---|---|---|
| `templates/bin/console` | `<unit>/bin/console` (mode 755) | POSIX `sh` dispatcher: local REPL, `--remote`, stack detection, honest "unsupported" report |
| `templates/bin/console.d/node.cjs` | `<unit>/bin/console.d/node.cjs` | Node.js REPL (CJS/ESM/compiled TS, NestJS, Prisma, hook) - only for Node units |
| `templates/bin/console.d/python.py` | `<unit>/bin/console.d/python.py` | Plain Python / FastAPI REPL - only for Python units that are neither Django nor Flask |

Copy only the helper(s) the unit's stack needs. Do not hand-rewrite the dispatcher; adjust the "Generated per project" variables at its top (`CONSOLE_KAMAL_ROOT`, `CONSOLE_KAMAL_CONFIG`, `CONSOLE_KAMAL_ROLE`) when the unit sits in a multi-unit repo.

Behavior of the dispatcher (verified by `tests/application-console/run_tests.sh`):

- `bin/console` / `bin/console --local` - REPL in this unit's own environment. `--local` is also exactly what runs inside the container, so remote mode can never recurse.
- `bin/console --remote [-d dest] [-r role] [-c file] [other kamal flags]` runs `kamal app exec -i --reuse <flags> "sh bin/console --local"`. Verified against Kamal 2.12: `-i` = interactive over SSH (`docker exec -it`), `--reuse` = attach to the **running** container (no new container, no second HTTP server, no duplicate workers), interactive exec targets the primary host and the primary role (pick another with `-r`). Flags are forwarded verbatim; stdin/stdout/TTY and the exit code propagate; nothing is piped or captured. It exposes no network endpoint.
- Destination safety: `--remote` never picks a destination silently. If the project has both staging and production configs and no `-d` was given, it refuses. `-d` with local mode is an error (never silently run locally when a destination was asked for).
- It uses `sh`, not `bash`, so it runs in alpine/slim images.

## Mandatory install rules (apply per Kamal-managed unit)

1. **No `bin/console`** -> install the template (+ needed helper). Do this even if other `bin/` wrappers exist, and even if the user didn't ask for the "fuller operational layer".
2. **Existing `bin/console` that is an application-aware console** (starts the app's REPL: `rails c`-like, `tinker`, `iex`, `manage.py shell`, node `repl`, ...) -> read it, keep it. Improve only what is demonstrably missing and without changing flags or meaning.
3. **Existing `bin/console` that is a remote Kamal wrapper** (the Arie layout: `kamal app exec -i ... bin/console`) -> keep its interface (`bin/console` stays remote, no silent change of meaning). Install the template **as `bin/console-local`** (default mode local) and document both. The remote wrapper's in-container command must target `bin/console-local --local` (or the stack's native console); fix it only if it currently launches a shell or the app's start command.
4. **Framework owns `bin/console`** (Symfony: `bin/console` is the framework CLI) -> never overwrite. Install the template as `bin/app-console`.
5. **Unsupported stack** (see recipes: Go, JVM-without-JDK, .NET runtime images, unknown) -> install the template anyway if a dispatcher still helps (it prints the limitation and exits 2), or skip the install and document the alternative from the recipe. Report the limitation in the Step 7 summary; never claim a console exists.
6. `chmod +x`. Ensure the files ship in the image (next section).

## Docker checklist (the console must work in the final image)

Check the unit's Dockerfile (multi-stage included) and fix only what is required for the console:

- `bin/` (including `bin/console.d/`) is copied into the **final** stage and not excluded by `.dockerignore`; executable bit survives `COPY`.
- The final stage contains the interpreter the console needs (it always has the app's own runtime) and **the code the console loads**: compiled `dist/`/`build/` for TypeScript, `node_modules` actually used (production deps). Do not install `tsx`/`ts-node`/a JDK/SDK just for the console; target compiled output instead.
- WORKDIR is the unit root (the dispatcher uses its own location, not the cwd, and `docker exec` starts in WORKDIR).
- The non-root runtime user can read/execute these files and `HOME`/tmp is writable enough for the REPL (history goes to the OS temp dir, optional).
- Environment: the console relies on the container's real env (Kamal injects it at container start). `.env` files are only a local convenience and never override real variables.
- Validate when Docker is available: `docker run --rm -i <image> sh bin/console --local` with `.exit` on stdin (done after the Step 5 build check).

## Acceptance criteria for any console, any stack

Persistent session; expression results shown; errors reported without ending the session; async support where the language allows; multiline via the native REPL; clean exit with resources closed; banner naming app and environment; no HTTP server, migrations, workers or schedulers started; context objects exposed **only if they genuinely exist and initialized**, via the application's own bootstrap/DI (never a parallel reimplementation of config); a project-owned hook (`console.config.cjs` for Node, `console_config.py` for Python) for apps whose real bootstrap the generic detection cannot know.

## Stack strategies

| Stack | Local | In container | Limits |
|---|---|---|---|
| Node.js (plain/Express/Fastify) | `console.d/node.cjs`: native `repl` (top-level `await`, `load()`, CJS+ESM), Prisma `prisma`/`db` when `@prisma/client` is generated, `console.config.*` hook | same file, `sh bin/console --local` | Targets what is in the image: compiled output for TS. No hot reload. TypeORM/other ORMs need the hook (data source config is app-specific) |
| NestJS | `NestFactory.createApplicationContext(AppModule)` from compiled `dist/app.module.js` -> `app`, `get(Token)`; no listener | same | Needs the build output (DI metadata requires `tsc`, not transpile-only runners) |
| Next.js | Node REPL + env + `load()` of server-side modules (compiled or plain JS); Prisma if present | same | Next internals, React server components, route handlers, and `next.config`-aliased imports (`@/...`) cannot be loaded outside the Next runtime; use relative paths or the hook. Standalone images ship only traced files: modules not traced into `.next/standalone` are absent - the console can only load what the image contains |
| Python Django | `manage.py shell` (native, auto-imports models) | same | |
| Python Flask | `flask shell` (app context) when `FLASK_APP`/`wsgi.py` exists, else plain | same | |
| Python FastAPI/plain | `console.d/python.py`: IPython (autoawait) if installed, else stdlib `code`; exposes `app` only if importable | same | Without IPython, use `asyncio.run(...)` for coroutines |
| PHP Laravel | `php artisan tinker` (requires `laravel/tinker` in the production dependencies) | same | Fails clearly if tinker was removed |
| PHP Symfony | `vendor/bin/psysh` via `bin/app-console` (`bin/console` untouched) | same | Needs `psy/psysh` outside `require-dev` for production use |
| Elixir | `iex -S mix` locally | release image: `<release>/bin/<app> remote` (set `CONSOLE_RELEASE_BIN`); attaches to the **running** node, real code and config | Needs the release env (RELEASE_NODE/cookie) which releases set by default |
| Go | none (see recipe) | none | Compiled language: report, offer an explicit project-owned admin subcommand pattern |
| Java/Spring | none by default (see recipe) | none by default | JShell needs a JDK + classpath; JRE-only images cannot run it |
| .NET | none by default (see recipe) | none | No REPL in runtime images |
| Unknown | detect language/framework, choose the best native REPL; else unsupported | | Never a bare shell |

## Multi-unit repos

Each Kamal-managed unit gets its own `<unit>/bin/console` for its own stack. Remote routing follows the deployment boundary decided in `agents/patterns/deployment-boundary.md`:

- Units consolidated in one deployment (roles): set `CONSOLE_KAMAL_ROOT` to the relative path of the directory holding `config/deploy.yml` and `CONSOLE_KAMAL_ROLE` to the unit's role; `-r` forwards through the dispatcher.
- Units in separate Level 3 deployments: also set `CONSOLE_KAMAL_CONFIG=config/deploy.<unit>.yml` per `agents/patterns/multi-service-repo.md`.
- Per-unit wrappers at the repo root (`bin/console-api`, ...) are thin `exec apps/api/bin/console "$@"` forwarders; they must keep forwarding flags verbatim. Make it unambiguous which unit/destination a console targets: the banner names the app, and the remote command prints Kamal's own "Launching interactive command with version ... on <host>" line.
- A worker unit's console exposes the worker's services without starting its job loop (same rule: no side effects at startup).

## Production safety (document, do not block)

A production console can mutate production data exactly like `rails console`. Document that in the project's Deployment section. Do not add arbitrary restrictions on normal administrative use; the only guard is "never silently pick a destination".

## Documentation to generate (Step 6)

```bash
bin/console                      # local REPL
bin/console --remote -d staging  # REPL inside the running staging container
bin/console --remote -d production -r web
```

Document only what the generated scripts do, plus the stack limitations above that apply to this unit.
