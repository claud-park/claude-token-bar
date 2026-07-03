import XCTest
@testable import ClaudeTokenBar

final class JSONExtractionTests: XCTestCase {
    func testExtractsObjectContainingExpectedTopLevelKeyAfterNPMJunk() throws {
        let stdout = """
        npm ERR! code EUSAGE
        {"error":{"code":"npm-noise"}}
        warning: retrying
        {"blocks":[{"isActive":true,"totalTokens":123}]}
        """

        let data = try XCTUnwrap(JSONExtractor.extractJSONObject(from: stdout, expectedKey: "blocks"))
        let decoded = try JSONDecoder().decode(BlocksResponse.self, from: data)

        XCTAssertEqual(decoded.blocks.first?.isActive, true)
        XCTAssertEqual(decoded.blocks.first?.totalTokens, 123)
    }

    func testReturnsNilWhenExpectedKeyIsAbsent() {
        let stdout = #"prefix {"daily":[]} suffix"#
        XCTAssertNil(JSONExtractor.extractJSONObject(from: stdout, expectedKey: "blocks"))
    }
}
