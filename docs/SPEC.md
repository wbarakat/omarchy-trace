# Trace — product and implementation specification

## Promise

**Production errors as a native Omarchy inbox — not another dashboard tab.**

Trace watches a Sentry organization for unresolved issues, makes new and
regressed errors visible in the Omarchy bar, and provides a fast native window
for the frequent triage loop. Sentry's website remains the place for deep
event exploration and administration.

## Product scope

Three surfaces, one plugin:

1. A calm bar icon. No count when everything is quiet; a count for unreviewed
   or regressed issues; a distinct disconnected/error treatment.
2. A tiled application window with an issue list and readable detail/stack
   trace. Narrow windows switch between list and detail instead of crushing
   both.
3. Desktop notification for an issue newly observed as a regression. One
   issue produces one notification while it remains regressed; if it recovers
   and later regresses again, it can notify again.

## Interaction

- `j` / `k` or arrows: move
- `Enter`: open selected issue
- `Esc`: detail to list, then close
- `e`: resolve
- `a`: assign to me
- `x`: mark reviewed
- `z`: choose a timed ignore duration
- `i`: explain with the configured Omarchy agent after privacy confirmation
- `o`: open in Sentry
- `y`: copy issue permalink
- `/` or `Ctrl+K`: search
- `p`, then `j` / `k` or arrows and `Enter`: choose project scope within the
  loaded inbox
- `g r`: regressions
- `g u`: unresolved
- `F5`: refresh
- `?`: shortcut help

Review, resolve, assignment, and ignore update only after the helper returns
success. Errors leave the current state intact and appear in the window's
status line.

Agent handoff uses `omarchy agent prompt`, never provider-specific commands.
Trace sends a bounded diagnostic packet only after confirmation, marks every
Sentry field as untrusted data, and asks the agent not to modify files unless
the user explicitly requests that in the agent session.

## Setup

The first-run window asks for:

- Sentry base URL, default `https://sentry.io`
- organization slug
- optional comma-separated project slugs
- optional comma-separated environments, defaulting to `production`; blank
  means every environment
- API token, accepted into GNOME Keyring over stdin

The non-secret configuration is stored at `~/.config/trace/config.json` with
mode `0600`; issue caches live under `~/.cache/trace/`, also private. Tokens
are retrieved with `secret-tool` and passed to curl through stdin/config, never
as an argument.

Demo mode requires no setup and uses checked-in realistic fixtures. It is a
first-class judging path rather than a second mock UI.

## Live API boundary

The initial provider is Sentry SaaS and self-hosted Sentry through its REST
API. The helper supports:

- list organization issues using a bounded unresolved query
- issue detail and latest event/stack trace
- resolve
- assign to the authenticated member where supported
- mark reviewed using Sentry's per-user inbox semantics
- timed ignore

The inbox is ordered for action: regressions first, then unreviewed/new inbox
items, then explicit high/medium/low Sentry priority, then most recently seen.
The project picker filters the loaded organization feed without another API
round trip.

Requests must set timeouts, honor non-2xx responses, redact secrets from error
text, validate URL/organization/issue identifiers, and never evaluate remote
data as shell or rich text.

## Visual direction

Dense but calm. Monospace, square corners, restrained dividers, one accent
color, urgency used only for actual regressions/failures. The issue list shows
project, level, title, culprit, last seen, and event/user counts. Detail gives
the title room, then compact metadata, then a stack trace with in-app frames
visually emphasized.

No charts, AI summaries, decorative gradients, avatars, or imitation of
Sentry's web navigation.

## Explicit non-goals

- project/release/user administration
- alert-rule editing
- dashboards and performance charts
- deleting issues or events
- pretending cached data is current
- multiple simultaneous organization profiles
- pagination or historical issue browsing
- supporting multiple error providers before the Sentry experience is done
