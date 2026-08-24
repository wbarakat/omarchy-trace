#!/usr/bin/env bash
# Trace's deliberately small Sentry boundary.  Every successful or failed
# invocation writes one JSON value to stdout; diagnostics never go there.
set -u
umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FIXTURE_DIR=${TRACE_FIXTURE_DIR:-"$SCRIPT_DIR/../fixtures"}
CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
CACHE_HOME=${XDG_CACHE_HOME:-"$HOME/.cache"}
CONFIG_DIR="$CONFIG_HOME/trace"
CONFIG_FILE="$CONFIG_DIR/config.json"
CACHE_DIR="$CACHE_HOME/trace"
LIST_CACHE="$CACHE_DIR/list.json"
MAX_CONFIG_BYTES=65536
MAX_CACHE_BYTES=1048576
MAX_STDIN_BYTES=32768
MAX_NOTIFY_BYTES=4096
MAX_TOKEN_BYTES=4096
MAX_FILTER_ITEMS=20
MAX_DETAIL_ITEMS=100

# The shell asks for chunked output so its streaming parser never has to hold
# an attacker-sized line. CLI output remains ordinary compact JSON.
if [ "${1:-}" = --chunk-output ]; then
  shift
  set -o pipefail
  "$0" "$@" | fold -w 4096
  exit "${PIPESTATUS[0]}"
fi

TMP_FILES=""
cleanup() {
  local f
  for f in $TMP_FILES; do [ -n "$f" ] && rm -f -- "$f" 2>/dev/null || :; done
}
trap cleanup EXIT HUP INT TERM

die() {
  local code=$1 message=$2 exit_code=${3:-1}
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg code "$code" --arg message "$message" \
      '{schemaVersion:1,state:"error",error:{code:$code,message:$message}}'
  else
    printf '{"schemaVersion":1,"state":"error","error":{"code":"%s","message":"%s"}}\n' \
      "invalid" "backend unavailable"
  fi
  exit "$exit_code"
}

need_jq() { command -v jq >/dev/null 2>&1 || die dependency-missing "jq is required"; }
need_jq

tmpfile() {
  local f
  f=$(mktemp "${TMPDIR:-/tmp}/trace-api.XXXXXX") || die internal "could not create private temporary file"
  chmod 600 -- "$f" 2>/dev/null || :
  TMP_FILES="$TMP_FILES $f"
  printf '%s' "$f"
}

