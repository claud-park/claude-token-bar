import XCTest
@testable import ClaudeTokenBar

final class SnapshotDecodingTests: XCTestCase {
    func testDecodesAndMapsActiveBlockShapeFromSpec() throws {
        let json = """
        {
          "blocks": [{
            "isActive": true,
            "startTime": "2026-07-03T00:00:00.000Z",
            "endTime": "2026-07-03T05:00:00.000Z",
            "totalTokens": 55800000,
            "costUSD": 70.41,
            "tokenCounts": {
              "inputTokens": 1700000,
              "outputTokens": 634000,
              "cacheCreationInputTokens": 4600000,
              "cacheReadInputTokens": 48866000
            },
            "burnRate": {
              "costPerHour": 36.6,
              "tokensPerMinute": 18400.5
            },
            "projection": {
              "totalCost": 168,
              "totalTokens": 99000000,
              "remainingMinutes": 161
            },
            "models": ["claude-fable-5"]
          }]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(BlocksResponse.self, from: json)
        let block = try XCTUnwrap(SnapshotMapper.mapBlock(response))

        XCTAssertEqual(block.totalTokens, 55_800_000)
        XCTAssertEqual(block.costUSD, 70.41)
        XCTAssertEqual(block.cacheCreationTokens, 4_600_000)
        XCTAssertEqual(block.cacheReadTokens, 48_866_000)
        XCTAssertEqual(block.costPerHour, 36.6)
        XCTAssertEqual(block.projectedCost, 168)
        XCTAssertEqual(block.models, ["claude-fable-5"])
    }

    func testDecodesAndMapsDailyShapeFromSpec() throws {
        let json = """
        {
          "daily": [{
            "date": "2026-07-03",
            "inputTokens": 1700000,
            "outputTokens": 634000,
            "cacheCreationTokens": 4600000,
            "cacheReadTokens": 48866000,
            "totalCost": 66.01,
            "modelBreakdowns": [{
              "modelName": "claude-fable-5",
              "inputTokens": 100,
              "outputTokens": 200,
              "cacheCreationTokens": 300,
              "cacheReadTokens": 400,
              "cost": 28.26
            }, {
              "modelName": "claude-sonnet-4",
              "inputTokens": 1,
              "outputTokens": 2,
              "cacheCreationTokens": 3,
              "cacheReadTokens": 4
            }]
          }],
          "totals": {
            "inputTokens": 1700000
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DailyResponse.self, from: json)
        let today = try XCTUnwrap(SnapshotMapper.mapDaily(response))

        XCTAssertEqual(today.date, "2026-07-03")
        XCTAssertEqual(today.totalTokens, 55_800_000)
        XCTAssertEqual(today.totalCost, 66.01)
        XCTAssertEqual(today.models[0], ModelUsage(name: "claude-fable-5", cost: 28.26))
        XCTAssertEqual(today.models[1], ModelUsage(name: "claude-sonnet-4", cost: nil))
    }
}
