#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
API="$ROOT/scripts/trace-api.sh"
TEST_CONFIG=$(mktemp -d)
TEST_CACHE=$(mktemp -d)
trap 'rm -rf -- "$TEST_CONFIG" "$TEST_CACHE"' EXIT

run_api() {
  XDG_CONFIG_HOME="$TEST_CONFIG" XDG_CACHE_HOME="$TEST_CACHE" TRACE_DEMO=1 "$API" "$@"
}
assert_json() {
  local value=$1
  printf '%s\n' "$value" | jq -e 'type == "object" and .schemaVersion == 1 and (.state|type) == "string"' >/dev/null
  [ "$(printf '%s\n' "$value" | wc -l)" -eq 1 ]
}

status=$(run_api status); assert_json "$status"
[ "$(jq -r .state <<<"$status")" = ready ]
list=$(run_api list); assert_json "$list"
[ "$(jq '.issues|length' <<<"$list")" -ge 2 ]
jq -e '.issues[] | has("id") and has("shortId") and has("title") and has("isRegression") and has("priority") and has("hasSeen") and has("inInbox") and has("permalink")' <<<"$list" >/dev/null
jq -e '.issues[] | select(.id == "9876543210") | .priority == "medium" and .hasSeen == true and .inInbox == true' <<<"$list" >/dev/null
limited=$(run_api list 10); assert_json "$limited"
[ "$(jq '.issues|length' <<<"$limited")" -le 10 ]

detail=$(run_api detail 1234567890); assert_json "$detail"
jq -e '.issue.id == "1234567890" and (.stacktrace|length) > 0 and (.breadcrumbs|length) > 0 and (.tags|length) > 0' <<<"$detail" >/dev/null
for action in resolve assign review; do
  result=$(run_api "$action" 1234567890); assert_json "$result"
  [ "$(jq -r .action <<<"$result")" = "$action" ]
done
result=$(run_api ignore 1234567890 30); assert_json "$result"
[ "$(jq -r .action <<<"$result")" = ignore ]
result=$(run_api notify); assert_json "$result"
jq -e '.notification.id == "1234567890"' <<<"$result" >/dev/null

if run_api detail '../../etc/passwd' >/dev/null 2>&1; then exit 1; fi
if run_api ignore 1234567890 0 >/dev/null 2>&1; then exit 1; fi
if run_api list 101 >/dev/null 2>&1; then exit 1; fi
if run_api unknown >/dev/null 2>&1; then exit 1; fi

printf 'test_helper.sh: ok\n'
