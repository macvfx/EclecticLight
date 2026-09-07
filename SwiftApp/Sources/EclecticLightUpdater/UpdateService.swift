import Foundation

// MARK: - Update / cleanup / organize service

struct UpdateLog {
    private(set) var lines: [String] = []

    @MainActor mutating func add(_ line: String) {
        lines.append(line)
        ActivityLog.shared.append(line)
    }

    var text: String { lines.joined(separator: "\n") }
}

@MainActor
final class UpdateService {

    private let session = PrivilegedSession()

    func updateGroup(_ g: GroupRow, installomatorPath: String?) async -> [String] {
        var log = UpdateLog()
        guard let latest = g.latest, g.status == .outdated || g.status == .downloadsOnlyOutdated else {
            return ["\(g.name): nothing to do"]
        }

        let target = g.target
        switch g.action {
        case .installomator:
            guard let label = g.key as String? else { return ["\(g.name): no label"] }
            if let path = installomatorPath {
                session.add("\(Shell.quote(path)) \(label) NOTIFY=silent")
                log.add("\(g.name): queued Installomator update (\(label))")
            } else {
                installInstallomator(session: session)
                session.add("\(Shell.quote("/usr/local/Installomator/Installomator.sh")) \(label) NOTIFY=silent")
                log.add("\(g.name): Installomator missing — queued install + update (\(label))")
            }
        case .download:
            let ok = await downloadAndInstall(group: g, log: &log)
            if !ok { return log.lines }
        case .none:
            break
        }

        // trash outdated copies after a successful update
        for copy in g.copies where copy.location == .applications {
            if g.action == .installomator && copy == target { continue }
            if versionLess(copy.version, latest.version) {
                FileOps.trash(URL(fileURLWithPath: copy.path), session: session)
                log.add("\(g.name): queued trash of old copy \(copy.path)")
                deepCleanParent(of: copy.path, log: &log)
            }
        }
        return log.lines
    }

    func install(_ entry: CatalogEntry) async -> [String] {
        var log = UpdateLog()
        let group = GroupRow(key: entry.key, name: entry.name, copies: [],
                             entry: entry, status: .downloadsOnly, action: .download)
        _ = await downloadAndInstall(group: group, log: &log)
        return log.lines
    }

    func cleanupStale(_ copies: [AppInfo]) async -> [String] {
        var log = UpdateLog()
        for copy in copies {
            FileOps.trash(URL(fileURLWithPath: copy.path), session: session)
            log.add("trashed \(copy.path)")
            deepCleanParent(of: copy.path, log: &log)
        }
        return log.lines
    }

    private func deepCleanParent(of path: String, log: inout UpdateLog) {
        let parent = (path as NSString).deletingLastPathComponent
        guard parent.hasPrefix(BundlePrefix.appsFolder) else { return }
        let msg = FileOps.removeEmptyFolder(parent, session: session)
        if !msg.isEmpty { log.add(msg) }
    }

    func ensureFolderCreated() async {
        guard !FileManager.default.fileExists(atPath: BundlePrefix.appsFolder) else { return }
        FileOps.ensureFolder(BundlePrefix.appsFolder, session: session)
        _ = await session.flush()
    }

    func organize(_ copies: [AppInfo]) async -> [String] {
        var log = UpdateLog()
        FileOps.ensureFolder(FileOps.appsFolder, session: session)
        for copy in copies {
            let dest = URL(fileURLWithPath: FileOps.appsFolder)
                .appendingPathComponent((copy.path as NSString).lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                if let existing = readApp(path: dest.path),
                   existing.bundleID == copy.bundleID,
                   existing.version == copy.version {
                    FileOps.trash(URL(fileURLWithPath: copy.path), session: session)
                    log.add("\(copy.path) is a duplicate of \(dest.path) — queued trash")
                } else {
                    log.add("skip (already exists): \(dest.path)")
                }
                continue
            }
            FileOps.move(URL(fileURLWithPath: copy.path), to: dest, session: session)
            log.add("move \(copy.path) -> \(dest.path)")
        }
        collectReadMeDocuments(log: &log)
        let readMeFolder = FileOps.appsFolder + "/ReadMe"
        FileOps.removeEmptyFolders(below: FileOps.appsFolder,
                                   preserving: readMeFolder,
                                   session: session)
        log.add("remove empty folders below \(FileOps.appsFolder)")
        return log.lines
    }

