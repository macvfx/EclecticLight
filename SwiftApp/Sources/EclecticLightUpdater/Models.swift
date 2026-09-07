import Foundation

enum BundlePrefix {
    static let eclecticlight = "co.eclecticlight."
    static let appsFolder = "/Applications/EclecticLight"
}

struct AppInfo: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let bundleID: String
    let name: String
    let version: String

    enum Location: String {
        case applications = "Applications"
        case downloads = "Downloads"
        case custom = "Custom"
    }

    var location: Location {
        if path.hasPrefix("/Applications") { return .applications }
        if path.hasPrefix(NSHomeDirectory() + "/Downloads") { return .downloads }
        return .custom
    }

    var key: String {
        normalize(bundleID.replacingOccurrences(of: BundlePrefix.eclecticlight, with: ""))
    }
}

struct CatalogVersion {
    let version: String
    let url: String
    let compat: String
}

struct CatalogEntry {
    let key: String
    var name: String
    var versions: [CatalogVersion] = []

    var latest: CatalogVersion? {
        versions.max { versionLess($0.version, $1.version) }
    }
}

enum GroupStatus {
    case outdated          // newest installed copy is behind latest
    case downloadsOnly     // only in ~/Downloads / custom, latest unknown
    case downloadsOnlyOutdated
    case current
    case noCatalog
}

enum GroupAction {
    case installomator
    case download
    case none
}

struct GroupRow: Identifiable {
    let key: String
    var name: String
    var copies: [AppInfo]
    var entry: CatalogEntry?
    var status: GroupStatus
    var action: GroupAction

    var id: String { key }

    var latest: CatalogVersion? { entry?.latest }

    var newestInstalled: AppInfo? {
        copies.filter { $0.location == .applications }
            .max { versionLess($0.version, $1.version) }
    }

    var target: AppInfo { newestInstalled ?? copies.max { versionLess($0.version, $1.version) }! }

    var isActive: Bool {
        guard let newestInstalled else { return false }
        return !newestInstalled.path.hasPrefix(BundlePrefix.appsFolder)
    }
}

struct CatalogData {
    var entries: [String: CatalogEntry] = [:]
    var installomatorLabels: Set<String> = []

    var installomatorMatches: [String: String] = [:]  // app key -> label
}

func normalize(_ s: String) -> String {
    s.lowercased().filter { $0.isLetter || $0.isNumber }
}

// MARK: - Version comparison

enum VerPart: Comparable {
    case num(Int)
    case alpha(String)

    static func < (lhs: VerPart, rhs: VerPart) -> Bool {
        switch (lhs, rhs) {
        case (.num(let a), .num(let b)): return a < b
        case (.alpha(let a), .alpha(let b)): return a < b
        case (.num, .alpha): return true
        case (.alpha, .num): return false
        }
    }
}

func versionKey(_ v: String) -> [VerPart] {
    let ns = v as NSString
    let regex = try! NSRegularExpression(pattern: "\\d+|[a-zA-Z]+")
    var out: [VerPart] = []
    regex.enumerateMatches(in: v, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
        guard let r = m?.range else { return }
        let t = ns.substring(with: r)
        if let n = Int(t) { out.append(.num(n)) } else { out.append(.alpha(t.lowercased())) }
    }
    return out
}

func versionLess(_ a: String, _ b: String) -> Bool {
    versionKey(a).lexicographicallyPrecedes(versionKey(b))
}

func versionDigits(_ v: String) -> String {
    v.filter { $0.isNumber }
}

// MARK: - Filesystem scanning

func scanApps(dirs: [String]) -> [AppInfo] {
    var results: [AppInfo] = []
    for base in dirs {
        guard FileManager.default.fileExists(atPath: base) else { continue }
        collectApps(in: base, into: &results)
    }
    return results
}

private func collectApps(in dir: String, into results: inout [AppInfo]) {
    let fm = FileManager.default
    let items = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
    for item in items {
        let path = (dir as NSString).appendingPathComponent(item)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
        if item.hasSuffix(".app") {
            if let app = readApp(path: path) { results.append(app) }
        } else {
            collectApps(in: path, into: &results)
        }
    }
}

