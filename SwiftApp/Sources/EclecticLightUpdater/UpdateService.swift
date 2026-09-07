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

    func installTool(_ entry: CatalogEntry) async -> Bool {
        guard CatalogFetcher.commandLineKeys.contains(entry.key),
              let latest = entry.latest, let url = URL(string: latest.url),
              url.scheme == "https", url.host == "eclecticlight.co" else { return false }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("elu-tool-" + UUID().uuidString)
        let archive = root.appendingPathComponent("download.zip")
        var log = UpdateLog()
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            log.add("\(entry.name): downloading package archive from \(url.absoluteString)")
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                log.add("\(entry.name): download failed: unsuccessful HTTP response")
                return false
            }
            try data.write(to: archive)
            log.add("\(entry.name): extracting package archive")
            let output = root.appendingPathComponent("extract.log")
            let code = await runLoggedProcess("/usr/bin/ditto", arguments: ["-x", "-k", archive.path, root.path], output: output)
            guard code == 0 else {
                log.add("\(entry.name): extraction failed (\(code)): " + ((try? String(contentsOf: output, encoding: .utf8)) ?? ""))
                return false
            }
            let packages = toolInstallerPackages(at: root, key: entry.key)
            guard packages.count == 1, let package = packages.first else {
                log.add("\(entry.name): expected exactly one \(entry.key)Installer.pkg; found \(packages.count). Files retained at \(root.path)")
                return false
            }
            let installOutput = root.appendingPathComponent("installer.log")
            try Data().write(to: installOutput)
            log.add("\(entry.name): requesting administrator permission to install \(package.lastPathComponent) on /")
            let ok = await Shell.runAdmin(script: "/usr/sbin/installer -pkg " + Shell.quote(package.path)
                + " -target / > " + Shell.quote(installOutput.path) + " 2>&1")
            log.add((try? String(contentsOf: installOutput, encoding: .utf8)) ?? "Installer output unavailable")
            log.add("\(entry.name): " + (ok ? "installer exited successfully." : "installer failed or administrator prompt was cancelled.") + " Log: \(installOutput.path)")
            return ok
        } catch {
            log.add("\(entry.name): package installation failed: \(error.localizedDescription)")
            return false
        }
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
        let extractionOutput = tmpDir.appendingPathComponent("extraction.log")
        let extractionStatus = await runLoggedProcess("/usr/bin/ditto",
            arguments: ["-x", "-k", zipURL.path, tmpDir.path], output: extractionOutput)
        log.add("\(group.name): extraction exit status=\(extractionStatus)")
        for line in archiveAppInventory(at: tmpDir) { log.add("\(group.name): \(line)") }
        guard extractionStatus == 0 else {
            log.add("\(group.name): extraction failed (exit \(extractionStatus)); archive at \(zipURL.path)")
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


/// Use a file for output so verbose child processes cannot fill an unread pipe.
func runLoggedProcess(_ executable: String, arguments: [String], output: URL) async -> Int32 {
    do {
        try Data().write(to: output)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = handle
            process.standardError = handle
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(returning: -1) }
        }
    } catch { return -1 }
}

func toolInstallerPackages(at root: URL, key: String) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(at: root,
        includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return [] }
    var result: [URL] = []
    for case let url as URL in enumerator {
        guard url.pathExtension.lowercased() == "pkg" else { continue }
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { enumerator.skipDescendants() }
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { continue }
        if normalize(url.deletingPathExtension().lastPathComponent) == key + "installer" { result.append(url) }
    }
    return result.sorted { $0.path < $1.path }
}

@MainActor
final class MunkiExporter: ObservableObject {
    @Published var entries: [CatalogEntry] = []
    @Published var selected: Set<String> = []
    @Published var busy = false
    @Published var status = "Load the catalog to choose downloads."
    @Published var output: URL?

