import XCTest
@testable import EclecticLightUpdater

final class ArchiveInventoryTests: XCTestCase {
    func testInventoryIncludesAllIdentitiesAndBrokenBundles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, id) in [("ExampleOne", "co.eclecticlight.exampleone"), ("ExampleTwo", "org.example.second")] {
            let contents = root.appendingPathComponent("Suite/\(name).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": name, "CFBundleIdentifier": id, "CFBundleShortVersionString": "1.2"], format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Broken.app"), withIntermediateDirectories: true)
        let text = archiveAppInventory(at: root).joined(separator: "\n")
        XCTAssertTrue(text.contains("3 app bundle(s)"))
        XCTAssertTrue(text.contains("name=ExampleOne | version=1.2 | bundle ID=co.eclecticlight.exampleone"))
        XCTAssertTrue(text.contains("bundle ID=org.example.second"))
        XCTAssertTrue(text.contains("Info.plist error:"))
    }

    func testEmptyArchiveHasExplicitZeroCount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(archiveAppInventory(at: root), ["Archive inventory: 0 app bundle(s)"])
    }
}
