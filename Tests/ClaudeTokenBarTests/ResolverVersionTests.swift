import XCTest
@testable import ClaudeTokenBar

final class ResolverVersionTests: XCTestCase {

    func testAcceptsMinimumAndNewerMajors() {
        XCTAssertTrue(CCUsageResolver.isSupportedVersion("20.0.14"))
        XCTAssertTrue(CCUsageResolver.isSupportedVersion("ccusage 21.3.0\n"))
    }

    func testRejectsStaleMajors() {
        XCTAssertFalse(CCUsageResolver.isSupportedVersion("17.2.0"))
        XCTAssertFalse(CCUsageResolver.isSupportedVersion("ccusage 19.9.9"))
    }

    func testRejectsGarbageOutput() {
        XCTAssertFalse(CCUsageResolver.isSupportedVersion(""))
        XCTAssertFalse(CCUsageResolver.isSupportedVersion("command not found"))
    }
}
