# Application console - expected agent behavior

Executable checks for the generated scripts live in `tests/application-console/run_tests.sh`. This file pins the *decisions* the agent must make (cannot be executed without an LLM). Each case: repo state -> required outcome.

1. **Node.js, no `bin/` at all** -> create `bin/deploy` **and** `bin/console` (+ `bin/console.d/node.cjs`), mode 755. Do not ask whether the user wants the console.
2. **Node.js, `bin/deploy` and `bin/setup` exist, no `bin/console`** -> existing wrappers untouched; `bin/console` is still created.
3. **Existing functional app-aware `bin/console`** (starts the app's REPL) -> read it, do not overwrite; at most make minimal compatible improvements.
4. **Existing remote-wrapper `bin/console`** (`kamal app exec -i ... bin/console`) -> its meaning does not change; template installed as `bin/console-local`; docs describe both.
5. **CommonJS / ESM** -> both loadable (`require` / `load()`); never emit a `require`-only instruction for an ESM project.
6. **TypeScript with compiled production output** -> console targets `dist/`; no `tsx`/`ts-node` added to the production image; Dockerfile final stage copies `bin/` and `dist/`.
7. **Python (Django / Flask / FastAPI)** -> Django `manage.py shell`, Flask `flask shell`, FastAPI via `console.d/python.py`.
8. **Multi-service repo with mixed stacks** -> every Kamal-managed unit has its own `<unit>/bin/console` for its own stack; consolidated units use `CONSOLE_KAMAL_ROLE`, Level 3 units also `CONSOLE_KAMAL_CONFIG`; existing deployment-boundary and wrapper naming are untouched.
9. **Symfony** -> `bin/console` never overwritten; template installed as `bin/app-console`.
10. **Go / JVM-without-JDK / .NET / unknown** -> no fake shell; limitation reported in the Step 7 summary; the recipe's honest alternative offered, not silently implemented.
11. **Docs** -> `bin/console` and `bin/console --remote -d <dest>` documented, plus the production-mutation warning; nothing documented that the script doesn't do.