valid_identifier() {
  [[ ${1:-} =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]]
}
valid_url() {
  local u=$1
  [[ "$u" =~ ^https://[^[:space:]/?#]+(:[0-9]{1,5})?([^[:space:]?#]*)$ ]] || \
    [[ "$u" =~ ^http://(localhost|127\.0\.0\.1)(:[0-9]{1,5})?([^[:space:]?#]*)$ ]]
}
clean_url() { printf '%s' "${1%/}"; }

read_bounded_regular_file() {
  local source=$1 maximum=$2
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$source" "$maximum" <<'PY'
import os
import stat
import sys

path = sys.argv[1]
try:
    maximum = int(sys.argv[2])
except (TypeError, ValueError):
    raise SystemExit(1)
if maximum <= 0:
    raise SystemExit(1)

fd = -1
try:
    fd = os.open(
        path,
        os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0),
    )
    opened = os.fstat(fd)
    if (
        not stat.S_ISREG(opened.st_mode)
        or opened.st_uid != os.geteuid()
        or opened.st_size <= 0
        or opened.st_size > maximum
    ):
        raise OSError

    chunks = []
    remaining = maximum + 1
    while remaining:
        chunk = os.read(fd, min(65536, remaining))
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)

    contents = b"".join(chunks)
    final = os.fstat(fd)
    if (
        not stat.S_ISREG(final.st_mode)
        or final.st_uid != os.geteuid()
        or final.st_size <= 0
        or final.st_size > maximum
        or not contents
        or len(contents) > maximum
    ):
        raise OSError

    output = sys.stdout.buffer
    output.write(contents)
    output.flush()
except (OSError, ValueError):
    raise SystemExit(1)
finally:
    if fd >= 0:
        os.close(fd)
PY
}

read_bounded_config() {
  CONFIG_JSON=$(
    set -o pipefail
    read_bounded_regular_file "$CONFIG_FILE" "$MAX_CONFIG_BYTES" 2>/dev/null \
      | jq -Rsec 'fromjson | select(type == "object")' 2>/dev/null
  ) || return 1
  [ -n "$CONFIG_JSON" ]
}

load_config() {
  local config_line project count=0
  read_bounded_config || return 1
  config_line=$(printf '%s' "$CONFIG_JSON" | jq -Rer --argjson max "$MAX_FILTER_ITEMS" '
    fromjson |
    def clean($limit):
      if type == "string" then gsub("[[:cntrl:]]"; "") | gsub("\\u007f"; "") | gsub("^[[:space:]]+|[[:space:]]+$"; "") | .[0:$limit]
      else "" end;
    def csv($default):
      if type == "array" then .[0:$max] | map(select(type == "string") | clean(128)) | map(select(length > 0)) | join(",")
      elif type == "string" then clean(2580)
      elif . == null then $default
      else "" end;
    [(.baseUrl | clean(2048)), (.organization | clean(128)), (.projects | csv("")),
     (if has("environments") then (.environments | csv("")) else "production" end)] | @tsv
  ' 2>/dev/null) || return 1
  IFS=$'\t' read -r BASE_URL ORG PROJECTS ENVIRONMENTS <<<"$config_line"
  # Older config files had no environment filter. Keep them usable while
  # matching the setup UI's production default; an explicit blank means all.
  valid_url "$BASE_URL" || return 1
  valid_identifier "$ORG" || return 1
  if [ -n "$PROJECTS" ]; then
    IFS=',' read -r -a loaded_projects <<<"$PROJECTS"
    for project in "${loaded_projects[@]}"; do
      valid_identifier "$project" || return 1
      count=$((count + 1)); [ "$count" -le "$MAX_FILTER_ITEMS" ] || return 1
    done
  fi
  count=0
  if [ -n "$ENVIRONMENTS" ]; then
    IFS=',' read -r -a loaded_environments <<<"$ENVIRONMENTS"
    for project in "${loaded_environments[@]}"; do
      [ -n "$project" ] && [ "${#project}" -le 128 ] || return 1
      count=$((count + 1)); [ "$count" -le "$MAX_FILTER_ITEMS" ] || return 1
    done
  fi
  return 0
}

secret_lookup() {
  command -v secret-tool >/dev/null 2>&1 || return 2
  (set -o pipefail; secret-tool lookup service trace base-url "$BASE_URL" organization "$ORG" 2>/dev/null | head -c $((MAX_TOKEN_BYTES + 1)))
}

secret_available() {
  local candidate
  candidate=$(secret_lookup) || return 1
  [[ "$candidate" =~ ^[A-Za-z0-9._~-]{1,4096}$ ]]
}

write_config() {
  local base=$1 org=$2 projects=$3 environments=${4-production} file
  mkdir -p -- "$CONFIG_DIR" 2>/dev/null || die config-error "could not create configuration directory"
  chmod 700 -- "$CONFIG_DIR" 2>/dev/null || :
  file=$(tmpfile)
  jq -cn --arg base "$base" --arg org "$org" --arg projects "$projects" --arg environments "$environments" \
    '{baseUrl:$base,organization:$org,projects:([ $projects | split(",")[] | gsub("^[[:space:]]+|[[:space:]]+$";"") | select(length > 0) ]),environments:([ $environments | split(",")[] | gsub("^[[:space:]]+|[[:space:]]+$";"") | select(length > 0) ])}' >"$file" || die config-error "could not write configuration"
  chmod 600 -- "$file" 2>/dev/null || die config-error "could not protect configuration"
  mv -f -- "$file" "$CONFIG_FILE" 2>/dev/null || die config-error "could not install configuration"
  chmod 600 -- "$CONFIG_FILE" 2>/dev/null || die config-error "could not protect configuration"
}

demo_enabled() { [ "${TRACE_DEMO:-0}" = 1 ] || [ "$DEMO" = 1 ]; }

# curl reads its authorization header from stdin. The token therefore never
# enters a temporary file, /proc/$pid/cmdline, or the process environment.
curl_api() {
  local method=$1 url=$2 payload=${3:-} body err token url_json method_json payload_json http rc max_bytes
  API_BODY=""; API_CODE=""; API_ERROR=""
  token=$(secret_lookup) || { API_ERROR="token unavailable"; return 1; }
  [ -n "$token" ] || { API_ERROR="token unavailable"; return 1; }
  [[ "$token" =~ ^[A-Za-z0-9._~-]{1,4096}$ ]] \
    || { token=""; API_ERROR="token format is invalid"; return 1; }
  max_bytes=${TRACE_MAX_RESPONSE_BYTES:-4194304}
  [[ "$max_bytes" =~ ^[0-9]+$ ]] && [ "$max_bytes" -ge 65536 ] && [ "$max_bytes" -le 16777216 ] \
    || { API_ERROR="invalid response size limit"; return 1; }
  body=$(tmpfile); err=$(tmpfile)
  url_json=$(jq -nr --arg v "$url" '$v|@json')
  method_json=$(jq -nr --arg v "$method" '$v|@json')
  http="$({
      printf 'url = %s\n' "$url_json"
      printf 'request = %s\n' "$method_json"
      printf 'connect-timeout = %s\nmax-time = %s\n' "${TRACE_CONNECT_TIMEOUT:-10}" "${TRACE_MAX_TIME:-30}"
      printf 'silent\nshow-error\nfail-with-body\n'
      printf 'header = "Authorization: Bearer %s"\n' "$token"
      printf 'header = %s\n' "$(jq -nr --arg v 'Accept: application/json' '$v|@json')"
      if [ -n "$payload" ]; then
        payload_json=$(jq -nr --arg v "$payload" '$v|@json')
        printf 'header = %s\n' "$(jq -nr --arg v 'Content-Type: application/json' '$v|@json')"
        printf 'data = %s\n' "$payload_json"
      fi
    } | "${TRACE_CURL_BIN:-curl}" --config - --max-filesize "$max_bytes" \
      --output "$body" --write-out '%{http_code}' 2>"$err")"
  rc=$?
  token=""
  if [ "$rc" -eq 63 ]; then API_ERROR="Sentry response exceeded the size limit"; return 1; fi
  if [ "$rc" -ne 0 ]; then API_ERROR="request failed"; return 1; fi
  [ "$(wc -c <"$body")" -le "$max_bytes" ] || { API_ERROR="Sentry response exceeded the size limit"; return 1; }
  if ! [[ "$http" =~ ^[0-9]{3}$ ]] || [ "$http" -lt 200 ] || [ "$http" -ge 300 ]; then
    API_CODE="$http"; API_BODY="$body"; API_ERROR="Sentry returned HTTP $http"; return 1
  fi
  API_CODE="$http"; API_BODY="$body"; return 0
}

normalize_issue() {
  jq -Rsc '
    def text: (if . == null then "" elif type == "string" then (gsub("[[:cntrl:]]"; "") | gsub("\\u007f"; "") | .[0:500]) elif type == "number" or type == "boolean" then tostring else "" end);
    def number: (if type == "number" then . elif type == "string" and length <= 64 then (tonumber? // 0) else 0 end);
    def boolean: (if . == true then true else false end);
    def seen: (if has("hasSeen") then (.hasSeen|boolean) elif has("has_seen") then (.has_seen|boolean) else false end);
    def inbox: (if has("inInbox") then (.inInbox|boolean) elif has("in_inbox") then (.in_inbox|boolean) else (.inbox != null) end);
    (fromjson? // {} | if type == "object" then . else {} end) |
    {id:(.id|text), shortId:((.shortId // .short_id // .id)|text),
     title:((.title // .metadata.value // .culprit // "Untitled")|text), culprit:(.culprit|text),
     project:((.project.slug // .project.name // .project // "")|text), environment:((.environment // .matchingEventEnvironment)|text),
     level:((.level // "error")|text), priority:((.priority // "")|text|ascii_downcase|if .=="high" or .=="medium" or .=="low" then . else "" end), hasSeen:seen, inInbox:inbox, status:((.status // "unresolved")|text),
     substatus:((.substatus // .statusDetails.substatus // "")|text),
     isUnhandled:((.isUnhandled // .is_unhandled // false)|boolean),
     isRegression:((.isRegression // .is_regression // (.substatus == "regressed"))|boolean),
     count:((.count)|number), userCount:((.userCount // .user_count)|number),
     firstSeen:((.firstSeen // .first_seen)|text), lastSeen:((.lastSeen // .last_seen)|text),
     assignedTo:(if .assignedTo == null then "" elif (.assignedTo|type)=="object" then ((.assignedTo.name // .assignedTo.email // .assignedTo.id)|text) else (.assignedTo|text) end),
     permalink:((.permalink // .web_url // "")|text)}'
}

normalize_list() {
  local source=$1 out=$2 limit=${3:-100}
  [[ "$limit" =~ ^[0-9]+$ ]] && [ "$limit" -ge 1 ] && [ "$limit" -le 100 ] || return 1
  [ -f "$source" ] || return 1
  jq -cn --rawfile raw "$source" --argjson limit "$limit" '
    def issue: (
      def text: (if . == null then "" elif type == "string" then (gsub("[[:cntrl:]]"; "") | gsub("\\u007f"; "") | .[0:500]) elif type == "number" or type == "boolean" then tostring else "" end);
      def number: (if type == "number" then . elif type == "string" and length <= 64 then (tonumber? // 0) else 0 end);
      def boolean: (if . == true then true else false end);
      def seen: (if has("hasSeen") then (.hasSeen|boolean) elif has("has_seen") then (.has_seen|boolean) else false end);
      def inbox: (if has("inInbox") then (.inInbox|boolean) elif has("in_inbox") then (.in_inbox|boolean) else (.inbox != null) end);
      {id:(.id|text), shortId:((.shortId // .short_id // .id)|text), title:((.title // .metadata.value // .culprit // "Untitled")|text), culprit:(.culprit|text), project:((.project.slug // .project.name // .project // "")|text), environment:((.environment // .matchingEventEnvironment)|text), level:((.level // "error")|text), priority:((.priority // "")|text|ascii_downcase|if .=="high" or .=="medium" or .=="low" then . else "" end), hasSeen:seen, inInbox:inbox, status:((.status // "unresolved")|text), substatus:((.substatus // .statusDetails.substatus // "")|text), isUnhandled:((.isUnhandled // .is_unhandled // false)|boolean), isRegression:((.isRegression // .is_regression // (.substatus == "regressed"))|boolean), count:((.count)|number), userCount:((.userCount // .user_count)|number), firstSeen:((.firstSeen // .first_seen)|text), lastSeen:((.lastSeen // .last_seen)|text), assignedTo:(if .assignedTo == null then "" elif (.assignedTo|type)=="object" then ((.assignedTo.name // .assignedTo.email // .assignedTo.id)|text) else (.assignedTo|text) end), permalink:((.permalink // .web_url // "")|text)}
    );
    ($raw | fromjson) as $document |
    (if ($document|type) == "array" then $document elif ($document.issues|type)=="array" then $document.issues else [] end)
    | .[0:$limit]
    | map(issue)
  ' >"$out" 2>/dev/null || return 1
}

emit_list() {
  local issues=$1 state=${2:-ready} cached=${3:-false}
  local fetched
  fetched=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '')
  jq -cn --arg state "$state" --argjson cached "$cached" --arg fetchedAt "$fetched" --slurpfile issues "$issues" \
    '{schemaVersion:1,state:$state,ready:($state == "ready"),configured:true,demoMode:false,cached:$cached,fetchedAt:$fetchedAt,issues:($issues[0] // [])}'
}

demo_list() {
  local limit=${1:-50} normalized
  normalized=$(tmpfile)
  normalize_list "$FIXTURE_DIR/issues.json" "$normalized" "$limit" || die fixture-error "invalid demo issue fixture"
  emit_list "$normalized" ready false | jq -c '.demoMode = true'
}

cache_list() {
  local normalized=$1 tmp
  mkdir -p -- "$CACHE_DIR" 2>/dev/null || return 1
  chmod 700 -- "$CACHE_DIR" 2>/dev/null || :
  tmp=$(tmpfile); jq -c . "$normalized" >"$tmp" 2>/dev/null && chmod 600 "$tmp" && mv -f -- "$tmp" "$LIST_CACHE"
}

copy_bounded_regular_file() {
  local source=$1 destination=$2 maximum=$3
  read_bounded_regular_file "$source" "$maximum" >"$destination" 2>/dev/null
}

fixture_detail() {
  local id=$1 f
  f="$FIXTURE_DIR/issue-$id.json"
  [ -f "$f" ] || return 1
  jq -c . "$f" 2>/dev/null
}

normalize_detail() {
  local issue=$1 event=$2
  jq -cn --rawfile issue_json "$issue" --rawfile event_json "$event" --argjson max "$MAX_DETAIL_ITEMS" '
    def scalar($limit): (if . == null then "" elif type == "string" then (gsub("[[:cntrl:]]"; "") | gsub("\\u007f"; "") | .[0:$limit]) elif type == "number" or type == "boolean" then tostring else "" end);
    def text: scalar(500);
    def shorttext: scalar(128);
    def longtext: scalar(1000);
    def integer: (if type == "number" then floor elif type == "string" and length <= 32 then (tonumber? // null) else null end);
    def frame: {filename:((.filename // .absPath // .module // "")|text), function:((.function // .name // "")|text), module:((.module // "")|shorttext), line:((.lineNo // .line // null)|integer), column:((.colNo // .column // null)|integer), context:((.context_line // .context // "")|longtext), inApp:((.inApp // .in_app // false) == true), vars:{}};
    ($issue_json | fromjson | if type == "object" then . else {} end) as $i |
    ($event_json | fromjson | if type == "object" then . else {} end) as $e |
    def issue: ($i | (
      def num: (if type=="number" then . elif type == "string" and length <= 64 then (tonumber? // 0) else 0 end);
      def boolean: (if . == true then true else false end);
      def seen: (if has("hasSeen") then (.hasSeen|boolean) elif has("has_seen") then (.has_seen|boolean) else false end);
      def inbox: (if has("inInbox") then (.inInbox|boolean) elif has("in_inbox") then (.in_inbox|boolean) else (.inbox != null) end);
      {id:(.id|text), shortId:((.shortId // .short_id // .id)|text), title:((.title // .metadata.value // .culprit // "Untitled")|text), culprit:(.culprit|text), project:((.project.slug // .project.name // .project // "")|text), environment:((.environment // .matchingEventEnvironment)|text), level:((.level // "error")|text), priority:((.priority // "")|text|ascii_downcase|if .=="high" or .=="medium" or .=="low" then . else "" end), hasSeen:seen, inInbox:inbox, status:((.status // "unresolved")|text), substatus:((.substatus // .statusDetails.substatus // "")|text), isUnhandled:((.isUnhandled // .is_unhandled // false)|boolean), isRegression:((.isRegression // .is_regression // (.substatus == "regressed"))|boolean), count:(.count|num), userCount:((.userCount // .user_count)|num), firstSeen:((.firstSeen // .first_seen)|text), lastSeen:((.lastSeen // .last_seen)|text), assignedTo:(if .assignedTo == null then "" elif (.assignedTo|type)=="object" then ((.assignedTo.name // .assignedTo.email // .assignedTo.id)|text) else (.assignedTo|text) end), permalink:((.permalink // .web_url // "")|text)}));
    (($e.entries // []) | if type == "array" then .[0:$max] else [] end |
      (first(.[] | select(.type == "exception" or .type == "stacktrace")) // {})) as $entry |
    (($entry.data.values // []) | if type == "array" then (.[0] // {}) else {} end |
      (.stacktrace.frames // []) | if type == "array" then .[0:$max] else [] end) as $frames |
    (($e.tags // $i.tags // []) | if type == "array" then .[0:$max] else [] end) as $tags |
    (($e.breadcrumbs.values // []) | if type == "array" then .[0:$max] else [] end) as $breadcrumbs |
    ($i.metadata | if type == "object" then . else {} end) as $metadata |
    {schemaVersion:1,state:"ready",issue:issue,
     metadata:{type:($metadata.type|text),value:($metadata.value|text),filename:($metadata.filename|text),function:($metadata.function|text)},
     tags:($tags | map(if type=="array" then {key:(.[0]|shorttext),value:(.[1]|text)} elif type=="object" then {key:((.key // .name // "")|shorttext),value:((.value // "")|text)} else empty end)),
     stacktrace:($frames | map(frame)),
     breadcrumbs:($breadcrumbs | map({timestamp:(.timestamp|shorttext),category:(.category|shorttext),message:((.message // .data // "")|longtext),level:(.level|shorttext)}))}
  '
}

config_or_die() { load_config || die not-configured "Trace is not configured"; }
validate_timeouts() {
  [[ ${TRACE_CONNECT_TIMEOUT:-10} =~ ^[0-9]+$ ]] && [ "${TRACE_CONNECT_TIMEOUT:-10}" -ge 1 ] && [ "${TRACE_CONNECT_TIMEOUT:-10}" -le 120 ] || die invalid-input "invalid connect timeout"
  [[ ${TRACE_MAX_TIME:-30} =~ ^[0-9]+$ ]] && [ "${TRACE_MAX_TIME:-30}" -ge 1 ] && [ "${TRACE_MAX_TIME:-30}" -le 120 ] || die invalid-input "invalid request timeout"
}
issue_arg() { valid_identifier "$1" || die invalid-input "invalid issue identifier"; }
valid_filter_csv() {
  local value=$1 item count=0
  [ -z "$value" ] && return 0
  IFS=',' read -r -a filter_items <<<"$value"
  for item in "${filter_items[@]}"; do
    item=$(printf '%s' "$item" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
    [ -n "$item" ] || die invalid-input "environment names must not be empty"
    [ "${#item}" -le 128 ] || die invalid-input "environment name is too long"
    [[ "$item" != *$'\n'* && "$item" != *$'\r'* ]] || die invalid-input "invalid environment name"
    count=$((count + 1)); [ "$count" -le 20 ] || die invalid-input "too many environments"
  done
}

command_configure() {
  local base="" org="" projects="" environments="production" token="" token_stdin=0 arg normalized_setup input_bytes
  # Service.qml sends setup as one JSON line. A raw token is still accepted
  # with --token-stdin, but tokens are never accepted as arguments.
  if { [ "$#" -eq 0 ] || { [ "$#" -eq 1 ] && [ "${1:-}" = "--token-stdin" ]; }; } && [ ! -t 0 ]; then
    local setup_line=""
    IFS= read -r -n $((MAX_STDIN_BYTES + 1)) setup_line || :
    input_bytes=$(printf '%s' "$setup_line" | wc -c)
    [ "$input_bytes" -le "$MAX_STDIN_BYTES" ] || die invalid-input "setup payload exceeds the size limit"
    if [ -n "$setup_line" ] && jq -Rse 'fromjson | type == "object"' >/dev/null 2>&1 <<<"$setup_line"; then
      normalized_setup=$(jq -cer --argjson max "$MAX_FILTER_ITEMS" '
        def scalar($limit): if type == "string" then .[0:$limit] else "" end;
        def csv:
          if type == "array" then .[0:$max] | map(select(type == "string") | .[0:128]) | join(",")
          elif type == "string" then .[0:2580]
          else "" end;
        {baseUrl:((.baseUrl // .base_url // "") | scalar(2048)),
         organization:((.organization // .org // "") | scalar(128)),
         projects:(.projects | csv),
         environments:(if has("environments") then (.environments | csv) else "production" end),
         token:(if (.token|type) == "string" then .token else "" end)}
      ' <<<"$setup_line") || die invalid-input "invalid setup payload"
      base=$(jq -r '.baseUrl' <<<"$normalized_setup")
      org=$(jq -r '.organization' <<<"$normalized_setup")
      projects=$(jq -r '.projects' <<<"$normalized_setup")
      environments=$(jq -r '.environments' <<<"$normalized_setup")
      token=$(jq -r '.token' <<<"$normalized_setup")
      token_stdin=1
    fi
  fi
  while [ "$#" -gt 0 ]; do
    arg=$1; shift
    case "$arg" in
      --base-url) [ "$#" -gt 0 ] || die invalid-input "missing base URL"; base=$1; shift;;
      --organization|--org) [ "$#" -gt 0 ] || die invalid-input "missing organization"; org=$1; shift;;
      --projects) [ "$#" -gt 0 ] || die invalid-input "missing projects"; projects=$1; shift;;
      --environments|--environment) [ "$#" -gt 0 ] || die invalid-input "missing environments"; environments=$1; shift;;
      --token-stdin) token_stdin=1;;
      --demo) DEMO=1;;
      -*) die invalid-input "unknown configure option";;
      *)
        if [ -z "$base" ]; then base=$arg
        elif [ -z "$org" ]; then org=$arg
        elif [ -z "$projects" ]; then projects=$arg
        elif [ "$environments" = "production" ]; then environments=$arg
        else die invalid-input "too many configure arguments"
        fi;;
    esac
  done
  [ -n "$base" ] && valid_url "$base" || die invalid-input "base URL must use HTTPS (or localhost HTTP)"
  valid_identifier "$org" || die invalid-input "invalid organization"
  if [ -n "$projects" ]; then
    local p project_count=0
    IFS=',' read -r -a p <<<"$projects"
    for project in "${p[@]}"; do
      project=$(printf '%s' "$project" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
      valid_identifier "$project" || die invalid-input "invalid project"
      project_count=$((project_count + 1)); [ "$project_count" -le "$MAX_FILTER_ITEMS" ] || die invalid-input "too many projects"
    done
  fi
  valid_filter_csv "$environments"
  if [ "$token_stdin" -eq 1 ] && [ -z "$token" ]; then
    IFS= read -r -s -n $((MAX_TOKEN_BYTES + 1)) token || :
  elif [ "$token_stdin" -ne 1 ]; then
    # A token is intentionally never accepted as a command-line argument.
    die invalid-input "provide the API token with --token-stdin"
  fi
  [ -n "$token" ] || die invalid-input "empty API token"
  [[ "$token" =~ ^[A-Za-z0-9._~-]{1,4096}$ ]] || die invalid-input "invalid API token format"
  command -v secret-tool >/dev/null 2>&1 || die dependency-missing "secret-tool is required to store the token"
  write_config "$(clean_url "$base")" "$org" "$projects" "$environments"
  BASE_URL=$(clean_url "$base") ORG="$org"
  printf '%s' "$token" | secret-tool store --label='Trace Sentry API token' service trace base-url "$BASE_URL" organization "$ORG" >/dev/null 2>/dev/null || die config-error "could not store token in GNOME Keyring"
  # The cache is intentionally not portable across organizations, project
  # scopes, or environment scopes. Never let a new connection inherit stale
  # issue data from the previous one.
  rm -f -- "$LIST_CACHE" 2>/dev/null || die config-error "could not clear the previous issue cache"
  jq -cn '{schemaVersion:1,state:"ready",configured:true}'
}

command_status() {
  if demo_enabled; then jq -cn '{schemaVersion:1,state:"ready",configured:true,demo:true}'; return; fi
  if load_config; then
    if secret_available; then jq -cn --arg base "$BASE_URL" --arg organization "$ORG" '{schemaVersion:1,state:"ready",configured:true,baseUrl:$base,organization:$organization}'
    else jq -cn --arg base "$BASE_URL" --arg organization "$ORG" '{schemaVersion:1,state:"setup",configured:false,baseUrl:$base,organization:$organization,message:"Sentry token is not available"}'; fi
  else jq -cn '{schemaVersion:1,state:"unconfigured",configured:false}'; fi
}

command_list() {
  local limit=${1:-50} normalized url projects_q="" environments_q="" project environment cached_source
  [[ "$limit" =~ ^[0-9]+$ ]] && [ "$limit" -ge 10 ] && [ "$limit" -le 100 ] || die invalid-input "issue limit must be 10-100"
  if demo_enabled; then demo_list "$limit"; return; fi
  config_or_die; validate_timeouts
  urlencode() { jq -nr --arg value "$1" '$value|@uri'; }
  if [ -n "$PROJECTS" ]; then IFS=',' read -r -a projects_arr <<<"$PROJECTS"; for project in "${projects_arr[@]}"; do projects_q="$projects_q&project=$(urlencode "$project")"; done; fi
  if [ -n "${ENVIRONMENTS:-}" ]; then IFS=',' read -r -a environments_arr <<<"$ENVIRONMENTS"; for environment in "${environments_arr[@]}"; do environments_q="$environments_q&environment=$(urlencode "$environment")"; done; fi
  url="$BASE_URL/api/0/organizations/$ORG/issues/?query=is%3Aunresolved&limit=$limit&sort=date&expand=inbox$projects_q$environments_q"
  if ! curl_api GET "$url"; then
    cached_source=$(tmpfile); normalized=$(tmpfile)
    if copy_bounded_regular_file "$LIST_CACHE" "$cached_source" "$MAX_CACHE_BYTES" && normalize_list "$cached_source" "$normalized" "$limit"; then
      emit_list "$normalized" stale true
    else
      die network-error "$API_ERROR"
    fi
    return
  fi
  normalized=$(tmpfile); normalize_list "$API_BODY" "$normalized" "$limit" || die api-error "invalid Sentry issue response"
  cache_list "$normalized" || :
  emit_list "$normalized" ready false
}

command_detail() {
  local id=$1 issue event result
  issue_arg "$id"
  if demo_enabled; then
    issue=$(fixture_detail "$id") || die not-found "demo issue not found"
    event=$(tmpfile); printf '%s' "$issue" >"$event"
    result=$(normalize_detail "$event" "$event") || die fixture-error "invalid demo detail fixture"
    printf '%s\n' "$result"; return
  fi
  config_or_die; validate_timeouts
  curl_api GET "$BASE_URL/api/0/organizations/$ORG/issues/$id/" || die network-error "$API_ERROR"
  issue=$(tmpfile); cp -- "$API_BODY" "$issue"
  event=$(tmpfile)
  if curl_api GET "$BASE_URL/api/0/organizations/$ORG/issues/$id/events/latest/"; then cp -- "$API_BODY" "$event"; else printf '{}\n' >"$event"; fi
  normalize_detail "$issue" "$event" || die api-error "invalid Sentry detail response"
}

command_action() {
  local action=$1 id=$2 payload result issue user
  issue_arg "$id"
  if [ "$action" = ignore ]; then
    [[ ${3:-} =~ ^[0-9]+$ ]] && [ "${3:-}" -ge 1 ] && [ "${3:-}" -le 43200 ] || die invalid-input "ignore duration must be 1-43200 minutes"
  fi
  if demo_enabled; then jq -cn --arg action "$action" --arg id "$id" '{schemaVersion:1,state:"ready",action:$action,issueId:$id}'; return; fi
  config_or_die; validate_timeouts
  case "$action" in
    resolve) payload='{"status":"resolved"}';;
    review) payload='{"hasSeen":true,"inbox":true}';;
    ignore) local duration=${3:-}; [[ "$duration" =~ ^[0-9]+$ ]] && [ "$duration" -ge 1 ] && [ "$duration" -le 43200 ] || die invalid-input "ignore duration must be 1-43200 minutes"; payload=$(jq -cn --argjson d "$duration" '{status:"ignored",statusDetails:{ignoreDuration:$d}}');;
    assign)
      curl_api GET "$BASE_URL/api/0/users/me/" || die network-error "could not determine current Sentry user"
      user=$(jq -Rer 'fromjson | (.id // empty) | if type == "string" or type == "number" then tostring | .[0:129] else empty end' "$API_BODY" 2>/dev/null) || die api-error "Sentry user response had no id"
      valid_identifier "$user" || die api-error "invalid Sentry user id"
      payload=$(jq -cn --arg user "$user" '{assignedTo:$user}');;
    *) die invalid-input "unsupported action";;
  esac
  curl_api PUT "$BASE_URL/api/0/organizations/$ORG/issues/$id/" "$payload" || die network-error "$API_ERROR"
  if jq -Rse 'fromjson | type == "object"' "$API_BODY" >/dev/null 2>&1; then
    issue=$(normalize_issue <"$API_BODY") || issue=$(jq -cn --arg id "$id" '{id:$id}')
  else
    issue=$(jq -cn --arg id "$id" '{id:$id}')
  fi
  jq -cn --arg action "$action" --argjson issue "$issue" '{schemaVersion:1,state:"ready",action:$action,issue:$issue}'
}

command_clear_token() {
  config_or_die
  command -v secret-tool >/dev/null 2>&1 || die dependency-missing "secret-tool is required"
  secret-tool clear service trace base-url "$BASE_URL" organization "$ORG" >/dev/null 2>/dev/null || die keyring-error "could not clear token"
  rm -f -- "$CONFIG_FILE" 2>/dev/null || die config-error "could not clear local configuration"
  rm -f -- "$LIST_CACHE" 2>/dev/null || die config-error "could not clear cached issues"
  jq -cn '{schemaVersion:1,state:"ready",action:"clear-token"}'
}

command_notify() {
  local id=${1:-} issues f input identity title permalink body input_bytes
  if [ ! -t 0 ]; then
    IFS= read -r -n $((MAX_NOTIFY_BYTES + 1)) input || input=""
    input_bytes=$(printf '%s' "$input" | wc -c)
    [ "$input_bytes" -le "$MAX_NOTIFY_BYTES" ] || die invalid-input "notification payload exceeds the size limit"
    if [ -n "$input" ] && jq -Rse 'fromjson | type == "object"' >/dev/null 2>&1 <<<"$input"; then
      identity=$(jq -nr --argjson input "$input" --arg fallback "$id" '($input.identity // $input.id // $fallback // "") | tostring | gsub("[[:cntrl:]]";"") | .[0:256]')
      title=$(jq -r '.title // "Trace regression"' <<<"$input")
      permalink=$(jq -r '.permalink // empty' <<<"$input")
      [[ "$identity" =~ ^[A-Za-z0-9_.:@/-]{1,256}$ ]] || die invalid-input "invalid notification identity"
      title=$(jq -nr --arg v "$title" '$v|gsub("[[:cntrl:]]";"")|.[0:200]')
      body=$(jq -nr --arg v "$permalink" '$v|gsub("[[:cntrl:]]";"")|.[0:500]')
      if command -v notify-send >/dev/null 2>&1; then notify-send --app-name Trace "$title" "$body" >/dev/null 2>/dev/null || :; fi
      jq -cn --arg identity "$identity" --arg title "$title" '{schemaVersion:1,state:"ready",action:"notify",notification:{identity:$identity,title:$title}}'
      return
    fi
  fi
  if [ -n "$id" ]; then issue_arg "$id"; command_detail "$id" | jq -c '{schemaVersion:1,state:.state,notification:(.issue // {})}'; return; fi
  if demo_enabled; then
    f=$(tmpfile); normalize_list "$FIXTURE_DIR/issues.json" "$f" || die fixture-error "invalid demo issue fixture"
    jq -cn --slurpfile i "$f" '{schemaVersion:1,state:"ready",notification:(first(($i[0] // [])[] | select(.isRegression == true)) // {})}'
  else
    f=$(tmpfile); command_list >"$f" || die network-error "could not list issues"
    jq -cn --slurpfile i "$f" '{schemaVersion:1,state:"ready",notification:(first(($i[0].issues // [])[] | select(.isRegression == true)) // {})}'
  fi
}

DEMO=0
if [ "${1:-}" = --demo ]; then DEMO=1; shift; fi
COMMAND=${1:-status}; shift || :
case "$COMMAND" in
  status) command_status "$@";;
  configure) command_configure "$@";;
  list) [ "$#" -le 1 ] || die invalid-input "list takes at most one issue limit"; command_list "${1:-50}";;
  detail) [ "$#" -eq 1 ] || die invalid-input "detail requires an issue id"; command_detail "$1";;
  resolve|assign|review) [ "$#" -eq 1 ] || die invalid-input "$COMMAND requires an issue id"; command_action "$COMMAND" "$1";;
  ignore) [ "$#" -ge 1 ] && [ "$#" -le 2 ] || die invalid-input "ignore requires issue id and duration"; command_action ignore "$1" "${2:-}";;
  clear-token) [ "$#" -eq 0 ] || die invalid-input "clear-token takes no arguments"; command_clear_token;;
  notify) [ "$#" -le 1 ] || die invalid-input "notify takes zero or one issue id"; command_notify "${1:-}";;
  --help|-h) jq -cn '{schemaVersion:1,state:"ready",commands:["status","configure","list","detail","resolve","assign","review","ignore","clear-token","notify"]}' ;;
  *) die invalid-input "unknown command";;
esac
