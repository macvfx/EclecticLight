import XCTest
@testable import EclecticLightUpdater

final class AvailableAppsTests: XCTestCase {
    func testMissingAppsExcludeLocalCopiesAndNonAppPackages() {
        let version = CatalogVersion(version: "1.0", url: "https://example.com/app.zip", compat: "")
        var catalog = CatalogData()
        for key in ["exampleinstalled", "exampledownloaded", "examplemissing", "deeptools", "help"] {
            catalog.entries[key] = CatalogEntry(key: key, name: key, versions: [version])
        }
        catalog.entries["empty"] = CatalogEntry(key: "empty", name: "empty")
        let apps = [
            AppInfo(path: "/Applications/Example.app", bundleID: "co.eclecticlight.exampleinstalled", name: "Example", version: "0.5"),
            AppInfo(path: NSHomeDirectory() + "/Downloads/Example.app", bundleID: "co.eclecticlight.exampledownloaded", name: "Example", version: "1.0")
        ]
        XCTAssertEqual(availableApps(apps: apps, catalog: catalog).map(\.key), ["examplemissing"])
    }

    func testSuiteMembersRemainIndependentlyInstallable() {
        let version = CatalogVersion(version: "1.0", url: "https://example.com/suite.zip", compat: "")
        var catalog = CatalogData()
        catalog.entries = CatalogFetcher.applyCatalogExceptions(to: [
            "deeptools": CatalogEntry(key: "deeptools", name: "DeepTools", versions: [version])
        ])
        let apps = [AppInfo(path: "/Applications/DeepCopy.app", bundleID: "co.eclecticlight.deepcopy", name: "DeepCopy", version: "1.0")]
        let keys = Set(availableApps(apps: apps, catalog: catalog).map(\.key))
        XCTAssertTrue(keys.contains("deeparchive"))
        XCTAssertTrue(keys.contains("deepunarchive"))
        XCTAssertFalse(keys.contains("deepcopy"))
        XCTAssertFalse(keys.contains("deeptools"))
    }
}
