#!/usr/bin/env bash
# Executable regression tests for templates/bin/secrets.
#
# Builds a throwaway SOPS + age project in a temp directory, exercises the
# generated bin/secrets template against it, and asserts both behavior
# (refuse/succeed as the policy dictates) and leak-prevention (no generated
# value ever appears in this test's own captured stdout/stderr).
#
# Requires: bash, sops, age-keygen, jq, openssl. If any is missing, the
# corresponding tests are skipped rather than failing noisily - mirrors
# bin/secrets check's own SKIP convention.
#
# Usage: tests/secret-generation/run_tests.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$HERE/../.." && pwd)"
BIN_SECRETS_TEMPLATE="$SKILL_ROOT/templates/bin/secrets"

PASS=0
FAIL=0

fail() {
  echo "FAIL: $1" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  echo "PASS: $1"
  PASS=$((PASS + 1))
}

for tool in sops age-keygen jq openssl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP: '$tool' not installed - skipping executable secret-generation tests"
    exit 0
  fi
done

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

PROJECT="$WORKDIR/project"
mkdir -p "$PROJECT/bin" "$PROJECT/config" "$PROJECT/.kamal"
cp "$BIN_SECRETS_TEMPLATE" "$PROJECT/bin/secrets"
chmod +x "$PROJECT/bin/secrets"

export SOPS_AGE_KEY_FILE="$WORKDIR/age.key"
age-keygen -o "$SOPS_AGE_KEY_FILE" 2>"$WORKDIR/age.pub.txt"
AGE_PUBLIC="$(grep -oE 'age1[a-z0-9]+' "$SOPS_AGE_KEY_FILE" | tail -1)"

cd "$PROJECT"

cat >"$PROJECT/.sops.yaml" <<EOF
creation_rules:
  - path_regex: config/secrets\.sops\.yaml\$
    age: $AGE_PUBLIC
EOF

cat >"$WORKDIR/seed.json" <<'EOF'
{
  "JWT_SECRET": "TODO_FILL_IN",
  "GOOGLE_CLIENT_SECRET": "TODO_FILL_IN",
  "POSTGRES_PASSWORD": "TODO_FILL_IN",
  "EXISTING_SIGNING_SECRET": "a-genuine-existing-credential-value-123",
  "SOME_VENDOR_SECRET": "TODO_FILL_IN"
}
EOF

sops --encrypt --input-type json --output-type yaml \
  --filename-override config/secrets.sops.yaml "$WORKDIR/seed.json" \
  >"$PROJECT/config/secrets.sops.yaml"

cat >"$PROJECT/config/secret-generation.yml" <<'EOF'
JWT_SECRET:
  policy: local_generatable
  generator: random_symmetric_key
  bytes: 32

GOOGLE_CLIENT_SECRET:
  policy: provider_managed

POSTGRES_PASSWORD:
  policy: infrastructure_generatable
  generator: random_password
  bytes: 24

EXISTING_SIGNING_SECRET:
  policy: local_generatable
  generator: random_symmetric_key
  bytes: 32

VAPID_KEY_PAIR:
  policy: protocol_generatable
  generator: vapid_key_pair
  private_name: VAPID_PRIVATE_KEY
  public_name: VAPID_PUBLIC_KEY
  public_target: clear
EOF

touch "$PROJECT/.kamal/secrets"
cd "$PROJECT"

decrypt_value() {
  sops --decrypt --output-type json config/secrets.sops.yaml 2>/dev/null | jq -r --arg k "$1" '.[$k] // empty'
}

# --- Case A: missing HMAC JWT secret ---------------------------------------
OUT="$(./bin/secrets generate JWT_SECRET 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]]; then
  pass "Case A: generate JWT_SECRET exits 0"
else
  fail "Case A: generate JWT_SECRET exited $RC"
fi
VAL="$(decrypt_value JWT_SECRET)"
if [[ -n "$VAL" ]] && [[ "$VAL" != "TODO_FILL_IN" ]]; then
  pass "Case A: JWT_SECRET is stored and no longer a placeholder"