func readApp(path: String) -> AppInfo? {
    guard let bundle = Bundle(url: URL(fileURLWithPath: path)),
          let bundleID = bundle.bundleIdentifier,
          bundleID.hasPrefix(BundlePrefix.eclecticlight)
    else { return nil }
    let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? (path as NSString).lastPathComponent
    let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        ?? (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        ?? ""
    return AppInfo(path: path, bundleID: bundleID, name: name, version: version)
}

// MARK: - Group analysis

func analyzeGroups(apps: [AppInfo], catalog: CatalogData) -> [GroupRow] {
    var byKey: [String: [AppInfo]] = [:]
    for app in apps { byKey[app.key, default: []].append(app) }

    var rows: [GroupRow] = []
    for (key, copies) in byKey {
        let entry = catalog.entries[key]
        let latest = entry?.latest
        let installed = copies.filter { $0.location == .applications }
        let newestInstalled = installed.max { versionLess($0.version, $1.version) }
        let newestOverall = copies.max { versionLess($0.version, $1.version) }

        var status: GroupStatus
        var action: GroupAction = .none
        if entry == nil {
            status = .noCatalog
        } else if let newestInstalled, let latest {
            if versionLess(newestInstalled.version, latest.version) {
                status = .outdated
                let active = !newestInstalled.path.hasPrefix(BundlePrefix.appsFolder)
                action = (active && catalog.installomatorLabels.contains(key)) ? .installomator : .download
            } else {
                status = .current
            }
        } else if let latest {
            if let newestOverall, versionLess(newestOverall.version, latest.version) {
                status = .downloadsOnlyOutdated
                action = .download
            } else {
                status = .downloadsOnly
            }
        } else {
            status = .downloadsOnly
        }

        rows.append(GroupRow(key: key,
                             name: entry?.name ?? copies[0].name,
                             copies: copies.sorted { versionLess($1.version, $0.version) },
                             entry: entry,
                             status: status,
                             action: action))
    }
    return rows.sorted { $0.name.lowercased() < $1.name.lowercased() }
}

func findStaleInstalledCopies(in rows: [GroupRow]) -> [AppInfo] {
    var out: [AppInfo] = []
    for g in rows where g.status == .current {
        guard let newestInstalled = g.newestInstalled else { continue }
        for copy in g.copies where copy.location == .applications && copy != newestInstalled {
            if versionLess(copy.version, newestInstalled.version) { out.append(copy) }
        }
    }
    return out
}

func findLooseCopies(in rows: [GroupRow]) -> [AppInfo] {
    rows.flatMap { $0.copies }
        .filter {
            ($0.path as NSString).deletingLastPathComponent != BundlePrefix.appsFolder
        }
        .sorted { $0.path < $1.path }
}

func hasOrganizationCleanupWork() -> Bool {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: BundlePrefix.appsFolder, isDirectory: true)
    let readMe = root.appendingPathComponent("ReadMe", isDirectory: true).path
    guard let enumerator = fm.enumerator(at: root,
                                         includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                                         options: [.skipsPackageDescendants]) else { return false }
    while let url = enumerator.nextObject() as? URL {
        if url.path == readMe {
            enumerator.skipDescendants()
            continue
        }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values?.isDirectory == true {
            if url.pathExtension.lowercased() == "app" {
                enumerator.skipDescendants()
                continue
            }
            if let contents = try? fm.contentsOfDirectory(atPath: url.path), contents.isEmpty {
                return true
            }
            continue
        }
        if values?.isRegularFile == true,
           ["pdf", "rtf"].contains(url.pathExtension.lowercased()) {
            return true
        }
    }
    return false
}

