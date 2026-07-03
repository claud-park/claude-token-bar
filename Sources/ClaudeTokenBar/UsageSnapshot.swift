import Foundation

// MARK: - Raw ccusage JSON shapes (all fields optional/defensive per spec)

struct TokenCounts: Decodable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
}

struct BurnRate: Decodable, Sendable {
    let costPerHour: Double?
    let tokensPerMinute: Double?
}

struct BlockProjection: Decodable, Sendable {
    let totalCost: Double?
    let totalTokens: Int?
    let remainingMinutes: Double?
}

struct BlockEntry: Decodable, Sendable {
    let isActive: Bool?
    let startTime: String?
    let endTime: String?
    let totalTokens: Int?
    let costUSD: Double?
    let tokenCounts: TokenCounts?
    let burnRate: BurnRate?
    let projection: BlockProjection?
    let models: [String]?
}

struct BlocksResponse: Decodable, Sendable {
    let blocks: [BlockEntry]
}

struct ModelBreakdown: Decodable, Sendable {
    let modelName: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationTokens: Int?
    let cacheReadTokens: Int?
    let cost: Double?
}

struct DailyEntry: Decodable, Sendable {
    let date: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationTokens: Int?
    let cacheReadTokens: Int?
    let totalCost: Double?
    let modelBreakdowns: [ModelBreakdown]?
}

struct DailyResponse: Decodable, Sendable {
    let daily: [DailyEntry]
}

// MARK: - Normalized app-facing model

struct ModelUsage: Codable, Sendable, Equatable {
    let name: String
    let cost: Double?
}

struct TodaySummary: Codable, Sendable, Equatable {
    let date: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let totalCost: Double
    let models: [ModelUsage]
}

struct BlockSummary: Codable, Sendable, Equatable {
    let startTime: Date
    let endTime: Date
    let totalTokens: Int
    let costUSD: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let costPerHour: Double?
    let tokensPerMinute: Double?
    let projectedCost: Double?
    let projectedTotalTokens: Int?
    let models: [String]
}

struct UsageSnapshot: Codable, Sendable, Equatable {
    var today: TodaySummary?
    var block: BlockSummary?
    var updatedAt: Date
    var errorMessage: String?

    static let empty = UsageSnapshot(today: nil, block: nil, updatedAt: .distantPast, errorMessage: nil)
}

// MARK: - Mapping from raw ccusage responses to the normalized model

enum SnapshotMapper {

    private static func makeISOFormatter(withFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = withFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return makeISOFormatter(withFractionalSeconds: true).date(from: string)
            ?? makeISOFormatter(withFractionalSeconds: false).date(from: string)
    }

    static func mapDaily(_ response: DailyResponse) -> TodaySummary? {
        guard let entry = response.daily.first else { return nil }
        let models = (entry.modelBreakdowns ?? []).map {
            ModelUsage(name: $0.modelName ?? "unknown", cost: $0.cost)
        }
        let input = entry.inputTokens ?? 0
        let output = entry.outputTokens ?? 0
        let cacheCreation = entry.cacheCreationTokens ?? 0
        let cacheRead = entry.cacheReadTokens ?? 0
        return TodaySummary(
            date: entry.date ?? "",
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: cacheCreation,
            cacheReadTokens: cacheRead,
            totalTokens: input + output + cacheCreation + cacheRead,
            totalCost: entry.totalCost ?? 0,
            models: models
        )
    }

    static func mapBlock(_ response: BlocksResponse) -> BlockSummary? {
        guard let entry = (response.blocks.first { $0.isActive == true }),
              let start = parseDate(entry.startTime),
              let end = parseDate(entry.endTime)
        else { return nil }

        let counts = entry.tokenCounts
        return BlockSummary(
            startTime: start,
            endTime: end,
            totalTokens: entry.totalTokens ?? 0,
            costUSD: entry.costUSD ?? 0,
            inputTokens: counts?.inputTokens ?? 0,
            outputTokens: counts?.outputTokens ?? 0,
            cacheCreationTokens: counts?.cacheCreationInputTokens ?? 0,
            cacheReadTokens: counts?.cacheReadInputTokens ?? 0,
            costPerHour: entry.burnRate?.costPerHour,
            tokensPerMinute: entry.burnRate?.tokensPerMinute,
            projectedCost: entry.projection?.totalCost,
            projectedTotalTokens: entry.projection?.totalTokens,
            models: entry.models ?? []
        )
    }

    /// Builds a fresh snapshot, falling back to `previous` per-section when a fetch
    /// did not run/succeed (nil response) so the UI never blanks a section that
    /// simply wasn't refetched this cycle.
    static func build(
        daily: DailyResponse?,
        blocks: BlocksResponse?,
        previous: UsageSnapshot,
        updatedAt: Date,
        errorMessage: String?
    ) -> UsageSnapshot {
        let today: TodaySummary?
        if let daily {
            today = mapDaily(daily)
        } else {
            today = previous.today
        }

        let block: BlockSummary?
        if let blocks {
            block = mapBlock(blocks)
        } else {
            block = previous.block
        }

        return UsageSnapshot(today: today, block: block, updatedAt: updatedAt, errorMessage: errorMessage)
    }
}
