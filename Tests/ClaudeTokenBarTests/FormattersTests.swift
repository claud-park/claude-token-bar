import XCTest
@testable import ClaudeTokenBar

final class FormattersTests: XCTestCase {
    func testTokensUseRawValueBelowOneThousand() {
        XCTAssertEqual(Formatters.tokens(999), "999")
        XCTAssertEqual(Formatters.tokens(-42), "-42")
    }

    func testTokensUseOneDecimalSuffixesAtThousandsAndMillions() {
        XCTAssertEqual(Formatters.tokens(1_000), "1.0K")
        XCTAssertEqual(Formatters.tokens(12_345), "12.3K")
        XCTAssertEqual(Formatters.tokens(1_234_567), "1.2M")
        XCTAssertEqual(Formatters.tokens(-1_234), "-1.2K")
    }

    func testCostFormatsTwoDecimalsAndTinyNonzeroAmounts() {
        XCTAssertEqual(Formatters.cost(12.345), "$12.35")
        XCTAssertEqual(Formatters.cost(0), "$0.00")
        XCTAssertEqual(Formatters.cost(0.001), "<$0.01")
        XCTAssertEqual(Formatters.cost(-0.001), "<$0.01")
    }

    func testCountdownUsesHoursAndMinutesAndNeverGoesNegative() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(Formatters.countdown(from: now, to: now.addingTimeInterval(9_660)), "2h 41m")
        XCTAssertEqual(Formatters.countdown(from: now, to: now.addingTimeInterval(2_460)), "41m")
        XCTAssertEqual(Formatters.countdown(from: now, to: now.addingTimeInterval(-10)), "0m")
    }
}
