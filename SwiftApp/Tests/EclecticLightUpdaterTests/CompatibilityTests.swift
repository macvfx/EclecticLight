import XCTest
@testable import EclecticLightUpdater

final class CompatibilityTests: XCTestCase {
    private func check(_ text: String, _ major: Int = 26, _ minor: Int = 0, _ patch: Int = 0) -> OSCompatibility {
        OSCompatibility.evaluate(text, system: OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch))
    }

    func testNamedListsAndRanges() {
        XCTAssertEqual(check("Universal App for Sonoma, Sequoia and Tahoe"), .compatible)
        XCTAssertEqual(check("Universal App for Big Sur to Tahoe", 14), .compatible)
        XCTAssertEqual(check("Universal App for Big Sur to Tahoe", 26, 6, 2), .compatible)
        XCTAssertEqual(check("Universal App for Catalina to Sequoia"), .possibleMismatch)
        XCTAssertEqual(check("Universal App for Sonoma and Sequoia"), .possibleMismatch)
        XCTAssertEqual(check("Tahoe only", 15), .possibleMismatch)
        XCTAssertEqual(check("High Sierra only", 10, 12), .possibleMismatch)
        XCTAssertEqual(check("High Sierra only", 10, 13, 6), .compatible)
    }

    func testMinimumVersionsAndUnknownText() {
        XCTAssertEqual(check("Sonoma 14.6 and later"), .compatible)
        XCTAssertEqual(check("Sonoma 14.6 and later", 14, 5), .possibleMismatch)
        XCTAssertEqual(check("Sonoma 14.6 and later", 14, 6), .compatible)
        XCTAssertEqual(check("macOS 26.2 or newer", 26, 1), .possibleMismatch)
        XCTAssertEqual(check("macOS 26.2 or newer", 26, 3), .compatible)
        XCTAssertEqual(check("Universal App"), .unknown)
        XCTAssertEqual(check(""), .unknown)
        XCTAssertEqual(check("Not compatible with Tahoe"), .unknown)
        XCTAssertEqual(check("Tahoe", 27), .possibleMismatch)
    }

    func testCompatibilitySurvivesCatalogParsing() {
        let html = "<a href=\"https://example.com/wp-content/uploads/2026/09/example12.zip\">Example 1.2</a> (Universal App for Sonoma, Sequoia and Tahoe)"
        let entry = CatalogFetcher.parseDownloadsPage(html)["example"]
        XCTAssertEqual(check(entry?.latest?.compat ?? ""), .compatible)
    }
}