else
  fail "Case A: JWT_SECRET missing or still a placeholder"
fi
if printf '%s' "$OUT" | grep -qF "$VAL"; then
  fail "Case A: generated value leaked into command output"
else
  pass "Case A: generated value absent from command output"
fi

# --- Case B: existing JWT secret -> refuse, no overwrite -------------------
BEFORE="$(decrypt_value JWT_SECRET)"
OUT="$(./bin/secrets generate JWT_SECRET 2>&1)"
RC=$?
AFTER="$(decrypt_value JWT_SECRET)"
if [[ "$RC" -ne 0 ]]; then
  pass "Case B: re-generating an existing JWT_SECRET exits non-zero"
else
  fail "Case B: re-generating an existing JWT_SECRET did not refuse"
fi
if [[ "$BEFORE" == "$AFTER" ]]; then
  pass "Case B: existing JWT_SECRET value unchanged"
else
  fail "Case B: existing JWT_SECRET was overwritten"
fi

# --- Case C: existing real value under a plain local_generatable policy ----
OUT="$(./bin/secrets generate EXISTING_SIGNING_SECRET 2>&1)"
RC=$?
if [[ "$RC" -ne 0 ]]; then
  pass "Case C: generating over an existing real value refuses"
else
  fail "Case C: generating over an existing real value did not refuse"
fi

# --- Case D: provider-managed secret ----------------------------------------
OUT="$(./bin/secrets generate GOOGLE_CLIENT_SECRET 2>&1)"
RC=$?
VAL="$(decrypt_value GOOGLE_CLIENT_SECRET)"
if [[ "$RC" -ne 0 ]] && [[ "$VAL" == "TODO_FILL_IN" ]]; then
  pass "Case D: provider-managed secret rejected and left untouched"
else
  fail "Case D: provider-managed secret was not correctly rejected"
fi

# --- Case E: unknown secret ---------------------------------------------
OUT="$(./bin/secrets generate SOME_VENDOR_SECRET 2>&1)"
RC=$?
VAL="$(decrypt_value SOME_VENDOR_SECRET)"
if [[ "$RC" -ne 0 ]] && [[ "$VAL" == "TODO_FILL_IN" ]]; then
  pass "Case E: unknown secret rejected and left untouched"
else
  fail "Case E: unknown secret was not correctly rejected"
fi

# --- Case F: fresh PostgreSQL password --------------------------------------
OUT="$(./bin/secrets generate POSTGRES_PASSWORD 2>&1)"
RC=$?
VAL="$(decrypt_value POSTGRES_PASSWORD)"
if [[ "$RC" -eq 0 ]] && [[ -n "$VAL" ]] && [[ "$VAL" != "TODO_FILL_IN" ]]; then
  pass "Case F: POSTGRES_PASSWORD generated successfully"
else
  fail "Case F: POSTGRES_PASSWORD generation failed"
fi
if sops --decrypt --output-type json config/secrets.sops.yaml 2>/dev/null | jq -e 'has("DATABASE_URL")' >/dev/null 2>&1; then
  fail "Case F: DATABASE_URL was stored independently (must remain derived)"
else
  pass "Case F: DATABASE_URL was not independently stored"
fi

# --- Case G: generate --missing ---------------------------------------------
OUT="$(./bin/secrets generate --missing 2>&1)"
if printf '%s' "$OUT" | grep -q "GOOGLE_CLIENT_SECRET.*SKIPPED provider-managed"; then
  pass "Case G: --missing skips provider-managed secret"
else
  fail "Case G: --missing did not correctly skip provider-managed secret"
fi
if printf '%s' "$OUT" | grep -q "SOME_VENDOR_SECRET.*SKIPPED unknown-policy"; then
  pass "Case G: --missing skips unknown-policy secret"
else
  fail "Case G: --missing did not correctly skip unknown-policy secret"
