import XCTest
@testable import EclecticLightUpdater

final class BacklogFeatureTests: XCTestCase {
    func testLabelParserRejectsLogLinesAndControlLabels() {
        XCTAssertEqual(installomatorLabels(from: "firefox\n[INFO] labels\nversion\nvaluesfromarguments\nbrokenexample\nchrome\nfirefox\nfoo;touch /tmp/bad\n"), ["chrome", "firefox"])
    }

    func testDirectoryIsUniqueAndCategorized() {
        let products = HelpDirectory.products
        XCTAssertEqual(Set(products.map(\.name)).count, products.count)
        XCTAssertTrue(products.contains { $0.name == "Mints" && $0.category.contains("Logs") && $0.category.contains("iCloud") })
        XCTAssertTrue(products.filter(\.isTool).count == 5)
        XCTAssertTrue(products.allSatisfy { URL(string: $0.page)?.host == "eclecticlight.co" })
    }

    @MainActor func testQueueOnlyRunsKnownSelectedLabelsAndStopsOnFailure() async {
        var scripts: [String] = []
        let model = InstallomatorModel { script in
            scripts.append(script)
            return scripts.count == 1
        }
        model.path = "/tmp/Example Installomator.sh"
        model.labels = ["alpha", "beta", "gamma"]
        model.selected = ["alpha", "beta", "gamma", "unknown"]
        await model.installSelected()
        XCTAssertEqual(scripts.count, 2)
        XCTAssertTrue(scripts[0].contains("'alpha' DEBUG=0"))
        XCTAssertTrue(scripts[1].contains("'beta' DEBUG=0"))
        XCTAssertFalse(model.busy)
        XCTAssertTrue(model.status.contains("1/3"))
    }

    func testOfficialPackageLabelDiscovery() async throws {
        let script = "/tmp/elu14-installomator-expanded/Installomator.pkg/Payload/Installomator.sh"
        guard FileManager.default.fileExists(atPath: script) else { throw XCTSkip("Official package fixture not unpacked") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        let code = await runLoggedProcess("/bin/zsh", arguments: ["--no-rcs", script], output: output)
        XCTAssertEqual(code, 0)
        let labels = installomatorLabels(from: try String(contentsOf: output, encoding: .utf8))
        XCTAssertTrue(labels.contains("firefox"))
        XCTAssertTrue(labels.contains("silentknight"))
        XCTAssertGreaterThan(labels.count, 500)
    }
}
