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

    /// Move an item; falls back to queueing a privileged `mv` if unprivileged fails.
    static func move(_ src: URL, to dest: URL, session: PrivilegedSession) {
        do {
            try FileManager.default.moveItem(at: src, to: dest)
        } catch {
            session.add("mkdir -p \(Shell.quote(dest.deletingLastPathComponent().path))"
                        + " && mv \(Shell.quote(src.path)) \(Shell.quote(dest.path))")
        }
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
            session.add("mkdir -p \(Shell.quote(path))")
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

    /// Remove only empty directories below the main apps folder. The final
    /// queued pass runs after any privileged moves in the same session.
    static func removeEmptyFolders(below root: String,
                                   preserving preserved: String,
                                   session: PrivilegedSession) {
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: URL(fileURLWithPath: root),
                                          includingPropertiesForKeys: [.isDirectoryKey],
                                          options: [.skipsPackageDescendants]) {
            let directories = enumerator.compactMap { $0 as? URL }
                .filter { url in
                    url.pathExtension.lowercased() != "app"
                        && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                }
                .sorted { $0.path.count > $1.path.count }
            for directory in directories where directory.path != preserved {
                guard let contents = try? fm.contentsOfDirectory(atPath: directory.path),
                      contents.isEmpty else { continue }
                try? fm.removeItem(at: directory)
            }
        }
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
