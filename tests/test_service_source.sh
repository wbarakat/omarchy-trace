#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() { printf 'test_service_source.sh: %s\n' "$1" >&2; exit 1; }
for property in state message ready configured demoMode issues visibleIssues unreadCount regressionCount selectedIssue selectedDetail selectedIndex loading detailLoading lastFetchedAt barTooltip windowOpen projectFilter projectOptions; do
  grep -q "property .*${property}" Service.qml || fail "Service must expose ${property}"
done
for method in applySettings refresh selectIndex moveSelection openSelected openWindow closeWindow back setFilter setSearch setProjectFilter loadDetail resolveIssue assignIssue ignoreIssue reviewIssue openIssue copyIssue explainIssue saveSetup enableDemo disableDemo clearCredentials; do
  grep -q "function ${method}" Service.qml || fail "Service must implement ${method}"
done
grep -q 'property var shell' Service.qml || fail "shell injection property missing"
grep -q 'property var manifest' Service.qml || fail "manifest injection property missing"
grep -q '__sourceDir' Service.qml || fail "helper path must use manifest.__sourceDir"
grep -q 'stdinEnabled: true' Service.qml || fail "credential setup must use stdin"
if grep -qE '^  required property' Service.qml; then fail "root service must not declare required properties"; fi
grep -q 'Timer {' Service.qml || fail "long-lived service must poll"
grep -q 'apiProcess.running' Service.qml || fail "operations must be serialized"
grep -q 'enqueue("detail", \[id\], "", demoMode)' Service.qml || fail "demo detail must stay offline"
grep -q 'enqueue(kind, \[id\].*demoMode)' Service.qml || fail "demo actions must stay offline"
grep -q 'applyDemoAction' Service.qml || fail "demo actions must update the local model"
grep -q 'selectedDetail = null' Service.qml || fail "selection scope changes must clear stale detail"
grep -q 'running: root.configured || root.demoMode' Service.qml || fail "polling must wait for status/configuration"
grep -q 'trace-agent-handoff.sh' Service.qml || fail "handoff must use the checked-in stdin helper"
grep -q '_agentPrompt = JSON.stringify' Service.qml || fail "handoff payload must use the bounded stdin protocol"
grep -q 'write(root._agentPrompt' Service.qml || fail "handoff payload must be written over stdin"
grep -q 'maxHelperOutputChars' Service.qml || fail "helper output must have a hard collection limit"
grep -q 'stdout: SplitParser' Service.qml || fail "helper output must be collected incrementally"
grep -q '\[helperPath, "--chunk-output"\]' Service.qml || fail "helper lines must be chunked before shell collection"
printf 'test_service_source.sh ok\n'
