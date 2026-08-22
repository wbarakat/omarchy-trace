# Trace for Omarchy

Trace is a native Omarchy inbox for unresolved and regressed Sentry issues. It
puts the frequent triage loop in a calm bar badge and tiled Quickshell window;
Sentry remains the place for event exploration, releases, dashboards, and
administration.

## What it does

- polls an organization issue list and caches the last valid response through
  the helper;
- scopes the feed to selected projects and environments, with a fast in-window
  project switcher;
- orders regressions, unreviewed inbox items, and explicit Sentry priorities
  ahead of routine issues without turning a quiet bar into a vanity counter;
- shows issue metadata, tags, breadcrumbs, and highlights in-app stack frames;
- reviews, resolves, assigns to the authenticated member, and timed-ignores
  issues;
- opens or copies the canonical Sentry permalink;
- has a demo path using the same service, model, and UI as live data.

It does not delete Sentry data, edit alert rules, provide dashboards, or embed a
browser. The initial provider is Sentry SaaS and self-hosted Sentry REST APIs.

## Install

Install and enable Trace from GitHub:

```bash
omarchy plugin add https://github.com/wbarakat/omarchy-trace.git --enable
```

For a local checkout or development install:

```bash
./install.sh                 # validates, symlinks, and restarts the shell
./install.sh --no-restart   # useful while iterating on source
```

The script backs up an existing `wbarakat.trace` install outside the plugin
directory before replacing it. It never edits Hyprland, Omarchy themes, or
other user configuration.

## Requirements

- Omarchy Quattro with shell plugin support;
- `curl` and `jq` for the Sentry REST helper;
- `secret-tool` from `libsecret` for live credentials;
- `wl-copy` from `wl-clipboard` for the copy action;
- `notify-send` from `libnotify` for optional regression notifications.

Demo mode is offline and only requires Omarchy plus `jq`.

## First run

Open Trace from its bar icon. Setup asks for the Sentry base URL (default
`https://sentry.io`), organization slug, optional comma-separated project
slugs, comma-separated environments (default `production`; blank means all),
and an API token. The token is accepted over stdin and stored only in GNOME
Keyring by `scripts/trace-api.sh`; it is never written to settings, fixtures,
logs, command arguments, or the process list. Non-secret settings are stored in
`~/.config/trace/config.json` with owner-only permissions, and caches are under
`~/.cache/trace/` with the same intent.

The token needs the smallest practical Sentry permissions for the actions you
use: issue read access, and issue write access for review, resolve, assignment,
and timed ignore. Use a personal user token when you want per-user review state
or assign-to-me; an organization token can be sufficient for read/resolve-only
use where your Sentry policy permits it. Trace cannot prevent Sentry
administrators from revoking a token; a disconnected state is shown instead of
treating stale data as current.

## Demo mode

Choose **Demo mode** from setup to inspect realistic checked-in issues without a
Sentry account or network access. Demo data is deliberately handled by the
same normalization, filtering, selection, and detail paths as live responses;
actions report their demo result and do not contact Sentry. Leave demo mode
from Settings to return to the configured organization.

## Keyboard controls

| Key | Action |
| --- | --- |
| `j` / `k`, arrows | Move through issues |
| `Enter` | Open, choose, or confirm the current action |
| `Esc` | Cancel, return from detail, then close the window |
| `e` | Resolve selected issue |
| `a` | Assign it to me |
| `x` | Mark it reviewed |
| `z`, then `j` / `k`, `Enter` | Choose a timed ignore duration; confirm with `Enter` |
| `o` | Open the Sentry permalink |
| `y` | Copy the permalink |
| `/`, `Ctrl+K` | Search |
| `p`, then `j` / `k`, `Enter` | Choose the current project scope |
| `g r` / `g u` | Regressions / unresolved |
| `F5` | Refresh |
| `?` | Show shortcuts |

Actions are only reflected after the helper reports success. A failed request
leaves the issue intact and puts its safe, shortened error in the status line.

### What the actions change

| Action | Result |
| --- | --- |
| Review | Keeps the issue unresolved, but clears its unreviewed attention state for you. |
| Resolve | Leaves the issue in Sentry as resolved and removes it from Trace’s unresolved inbox. |
| Assign | Assigns the issue to your Sentry account and keeps it in the inbox. |
| Ignore | Marks the issue ignored for the chosen duration; it leaves the inbox until Sentry reactivates it. |
| Open / copy | Does not change the issue; it opens or copies the canonical Sentry URL. |

In demo mode these changes are local and reset when the demo data reloads.

## Security and limitations

Trace treats all API text as untrusted plain text: control characters are
removed and fields are length-limited before they reach QML. URLs are accepted
only with `http` or `https` schemes. The helper validates identifiers and URL
components, uses request timeouts, rejects non-2xx responses, and redacts
credential-shaped values from errors. Cached data is labelled by its fetch time;
it is never presented as live when Sentry is unavailable.

Trace is a thin inbox, not a replacement for Sentry. One connection represents
one Sentry organization; switching organizations deliberately means
reconnecting. Search and the project picker operate on the current bounded
fetch (10–100 issues), and pagination is not yet exposed. Large organizations
may still encounter Sentry rate limits, and filters narrow the list rather than
changing Sentry permissions. Stack traces and breadcrumbs can contain
application-sensitive information; they remain local until you explicitly open
the permalink or copy it.

## Removal

```bash
omarchy plugin disable wbarakat.trace
omarchy plugin remove wbarakat.trace
```

Removing the plugin does not silently destroy credentials or cached data. To
remove those deliberately, use the keyring UI or the exact service entry shown
by your installation, then remove the private Trace directories:

```bash
rm -rf ~/.config/trace ~/.cache/trace
```

Only run that command if you want to discard the saved organization settings
and cache. Revoke the Sentry token in Sentry as well when the machine should no
longer be trusted.

Using **disconnect** inside Trace removes its current token, configuration, and
cached issue list. Removing the plugin files alone deliberately does not.

## Development and validation

```bash
make validate
```

Validation runs the pure Node model tests, shell/source regressions, Omarchy
plugin validation when available, `git diff --check`, and `qmllint` when it is
installed. The project specification is in [docs/SPEC.md](docs/SPEC.md).

Trace is independent software and is not affiliated with Sentry.
