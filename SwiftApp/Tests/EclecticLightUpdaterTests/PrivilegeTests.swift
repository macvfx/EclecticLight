import XCTest
@testable import EclecticLightUpdater

/// File operations ask for administrator rights only when the current user cannot do the job.
///
/// Before 1.5.3 every Organize queued an elevated cleanup pass whether or not anything needed
/// it, so it always ended with a password prompt; and a folder created with rights stayed owned
/// by root, which made the next run need rights too.
final class PrivilegeTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("elu-privilege-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Some tests make folders read-only; restore them so the tree can be removed.
        if let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in walker {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }
        try? fm.removeItem(at: root)
    }

    private func makeFile(_ path: String, _ text: String = "x") throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    // MARK: - Moves

    func testMoveInWritableFoldersHappensNowAndQueuesNothing() throws {
        let session = PrivilegedSession()
        let source = try makeFile("nested/Read Me's.rtf")
        let destination = root.appendingPathComponent("ReadMe/Read Me's.rtf")

        let outcome = FileOps.move(source, to: destination, session: session)

        XCTAssertEqual(outcome, .moved)
        XCTAssertFalse(session.hasPending, "a move the user can do must not ask for rights")
        XCTAssertTrue(fm.fileExists(atPath: destination.path))
        XCTAssertFalse(fm.fileExists(atPath: source.path))
    }

    func testMoveOutOfAReadOnlyFolderIsQueuedAndHandsNewFoldersBack() throws {
        let session = PrivilegedSession()
        let source = try makeFile("locked/Guide.pdf")
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: source.deletingLastPathComponent().path)
        let destination = root.appendingPathComponent("ReadMe/Guide.pdf")

        let outcome = FileOps.move(source, to: destination, session: session)

        XCTAssertEqual(outcome, .queued)
        XCTAssertTrue(fm.fileExists(atPath: source.path), "nothing may be half-moved before the prompt")
        XCTAssertFalse(fm.fileExists(atPath: destination.path))
        let command = try XCTUnwrap(session.pending.first)
        XCTAssertEqual(session.pendingCount, 1)
        XCTAssertTrue(command.contains("chown \(FileOps.currentOwner)"),
                      "a folder created as root must be handed back to the user")
        XCTAssertTrue(command.contains("mv " + Shell.quote(source.path) + " " + Shell.quote(destination.path)))
    }

    func testCanMoveUnprivilegedNeedsBothParentsWritable() throws {
        let source = try makeFile("a/item.txt")
        let writableTarget = root.appendingPathComponent("b/item.txt")
        XCTAssertTrue(FileOps.canMoveUnprivileged(source, to: writableTarget))

        let lockedFolder = root.appendingPathComponent("locked")
        try fm.createDirectory(at: lockedFolder, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedFolder.path)
        XCTAssertFalse(FileOps.canMoveUnprivileged(source, to: lockedFolder.appendingPathComponent("item.txt")))
    }

    // MARK: - Folders

    func testEnsureFolderCreatesItWithoutRights() {
        let session = PrivilegedSession()
        let folder = root.appendingPathComponent("EclecticLight/ReadMe")

        FileOps.ensureFolder(folder.path, session: session)

        XCTAssertTrue(fm.fileExists(atPath: folder.path))
        XCTAssertFalse(session.hasPending)
    }

    /// The regression: tidying a tree the user owns must not queue an elevated pass.
    func testRemovingEmptyFoldersTheUserOwnsQueuesNothing() throws {
        let session = PrivilegedSession()
        let apps = root.appendingPathComponent("EclecticLight")
        let readMe = apps.appendingPathComponent("ReadMe")
        try fm.createDirectory(at: readMe, withIntermediateDirectories: true)
        try fm.createDirectory(at: apps.appendingPathComponent("alifix13/Docs"), withIntermediateDirectories: true)
        try fm.createDirectory(at: apps.appendingPathComponent("Empty.app"), withIntermediateDirectories: true)
        _ = try makeFile("EclecticLight/kept/notes.txt")

        FileOps.removeEmptyFolders(below: apps.path, preserving: readMe.path, session: session)

        XCTAssertFalse(session.hasPending, "nothing here needs administrator rights")
        XCTAssertFalse(fm.fileExists(atPath: apps.appendingPathComponent("alifix13").path))
        XCTAssertTrue(fm.fileExists(atPath: readMe.path), "the ReadMe folder is kept even when empty")
        XCTAssertTrue(fm.fileExists(atPath: apps.appendingPathComponent("Empty.app").path), "app bundles are never removed")
        XCTAssertTrue(fm.fileExists(atPath: apps.appendingPathComponent("kept/notes.txt").path))
    }

    /// Elevated moves empty folders only after the prompt, so the cleanup has to follow them.
    func testEmptyFolderPassIsQueuedBehindWaitingElevatedMoves() throws {
        let session = PrivilegedSession()
        session.add("mv 'a' 'b'")
        let apps = root.appendingPathComponent("EclecticLight")
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)

        FileOps.removeEmptyFolders(below: apps.path, preserving: apps.appendingPathComponent("ReadMe").path, session: session)

        XCTAssertEqual(session.pendingCount, 2)
        XCTAssertTrue(session.pending[1].contains("-type d -empty"))
    }

    func testEmptyFolderPassIsQueuedWhenAFolderCannotBeRemoved() throws {
        let session = PrivilegedSession()
        let apps = root.appendingPathComponent("EclecticLight")
        let locked = apps.appendingPathComponent("locked")
        try fm.createDirectory(at: locked.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)

        FileOps.removeEmptyFolders(below: apps.path, preserving: apps.appendingPathComponent("ReadMe").path, session: session)

        XCTAssertEqual(session.pendingCount, 1, "a folder this user cannot remove is left for the single prompt")
    }
}
