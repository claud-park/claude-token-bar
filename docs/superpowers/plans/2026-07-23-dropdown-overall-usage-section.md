# Dropdown Overall Usage Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the ClaudeTokenBar menu-bar dropdown so the account-wide Session/Weekly limit percentages appear in a visually distinct "Overall (Web + Desktop + Code)" section at the top, separated from a "Claude Code (this app)" section containing the existing local-transcript stats (Today / Current block / per-model).

**Architecture:** Single-file change to `Sources/ClaudeTokenBar/StatusItemController.swift`. Add one new private helper, `sectionHeaderItem(_:)`, that builds a non-interactive `NSMenuItem` with a bold, secondary-colored `attributedTitle`. Reorder the body of `makeMenu()` to emit the two headers in the right places. No other file changes — `LimitsProvider`, `RefreshCoordinator`, `UsageSnapshot`, and `Formatters` are untouched; all data these sections show is already fetched today.

**Tech Stack:** Swift 6.0, AppKit (`NSMenu`, `NSMenuItem`, `NSAttributedString`), Swift Package Manager.

## Global Constraints

- No changes to data fetching, parsing, or the `LimitsSnapshot`/`UsageSnapshot` models — this is a menu-layout-only change (per spec "Design" step 5 and "Out of scope").
- When `currentLimits()` returns `nil`, the entire "Overall" section (header + lines) must be omitted — no placeholder/error row (spec step 4).
- Section headers use `NSFont.systemFont(ofSize: 11, weight: .semibold)` and `NSColor.secondaryLabelColor` (spec step 3).
- Exact header copy: `🌐 Overall (Web + Desktop + Code)` and `💻 Claude Code (this app)` (spec design mockup).
- No automated UI test is added: `StatusItemController` has zero existing unit test coverage (the test suite only covers pure logic — `Formatters`, JSON extraction, decoding, resolver version) and `NSMenu`/`NSMenuItem` construction isn't practically unit-testable without a running app session. This plan verifies via `swift build` (compile correctness) plus the manual QA checklist from the spec's Testing section, consistent with existing project conventions.

---

### Task 1: Add section-header helper and reorder the dropdown menu

**Files:**
- Modify: `Sources/ClaudeTokenBar/StatusItemController.swift:75-140` (`makeMenu()`), and `:151-155` (add new helper next to `disabledItem(_:)`)

**Interfaces:**
- Consumes: `LimitsSnapshot` (`sessionPercent: Double`, `sessionResetsAt: Date?`, `weeklyPercent: Double?`, `weeklyResetsAt: Date?`) from `LimitsProvider.swift:17-22`; `currentLimits() -> LimitsSnapshot?` (existing private method, `StatusItemController.swift:145-149`, unchanged); `Formatters.percent(_:)` and `Formatters.resetTime(_:)`/`Formatters.resetDay(_:)` (existing, unchanged).
- Produces: new private method `sectionHeaderItem(_ title: String) -> NSMenuItem` for use within `StatusItemController` only (not consumed by any other file).

- [ ] **Step 1: Add the `sectionHeaderItem(_:)` helper**

Add this new private method immediately after the existing `disabledItem(_:)` method (currently `StatusItemController.swift:151-155`):

```swift
    private func sectionHeaderItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        return item
    }
```

- [ ] **Step 2: Reorder `makeMenu()` to emit the "Overall" section first**

Replace the full body of `makeMenu()` (`StatusItemController.swift:75-140`) with:

