import Foundation

// MARK: - Shell helpers

enum Shell {
    /// Quote a value for safe use inside a POSIX shell command line.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Run a command with osascript `do shell script ... with administrator privileges`.
    /// Shows ONE password prompt for the whole script.
    static func runAdmin(script: String) async -> Bool {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
        return await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", appleScript]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            p.terminationHandler = { proc in
                cont.resume(returning: proc.terminationStatus == 0)
            }
            do { try p.run() } catch { cont.resume(returning: false) }
        }
    }
}

// MARK: - Single-prompt privileged session

/// Accumulates privileged shell commands and runs them ALL through one admin
/// password prompt when flushed — so updating/cleaning/organizing many apps
/// costs a single prompt, not one per app.
/// Only ever touched from the main actor, hence `@unchecked Sendable`.
final class PrivilegedSession: @unchecked Sendable {
    private var commands: [String] = []

    var pendingCount: Int { commands.count }
    /// The queued commands, in order. Read by tests; nothing else needs them.
    var pending: [String] { commands }
    var hasPending: Bool { !commands.isEmpty }

    func add(_ cmd: String) { commands.append(cmd) }

    func flush() async -> Bool {
        guard !commands.isEmpty else { return true }
        let joined = commands.joined(separator: " ; ")
        commands = []
        return await Shell.runAdmin(script: joined)
    }
}

// MARK: - Unprivileged file operations (no prompts for admin users)

enum FileOps {
    static let appsFolder = BundlePrefix.appsFolder
    static let trashFolder = NSHomeDirectory() + "/.Trash/"

    enum MoveOutcome: Equatable {
        /// Done now, as the current user.
        case moved
        /// Needs administrator rights; waits for the session's single prompt.
        case queued
        /// Started as the current user and stopped part-way. Not retried with rights:
        /// the destination already holds something, and a second `mv` would nest inside it.
        case failed
    }

    /// `uid:gid` of the person running the app, for handing back folders made as root.
    static var currentOwner: String { "\(getuid()):\(getgid())" }

    private static func nearestExisting(_ url: URL) -> URL {
        var current = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: current.path), current.path != "/" {
            current = current.deletingLastPathComponent()
        }
        return current
    }

    /// True when the current user can complete the move without leaving half of it behind.
    ///
    /// Both parent folders must be writable. Across volumes a move is a copy and then a
    /// delete, so the source must also be the user's own — otherwise the copy succeeds, the
    /// delete fails, and an elevated retry would nest the item inside the first copy.
    static func canMoveUnprivileged(_ src: URL, to dest: URL) -> Bool {
        let fm = FileManager.default
        let sourceParent = src.deletingLastPathComponent()
        let target = nearestExisting(dest.deletingLastPathComponent())
        guard fm.isWritableFile(atPath: sourceParent.path), fm.isWritableFile(atPath: target.path) else {
            return false
        }
        let sourceVolume = (try? fm.attributesOfItem(atPath: sourceParent.path))?[.systemNumber] as? NSNumber
        let targetVolume = (try? fm.attributesOfItem(atPath: target.path))?[.systemNumber] as? NSNumber
        if let sourceVolume, let targetVolume, sourceVolume == targetVolume { return true }
        let owner = (try? fm.attributesOfItem(atPath: src.path))?[.ownerAccountID] as? NSNumber
        return owner?.uint32Value == getuid()
    }

    /// Move an item as the current user when that can succeed; otherwise queue an elevated
    /// `mv`. A folder the elevated step has to create is handed back to the user, so the
    /// next run needs no rights.
    @discardableResult
    static func move(_ src: URL, to dest: URL, session: PrivilegedSession) -> MoveOutcome {
        let fm = FileManager.default
        let folder = dest.deletingLastPathComponent()
        if canMoveUnprivileged(src, to: dest) {
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try fm.moveItem(at: src, to: dest)
                return .moved
            } catch {
                if fm.fileExists(atPath: dest.path) { return .failed }
            }
        }
        let quotedFolder = Shell.quote(folder.path)
        session.add("{ [ -d \(quotedFolder) ] || { mkdir -p \(quotedFolder) && chown \(currentOwner) \(quotedFolder); }; }"
                    + " && mv \(Shell.quote(src.path)) \(Shell.quote(dest.path))")
        return .queued
    }

    /// Trash an item; falls back to queueing a privileged `mv` to the user Trash.
    static func trash(_ url: URL, session: PrivilegedSession) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            session.add("mv \(Shell.quote(url.path)) \(Shell.quote(trashFolder))")
        }
    }

    static func ensureFolder(_ path: String, session: PrivilegedSession) {
        do {
            try FileManager.default.createDirectory(atPath: path,
                                                    withIntermediateDirectories: true)
        } catch {
            // Only reached when the folder is missing and cannot be made as this user.
            session.add("mkdir -p \(Shell.quote(path)) && chown \(currentOwner) \(Shell.quote(path))")
        }
    }

    /// Remove a now-empty version folder inside /Applications/EclecticLight.
    /// Returns a log line, or "" when nothing was done (folder not empty/absent).
    static func removeEmptyFolder(_ path: String, session: PrivilegedSession) -> String {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path),
              contents.isEmpty else { return "" }
        do {
            try FileManager.default.removeItem(atPath: path)
            return "removed empty folder \(path)"
        } catch {
            session.add("rmdir \(Shell.quote(path))")
            return "queued removal of empty folder \(path)"
        }
    }

    /// Remove only empty directories below the main apps folder.
    ///
    /// An elevated pass is queued only when it has something to do: a folder this user
    /// could not remove, or elevated moves already waiting that will empty folders later.
    /// It used to be queued every time, so every Organize ended with a password prompt
    /// even when nothing needed one.
    static func removeEmptyFolders(below root: String,
                                   preserving preserved: String,
                                   session: PrivilegedSession) {
        let fm = FileManager.default
        var needsElevatedPass = session.hasPending
        if let enumerator = fm.enumerator(at: URL(fileURLWithPath: root),
                                          includingPropertiesForKeys: [.isDirectoryKey],
                                          options: [.skipsPackageDescendants]) {
            let directories = enumerator.compactMap { $0 as? URL }
                .filter { url in
                    url.pathExtension.lowercased() != "app"
                        && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                }
                .sorted { $0.path.count > $1.path.count }
            // Compared after resolving symlinks: the enumerator reports resolved paths, so a
            // preserved folder reached through a link would otherwise not match and be removed.
            let keep = URL(fileURLWithPath: preserved).resolvingSymlinksInPath().path
            for directory in directories where directory.resolvingSymlinksInPath().path != keep {
                guard let contents = try? fm.contentsOfDirectory(atPath: directory.path),
                      contents.isEmpty else { continue }
                do {
                    try fm.removeItem(at: directory)
                } catch {
                    needsElevatedPass = true
                }
            }
        }
        guard needsElevatedPass else { return }
        session.add("/usr/bin/find \(Shell.quote(root)) -depth -type d -empty "
                    + "! -path \(Shell.quote(root)) ! -path \(Shell.quote(preserved)) "
                    + "! -name '*.app' ! -path '*.app/*' -delete")
    }
}

// MARK: - Installomator

func findInstallomator() -> String? {
    let candidates = [
        "/usr/local/Installomator/Installomator.sh",
        "/usr/local/bin/Installomator.sh",
        "/usr/local/bin/installomator",
        "/opt/homebrew/bin/installomator",
        "/usr/bin/installomator",
    ]
    for p in candidates where FileManager.default.fileExists(atPath: p) {
        return p
    }
    return nil
}
