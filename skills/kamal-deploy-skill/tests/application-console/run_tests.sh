#!/usr/bin/env bash
# Executable regression tests for templates/bin/console (+ console.d/*).
# Builds throwaway fixture projects in a temp dir, installs the template the way the
# Skill does, then actually starts the console with piped stdin and checks behavior.
# No network, database, deployment or real credentials. Missing runtimes => SKIP (reported
# separately from PASS; a skipped test never counts as passing).
# Usage: tests/application-console/run_tests.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$(cd "$HERE/../../templates/bin" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; SKIP=0
ok()   { echo "PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL: $1" >&2; [ -n "${2:-}" ] && { echo "----- output -----" >&2; echo "$2" >&2; }; FAIL=$((FAIL+1)); }
skip() { echo "SKIP: $1 ($2)"; SKIP=$((SKIP+1)); }
has()  { command -v "$1" >/dev/null 2>&1; }
contains() { case "$1" in *"$2"*) return 0;; esac; return 1; }

install_console() { # dir [name]
  mkdir -p "$1/bin/console.d"; cp "$TPL/console" "$1/bin/${2:-console}"; chmod +x "$1/bin/${2:-console}"
  cp "$TPL"/console.d/* "$1/bin/console.d/"
}
# Feed lines one at a time (like a human typing) so async `await` lines finish before the next one.
paced() { while IFS= read -r l; do printf '%s\n' "$l"; sleep 0.4; done; }
run() { # dir input [script]
  (cd "$1" && printf '%s\n' "$2" | paced | timeout 40 "bin/${3:-console}" 2>&1); }

# ---------------------------------------------------------------- Node.js
if has node; then
  d="$TMP/cjs"; mkdir -p "$d/lib"; install_console "$d"
  echo '{"name":"cjs-app"}' > "$d/package.json"
  echo 'module.exports = { greet: (n) => "hi " + n };' > "$d/lib/svc.js"
  out="$(run "$d" $'1 + 1\nconst a = 41\na + 1\nconst s = require("./lib/svc.js")\ns.greet("x")\nawait Promise.resolve(7)\nthrow new Error("boom")\n"still alive"\n.exit')"; rc=$?
  if contains "$out" "cjs-app console" && contains "$out" "42" && contains "$out" "'hi x'" \
     && contains "$out" "boom" && contains "$out" "'still alive'" && [ $rc -eq 0 ]; then
    ok "node CommonJS: expressions, persistent vars, require, top-level await, error survives, clean exit"
  else bad "node CommonJS console" "$out"; fi

  d="$TMP/esm"; mkdir -p "$d/lib"; install_console "$d"
  echo '{"name":"esm-app","type":"module"}' > "$d/package.json"
  echo 'export const answer = () => 42; export default { v: 1 };' > "$d/lib/svc.js"
  out="$(run "$d" $'const m = await load("./lib/svc.js")\nm.answer()\nconst n = await import("./lib/svc.js")\nn.default.v\n.exit')"
  if contains "$out" "esm-app console" && contains "$out" "42" && contains "$out" "> 1" && ! contains "$out" "ERR_REQUIRE_ESM"; then
    ok "node ESM: load() and dynamic import() reach application modules"
  else bad "node ESM console" "$out"; fi

  d="$TMP/ts"; mkdir -p "$d/dist/users"; install_console "$d"
  echo '{"name":"ts-app"}' > "$d/package.json"
  cat > "$d/dist/users/users.service.js" <<'JS'
exports.UsersService = class { findById(id) { return { id, email: "u" + id + "@example.com" }; } };
JS
  cat > "$d/console.config.cjs" <<'JS'
module.exports = async ({ load }) => {
  const { UsersService } = await load("./dist/users/users.service.js");
  return { context: { usersService: new UsersService() }, close: async () => { require("fs").writeFileSync(".closed", "1"); } };
};
JS
  out="$(run "$d" $'usersService.findById(42).email\n.exit')"
  if contains "$out" "u42@example.com" && [ -f "$d/.closed" ]; then
    ok "node TypeScript (compiled dist/): hook-provided service reachable, close() ran on exit"
  else bad "node TypeScript compiled console" "$out"; fi

  d="$TMP/nest"; mkdir -p "$d/dist" "$d/node_modules/@nestjs/core"; install_console "$d"
  echo '{"name":"nest-app","dependencies":{"@nestjs/core":"*"}}' > "$d/package.json"
  echo '{"sourceRoot":"src"}' > "$d/nest-cli.json"
  echo '{"name":"@nestjs/core","main":"index.js"}' > "$d/node_modules/@nestjs/core/package.json"
  cat > "$d/node_modules/@nestjs/core/index.js" <<'JS'
exports.NestFactory = { async createApplicationContext(m, o) {
  if (m.name !== "AppModule") throw new Error("wrong module");
  return { get: (t) => new t(), close: async () => require("fs").writeFileSync(".nest-closed", "1"), listen: () => { throw new Error("must not listen"); } };
} };
JS
  cat > "$d/dist/app.module.js" <<'JS'
class Svc { who() { return "nest-service"; } }
class AppModule {}
exports.AppModule = AppModule; exports.Svc = Svc;
JS
  out="$(run "$d" $'const { Svc } = await load("./dist/app.module.js")\nget(Svc).who()\n.exit')"
  if contains "$out" "NestJS application context" && contains "$out" "nest-service" && [ -f "$d/.nest-closed" ]; then
    ok "NestJS: DI application context (no listener), get(Provider) works, app.close() on exit"
  else bad "NestJS console" "$out"; fi

  d="$TMP/nest-nobuild"; mkdir -p "$d/node_modules/@nestjs/core"; install_console "$d"
  echo '{"name":"n2"}' > "$d/package.json"; echo '{"name":"@nestjs/core","main":"index.js"}' > "$d/node_modules/@nestjs/core/package.json"; echo '' > "$d/node_modules/@nestjs/core/index.js"
  out="$(run "$d" '.exit')"
  contains "$out" "no compiled app.module.js" && ok "NestJS without dist/: explicit note, REPL still usable" || bad "NestJS missing build" "$out"

  d="$TMP/env"; install_console "$d"; echo '{"name":"env-app"}' > "$d/package.json"; printf 'FOO=fromfile\nBAR=fromfile\n' > "$d/.env"
  out="$( cd "$d" && printf '%s\n%s\n' 'process.env.FOO + "/" + process.env.BAR' '.exit' | paced | FOO=real timeout 30 bin/console 2>&1)"
  contains "$out" "'real/fromfile'" && ok "node: .env fills gaps but never overrides real environment" || bad "node env handling" "$out"
else
  for t in "node CommonJS" "node ESM" "node TypeScript" "NestJS"; do skip "$t" "node not installed"; done
fi

# ---------------------------------------------------------------- Python
if has python3; then
  d="$TMP/py"; mkdir -p "$d/pkg"; install_console "$d"
  echo 'flask-free' > "$d/requirements.txt"
  echo 'def total(xs): return sum(xs)' > "$d/pkg/svc.py"
  out="$(cd "$d" && printf '%s\n' 'x = 20' 'x + 1' 'from pkg.svc import total' 'total([1,2,3])' '1/0' '"alive"' 'exit()' | PYTHON=python3 timeout 30 bin/console 2>&1)"; rc=$?
  if contains "$out" "py console" && contains "$out" "21" && contains "$out" "6" && contains "$out" "ZeroDivisionError" && contains "$out" "'alive'" && [ $rc -eq 0 ]; then
    ok "python: expressions, persistent vars, project import, error survives, clean exit"
  else bad "python console" "$out"; fi
else skip "python console" "python3 not installed"; fi

# ---------------------------------------------------------------- Remote dispatch (fake kamal)
mkdir -p "$TMP/fakebin"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$KAMAL_ARGS_OUT"; exit "${FAKE_KAMAL_EXIT:-0}"\n' > "$TMP/fakebin/kamal"
chmod +x "$TMP/fakebin/kamal"
d="$TMP/remote"; mkdir -p "$d/config"; install_console "$d"; echo '{"name":"r"}' > "$d/package.json"
touch "$d/config/deploy.yml" "$d/config/deploy.staging.yml" "$d/config/deploy.production.yml"
export KAMAL_ARGS_OUT="$TMP/kamal.args"
(cd "$d" && PATH="$TMP/fakebin:$PATH" bin/console --remote -d staging -q >/dev/null 2>&1); rc=$?
args="$(tr '\n' ' ' < "$KAMAL_ARGS_OUT")"
[ "$args" = "app exec -i --reuse -d staging -q sh bin/console --local " ] && [ $rc -eq 0 ] \
  && ok "remote: kamal app exec -i --reuse, flags forwarded verbatim, in-container command is --local (no recursion)" || bad "remote dispatch args: '$args' rc=$rc"
(cd "$d" && PATH="$TMP/fakebin:$PATH" bin/console --remote >/dev/null 2>&1); rc=$?
[ $rc -ne 0 ] && ok "remote: refuses to guess a destination when staging+production exist" || bad "remote without destination should refuse"
(cd "$d" && PATH="$TMP/fakebin:$PATH" FAKE_KAMAL_EXIT=7 bin/console --remote -d production >/dev/null 2>&1); rc=$?
[ $rc -eq 7 ] && ok "remote: kamal's exit code propagates" || bad "exit code not propagated (got $rc)"
(cd "$d" && PATH="$TMP/fakebin:$PATH" bin/console -d staging >/dev/null 2>&1); rc=$?
[ $rc -ne 0 ] && ok "local mode rejects -d (never silently runs locally when a destination was requested)" || bad "local mode accepted -d"

m="$TMP/mono"; mkdir -p "$m/config" "$m/apps/api" "$m/apps/ml"; touch "$m/config/deploy.api.yml"
install_console "$m/apps/api"; install_console "$m/apps/ml"
echo '{"name":"api"}' > "$m/apps/api/package.json"; echo 'x' > "$m/apps/ml/requirements.txt"
sed -i 's|^CONSOLE_KAMAL_ROOT=.*|CONSOLE_KAMAL_ROOT="${CONSOLE_KAMAL_ROOT:-../..}"|; s|^CONSOLE_KAMAL_CONFIG=.*|CONSOLE_KAMAL_CONFIG="${CONSOLE_KAMAL_CONFIG:-config/deploy.api.yml}"|; s|^CONSOLE_KAMAL_ROLE=.*|CONSOLE_KAMAL_ROLE="${CONSOLE_KAMAL_ROLE:-web}"|' "$m/apps/api/bin/console"
(cd "$m" && PATH="$TMP/fakebin:$PATH" apps/api/bin/console --remote >/dev/null 2>&1)
args="$(tr '\n' ' ' < "$KAMAL_ARGS_OUT")"
[ "$args" = "app exec -i --reuse -c config/deploy.api.yml -r web sh bin/console --local " ] \
  && ok "multi-unit: unit wrapper injects its own -c/-r and runs kamal from the config root" || bad "multi-unit remote args: '$args'"
if has node && has python3; then
  o1="$(cd "$m" && printf '.exit\n' | apps/api/bin/console 2>&1)"; o2="$(cd "$m" && printf 'exit()\n' | PYTHON=python3 apps/ml/bin/console 2>&1)"
  contains "$o1" "api console" && contains "$o2" "ml console" && ok "multi-unit mixed stacks: each unit starts its own stack's REPL" || bad "mixed stacks" "$o1 / $o2"
else skip "multi-unit mixed stacks" "node/python3 missing"; fi

# ---------------------------------------------------------------- Unsupported stacks are reported, never faked
d="$TMP/go"; install_console "$d"; echo 'module x' > "$d/go.mod"
out="$(run "$d" "" )"; rc=$?
out2="$(cd "$d" && bin/console 2>&1 </dev/null)"; rc=$?
[ $rc -eq 2 ] && contains "$out2" "no application-aware REPL" && contains "$out2" "refusing to fall back to a plain shell" \
  && ok "Go: explicit unsupported report (exit 2), no shell fallback" || bad "Go unsupported handling (rc=$rc)" "$out2"
d="$TMP/unknown"; install_console "$d"; (cd "$d" && bin/console >/dev/null 2>&1 </dev/null); rc=$?
[ $rc -eq 2 ] && ok "unrecognized stack: unsupported report, no shell fallback" || bad "unknown stack rc=$rc"

# ---------------------------------------------------------------- Symfony: bin/console is the framework's own CLI
d="$TMP/symfony"; mkdir -p "$d/bin" "$d/vendor/bin"; echo '#!/usr/bin/env php' > "$d/bin/console"; chmod +x "$d/bin/console"
echo '{"require":{"symfony/framework-bundle":"*"}}' > "$d/composer.json"
cp "$TPL/console" "$d/bin/app-console"; chmod +x "$d/bin/app-console"
before="$(cat "$d/bin/console")"
out="$(cd "$d" && bin/app-console 2>&1 </dev/null)"; rc=$?
[ "$(cat "$d/bin/console")" = "$before" ] && [ $rc -eq 2 ] && contains "$out" "PsySH" \
  && ok "Symfony: framework bin/console untouched; app-console reports missing PsySH instead of faking" || bad "Symfony handling rc=$rc" "$out"

# ---------------------------------------------------------------- Template hygiene
sh -n "$TPL/console" && ok "template is valid POSIX sh (runs on alpine/slim images without bash)" || bad "sh -n failed"
! grep -qE '^\s*exec (ba)?sh\b' "$TPL/console" && ok "template never execs a bare shell as the console" || bad "template execs a shell"

# ---------------------------------------------------------------- Container execution (optional)
img=""
if has docker; then for i in node:20-alpine node:22-alpine node:20-slim node:22-slim; do docker image inspect "$i" >/dev/null 2>&1 && { img="$i"; break; }; done; fi
if [ -n "$img" ]; then
  d="$TMP/cont"; mkdir -p "$d/dist"; install_console "$d"
  echo '{"name":"cont-app"}' > "$d/package.json"; echo 'module.exports={n:()=>"in-container"};' > "$d/dist/m.js"; chmod -R a+rX "$d"
  out="$(printf 'require("./dist/m.js").n()\n.exit\n' | paced | docker run --rm -i -v "$d:/app:ro" -w /app -u 1000:1000 "$img" sh bin/console --local 2>&1)"
  contains "$out" "in-container" && ok "container ($img, non-root): console runs via sh bin/console --local" || bad "container console" "$out"
else skip "container execution" "docker or a local node image not available"; fi

echo; echo "passed: $PASS  failed: $FAIL  skipped: $SKIP"
[ "$FAIL" -eq 0 ]
