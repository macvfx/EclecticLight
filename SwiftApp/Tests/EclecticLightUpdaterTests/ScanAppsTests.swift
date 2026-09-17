import XCTest
@testable import EclecticLightUpdater

final class ScanAppsTests: XCTestCase {
    private let fm = FileManager.default

    private func makeApp(at url: URL, id: String = "co.eclecticlight.example") throws {
        let contents = url.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleName": "Example", "CFBundleIdentifier": id,
                     "CFBundleShortVersionString": "1.0"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }

    func testSkipsDirectoryAndAppSymlinksButKeepsRealCopies() throws {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let scan = root.appendingPathComponent("Scan")
        let first = scan.appendingPathComponent("Applications/Example.app")
        let second = scan.appendingPathComponent("Archive/Example.app")
        let outside = root.appendingPathComponent("Outside/Other.app")
        try makeApp(at: first)
        try makeApp(at: second)
        try makeApp(at: outside, id: "co.eclecticlight.other")
        try fm.createSymbolicLink(at: scan.appendingPathComponent("LinkedApplications"),
                                  withDestinationURL: first.deletingLastPathComponent())
        try fm.createSymbolicLink(at: scan.appendingPathComponent("Linked.app"), withDestinationURL: first)
        try fm.createSymbolicLink(at: scan.appendingPathComponent("Outside"),
                                  withDestinationURL: outside.deletingLastPathComponent())
        try fm.createSymbolicLink(atPath: scan.appendingPathComponent("RelativeApplications").path,
                                  withDestinationPath: "Applications")
        try fm.createSymbolicLink(atPath: scan.appendingPathComponent("Broken.app").path,
                                  withDestinationPath: "Missing.app")
        XCTAssertEqual(Set(scanApps(dirs: [scan.path]).map(\.path)), Set([first.path, second.path]))
    }

    func testSkipsSymlinkScanRootAndLinkCycles() throws {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let scan = root.appendingPathComponent("Scan")
        let app = scan.appendingPathComponent("Example.app")
        try makeApp(at: app)
        let alias = root.appendingPathComponent("Alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: scan)
        XCTAssertTrue(scanApps(dirs: [alias.path]).isEmpty)
        try fm.createSymbolicLink(at: scan.appendingPathComponent("Loop"), withDestinationURL: scan)
        XCTAssertEqual(scanApps(dirs: [scan.path]).map(\.path), [app.path])
    }
}
