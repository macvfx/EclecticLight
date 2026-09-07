import XCTest
@testable import EclecticLightUpdater

final class ActivityLogTests: XCTestCase {
    @MainActor func testLogSurvivesReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ActivityLog(directory: directory)
        first.append("Example app: extraction failed")
        let second = ActivityLog(directory: directory)
        XCTAssertTrue(second.text.contains("Example app: extraction failed"))
        XCTAssertTrue(second.errorMessage.isEmpty)
        XCTAssertTrue(try String(contentsOf: second.url, encoding: .utf8).contains("Example app: extraction failed"))
    }
}
