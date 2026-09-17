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

    static let commandLineKeys: Set<String> = ["alisma", "blowhole", "cintch", "cmpxat", "unorml"]

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
        // Verified from the downloaded app bundles. Move rather than duplicate
        // entries so discovery and installed-app scanning use the same identity.
        for (source, target) in ["cirrus": "cirrusmac", "t2m2": "thetimemachinemechanic2"] {
            if let entry = entries.removeValue(forKey: source) {
                entries[target] = CatalogEntry(key: target, name: entry.name, versions: entry.versions)
            }
        }
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
        return applyGoldenGateCompatibility(to: entries)
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


extension CatalogFetcher {
    static let goldenGateSourceURL = "https://eclecticlight.co/2026/09/12/which-of-my-apps-for-macos-golden-gate/"

    // Dated publisher evidence, scoped to the exact release and download URL.
    // Preserve live descriptions and newer releases; omission is not incompatibility.
    // The article says 37 apps, but enumerates 38 app releases and five CLI tools.
    static let goldenGateReleases: [(key: String, name: String, version: String, url: String, note: String)] = [
        ("alifix", "Alifix", "1.4", "https://eclecticlight.co/wp-content/uploads/2025/07/alifix14.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("apfelstrudel", "Apfelstrudel", "1.6", "https://eclecticlight.co/wp-content/uploads/2025/06/apfelstrudel16.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("cirrusmac", "Cirrus", "1.16", "https://eclecticlight.co/wp-content/uploads/2025/06/cirrus116.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026. Further feature and interface work planned."),
        ("cormorant", "Cormorant", "1.6", "https://eclecticlight.co/wp-content/uploads/2025/07/cormorant16.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("delighted", "DelightEd", "2.5", "https://eclecticlight.co/wp-content/uploads/2026/03/delighted25.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("deltafree", "DeltaFree", "1.1", "https://eclecticlight.co/wp-content/uploads/2026/08/deltafree11.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("dintch", "Dintch", "1.8", "https://eclecticlight.co/wp-content/uploads/2025/07/dintch18.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("disclipper", "Disclipper", "1.0", "https://eclecticlight.co/wp-content/uploads/2026/01/disclipper10.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("dropsum", "DropSum", "1.2", "https://eclecticlight.co/wp-content/uploads/2025/08/dropsum12.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("dystextia", "Dystextia", "1.9", "https://eclecticlight.co/wp-content/uploads/2025/07/dystextia19.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("fintch", "Fintch", "1.4", "https://eclecticlight.co/wp-content/uploads/2025/07/fintch14.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("logistician", "Logistician", "1.5", "https://eclecticlight.co/wp-content/uploads/2026/09/logistician15.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("logui", "LogUI", "1.1", "https://eclecticlight.co/wp-content/uploads/2026/07/logui11.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026. Applies to build 88."),
        ("metamer", "Metamer", "1.6", "https://eclecticlight.co/wp-content/uploads/2025/07/metamer16.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("mints", "Mints", "1.22", "https://eclecticlight.co/wp-content/uploads/2026/07/mints122.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("nalaprop", "Nalaprop", "1.4", "https://eclecticlight.co/wp-content/uploads/2025/07/nalaprop14.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("podofyllin", "Podofyllin", "1.4", "https://eclecticlight.co/wp-content/uploads/2025/06/podofyllin14.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026. The article lists stable 1.4; 1.5 was in beta."),
        ("precize", "Precize", "1.16", "https://eclecticlight.co/wp-content/uploads/2025/06/precize116.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("providable", "Providable", "1.2", "https://eclecticlight.co/wp-content/uploads/2026/01/providable12.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("quarant2", "Quarant2", "1.0", "https://eclecticlight.co/wp-content/uploads/2026/06/quarant21.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("revisionist", "Revisionist", "1.10", "https://eclecticlight.co/wp-content/uploads/2025/06/revisionist110.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("silentknight", "SilentKnight", "2.14", "https://eclecticlight.co/wp-content/uploads/2026/03/silentknight214.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026. Publisher prefers SilentKnight 3."),
        ("silentknight3", "SilentKnight 3", "3.02", "https://eclecticlight.co/wp-content/uploads/2026/07/sk302.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026. Apple silicon only."),
        ("sparsity", "Sparsity", "1.4", "https://eclecticlight.co/wp-content/uploads/2025/07/sparsity14.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("spotcord", "Spotcord", "1.0", "https://eclecticlight.co/wp-content/uploads/2025/07/spotcord10.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("spottest", "SpotTest", "1.3", "https://eclecticlight.co/wp-content/uploads/2026/07/spottest13.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("spundle", "Spundle", "1.9", "https://eclecticlight.co/wp-content/uploads/2025/06/spundle19.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("stibium", "Stibium", "1.2", "https://eclecticlight.co/wp-content/uploads/2025/07/stibium12.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("systhist", "SystHist", "1.22", "https://eclecticlight.co/wp-content/uploads/2026/06/systhist122.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("textovert", "Textovert", "1.1", "https://eclecticlight.co/wp-content/uploads/2025/11/textovert11.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("thetimemachinemechanic2", "The Time Machine Mechanic (T2M2)", "2.03", "https://eclecticlight.co/wp-content/uploads/2025/06/t2m2203.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026. Time Machine fixes may follow further experience."),
        ("utiutility", "UTIutility", "1.4", "https://eclecticlight.co/wp-content/uploads/2025/07/utiutil14.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("versatility", "Versatility", "1.2", "https://eclecticlight.co/wp-content/uploads/2026/06/versatility12.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("viable", "Viable", "1.0.12", "https://eclecticlight.co/wp-content/uploads/2023/11/viable1b12.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026. Further feature and interface work planned. Apple silicon only."),
        ("viables", "ViableS", "1.0.12", "https://eclecticlight.co/wp-content/uploads/2023/11/viables1b12.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026. Further feature and interface work planned. Apple silicon only."),
        ("vimy", "Vimy", "0.7", "https://eclecticlight.co/wp-content/uploads/2023/11/vimy07.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026. Further feature and interface work planned. Apple silicon only."),
        ("xattred", "xattred", "1.7", "https://eclecticlight.co/wp-content/uploads/2025/12/xattred17.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("xprocheck", "XProCheck", "1.7", "https://eclecticlight.co/wp-content/uploads/2025/06/xprocheck17.zip", "Publisher-tested for Golden Gate (macOS 27); September 12, 2026."),
        ("alisma", "alisma", "4", "https://eclecticlight.co/wp-content/uploads/2023/07/alisma4.zip", "Publisher believes compatible with Golden Gate (macOS 27); September 12, 2026."),
        ("blowhole", "blowhole", "11", "https://eclecticlight.co/wp-content/uploads/2023/07/blowhole11.zip", "Publisher believes compatible with Golden Gate (macOS 27); September 12, 2026."),
        ("cintch", "cintch", "3", "https://eclecticlight.co/wp-content/uploads/2023/07/cintch3.zip", "Publisher believes compatible with Golden Gate (macOS 27); September 12, 2026."),
        ("cmpxat", "cmpxat", "4", "https://eclecticlight.co/wp-content/uploads/2023/07/cmpxat4.zip", "Publisher believes compatible with Golden Gate (macOS 27); September 12, 2026."),
        ("unorml", "unorml", "5", "https://eclecticlight.co/wp-content/uploads/2023/07/unorml5.zip", "Publisher believes compatible with Golden Gate (macOS 27); September 12, 2026."),
    ]

    static func applyGoldenGateCompatibility(to parsed: [String: CatalogEntry]) -> [String: CatalogEntry] {
        var entries = parsed
        for release in goldenGateReleases {
            var entry = entries[release.key] ?? CatalogEntry(key: release.key, name: release.name)
            if let index = entry.versions.firstIndex(where: {
                $0.version == release.version && $0.url == release.url
            }) {
                let existing = entry.versions[index]
                if !existing.compat.contains(release.note) {
                    entry.versions[index] = CatalogVersion(version: existing.version, url: existing.url,
                        compat: [existing.compat, release.note].filter { !$0.isEmpty }.joined(separator: " "))
                }
            } else if !entry.versions.contains(where: { $0.version == release.version || $0.url == release.url }) {
                // Supply an article-listed release missing from the downloads page.
                // Never substitute evidence for another archive with the same version.
                entry.versions.append(CatalogVersion(version: release.version, url: release.url, compat: release.note))
            }
            entries[release.key] = entry
        }
        return entries
    }
}
