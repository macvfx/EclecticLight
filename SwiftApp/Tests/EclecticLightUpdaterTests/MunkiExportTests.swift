import XCTest
@testable import EclecticLightUpdater

final class MunkiExportTests: XCTestCase {
    func testArtifactNamesPreserveVersionDots() {
        XCTAssertEqual(munkiArtifactName(key: "logui", version: "1.1", extension: "dmg"), "logui-1.1.dmg")
        XCTAssertEqual(munkiArtifactName(key: "alisma", version: "4", extension: "pkg"), "alisma-4.pkg")
        XCTAssertEqual(munkiArtifactName(key: "example", version: "1.2.3b1", extension: "dmg"), "example-1.2.3b1.dmg")
    }

    @MainActor func testLiveAppAndPackageExport() async throws {
        guard ProcessInfo.processInfo.environment["ELU_LIVE_EXPORT_TEST"] == "1" else {
            throw XCTSkip("Opt-in download and disk-image integration test")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("elu-export-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let exporter = MunkiExporter()
        exporter.entries = [
            CatalogEntry(key: "cirrusmac", name: "Cirrus", versions: [CatalogVersion(version: "1.16", url: "https://eclecticlight.co/wp-content/uploads/2025/06/cirrus116.zip", compat: "Tahoe")]),
            CatalogEntry(key: "alisma", name: "alisma", versions: [CatalogVersion(version: "4", url: "https://eclecticlight.co/wp-content/uploads/2023/07/alisma4.zip", compat: "Tahoe")])
        ]
        exporter.selected = Set(exporter.entries.map(\.key))
        await exporter.export(to: root)
        XCTAssertEqual(exporter.status, "Export complete: 2 succeeded, 0 failed.")
        let folder = try XCTUnwrap(exporter.output)
        let report = try String(contentsOf: folder.appendingPathComponent("export-report.txt"), encoding: .utf8)
        XCTAssertTrue(report.contains("DMG contents verified"))
        XCTAssertTrue(report.contains("SUCCESS: alisma-4.pkg"))
        let hashes = try String(contentsOf: folder.appendingPathComponent("SHA256SUMS.txt"), encoding: .utf8)
        XCTAssertEqual(hashes.split(separator: "\n").count, 2)
    }
}
