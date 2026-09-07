import Foundation

enum CatalogError: Error {
    case badURL
    case network(Error)
}

struct CatalogFetcher {
    static let siteURL = "https://eclecticlight.co/downloads/"
    static let labelsURL = "https://raw.githubusercontent.com/Installomator/Installomator/main/Labels.txt"

    // zip prefixes that don't map cleanly to a bundle-id app name
    static let zipOverrides = ["sk": "silentknight3"]

    // Suite downloads containing app bundles with different bundle-id suffixes.
    static let catalogAliases: [String: (source: String, name: String)] = [
        "deeparchive": ("deeptools", "DeepArchive"),
        "deepunarchive": ("deeptools", "DeepUnarchive"),
        "deepcopy": ("deeptools", "DeepCopy"),
        "skintm": ("skint", "SkintM"),
    ]

    static let nonAppPrefixes: Set<String> = [
        "macappscaffold", "scriptbase", "dropsy", "basicpdfviewer",
        "help", "lockrattlerhelp", "swiftscrapbook", "macproblems",
        "ovidmetamorphosesbook1a", "ovidmetamorphosesbook1b", "salomestory",
        "elainetheladyofshalott", "latexpaper", "latextuftebk",
    ]

    static func fetchString(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw CatalogError.badURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func fetchCatalog() async throws -> CatalogData {
        async let pageTask = try fetchString(siteURL)
        async let labelsTask = try fetchString(labelsURL)

        let (html, labelsText) = try await (pageTask, labelsTask)
        var catalog = CatalogData()
        catalog.entries = applyCatalogExceptions(to: parseDownloadsPage(html))
        catalog.installomatorLabels = Set(
            labelsText.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        catalog.installomatorMatches = matchLabels(catalog)
        return catalog
    }

    // MARK: - Downloads page parsing

    static func cleanHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func captureGroups(_ s: String, pattern: String) -> [String]? {
        let ns = s as NSString
        let regex = try! NSRegularExpression(pattern: pattern)
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return (0..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
    }

    static func parseLinkText(_ raw: String) -> (name: String?, version: String?, compat: String) {
        let cleaned = cleanHTML(raw)
        var pre = cleaned
        var compat = ""
        if let idx = cleaned.firstIndex(of: "(") {
            pre = String(cleaned[..<idx]).trimmingCharacters(in: .whitespaces)
            compat = String(cleaned[idx...])
        } else {
            pre = cleaned.trimmingCharacters(in: .whitespaces)
        }

        let ns = cleaned as NSString
        if let m = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)+[a-zA-Z0-9]*)"#)
            .firstMatch(in: cleaned, range: NSRange(location: 0, length: ns.length)) {
            let vr = m.range
            let version = ns.substring(with: vr)
            if vr.location < (pre as NSString).length {
                let name = ns.substring(with: NSRange(location: 0, length: vr.location))
                    .trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return (name, version, compat) }
            } else if !pre.isEmpty {
                return (pre, version, compat)
            }
        }
        if let groups = captureGroups(pre, pattern: #"^(.*?)\s+(\d+[a-zA-Z0-9]*)$"#) {
            let name = groups[1].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return (name, groups[2], compat) }
        }
        if !pre.isEmpty, !pre.contains(where: { $0.isWhitespace }) {
            return (pre, nil, compat)
        }
        return (nil, nil, compat)
    }

    static func parseDownloadsPage(_ html: String) -> [String: CatalogEntry] {
        var entries: [String: CatalogEntry] = [:]
        let ns = html as NSString
        let regex = try! NSRegularExpression(
            pattern: #"<a[^>]+href="([^"]*/wp-content/uploads/[0-9]{4}/[0-9]{2}/([^"/]+\.zip))"[^>]*>(.*?)</a>([^<]*)"#,
            options: [.dotMatchesLineSeparators]
        )
        regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let url = ns.substring(with: m.range(at: 1))
            let zipName = ns.substring(with: m.range(at: 2))
            let anchor = ns.substring(with: m.range(at: 3))
            let trailing = ns.substring(with: m.range(at: 4))
            let zipBase = (zipName as NSString).deletingPathExtension

            var name: String?
            var version: String?
            var compat = ""
            let parsed = parseLinkText(anchor + trailing)
            name = parsed.name
            version = parsed.version
            compat = parsed.compat

            var key: String?
            let zipPrefix = captureGroups(zipBase, pattern: #"^([a-z]+)"#)?[1]
            if let zipPrefix, zipOverrides[zipPrefix] != nil {
                key = normalize(zipOverrides[zipPrefix]!)
            } else if let name, !name.contains(where: { $0.isWhitespace }),
                      name.contains(where: { $0.isLetter }) {
                key = normalize(name)
            } else if let zipPrefix {
                key = normalize(zipPrefix)
            }
            guard let key else { return }

            if version == nil {
                if name == nil,
                   let groups = captureGroups(zipBase, pattern: #"^([a-z]+)"#) {
                    name = groups[1]
                }
                version = captureGroups(zipBase, pattern: #"(\d+(?:\.\d+)*[a-zA-Z0-9]*)$"#)?[1]
                compat = ""
            }
            guard let version, !version.isEmpty else { return }

            var entry = entries[key] ?? CatalogEntry(key: key, name: name ?? key)
            entry.name = name ?? key
            entry.versions.append(CatalogVersion(version: version, url: url, compat: compat))
            entries[key] = entry
        }
        return entries
    }

    static func applyCatalogExceptions(to parsed: [String: CatalogEntry]) -> [String: CatalogEntry] {
        var entries = parsed
        for (alias, mapping) in catalogAliases where entries[alias] == nil {
            guard let source = entries[mapping.source] else { continue }
            entries[alias] = CatalogEntry(key: alias,
                                          name: mapping.name,
                                          versions: source.versions)
        }
        // AppexIndexer isn't listed on the main downloads page. Version 1.1
        // is verified by its 30 June 2025 release article.
        if entries["appexindexer"] == nil {
            entries["appexindexer"] = CatalogEntry(
                key: "appexindexer",
                name: "AppexIndexer",
                versions: [CatalogVersion(
                    version: "1.1",
                    url: "https://eclecticlight.co/wp-content/uploads/2025/06/appexindexer11.zip",
                    compat: "(Sonoma 14.6 and later)"
                )]
            )
        }
        return entries
    }

    // MARK: - Installomator label matching

    static func matchLabels(_ catalog: CatalogData) -> [String: String] {
        var out: [String: String] = [:]
        for key in catalog.entries.keys where catalog.installomatorLabels.contains(key) {
            out[key] = key
        }
        return out
    }
}
