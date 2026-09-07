import XCTest
@testable import EclecticLightUpdater

final class ToolPackageTests: XCTestCase {
    func testSelectionExcludesOtherPackagesAndDetectsAmbiguity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("exampleInstaller.pkg"))
        try Data().write(to: root.appendingPathComponent("otherInstaller.pkg"))
        XCTAssertEqual(toolInstallerPackages(at: root, key: "example").count, 1)
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("exampleInstaller.pkg"))
        XCTAssertEqual(toolInstallerPackages(at: root, key: "example").count, 2)
        XCTAssertTrue(toolInstallerPackages(at: root, key: "missing").isEmpty)
    }

    func testProcessCapturesOutputAndFailureStatus() async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        let result = await runLoggedProcess("/bin/sh", arguments: ["-c", "echo 'Example failure'; exit 7"], output: output)
        XCTAssertEqual(result, 7)
        XCTAssertTrue(try String(contentsOf: output, encoding: .utf8).contains("Example failure"))
    }
}