```swift
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        if let error = snapshot.errorMessage {
            menu.addItem(disabledItem("⚠ \(error)"))
            menu.addItem(.separator())
        }

        if let limits = currentLimits() {
            menu.addItem(sectionHeaderItem("🌐 Overall (Web + Desktop + Code)"))
            var session = "Session limit \(Formatters.percent(limits.sessionPercent)) used"
            if let resets = limits.sessionResetsAt {
                session += " · resets \(Formatters.resetTime(resets))"
            }
            menu.addItem(disabledItem(session))
            if let weekly = limits.weeklyPercent {
                var week = "Weekly limit \(Formatters.percent(weekly)) used"
                if let resets = limits.weeklyResetsAt {
                    week += " · resets \(Formatters.resetDay(resets))"
                }
                menu.addItem(disabledItem(week))
            }
            menu.addItem(.separator())
        }

        menu.addItem(sectionHeaderItem("💻 Claude Code (this app)"))

        if let today = snapshot.today {
            menu.addItem(disabledItem("Today - \(Formatters.cost(today.totalCost)) · \(Formatters.tokens(today.totalTokens)) tokens"))
            menu.addItem(disabledItem("  in \(Formatters.tokens(today.inputTokens)) · out \(Formatters.tokens(today.outputTokens)) · cache-w \(Formatters.tokens(today.cacheCreationTokens)) · cache-r \(Formatters.tokens(today.cacheReadTokens))"))
        } else {
            menu.addItem(disabledItem("No usage today"))
        }

        menu.addItem(.separator())

        if let block = snapshot.block, block.endTime > Date() {
            menu.addItem(disabledItem("Current block (resets \(Formatters.resetTime(block.endTime)), \(Formatters.countdown(from: Date(), to: block.endTime)) left)"))
            menu.addItem(disabledItem("  \(Formatters.tokens(block.totalTokens)) tokens · \(Formatters.cost(block.costUSD))"))
            let burn = block.costPerHour.map { Formatters.cost($0) + "/h" } ?? "-"
            let projection = block.projectedCost.map { Formatters.cost($0) } ?? "-"
            menu.addItem(disabledItem("  burn \(burn) · proj \(projection) by reset"))
        } else {
            menu.addItem(disabledItem("Current block - idle"))
        }

        if let models = snapshot.today?.models, !models.isEmpty {
            menu.addItem(.separator())
            for model in models {
                let cost = model.cost.map(Formatters.cost) ?? "-"
                menu.addItem(disabledItem("\(model.name) - \(cost)"))
            }
        }

        menu.addItem(.separator())
        if snapshot.updatedAt == .distantPast {
            menu.addItem(disabledItem("Updated -"))
        } else {
            menu.addItem(disabledItem("Updated \(Formatters.time(snapshot.updatedAt))"))
        }

        menu.addItem(actionItem("Refresh Now", action: #selector(refreshNow)))
        menu.addItem(actionItem("Open transcripts folder", action: #selector(openTranscriptsFolder)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit", action: #selector(quit)))

        return menu
    }
```

This is a pure reorder of the existing lines from the original `makeMenu()`, plus: the `sectionHeaderItem("🌐 Overall …")` call inserted right before the (now-first) Session/Weekly block, and the `sectionHeaderItem("💻 Claude Code …")` call inserted unconditionally right before the "Today" block. Everything from "Today" downward is byte-for-byte identical to the original — only its position relative to the Overall block moved.

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: `Build complete!` with no errors or warnings about `StatusItemController.swift`.

- [ ] **Step 4: Run the existing test suite to confirm no regressions**

Run: `swift test`
Expected: all existing tests pass (this change touches no code any test covers, so this is a regression guard, not new coverage).

- [ ] **Step 5: Package and manually verify the dropdown**

Run: `./Scripts/package.sh && open dist/ClaudeTokenBar.app`

Then, with the app running, click the 🐾 menu bar icon and check:

1. **Normal case (limits available):** "🌐 Overall (Web + Desktop + Code)" appears at the top in bold/secondary-colored text, followed by the Session limit line and (if present) Weekly limit line, then a separator, then "💻 Claude Code (this app)" in the same bold style, then Today / Current block / per-model lines exactly as before.
2. **Limits unavailable:** disconnect from the network before launching the app (or quit/relaunch with Wi-Fi off) so the `/api/oauth/usage` fetch in `LimitsProvider.fetch()` fails — confirm the "Overall" header and its lines are completely absent (no empty header, no dangling separator), and the menu opens starting directly at "💻 Claude Code (this app)".
3. **No weekly limit:** if the API response has no `seven_day` field, confirm only the Session limit line renders under "Overall" (no empty Weekly line).
4. Quit the app (`Quit` menu item) when done.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeTokenBar/StatusItemController.swift
git commit -m "$(cat <<'EOF'
feat: split dropdown into Overall and Claude Code sections

Session/Weekly limit percentages reflect the whole Claude account
(web + desktop + Code) on Pro/Max plans, not just this app's local
activity. Move them to a labeled "Overall" section at the top of the
dropdown, separated from the existing Claude-Code-local stats.
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** step 1 (move Overall to top) → Task 1 Step 2. Step 2 (add "Claude Code (this app)" header) → Task 1 Step 2. Step 3 (bold/secondary-colored header styling via `attributedTitle`) → Task 1 Step 1. Step 4 (omit Overall section entirely when `currentLimits()` is nil) → Task 1 Step 2 (`if let limits = currentLimits() { … }` guards the whole block, unchanged from original). Step 5 (no data/fetch changes) → confirmed, only `StatusItemController.swift` touched. Testing steps 1-4 from the spec → Task 1 Step 5, items 1-3 (weekly-absent case folded into item 3).
- **Placeholder scan:** none — every step has literal code or an exact command with expected output.
- **Type consistency:** `sectionHeaderItem(_ title: String) -> NSMenuItem` matches its two call sites in Step 2; `disabledItem`, `actionItem`, `currentLimits()`, `Formatters.*` all match their existing signatures in the codebase (verified against `StatusItemController.swift` as read during planning).
