import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private static let icon = "🐾"

    private let statusItem: NSStatusItem
    private var snapshot = UsageSnapshot.empty
    private var refreshAction: (() -> Void)?
    private var uiTickTimer: Timer?

    init(statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)) {
        self.statusItem = statusItem
        super.init()
        // Without an autosave name the item persists visibility under the shared
        // "Item-0" key in com.apple.controlcenter — a stale hidden flag there
        // (observed on this machine) silently hides every unnamed status item.
        statusItem.autosaveName = "ClaudeTokenBar"
        statusItem.isVisible = true
        // Tahoe hosts status items out-of-process in Control Center; title-only
        // buttons fail to propagate content/width and collapse to zero. An
        // image-based button (template SF Symbol) is required to render.
        let paw = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Claude token usage")
        paw?.isTemplate = true
        statusItem.button?.image = paw
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = " ..."
        statusItem.menu = makeMenu()
        uiTickTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.renderTitle()
                self?.statusItem.menu = self?.makeMenu()
            }
        }
    }

    func setRefreshAction(_ action: @escaping () -> Void) {
        refreshAction = action
    }

    func render(_ snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        renderTitle()
        statusItem.menu = makeMenu()
        if ProcessInfo.processInfo.environment["CLAUDETOKENBAR_DEBUG"] != nil {
            let frame = statusItem.button?.window?.frame ?? .zero
            FileHandle.standardError.write(Data("DEBUG isVisible=\(statusItem.isVisible) title='\(statusItem.button?.title ?? "nil")' windowFrame=\(frame)\n".utf8))
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshAction?()
    }

    private func renderTitle() {
        let title: String
        if snapshot.updatedAt == .distantPast {
            title = " ..."
        } else if let block = snapshot.block, block.endTime > Date() {
            if let limits = currentLimits() {
                title = " \(Formatters.tokens(block.totalTokens)) · \(Formatters.percent(limits.sessionPercent))"
            } else {
                title = " \(Formatters.tokens(block.totalTokens)) · \(Formatters.countdown(from: Date(), to: block.endTime))"
            }
        } else if let limits = currentLimits() {
            title = " \(Formatters.percent(limits.sessionPercent))"
        } else {
            title = " idle"
        }
        statusItem.button?.title = snapshot.errorMessage == nil ? title : "\(title) ⚠"
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        if let error = snapshot.errorMessage {
            menu.addItem(disabledItem("⚠ \(error)"))
            menu.addItem(.separator())
        }

        if let today = snapshot.today {
            menu.addItem(disabledItem("Today - \(Formatters.cost(today.totalCost)) · \(Formatters.tokens(today.totalTokens)) tokens"))
            menu.addItem(disabledItem("  in \(Formatters.tokens(today.inputTokens)) · out \(Formatters.tokens(today.outputTokens)) · cache-w \(Formatters.tokens(today.cacheCreationTokens)) · cache-r \(Formatters.tokens(today.cacheReadTokens))"))
        } else {
            menu.addItem(disabledItem("No usage today"))
        }

        menu.addItem(.separator())

        if let limits = currentLimits() {
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

    /// Limits data is only trustworthy until its own reset time — after that,
    /// carry-over from a failed refresh would show a stale percentage, so fall
    /// back to the countdown display instead.
    private func currentLimits() -> LimitsSnapshot? {
        guard let limits = snapshot.limits else { return nil }
        if let resets = limits.sessionResetsAt, resets <= Date() { return nil }
        return limits
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func refreshNow() {
        refreshAction?()
    }

    @objc private func openTranscriptsFolder() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
