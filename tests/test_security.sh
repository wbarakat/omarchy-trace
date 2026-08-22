#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
API="$ROOT/scripts/trace-api.sh"
TMP=$(mktemp -d)
BIN="$TMP/bin"
TEST_TOKEN="trace-test-token-${RANDOM}${RANDOM}"
mkdir -p -- "$BIN"
trap 'rm -rf -- "$TMP"' EXIT

# A local stand-in lets this test exercise configure without touching a user's keyring.
cat >"$BIN/secret-tool" <<'SH'
#!/usr/bin/env bash
set -e
case "${1:-}" in
  store) IFS= read -r token || :; [ "$token" = '__TEST_TOKEN__' ]; exit;;
  lookup) printf '%s\n' '__TEST_TOKEN__'; exit;;
  clear) exit;;
  *) exit 1;;
esac
SH
sed -i "s/__TEST_TOKEN__/$TEST_TOKEN/g" "$BIN/secret-tool"
chmod 700 -- "$BIN/secret-tool"

CONFIG="$TMP/config" CACHE="$TMP/cache"
mkdir -p -- "$CONFIG" "$CACHE"
mkdir -p -- "$CACHE/trace"
printf '%s\n' 'old organization data' >"$CACHE/trace/list.json"
output=$(printf '%s\n' "$TEST_TOKEN" | PATH="$BIN:$PATH" XDG_CONFIG_HOME="$CONFIG" XDG_CACHE_HOME="$CACHE" "$API" configure --base-url https://sentry.example.test --organization acme --projects web,api --token-stdin)
printf '%s\n' "$output" | jq -e '.schemaVersion == 1 and .state == "ready"' >/dev/null
config_file="$CONFIG/trace/config.json"
[ "$(stat -c %a "$config_file")" = 600 ]
! grep -Fq "$TEST_TOKEN" "$config_file"
[ ! -e "$CACHE/trace/list.json" ]
printf '%s\n' 'current organization data' >"$CACHE/trace/list.json"
clear_output=$(PATH="$BIN:$PATH" XDG_CONFIG_HOME="$CONFIG" XDG_CACHE_HOME="$CACHE" "$API" clear-token)
printf '%s\n' "$clear_output" | jq -e '.state == "ready" and .action == "clear-token"' >/dev/null
[ ! -e "$config_file" ]
[ ! -e "$CACHE/trace/list.json" ]

# Exercise the exact one-line JSON contract used by Service.qml as well as the
# CLI form above. Neither path may persist the token outside the keyring.
JSON_CONFIG="$TMP/json-config"
mkdir -p -- "$JSON_CONFIG"
setup_json=$(jq -cn --arg token "$TEST_TOKEN" '{baseUrl:"https://sentry.example.test",organization:"acme",projects:"web, api",environments:["production","us east"],token:$token}')
json_output=$(printf '%s\n' "$setup_json" | PATH="$BIN:$PATH" XDG_CONFIG_HOME="$JSON_CONFIG" XDG_CACHE_HOME="$CACHE" "$API" configure --token-stdin)
printf '%s\n' "$json_output" | jq -e '.state == "ready" and .configured == true' >/dev/null
! grep -Fq "$TEST_TOKEN" "$JSON_CONFIG/trace/config.json"
jq -e '.projects == ["web", "api"]' "$JSON_CONFIG/trace/config.json" >/dev/null
jq -e '.environments == ["production", "us east"]' "$JSON_CONFIG/trace/config.json" >/dev/null

# URL filters are encoded and repeated rather than interpolated raw.
grep -qE 'project=\$\(urlencode "\$project"\)' "$ROOT/scripts/trace-api.sh"
grep -qE 'environment=\$\(urlencode "\$environment"\)' "$ROOT/scripts/trace-api.sh"
grep -q 'expand=inbox' "$ROOT/scripts/trace-api.sh"
grep -qE 'review\) payload=.*hasSeen.*inbox' "$ROOT/scripts/trace-api.sh"

! grep -R -nE 'Bearer[[:space:]]+[A-Za-z0-9._-]{20,}' "$ROOT/scripts" "$ROOT/fixtures"

bad=$(XDG_CONFIG_HOME="$CONFIG" XDG_CACHE_HOME="$CACHE" TRACE_DEMO=1 "$API" detail '../secret' || true)
printf '%s\n' "$bad" | jq -e '.state == "error" and .error.code == "invalid-input"' >/dev/null

printf 'test_security.sh: ok\n'