    private func collectReadMeDocuments(log: inout UpdateLog) {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: FileOps.appsFolder, isDirectory: true)
        let readMe = root.appendingPathComponent("ReadMe", isDirectory: true)
        guard let enumerator = fm.enumerator(at: root,
                                             includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                                             options: [.skipsPackageDescendants]) else { return }
        var documents: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if url.path == readMe.path {
                enumerator.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true && url.pathExtension.lowercased() == "app" {
                enumerator.skipDescendants()
            } else if values?.isRegularFile == true,
                      ["pdf", "rtf"].contains(url.pathExtension.lowercased()) {
                documents.append(url)
            }
        }
        guard !documents.isEmpty else { return }
        FileOps.ensureFolder(readMe.path, session: session)
        var reserved = Set(((try? fm.contentsOfDirectory(atPath: readMe.path)) ?? [])
            .map { $0.lowercased() })
        for source in documents.sorted(by: { $0.path < $1.path }) {
            let destinationName = uniqueDocumentName(source.lastPathComponent, reserved: &reserved)
            let destination = readMe.appendingPathComponent(destinationName)
            FileOps.move(source, to: destination, session: session)
            log.add("readme \(source.path) -> \(destination.path)")
        }
    }

    private func uniqueDocumentName(_ name: String, reserved: inout Set<String>) -> String {
        let ns = name as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        var candidate = name
        var suffix = 2
        while reserved.contains(candidate.lowercased()) {
            candidate = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
            suffix += 1
        }
        reserved.insert(candidate.lowercased())
        return candidate
    }

    /// Run every queued privileged command with ONE admin prompt.
    func flushPrivileged() async -> Bool {
        await session.flush()
    }

    func hasPending() -> Bool { session.hasPending }

    // MARK: - Manual download + install

    private func downloadAndInstall(group: GroupRow, log: inout UpdateLog) async -> Bool {
        guard let latest = group.latest, let url = URL(string: latest.url) else {
            log.add("\(group.name): no download URL")
            return false
        }
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("elu-" + group.key + "-" + UUID().uuidString, isDirectory: true)
        try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let zipURL = tmpDir.appendingPathComponent((latest.url as NSString).lastPathComponent)

        log.add("\(group.name): downloading \(latest.url)")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                log.add("\(group.name): download returned an unsuccessful HTTP response")
                return false
            }
            try data.write(to: zipURL)
        } catch {
            log.add("\(group.name): download failed — \(error.localizedDescription)")
            return false
        }

        log.add("\(group.name): expected bundle ID=\(BundlePrefix.eclecticlight)\(group.key) (normalized suffix match)")
        log.add("\(group.name): unzipping")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipURL.path, tmpDir.path]
        ditto.standardOutput = Pipe()
        ditto.standardError = Pipe()
        do {
            try ditto.run()
            ditto.waitUntilExit()
        } catch {
            log.add("\(group.name): unzip failed — \(error.localizedDescription)")
            return false
        }
        log.add("\(group.name): extraction exit status=\(ditto.terminationStatus)")
        for line in archiveAppInventory(at: tmpDir) { log.add("\(group.name): \(line)") }
        guard ditto.terminationStatus == 0 else {
            log.add("\(group.name): extraction failed (exit \(ditto.terminationStatus)); archive at \(zipURL.path)")
            return false
        }
        guard let newestApp = newestAppBundle(in: tmpDir.path, matchingKey: group.key) else {
            log.add("\(group.name): no matching co.eclecticlight.\(group.key) app found in download")
            log.add("\(group.name): extracted files retained at \(tmpDir.path). This may be a command-line tool or a catalog mapping mismatch.")
            return false
        }

        log.add("\(group.name): selected app=\(newestApp)")
        let destDir = FileOps.appsFolder + "/" + group.key + versionDigits(latest.version)
        let dest = URL(fileURLWithPath: destDir)
            .appendingPathComponent((newestApp as NSString).lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            log.add("\(group.name): \(dest.path) already exists")
            return false
        }
        FileOps.ensureFolder(FileOps.appsFolder, session: session)
        FileOps.move(URL(fileURLWithPath: newestApp), to: dest, session: session)
        log.add("\(group.name): prepared \(latest.version) for installation at \(dest.path)")
        return true
    }

    private func newestAppBundle(in dir: String, matchingKey key: String) -> String? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
        var found: [String] = []
        for item in items {
            let path = (dir as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            if item.hasSuffix(".app") {
                if readApp(path: path)?.key == key { found.append(path) }
            } else {
                if let nested = newestAppBundle(in: path, matchingKey: key) { found.append(nested) }
            }
        }
        return found.max { versionLess(installedVersion(of: $0), installedVersion(of: $1)) }
    }

    private func installedVersion(of path: String) -> String {
        readApp(path: path)?.version ?? ""
    }
}

func organizeFolderName(_ app: AppInfo) -> String {
    let name = normalize(app.name)
    return name + versionDigits(app.version)
}
