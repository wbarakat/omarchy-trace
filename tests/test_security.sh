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

# curl receives the bearer header only through stdin. Its argv contains a
# response cap and never points at a token-bearing config file.
cat >"$BIN/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
config=$(cat)
grep -Fq 'Authorization: Bearer __TEST_TOKEN__' <<<"$config"
output="" max="" config_source=""
printf '%s\n' "$*" >"$TRACE_TEST_CURL_ARGS"
[ -z "${TRACE_TEST_CURL_CONFIG:-}" ] || printf '%s' "$config" >"$TRACE_TEST_CURL_CONFIG"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) config_source=${2:-}; shift 2;;
    --max-filesize) max=${2:-}; shift 2;;
    --output) output=${2:-}; shift 2;;
    --write-out) shift 2;;
    *) shift;;
  esac
done
[ "$config_source" = - ]
[ "$max" = "${TRACE_TEST_EXPECT_MAX:-65536}" ]
[ -n "$output" ]
if [ "${TRACE_TEST_FAIL:-0}" = 1 ]; then
  exit 7
elif [ "${TRACE_TEST_OVERSIZE:-0}" = 1 ]; then
  head -c 65537 /dev/zero | tr '\0' x >"$output"
elif [ "${TRACE_TEST_MULTI_JSON:-0}" = 1 ]; then
  printf '[]\n[]\n' >"$output"
elif [ "${TRACE_TEST_DETAIL:-0}" = 1 ]; then
  if grep -Fq '/events/latest/' <<<"$config"; then
    jq -cn '
      ("x" * 2000) as $long |
      {entries:([{type:"exception",data:{values:[{stacktrace:{frames:[range(0;1000) |
        {filename:(if . < 100 then $long else ("frame-" + (.|tostring)) end),function:(if . < 100 then $long else "run" end),module:(if . < 100 then $long else "app" end),lineNo:.,context_line:(if . == 0 then {nested:[range(0;1000)]} elif . < 100 then $long else "source" end),inApp:true,vars:{secret:[range(0;100)]}}]}}]}}]
        + [range(1;1000) | {type:"message",data:{value:.}}]),
       tags:[range(0;1000) | {key:(if . < 100 then $long else ("tag-" + (.|tostring)) end),value:(if . == 0 then {nested:[range(0;1000)]} elif . < 100 then $long else (.|tostring) end)}],
       breadcrumbs:{values:[range(0;1000) |
         {timestamp:(if . < 100 then $long else "2026-08-23T00:00:00Z" end),category:(if . < 100 then $long else "test" end),level:(if . < 100 then $long else "info" end),message:(if . == 0 then {nested:[range(0;1000)]} elif . < 100 then $long else ("crumb-" + (.|tostring)) end)}]}}
    ' >"$output"
  else
    jq -cn '{id:"123",shortId:"WEB-123",title:"Bounded detail",project:{slug:"web"},metadata:
      (reduce range(0;1000) as $i ({}; .[("provider-" + ($i|tostring))] = {nested:[range(0;100)]})
       + {type:"Error",value:"boom",filename:"app.js",function:"run"})}' >"$output"
  fi
elif [ "${TRACE_TEST_MANY_ISSUES:-0}" = 1 ]; then
  # A compact provider array stays well under the wire cap but would expand
  # dramatically if every sparse item were normalized before slicing.
  jq -cn '[range(0;1000) | {id:(.|tostring)}]' >"$output"
else
  printf '[]\n' >"$output"
fi
printf '200'
SH
sed -i "s/__TEST_TOKEN__/$TEST_TOKEN/g" "$BIN/curl"
chmod 700 -- "$BIN/curl"

CURL_CONFIG="$TMP/curl-config"
CURL_CACHE="$TMP/curl-cache"
mkdir -p -- "$CURL_CONFIG" "$CURL_CACHE"
printf '%s\n' "$TEST_TOKEN" | PATH="$BIN:$PATH" XDG_CONFIG_HOME="$CURL_CONFIG" XDG_CACHE_HOME="$CURL_CACHE" \
  "$API" configure --base-url https://sentry.example.test --organization acme --token-stdin >/dev/null
curl_output=$(PATH="$BIN:$PATH" XDG_CONFIG_HOME="$CURL_CONFIG" XDG_CACHE_HOME="$CURL_CACHE" \
  TRACE_CURL_BIN="$BIN/curl" TRACE_MAX_RESPONSE_BYTES=65536 TRACE_TEST_CURL_ARGS="$TMP/curl-args" "$API" list 10)
