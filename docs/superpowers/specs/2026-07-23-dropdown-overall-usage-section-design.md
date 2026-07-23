# Dropdown: separate "Overall" usage section

## Problem

The menu bar title already shows the official session-limit percentage
(`🐾 55.3M · 42%`), sourced from `/api/oauth/usage` via `LimitsProvider`. For
Claude Pro/Max plans, that percentage reflects the account's shared usage
pool across claude.ai web, Claude Desktop, and Claude Code — not just this
app's local activity.

In the dropdown (`StatusItemController.makeMenu()`), the Session/Weekly limit
lines currently sit unlabeled between the "Today" and "Current block"
sections (`StatusItemController.swift:93-107`), which are both derived from
local `~/.claude/projects` transcripts via `ccusage`. Nothing distinguishes
the account-wide numbers from the Claude-Code-only numbers, so a user can
easily read the whole dropdown as "Claude Code usage."

## Goal

Make the account-wide vs. Claude-Code-only distinction visually obvious in
the dropdown, without changing any data source or fetch logic — both values
are already fetched today.

## Design

Reorder the dropdown into two labeled sections:

```
🌐 Overall (Web + Desktop + Code)
   Session limit 42% used · resets 2:15 PM
   Weekly limit 18% used · resets Sun
─────────────────────────────
💻 Claude Code (this app)
Today - $3.20 · 55.3M tokens
  in ... · out ... · cache-w ... · cache-r ...
─────────────────────────────
Current block (resets 4:56 PM, 2h41m left)
  55.3M tokens · $3.20
  burn $1.20/h · proj $4.10 by reset
─────────────────────────────
claude-opus-4-8 - $2.10
claude-sonnet-5 - $1.10
─────────────────────────────
Updated 2:03 PM
Refresh Now
Open transcripts folder
─────────────────────────────
Quit
```

Changes to `makeMenu()`:

1. Move the "Overall" block (currently the Session/Weekly limit lines) to
   the top of the menu, immediately after the error banner (if any) and
   before "Today". Prefix it with a bold section header item:
   `🌐 Overall (Web + Desktop + Code)`.
2. Add a matching bold section header `💻 Claude Code (this app)`
   immediately before the existing "Today" line, so everything from there
   down (Today, Current block, per-model breakdown) reads as
   Claude-Code-local data.
3. Section headers are non-interactive `NSMenuItem`s using
   `attributedTitle` (semibold, `NSFont.systemFont(ofSize: 11, weight:
   .semibold)`, `NSColor.secondaryLabelColor`) rather than plain `title`, so
   they read visually distinct from the data rows below them — similar to
   macOS system menu section headers. Implemented as a new
   `sectionHeaderItem(_:)` helper alongside the existing `disabledItem(_:)`
   and `actionItem(_:)` helpers.
4. If `currentLimits()` returns `nil` (limits unavailable — no credential,
   fetch failed, or past reset), the entire "Overall" section (header +
   lines) is omitted, same as today's behavior for the Session/Weekly
   lines. No placeholder/error row is added for this case — the app already
   surfaces fetch errors via the existing `snapshot.errorMessage` banner.
5. No changes to `LimitsProvider`, `RefreshCoordinator`, `UsageSnapshot`, or
   any data fetch/parsing code — this is purely a menu-construction reorder
   in `StatusItemController.makeMenu()`.

## Out of scope

- No new data source for Desktop/web-specific breakdowns (token counts,
  cost, per-model) — those aren't available locally; only the account-wide
  percentage is obtainable via the existing endpoint.
- No change to the menu bar title format.
- No change to README/docs wording (may be a quick separate follow-up, not
  bundled here).

## Testing

`StatusItemController` builds `NSMenu`/`NSMenuItem` directly and has no
existing unit test coverage (the test suite only covers pure logic:
`Formatters`, JSON extraction, decoding, resolver version). This change
stays consistent with that — verify manually:

1. `./Scripts/package.sh` (or build + `open dist/ClaudeTokenBar.app`).
2. With valid limits data: confirm the "Overall" section appears at the
   top with both header rows correctly bolded/colored, followed by the
   separator, then "Claude Code (this app)" header, then Today/Current
   block/models unchanged in content.
3. Temporarily break the credential lookup (or wait past the session reset)
   to confirm the "Overall" section disappears cleanly with no leftover
   separator or empty header.
4. Confirm weekly-limit-absent case (fresh account / API omits
   `seven_day`) still renders the Session line without a Weekly line, under
   the same "Overall" header.
