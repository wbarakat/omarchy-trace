# Trace Working Agreement

Trace is a native Omarchy Quattro Sentry inbox. Keep the product narrow:
surface new and regressed production errors, make common triage actions fast,
and hand deep investigation back to Sentry.

## Product rules

- Native QML only. No embedded browser, Electron, or HTML UI.
- Keyboard-first and fully usable with a mouse.
- Use Omarchy `Color` and `Style` tokens; do not hard-code a theme palette.
- External API text must render as `Text.PlainText`, be control-character
  stripped, and be length limited before it enters the UI.
- Store Sentry tokens only in GNOME Keyring. Never place secrets in settings,
  config JSON, command arguments, logs, fixtures, or the process list.
- Never delete Sentry data. Resolve, assign, and timed-ignore are reversible.
- Demo mode must exercise the same model and UI paths as live data.
- The quiet state is quiet: no vanity counters or noisy notifications.
- Runtime code must not edit the user's broader Omarchy configuration.

## Architecture contract

- `Service.qml` owns long-lived state and calls `scripts/trace-api.sh`.
- `BarWidget.qml` is one badge and one click; it summons the panel/window.
- `App.qml` is the full tiled application window.
- The helper prints exactly one JSON document to stdout for every invocation.
- State documents use `schemaVersion: 1` and a top-level `state` string.
- Issue objects use: `id`, `shortId`, `title`, `culprit`, `project`,
  `environment`, `level`, `priority`, `hasSeen`, `inInbox`, `status`,
  `substatus`, `isUnhandled`, `isRegression`, `count`, `userCount`, `firstSeen`,
  `lastSeen`, `assignedTo`, `permalink`.
- Detail documents add fixed scalar `metadata`, `tags`, `stacktrace`, and `breadcrumbs`.
- Stack frames use: `filename`, `function`, `module`, `line`, `column`,
  `context`, `inApp`, `vars`; provider frame variables are deliberately returned
  as an empty object rather than copied recursively.

## Validation

Run `make validate`. At minimum this must cover the manifest, shell helper,
fixture schema, source-safety regressions, and `qmllint` when available.