    func load() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        status = "Loading eclecticlight.co catalog…"
        do {
            let catalog = try await CatalogFetcher.fetchCatalog()
            entries = (availableApps(apps: [], catalog: catalog) + catalog.entries.values.filter {
                CatalogFetcher.commandLineKeys.contains($0.key)
            }).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            selected = []
            status = "Choose apps or packages. Compatibility does not restrict export."
        } catch { status = "Catalog failed: \(error.localizedDescription)" }
    }

    func export(to parent: URL) async {
        guard !busy, !selected.isEmpty else { return }
        busy = true
        defer { busy = false }
        let fm = FileManager.default
        let folder = parent.appendingPathComponent("EclecticLight-Munki-" + UUID().uuidString)
        let work = fm.temporaryDirectory.appendingPathComponent("elu-munki-" + UUID().uuidString)
        var report = ["Eclectic Light Munki export", "Import successful artifacts using munkiimport or MunkiAdmin. Catalogs and assignments are not configured."]
        var checksums: [String] = []
        var downloaded: [String: URL] = [:]
        var successes = 0
        let chosen = entries.filter { selected.contains($0.key) }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            output = folder
            for (index, entry) in chosen.enumerated() {
                status = "Exporting \(entry.name) (\(index + 1)/\(chosen.count))"
                var pendingArtifact: URL?
                do {
                    guard let latest = entry.latest, let url = URL(string: latest.url),
                          url.scheme == "https", url.host == "eclecticlight.co" else { throw ExportError.invalidDownload }
                    report.append("\n\(entry.name) | catalog version=\(latest.version) | source=\(latest.url) | compatibility=\(latest.compat)")
                    let extracted: URL
                    if let cached = downloaded[latest.url] { extracted = cached }
                    else {
                        extracted = work.appendingPathComponent(UUID().uuidString)
                        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
                        let (data, response) = try await URLSession.shared.data(from: url)
                        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ExportError.invalidDownload }
                        let zip = extracted.appendingPathComponent("source.zip")
                        try data.write(to: zip)
                        try await exportCommand("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path], work: work)
                        downloaded[latest.url] = extracted
                    }
                    let artifact: URL
                    if CatalogFetcher.commandLineKeys.contains(entry.key) {
                        let packages = toolInstallerPackages(at: extracted, key: entry.key)
                        guard packages.count == 1, let package = packages.first else { throw ExportError.ambiguousPackage }
                        artifact = folder.appendingPathComponent(munkiArtifactName(key: entry.key, version: latest.version, extension: "pkg"))
                        pendingArtifact = artifact
                        try await exportCommand("/usr/bin/ditto", [package.path, artifact.path], work: work)
                    } else {
                        let apps = scanApps(dirs: [extracted.path]).filter { $0.key == entry.key }
                        guard let app = apps.max(by: { versionLess($0.version, $1.version) }) else { throw ExportError.noMatchingApp }
                        guard !versionLess(app.version, latest.version) else { throw ExportError.oldVersion }
                        let stage = work.appendingPathComponent(UUID().uuidString)
                        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
                        let staged = stage.appendingPathComponent(URL(fileURLWithPath: app.path).lastPathComponent)
                        try await exportCommand("/usr/bin/ditto", [app.path, staged.path], work: work)
                        artifact = folder.appendingPathComponent(munkiArtifactName(key: entry.key, version: app.version, extension: "dmg"))
                        pendingArtifact = artifact
                        try await exportCommand("/usr/bin/hdiutil", ["create", "-srcfolder", stage.path, "-volname", entry.name, "-format", "UDZO", artifact.path], work: work)
                        try await exportCommand("/usr/bin/hdiutil", ["verify", artifact.path], work: work)
                        let mount = work.appendingPathComponent(UUID().uuidString)
                        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
                        try await exportCommand("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, artifact.path], work: work)
                        let mounted = scanApps(dirs: [mount.path])
                        let valid = mounted.count == 1 && mounted[0].bundleID == app.bundleID && mounted[0].version == app.version
                        try await exportCommand("/usr/bin/hdiutil", ["detach", mount.path], work: work)
                        guard valid else { throw ExportError.validationFailed }
                        report.append("Bundle ID=\(app.bundleID) | actual version=\(app.version) | DMG contents verified")
                    }
                    let hashFile = work.appendingPathComponent(UUID().uuidString)
                    let hashStatus = await runLoggedProcess("/usr/bin/shasum", arguments: ["-a", "256", artifact.path], output: hashFile)
                    guard hashStatus == 0, let hash = try String(contentsOf: hashFile, encoding: .utf8).split(separator: " ").first else { throw ExportError.validationFailed }
                    checksums.append("\(hash)  \(artifact.lastPathComponent)")
                    report.append("SUCCESS: \(artifact.lastPathComponent)")
                    successes += 1
                } catch {
                    if let pendingArtifact { try? fm.removeItem(at: pendingArtifact) }
                    report.append("FAILED: \(entry.name): \(error.localizedDescription). Only SUCCESS items are ready for import.")
                }
                try report.joined(separator: "\n").write(to: folder.appendingPathComponent("export-report.txt"), atomically: true, encoding: .utf8)
                try (checksums.joined(separator: "\n") + "\n").write(to: folder.appendingPathComponent("SHA256SUMS.txt"), atomically: true, encoding: .utf8)
            }
            status = "Export complete: \(successes) succeeded, \(chosen.count - successes) failed."
            report.append(status)
            try report.joined(separator: "\n").write(to: folder.appendingPathComponent("export-report.txt"), atomically: true, encoding: .utf8)
            try? fm.removeItem(at: work)
        } catch { status = "Export failed: \(error.localizedDescription)" }
        ActivityLog.shared.append(status)
    }
}

enum ExportError: String, LocalizedError {
    case invalidDownload = "Download URL or HTTP response is invalid."
    case ambiguousPackage = "Expected exactly one matching package."
    case noMatchingApp = "No app matched the catalog bundle ID."
    case oldVersion = "Downloaded app is older than the catalog version."
    case validationFailed = "Artifact validation failed."
    var errorDescription: String? { rawValue }
}

func exportCommand(_ executable: String, _ arguments: [String], work: URL) async throws {
    let output = work.appendingPathComponent(UUID().uuidString + ".log")
    let status = await runLoggedProcess(executable, arguments: arguments, output: output)
    guard status == 0 else {
        let details = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        throw NSError(domain: "MunkiExport", code: Int(status), userInfo: [NSLocalizedDescriptionKey: URL(fileURLWithPath: executable).lastPathComponent + " failed: " + details])
    }
}


func munkiArtifactName(key: String, version: String, extension fileExtension: String) -> String {
    let safeVersion = version.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    return normalize(key) + "-" + safeVersion + "." + fileExtension
}