jq -e '.state == "ready" and (.issues | length) == 0' <<<"$curl_output" >/dev/null
! grep -Fq "$TEST_TOKEN" "$TMP/curl-args"
grep -Fq -- '--config -' "$TMP/curl-args"
grep -Fq -- '--max-filesize 65536' "$TMP/curl-args"
if grep -nE 'jq .*Bearer|--arg[^[:cntrl:]]*\$token' "$ROOT/scripts/trace-api.sh"; then
  printf 'token must not enter formatter process arguments\n' >&2
  exit 1
fi

many_output=$(PATH="$BIN:$PATH" XDG_CONFIG_HOME="$CURL_CONFIG" XDG_CACHE_HOME="$CURL_CACHE" \
  TRACE_CURL_BIN="$BIN/curl" TRACE_MAX_RESPONSE_BYTES=65536 TRACE_TEST_CURL_ARGS="$TMP/curl-args" \
  TRACE_TEST_MANY_ISSUES=1 "$API" list 10)
jq -e '(.issues | length) == 10 and .issues[0].id == "0" and .issues[9].id == "9"' <<<"$many_output" >/dev/null

multi_json_output=$(PATH="$BIN:$PATH" XDG_CONFIG_HOME="$CURL_CONFIG" XDG_CACHE_HOME="$CURL_CACHE" \
  TRACE_CURL_BIN="$BIN/curl" TRACE_MAX_RESPONSE_BYTES=65536 TRACE_TEST_CURL_ARGS="$TMP/curl-args" \
  TRACE_TEST_MULTI_JSON=1 "$API" list 10 || :)
jq -e '.state == "error" and .error.code == "api-error"' <<<"$multi_json_output" >/dev/null

# Detail normalization must bound every provider array before mapping it. It
# also keeps only fixed scalar metadata and deliberately drops arbitrary frame
# variables, preventing recursive object amplification.
detail_output=$(PATH="$BIN:$PATH" XDG_CONFIG_HOME="$CURL_CONFIG" XDG_CACHE_HOME="$CURL_CACHE" \
  TRACE_CURL_BIN="$BIN/curl" TRACE_MAX_RESPONSE_BYTES=4194304 TRACE_TEST_EXPECT_MAX=4194304 \
  TRACE_TEST_CURL_ARGS="$TMP/curl-args" TRACE_TEST_DETAIL=1 "$API" detail 123)
jq -e '
  .state == "ready" and .issue.id == "123"
  and (.stacktrace | length) == 100 and (.tags | length) == 100 and (.breadcrumbs | length) == 100
  and .stacktrace[0].vars == {} and .stacktrace[0].context == ""
  and .tags[0].value == "" and .breadcrumbs[0].message == ""
  and (.metadata | keys | sort) == ["filename","function","type","value"]
' <<<"$detail_output" >/dev/null
[ "$(printf '%s' "$detail_output" | wc -c)" -lt 600000 ]

# A bounded config may contain large local arrays, but only the first 20 items
# can become query filters and non-scalar elements are never stringified.
jq -cn '{baseUrl:"https://sentry.example.test",organization:"acme",
  projects:[range(0;1000) | ("project" + (.|tostring))],
  environments:[range(0;1000) | ("environment" + (.|tostring))]}' >"$CURL_CONFIG/trace/config.json"
bounded_config_output=$(PATH="$BIN:$PATH" XDG_CONFIG_HOME="$CURL_CONFIG" XDG_CACHE_HOME="$CURL_CACHE" \
  TRACE_CURL_BIN="$BIN/curl" TRACE_MAX_RESPONSE_BYTES=65536 TRACE_TEST_CURL_ARGS="$TMP/curl-args" \
  TRACE_TEST_CURL_CONFIG="$TMP/curl-config-input" "$API" list 10)
jq -e '.state == "ready"' <<<"$bounded_config_output" >/dev/null
[ "$(grep -o '&project=' "$TMP/curl-config-input" | wc -l)" -eq 20 ]
[ "$(grep -o '&environment=' "$TMP/curl-config-input" | wc -l)" -eq 20 ]

