#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
HELPER="$ROOT/scripts/trace-agent-handoff.sh"
TMP=$(mktemp -d)
BIN="$TMP/bin"
RUNTIME="$TMP/runtime"
mkdir -p -- "$BIN" "$RUNTIME"
chmod 700 -- "$RUNTIME"
trap 'rm -rf -- "$TMP"' EXIT

cat >"$BIN/omarchy" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  "default agent")
    printf 'claude\n'
    ;;
  "agent prompt")
    printf '%s\n' "$*" >"$TRACE_TEST_AGENT_ARGS"
    fifo=$(sed -n "s/.*cat -- '\([^']*\)'.*/\1/p" <<<"${3:-}")
    [ -p "$fifo" ]
    cat -- "$fifo" >"$TRACE_TEST_AGENT_CAPTURE"
    ;;
  *)
    exit 1
    ;;
esac
SH
chmod 700 -- "$BIN/omarchy"

secret='TRACE_PRIVATE_DIAGNOSTIC_7f5d'
packet="Sentry title and stack: $secret"
input=$(jq -cn --arg prompt "$packet" '{prompt:$prompt}')
output=$(printf '%s\n' "$input" | PATH="$BIN:$PATH" XDG_RUNTIME_DIR="$RUNTIME" \
  TRACE_TEST_AGENT_ARGS="$TMP/agent-args" TRACE_TEST_AGENT_CAPTURE="$TMP/agent-capture" "$HELPER")

jq -e '.state == "ready" and .agent == "claude"' <<<"$output" >/dev/null
[ "$(cat "$TMP/agent-capture")" = "$packet" ]
! grep -Fq "$secret" "$TMP/agent-args"
grep -Fq 'cat --' "$TMP/agent-args"
# The writer owns cleanup and may be scheduled a few milliseconds after the
# fake reader closes. Wait for that asynchronous contract instead of racing it.
for _ in {1..40}; do
  [ -z "$(find "$RUNTIME" -mindepth 1 -print -quit)" ] && break
  sleep 0.025
done
[ -z "$(find "$RUNTIME" -mindepth 1 -print -quit)" ]

oversized=$(jq -cn --arg prompt "$(printf 'x%.0s' {1..12001})" '{prompt:$prompt}')
error=$(printf '%s\n' "$oversized" | PATH="$BIN:$PATH" XDG_RUNTIME_DIR="$RUNTIME" "$HELPER" || :)
jq -e '.state == "error" and .error.message == "agent handoff prompt is too large"' <<<"$error" >/dev/null

printf 'test_agent_handoff.sh: ok\n'
