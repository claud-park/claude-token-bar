import Foundation

@MainActor
final class RefreshCoordinator {
    private let provider: CCUsageProvider
    private let store: StateStore
    private let projectsURL: URL
    private let onSnapshot: @MainActor (UsageSnapshot) -> Void

    private var snapshot = UsageSnapshot.empty
    private var signature: ProjectSignature?
    private var pricingRefreshDay: String?
    private var isRefreshing = false
    private var pendingForceRefresh = false
    private var debounceTask: Task<Void, Never>?
    private var safetyTimer: Timer?

    init(
        provider: CCUsageProvider,
        store: StateStore,
        projectsURL: URL,
        onSnapshot: @escaping @MainActor (UsageSnapshot) -> Void
    ) {
        self.provider = provider
        self.store = store
        self.projectsURL = projectsURL
        self.onSnapshot = onSnapshot
    }

    func start() {
        Task {
            let stored = await store.load()
            snapshot = stored.snapshot
            signature = stored.signature
            pricingRefreshDay = stored.pricingRefreshDay
            onSnapshot(snapshot)
            refreshNow(force: true)
        }

        safetyTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow(force: false)
            }
        }
    }

    func stop() {
        safetyTimer?.invalidate()
        safetyTimer = nil
        debounceTask?.cancel()
    }

    func scheduleDebouncedRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.refreshNow(force: false)
        }
    }

    func refreshNow(force: Bool) {
        if isRefreshing {
            pendingForceRefresh = pendingForceRefresh || force
            return
        }

        isRefreshing = true
        Task {
            await performRefresh(force: force)
            isRefreshing = false

            if pendingForceRefresh {
                pendingForceRefresh = false
                refreshNow(force: true)
            }
        }
    }

    private func performRefresh(force: Bool) async {
        let newSignature = await Task.detached(priority: .utility) {
            ProjectsWatcher.computeSignature(at: self.projectsURL)
        }.value

        if !force, newSignature == signature {
            onSnapshot(snapshot)
            return
        }

        let todayString = Self.yyyymmdd(Date())
        let fetchResult = await fetchSnapshotPieces(sinceYYYYMMDD: todayString)
        let newSnapshot = SnapshotMapper.build(
            daily: fetchResult.daily,
            blocks: fetchResult.blocks,
            previous: snapshot,
            updatedAt: Date(),
            errorMessage: fetchResult.errorMessage
        )

        snapshot = newSnapshot
        signature = newSignature
        onSnapshot(newSnapshot)
        await store.save(StoredState(snapshot: newSnapshot, signature: newSignature, pricingRefreshDay: pricingRefreshDay))
        maybeRefreshPricingCache(todayString)
    }

    private func fetchSnapshotPieces(sinceYYYYMMDD: String) async -> (daily: DailyResponse?, blocks: BlocksResponse?, errorMessage: String?) {
        async let dailyFetch: Result<DailyResponse, Error> = result { try await self.provider.fetchDaily(sinceYYYYMMDD: sinceYYYYMMDD) }
        async let blocksFetch: Result<BlocksResponse, Error> = result { try await self.provider.fetchBlocks() }

        let dailyResult = await dailyFetch
        let blocksResult = await blocksFetch

        var errors: [String] = []
        let daily: DailyResponse?
        switch dailyResult {
        case .success(let response):
            daily = response
        case .failure(let error):
            daily = nil
            errors.append(displayMessage(for: error))
        }

        let blocks: BlocksResponse?
        switch blocksResult {
        case .success(let response):
            blocks = response
        case .failure(let error):
            blocks = nil
            errors.append(displayMessage(for: error))
        }

        return (daily, blocks, errors.first)
    }

    private func maybeRefreshPricingCache(_ todayString: String) {
        guard pricingRefreshDay != todayString else { return }
        pricingRefreshDay = todayString
        Task {
            await provider.refreshPricingCacheBestEffort()
            await store.save(StoredState(snapshot: snapshot, signature: signature, pricingRefreshDay: todayString))
        }
    }

    private static func yyyymmdd(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

private func result<T: Sendable>(_ body: @Sendable @escaping () async throws -> T) async -> Result<T, Error> {
    do {
        return .success(try await body())
    } catch {
        return .failure(error)
    }
}

private func displayMessage(for error: Error) -> String {
    if let fetchError = error as? CCUsageProvider.FetchError {
        switch fetchError {
        case .ccusageUnavailable:
            return "ccusage unavailable - npm i -g ccusage"
        case .timeout:
            return "ccusage timed out"
        case .invalidOutput:
            return "ccusage returned invalid JSON"
        case .processFailed(let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "ccusage failed" : trimmed
        }
    }
    return error.localizedDescription
}
