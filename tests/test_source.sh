#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() { printf 'test_source.sh: %s\n' "$1" >&2; exit 1; }
[[ -f Model.js ]] || fail "Model.js is missing"
[[ -f Service.qml ]] || fail "Service.qml is missing"
grep -q 'function sanitize' Model.js || fail "external text must pass through Model.sanitize"
grep -q 'control' Model.js || fail "Model must document/control its text boundary"
grep -q 'safeUrl' Model.js || fail "external URLs need a safe scheme check"
grep -q 'trace-api.sh' Service.qml || fail "Service must use the checked-in helper"
if grep -nE 'command[^\n]*(token|apiKey|secret)' Service.qml; then
  fail "credentials must never be passed as Process command arguments"
fi
grep -q 'stdinEnabled: true' Service.qml || fail "setup requires Process stdin"
grep -q 'write(root._inputPayload' Service.qml || fail "setup payload must be written over stdin"
if grep -q 'execDetached(\["omarchy", "agent", "prompt"' Service.qml; then
  fail "diagnostic context must never be passed to the agent in process arguments"
fi
grep -q 'function openProjectMenu' App.qml || fail "project picker needs a keyboard entry point"
grep -q 'function moveProjectMenu' App.qml || fail "project picker needs a keyboard movement method"
grep -q 'function chooseProjectMenu' App.qml || fail "project picker needs a keyboard selection method"
grep -q 'function moveIgnoreMenu' App.qml || fail "ignore picker needs a keyboard movement method"
grep -q 'function chooseIgnoreMenu' App.qml || fail "ignore picker needs a keyboard selection method"
grep -q 'function moveChoice' App.qml || fail "popup choices need indexed keyboard navigation"
grep -q 'popupType: Popup.Item' App.qml || fail "popups must remain in the focused panel item tree"
grep -q 'projectMenuFocus.forceActiveFocus' App.qml || fail "project picker must take keyboard focus"
grep -q 'ignoreMenuFocus.forceActiveFocus' App.qml || fail "ignore picker must take keyboard focus"
grep -q 'event.text === "j".*Qt.Key_Down' App.qml || fail "popup navigation must accept j/k and arrows"
grep -q 'Qt.Key_Return.*Qt.Key_Enter' App.qml || fail "popup navigation must accept Enter"
grep -q 'Shortcut { sequence: "Z"' App.qml || fail "ignore must have a window-level keyboard shortcut"
grep -q 'Shortcut { sequence: "I".*root.confirm("explain")' App.qml || fail "agent handoff must have a window-level keyboard shortcut"
grep -q 'Shortcut { sequence: "Return".*root.runPending' App.qml || fail "confirmations must be keyboard-operable after popup focus changes"
grep -q 'Keys.priority: Keys.BeforeItem' App.qml || fail "panel commands must take priority over clicked controls"
grep -q 'function actionDescription' App.qml || fail "confirmations must explain where issues go"
grep -q 'agent may transmit this context to its provider' App.qml || fail "agent handoff confirmation must disclose external context"
if grep -nE 'bash[" ]*,[" ]*-c|sh[" ]*,[" ]*-c|\| *bash|\| *sh' Service.qml; then
  fail "Service must not evaluate remote data as shell code"
fi
grep -q -- '--config - --max-filesize' scripts/trace-api.sh || fail "Sentry requests must stream credentials and cap responses"
if grep -qE -- '--config[[:space:]]+"?\$cfg' scripts/trace-api.sh; then
  fail "curl credentials must never be written to a config file"
fi
printf 'test_source.sh ok\n'
