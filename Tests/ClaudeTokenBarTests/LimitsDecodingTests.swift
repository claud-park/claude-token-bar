import XCTest
@testable import ClaudeTokenBar

final class LimitsDecodingTests: XCTestCase {

    private let fixture = """
    {
     "five_hour": {
      "utilization": 96.0,
      "resets_at": "2026-07-03T10:20:00.450756+00:00",
      "limit_dollars": null
     },
     "seven_day": {
      "utilization": 20.0,
      "resets_at": "2026-07-09T07:00:00.450777+00:00"
     },
     "seven_day_opus": null,
     "extra_usage": {"is_enabled": false}
    }
    """

    func testDecodesAndMapsOAuthUsageResponse() throws {
        let decoded = try JSONDecoder().decode(OAuthUsageResponse.self, from: Data(fixture.utf8))
        let mapped = LimitsProvider.map(decoded)
        XCTAssertEqual(mapped?.sessionPercent, 96.0)
        XCTAssertEqual(mapped?.weeklyPercent, 20.0)
        // Microsecond fractions must still parse (trimmed to milliseconds).
        XCTAssertNotNil(mapped?.sessionResetsAt)
        XCTAssertNotNil(mapped?.weeklyResetsAt)
    }

    func testMissingFiveHourMapsToNil() throws {
        let decoded = try JSONDecoder().decode(OAuthUsageResponse.self, from: Data("{}".utf8))
        XCTAssertNil(LimitsProvider.map(decoded))
    }

    func testPercentFormatting() {
        XCTAssertEqual(Formatters.percent(96.0), "96%")
        XCTAssertEqual(Formatters.percent(0.4), "0%")
        XCTAssertEqual(Formatters.percent(99.6), "100%")
        XCTAssertEqual(Formatters.percent(-1), "0%")
    }
}