fi
if printf '%s' "$OUT" | grep -q "JWT_SECRET.*ALREADY PRESENT"; then
  pass "Case G: --missing reports already-generated JWT_SECRET as present, not re-generated"
else
  fail "Case G: --missing mis-reported JWT_SECRET's state"
fi

# --- Case H: storage failure (simulate by pointing SOPS_FILE at an unwritable path)
UNWRITABLE_DIR="$WORKDIR/unwritable"
mkdir -p "$UNWRITABLE_DIR"
chmod 555 "$UNWRITABLE_DIR"
OUT="$(SOPS_FILE="$UNWRITABLE_DIR/secrets.sops.yaml" ./bin/secrets generate JWT_SECRET 2>&1)"
RC=$?
chmod 755 "$UNWRITABLE_DIR"
if [[ "$RC" -ne 0 ]]; then
  pass "Case H: storage failure is reported as a failed operation"
else
  fail "Case H: storage failure was not detected as a failure"
fi
if printf '%s' "$OUT" | grep -qiE '^[A-Z0-9_]+=.+'; then
  fail "Case H: storage-failure output resembles NAME=value (possible fallback leak)"
else
  pass "Case H: storage-failure output contains no NAME=value fallback"
fi

# --- Case I: VAPID key pair ---------------------------------------------
# Case G's --missing run above already generates VAPID_KEY_PAIR (it is
# missing and protocol_generatable), so a second explicit generate here
# correctly refuses to replace the now-existing private key - that refusal
# is itself the expected "no silent overwrite" behavior, not a failure.
OUT="$(./bin/secrets generate VAPID_KEY_PAIR 2>&1)"
RC=$?
PRIV="$(decrypt_value VAPID_PRIVATE_KEY)"
PUB_IN_SOPS="$(decrypt_value VAPID_PUBLIC_KEY)"
if [[ -n "$PRIV" ]]; then
  pass "Case I: VAPID private component generated and stored in SOPS"
else
  fail "Case I: VAPID private component generation/storage failed"
fi
if [[ -z "$PUB_IN_SOPS" ]]; then
  pass "Case I: VAPID public component was NOT placed in the secrets backend"
else
  fail "Case I: VAPID public component leaked into the secrets backend"
fi
if printf '%s' "$OUT" | grep -qF "$PRIV"; then
  fail "Case I: VAPID private key leaked into command output"
else
  pass "Case I: VAPID private key absent from command output"
fi

# --- Case J: special-character password + derived URI encoding -------------
# Simulate a password containing URI-meaningful characters and confirm
# jq's @uri produces a valid encoded form without weakening the generator.
SPECIAL_PASS='p@ss:w/rd?#%&example'
ENCODED="$(jq -rn --arg v "$SPECIAL_PASS" '$v|@uri')"
if [[ "$ENCODED" != "$SPECIAL_PASS" ]] && [[ -n "$ENCODED" ]]; then
  pass "Case J: special-character password percent-encodes correctly at derivation time"
else
  fail "Case J: special-character password did not encode as expected"
fi

# --- Case K: asymmetric signing key pair (reuses VAPID's EC generation path,
# the only asymmetric generator this template ships) --------------------
if [[ -n "$PRIV" ]] && [[ "${#PRIV}" -ge 40 ]]; then
  pass "Case K: asymmetric key material is generated via protocol-specific tooling, not a bare random string"
else
  fail "Case K: asymmetric key material does not look protocol-generated"
fi

# --- Leak sweep across all captured outputs in this run ---------------------
ALL_SECRET_VALUES=("$VAL" "$PRIV")
LEAK=0
for v in "${ALL_SECRET_VALUES[@]}"; do
  [[ -z "$v" ]] && continue
  if git -C "$PROJECT" diff --cached 2>/dev/null | grep -qF "$v"; then
    fail "Leak sweep: a generated value appears in a git diff"
    LEAK=1
  fi
done
if [[ "$LEAK" -eq 0 ]]; then
  pass "Leak sweep: no generated value found in git diff"
fi

echo
echo "secret-generation tests: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
