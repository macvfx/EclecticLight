import XCTest
@testable import EclecticLightUpdater

final class Release12Tests: XCTestCase {
    func testMappingsAndToolExclusion() {
        let v = CatalogVersion(version: "2.03", url: "https://example.com/test.zip", compat: "Tahoe")
        let entries = Dictionary(uniqueKeysWithValues: ["cirrus", "t2m2", "alisma", "blowhole", "cintch", "cmpxat", "unorml"].map {
            ($0, CatalogEntry(key: $0, name: $0, versions: [v]))
        })
        var catalog = CatalogData()
        catalog.entries = CatalogFetcher.applyCatalogExceptions(to: entries)
        XCTAssertNil(catalog.entries["cirrus"])
        XCTAssertNil(catalog.entries["t2m2"])
        XCTAssertNotNil(catalog.entries["cirrusmac"])
        XCTAssertNotNil(catalog.entries["thetimemachinemechanic2"])
        let keys = Set(availableApps(apps: [], catalog: catalog).map(\.key))
        XCTAssertTrue(keys.isDisjoint(with: CatalogFetcher.commandLineKeys))
        let copy = AppInfo(path: "/Applications/Example.app", bundleID: "co.eclecticlight.CirrusMac", name: "Example", version: "2.03")
        XCTAssertFalse(availableApps(apps: [copy], catalog: catalog).contains { $0.key == "cirrusmac" })
    }

    func testVerificationRequiresCorrectIdentityAndVersion() {
        let entry = CatalogEntry(key: "example", name: "Example", versions: [CatalogVersion(version: "2.0", url: "", compat: "")])
        func app(_ id: String, _ version: String) -> AppInfo {
            AppInfo(path: "/Applications/EclecticLight/Example.app", bundleID: id, name: "Example", version: version)
        }
        XCTAssertFalse(installationSucceeded(entry, installed: []))
        XCTAssertFalse(installationSucceeded(entry, installed: [app("co.eclecticlight.example", "1.0")]))
        XCTAssertFalse(installationSucceeded(entry, installed: [app("co.eclecticlight.other", "2.0")]))
        XCTAssertTrue(installationSucceeded(entry, installed: [app("co.eclecticlight.example", "2.0")]))
    }
}
