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

    func testGoldenGateNamesAndRanges() {
        XCTAssertEqual(check("Golden Gate", 27, 1), .compatible)
        XCTAssertEqual(check("Tahoe and Golden Gate", 27), .compatible)
        XCTAssertEqual(check("Big Sur to Golden Gate", 27, 6), .compatible)
        XCTAssertEqual(check("Golden Gate only", 26), .possibleMismatch)
        XCTAssertEqual(check("Golden Gate", 28), .possibleMismatch)
    }

    func testGoldenGateSnapshotAndIdentityMappings() {
        let entries = CatalogFetcher.applyCatalogExceptions(to: [:])
        for release in CatalogFetcher.goldenGateReleases {
            let latest = entries[release.key]?.latest
            XCTAssertEqual(latest?.version, release.version, release.name)
            XCTAssertEqual(check(latest?.compat ?? "", 27), .compatible, release.name)
        }
        XCTAssertNil(entries["cirrus"])
        XCTAssertNil(entries["t2m2"])
        XCTAssertNotNil(entries["cirrusmac"])
        XCTAssertNotNil(entries["thetimemachinemechanic2"])
        XCTAssertTrue(entries["silentknight3"]!.latest!.compat.contains("Apple silicon only"))
        XCTAssertTrue(entries["logui"]!.latest!.compat.contains("build 88"))
        XCTAssertTrue(entries["alisma"]!.latest!.compat.contains("believes"))
    }

    func testGoldenGateEvidenceDoesNotLeakToOtherVersionsOrArchives() {
        let release = CatalogFetcher.goldenGateReleases.first { $0.key == "mints" }!
        let original = CatalogEntry(key: "mints", name: "Mints", versions: [
            CatalogVersion(version: "1.21", url: "https://example.com/old.zip", compat: "Tahoe"),
            CatalogVersion(version: release.version, url: release.url, compat: "Sonoma and Tahoe"),
            CatalogVersion(version: "1.23", url: "https://example.com/new.zip", compat: "Tahoe")
        ])
        let result = CatalogFetcher.applyGoldenGateCompatibility(to: ["mints": original])["mints"]!
        XCTAssertEqual(result.latest?.version, "1.23")
        XCTAssertEqual(result.latest?.compat, "Tahoe")
        XCTAssertEqual(result.versions[0].compat, "Tahoe")
        XCTAssertEqual(check(result.versions[1].compat, 14), .compatible)
        XCTAssertEqual(check(result.versions[1].compat, 27), .compatible)
        let repeated = CatalogFetcher.applyGoldenGateCompatibility(to: ["mints": result])["mints"]!
        XCTAssertEqual(repeated.versions.map(\.compat), result.versions.map(\.compat))
        let alternate = CatalogEntry(key: "mints", name: "Mints", versions: [
            CatalogVersion(version: release.version, url: "https://example.com/other.zip", compat: "Tahoe")
        ])
        let untouched = CatalogFetcher.applyGoldenGateCompatibility(to: ["mints": alternate])["mints"]!
        XCTAssertEqual(untouched.versions.count, 1)
        XCTAssertEqual(untouched.latest?.compat, "Tahoe")
    }

    func testCompatibilitySurvivesCatalogParsing() {
        let html = "<a href=\"https://example.com/wp-content/uploads/2026/09/example12.zip\">Example 1.2</a> (Universal App for Sonoma, Sequoia and Tahoe)"
        let entry = CatalogFetcher.parseDownloadsPage(html)["example"]
        XCTAssertEqual(check(entry?.latest?.compat ?? ""), .compatible)
    }
}
