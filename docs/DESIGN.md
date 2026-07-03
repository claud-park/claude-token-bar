# ClaudeTokenBar — Design Spec (v1)

macOS menu bar widget showing live Claude Code token usage. Synthesized from two
independent design passes (deep-reasoner + Codex); pipeline decision went to the
ccusage-as-engine approach.

## Architecture

- **Form factor**: native `NSStatusItem` menu bar app, pure SPM executable
  (`swift build`, no Xcode project). `NSApplication` with
  `.setActivationPolicy(.accessory)` — no Dock icon.
- **Data engine**: shell out to `ccusage` (community CLI, already works on this
  machine). It owns dedup (`message.id`+`requestId`), 5-hour block windowing,
  and pricing tables (it prices `claude-fable-5` correctly). We do NOT parse
  the JSONL transcripts ourselves in v1.
- **Refresh**: FSEvents on `~/.claude/projects` (recursive, ~3s debounce) as
  primary trigger; 60s safety timer; refresh on menu open; refresh on
  `NSWorkspace.didWakeNotification`. A separate 60s UI tick re-renders the
  countdown only (no subprocess).
- **Change gate**: before invoking ccusage, compute a signature = set of
  `(path, mtime, size)` for `*.jsonl` under `~/.claude/projects` modified in
  the last 26h (stat-only walk; ~200 files). Signature unchanged → reuse cached
  snapshot, skip subprocess.
- **Failure mode**: ccusage error/timeout → keep showing last good snapshot,
  add ⚠ to the menu bar title and an error row in the dropdown. Never blank,
  never crash, never block the main thread.

## ccusage invocation (hard requirements — verified pitfalls)

1. Resolve binary: prefer `ccusage` on `PATH`; else `npx -y ccusage@20`
   (pinned major).
2. Run with **cwd = user home** (a temp/neutral dir is also fine). Running npx
   from a node project dir corrupts stdout with npm error JSON — verified.
3. Two calls per refresh, async off-main, ~20s timeout each:
   - `ccusage blocks --active --json --offline`
   - `ccusage daily --json --offline --since <YYYYMMDD today, local tz>`
4. **Defensive JSON extraction**: stdout may contain junk before the payload.
   Scan for the first `{` whose parse succeeds AND contains the expected
   top-level key (`blocks` / `daily`), else treat as failure.
5. `--offline` uses ccusage's cached pricing. Once per day, run one call
   without `--offline` in the background to refresh the pricing cache
   (best-effort; ignore failures).

### Observed JSON shapes (ccusage v20.0.14, guard all fields as optional)

`blocks --active --json` → `{"blocks":[{ "isActive":true, "startTime":ISO,
"endTime":ISO, "totalTokens":Int, "costUSD":Double,
"tokenCounts":{"inputTokens","outputTokens","cacheCreationInputTokens","cacheReadInputTokens"},
"burnRate":{"costPerHour","tokensPerMinute"},
"projection":{"totalCost","totalTokens","remainingMinutes"}, "models":[String] }]}`

`daily --json` → `{"daily":[{ "date", "inputTokens","outputTokens",
"cacheCreationTokens","cacheReadTokens","totalCost"?,
"modelBreakdowns":[{"modelName","inputTokens","outputTokens","cacheCreationTokens","cacheReadTokens","cost"}] }], "totals":{...}}`

## Display

- **Menu bar title**: `⚡ 55.3M · 2h41m` = active block total tokens
  (abbreviated) + time until block reset. No active block → `⚡ idle`.
  Error state appends `⚠`. While first load: `⚡ …`.
- **Dropdown menu** (plain NSMenu, disabled info items + separators):
  - `Today — $66.01 · 54.7M tokens`
  - `  in 1.7M · out 634K · cache-w 4.6M · cache-r 48.9M`
  - separator
  - `Current block (resets 14:00, 2h41m left)`
  - `  55.8M tokens · $70.41`
  - `  burn $36.6/h · proj $168 by reset`
  - separator
  - per-model today: `claude-fable-5 — $28.26` etc. (from modelBreakdowns;
    model with missing cost → `—`)
  - separator
  - `Updated 11:42:03` (info)
  - `Refresh Now` (action)
  - `Open transcripts folder` (action, opens ~/.claude/projects in Finder)
  - `Quit` (action)
- **Formatting**: tokens `999`, `1.0K`, `12.3K`, `1.2M` (1 decimal ≥1K);
  cost `$12.34` (2dp), `<$0.01` for tiny nonzero; countdown `2h 41m` / `41m`;
  all times local, derived from ccusage UTC ISO timestamps at render time
  (recompute countdown from `endTime`, never cache a delta).

## Files

```
Package.swift                      # executable, platforms: [.macOS(.v14)]
Sources/ClaudeTokenBar/
  main.swift                       # NSApplication bootstrap, accessory policy
  AppDelegate.swift                # wiring: watcher → coordinator → UI, wake notif
  StatusItemController.swift       # NSStatusItem title + NSMenu build, UI tick
  RefreshCoordinator.swift         # debounce, single-flight, signature gate, timers
  ProjectsWatcher.swift            # FSEventStream on ~/.claude/projects
  CCUsageProvider.swift            # binary resolution, Process exec, JSON extraction
  UsageSnapshot.swift              # normalized model (today + block + models + meta)
  StateStore.swift                 # last snapshot + signature → ~/Library/Application Support/ClaudeTokenBar/state.json
  Formatters.swift                 # pure functions: tokens, cost, countdown
Tests/ClaudeTokenBarTests/
  FormattersTests.swift
  JSONExtractionTests.swift        # incl. npm-junk-before-JSON fixture
  SnapshotDecodingTests.swift      # fixtures of both ccusage shapes
```

Keep dependencies zero (Foundation + AppKit + CoreServices only).
Swift 6 concurrency: annotate UI classes `@MainActor`; subprocess + file walk
on background tasks.

## Edge cases (must handle)

- No data / no active block → `idle` state, dropdown shows today only or
  "no usage today".
- First run, no cache → title `…`, populate after first fetch (~1–4s).
- ccusage missing (no PATH binary, npx fails) → persistent ⚠ + error row
  "ccusage unavailable — npm i -g ccusage".
- Timezone/clock change, wake from sleep → recompute immediately.
- Signature gate must include file deletions (set comparison, not just max mtime).

## Verification plan

1. `swift build` + `swift test` green.
2. Launch app, confirm menu bar item appears with block tokens + countdown.
3. Cross-check dropdown numbers against `ccusage daily` and
   `ccusage blocks --active` run manually — must match exactly (same engine).
4. Touch a jsonl under ~/.claude/projects → single refresh within ~5s.