// Catalog packages such as DeepTools are represented by their individual apps.
func availableApps(apps: [AppInfo], catalog: CatalogData) -> [CatalogEntry] {
    let present = Set(apps.map(\.key))
    let packageKeys: Set<String> = ["deeptools"]
    return catalog.entries.values.filter {
        !present.contains($0.key)
            && !CatalogFetcher.nonAppPrefixes.contains($0.key)
            && !packageKeys.contains($0.key)
            && $0.latest != nil
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

// Description-based OS check; this does not replace testing the downloaded app.
enum OSCompatibility: String {
    case compatible = "Compatible (description)"
    case possibleMismatch = "May not be compatible"
    case unknown = "Compatibility unknown"

    static let releases: [(name: String, version: String)] = [
        ("El Capitan", "10.11"), ("High Sierra", "10.13"), ("Sierra", "10.12"),
        ("Mojave", "10.14"), ("Catalina", "10.15"), ("Big Sur", "11"),
        ("Monterey", "12"), ("Ventura", "13"), ("Sonoma", "14"),
        ("Sequoia", "15"), ("Tahoe", "26")
    ]

    static var systemDescription: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let key = os.majorVersion == 10 ? "10.\(os.minorVersion)" : "\(os.majorVersion)"
        let name = releases.first { $0.version == key }?.name
        return "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)" + (name.map { " \($0)" } ?? "")
    }

    static func evaluate(_ description: String,
                         system: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> OSCompatibility {
        var text = description.lowercased()
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        // Avoid claiming support from negated or qualified mentions.
        if text.range(of: #"\b(not|except|excluding|untested|experimental)\b"#, options: .regularExpression) != nil {
            return .unknown
        }
        // Replace longer names first so High Sierra never matches Sierra.
        for release in releases.sorted(by: { $0.name.count > $1.name.count }) {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: release.name.lowercased())
                + #"\b(?:\s+(\d+(?:\.\d+){0,2}))?"#
            let regex = try! NSRegularExpression(pattern: pattern)
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
                let version = match.range(at: 1).location == NSNotFound
                    ? release.version : ns.substring(with: match.range(at: 1))
                text = (text as NSString).replacingCharacters(in: match.range, with: "macos " + version)
            }
        }
        let regex = try! NSRegularExpression(pattern: #"\b(?:macos|os x)\s+(\d+(?:\.\d+){0,2})"#)
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return .unknown }
        let current = [system.majorVersion, system.minorVersion, system.patchVersion]
        func parts(_ value: String) -> [Int] {
            let numbers = value.split(separator: ".").compactMap { Int($0) }
            return Array((numbers + [0, 0, 0]).prefix(3))
        }
        func less(_ a: [Int], _ b: [Int]) -> Bool { a.lexicographicallyPrecedes(b) }
        for (index, match) in matches.enumerated() {
            let raw = ns.substring(with: match.range(at: 1))
            let lower = parts(raw)
            let end = NSMaxRange(match.range)
            let nextStart = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let suffix = ns.substring(with: NSRange(location: end, length: nextStart - end))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix.range(of: #"^(?:and|or)\s+(?:later|newer|above)\b|^\+"#, options: .regularExpression) != nil {
                if !less(current, lower) { return .compatible }
            } else if index + 1 < matches.count,
                      suffix.range(of: #"^(?:to|through|[-–—])$"#, options: .regularExpression) != nil {
                let upperRaw = ns.substring(with: matches[index + 1].range(at: 1))
                let upper = parts(upperRaw)
                let precision = upperRaw.split(separator: ".").count
                if !less(current, lower),
                   !Array(upper.prefix(precision)).lexicographicallyPrecedes(Array(current.prefix(precision))) {
                    return .compatible
                }
            } else {
                // A named release covers its point releases; a stated point version is a minimum within that release.
                let sameRelease = current[0] == lower[0] && (lower[0] != 10 || current[1] == lower[1])
                if sameRelease && !less(current, lower) { return .compatible }
            }
        }
        return .possibleMismatch
    }
}

/// Diagnostic inventory includes non-Eclectic apps and bundles with missing metadata.
func archiveAppInventory(at root: URL) -> [String] {
    var lines: [String] = []
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                        errorHandler: { url, error in
        lines.append("Inventory read error at \(url.path): \(error.localizedDescription)")
        return true
    }) else { return ["Inventory unavailable at \(root.path)"] }
    var count = 0
    for case let url as URL in enumerator {
        guard url.pathExtension.lowercased() == "app" else { continue }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
        count += 1
        let relativePath = String(url.path.dropFirst(root.path.count + 1))
        do {
            let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
            let name = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
            let version = plist["CFBundleShortVersionString"] as? String ?? plist["CFBundleVersion"] as? String ?? "<missing>"
            let bundleID = plist["CFBundleIdentifier"] as? String ?? "<missing>"
            lines.append("App: \(relativePath) | name=\(name) | version=\(version) | bundle ID=\(bundleID)")
        } catch {
            lines.append("App: \(relativePath) | name=\(url.deletingPathExtension().lastPathComponent) | version=<unreadable> | bundle ID=<unreadable> | Info.plist error: \(error.localizedDescription)")
        }
    }
    return ["Archive inventory: \(count) app bundle(s)"] + lines.sorted()
}