# Oversized and symlinked user-writable configuration is rejected before jq
# can parse or map it.
head -c 65537 /dev/zero | tr '\0' x >"$CURL_CONFIG/trace/config.json"
oversized_config_status=$(PATH="$BIN:$PATH" XDG_CONFIG_HOME="$CURL_CONFIG" XDG_CACHE_HOME="$CURL_CACHE" "$API" status)
jq -e '.state == "unconfigured" and .configured == false' <<<"$oversized_config_status" >/dev/null
printf '%s\n' '{"baseUrl":"https://sentry.example.test","organization":"acme"}' >"$TMP/symlink-target.json"
rm -f -- "$CURL_CONFIG/trace/config.json"
ln -s -- "$TMP/symlink-target.json" "$CURL_CONFIG/trace/config.json"
symlink_config_status=$(PATH="$BIN:$PATH" XDG_CONFIG_HOME="$CURL_CONFIG" XDG_CACHE_HOME="$CURL_CACHE" "$API" status)
jq -e '.state == "unconfigured" and .configured == false' <<<"$symlink_config_status" >/dev/null
rm -f -- "$CURL_CONFIG/trace/config.json"
printf '%s\n%s\n' '{"baseUrl":"https://sentry.example.test","organization":"acme"}' '{}' >"$CURL_CONFIG/trace/config.json"
multi_config_status=$(PATH="$BIN:$PATH" XDG_CONFIG_HOME="$CURL_CONFIG" XDG_CACHE_HOME="$CURL_CACHE" "$API" status)
jq -e '.state == "unconfigured" and .configured == false' <<<"$multi_config_status" >/dev/null

# Setup and notification stdin have independent hard byte ceilings.
oversized_setup=$(jq -cn --arg token "$TEST_TOKEN" --arg padding "$(head -c 33000 /dev/zero | tr '\0' x)" \
  '{baseUrl:"https://sentry.example.test",organization:"acme",token:$token,padding:$padding}')
oversized_setup_output=$(printf '%s\n' "$oversized_setup" | PATH="$BIN:$PATH" XDG_CONFIG_HOME="$TMP/oversized-setup" \
  XDG_CACHE_HOME="$CURL_CACHE" "$API" configure --token-stdin || :)
jq -e '.state == "error" and .error.message == "setup payload exceeds the size limit"' <<<"$oversized_setup_output" >/dev/null
oversized_notify_output=$(head -c 4097 /dev/zero | tr '\0' x | TRACE_DEMO=1 "$API" notify || :)
jq -e '.state == "error" and .error.message == "notification payload exceeds the size limit"' <<<"$oversized_notify_output" >/dev/null

# A stale cache is local input too: it must be a bounded regular file and is
# normalized again before it reaches the shell output boundary.
rm -f -- "$CURL_CONFIG/trace/config.json"
cp -- "$TMP/symlink-target.json" "$CURL_CONFIG/trace/config.json"
mkdir -p -- "$CURL_CACHE/trace"
head -c 1048577 /dev/zero | tr '\0' x >"$CURL_CACHE/trace/list.json"
oversized_cache_output=$(PATH="$BIN:$PATH" XDG_CONFIG_HOME="$CURL_CONFIG" XDG_CACHE_HOME="$CURL_CACHE" \
  TRACE_CURL_BIN="$BIN/curl" TRACE_MAX_RESPONSE_BYTES=65536 TRACE_TEST_CURL_ARGS="$TMP/curl-args" \
  TRACE_TEST_FAIL=1 "$API" list 10 || :)
jq -e '.state == "error" and .error.code == "network-error"' <<<"$oversized_cache_output" >/dev/null

oversize_output=$(PATH="$BIN:$PATH" XDG_CONFIG_HOME="$CURL_CONFIG" XDG_CACHE_HOME="$TMP/no-cache" \
  TRACE_CURL_BIN="$BIN/curl" TRACE_MAX_RESPONSE_BYTES=65536 TRACE_TEST_CURL_ARGS="$TMP/curl-args" \
  TRACE_TEST_OVERSIZE=1 "$API" list 10 || :)
jq -e '.state == "error" and .error.message == "Sentry response exceeded the size limit"' <<<"$oversize_output" >/dev/null

# URL filters are encoded and repeated rather than interpolated raw.
grep -qE 'project=\$\(urlencode "\$project"\)' "$ROOT/scripts/trace-api.sh"
grep -qE 'environment=\$\(urlencode "\$environment"\)' "$ROOT/scripts/trace-api.sh"
grep -q 'expand=inbox' "$ROOT/scripts/trace-api.sh"
grep -qE 'review\) payload=.*hasSeen.*inbox' "$ROOT/scripts/trace-api.sh"
! grep -qE 'to_entries\[|map\([^)]*\)\[0:|map\([^;]*\)\s*\|\s*\.\[0:' "$ROOT/scripts/trace-api.sh"

! grep -R -nE 'Bearer[[:space:]]+[A-Za-z0-9._-]{20,}' "$ROOT/scripts" "$ROOT/fixtures"

bad=$(XDG_CONFIG_HOME="$CONFIG" XDG_CACHE_HOME="$CACHE" TRACE_DEMO=1 "$API" detail '../secret' || true)
printf '%s\n' "$bad" | jq -e '.state == "error" and .error.code == "invalid-input"' >/dev/null

printf 'test_security.sh: ok\n'
