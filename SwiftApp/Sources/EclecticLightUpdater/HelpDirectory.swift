import SwiftUI

struct HelpProduct: Identifiable {
    var id: String { name }
    let name: String
    let summary: String
    let category: String
    let page: String
    var isTool: Bool { ["unorml", "cmpxat", "cintch", "alisma", "blowhole"].contains(name) }
}

enum HelpDirectory {
    // Concise editorial descriptions, based on the publisher's menu, reviewed 2026-09-17.
    static let reviewedDate = "September 17, 2026"
    static let sourceURL = URL(string: "https://eclecticlight.co/free-software-menu/")!
    static let products: [HelpProduct] = {
        let groups: [(String, String, String)] = [
            ("Updates & security", "lockrattler-systhist", "Skint|Checks important macOS security settings daily and highlights potential problems. Useful for ongoing security monitoring.;SilentKnight|Checks firmware, security settings and security data updates, helping you see whether your Mac’s protections are current.;SystHist|Shows the history of macOS system and security updates installed on this Mac, including less visible background updates."),
            ("Security", "consolation-t2m2-and-log-utilities", "XProCheck|Reads macOS logs to report completed XProtect Remediator scans and their results. Helps confirm that malware scanning is taking place."),
            ("Time Machine", "consolation-t2m2-and-log-utilities", "T2M2|Analyses Time Machine logs for backup timing, errors and warning signs. Explains potential backup problems without requiring you to read raw logs."),
            ("Text", "text-utilities-nalaprop-dystextia-and-others", "Textovert|Converts document text between formats such as plain text, RTF, HTML and Word. It can also extract text from PDFs.;Disclipper|Opens Finder clipping files and saves their contents into usable files. Supports text and picture clippings as well as web and mail locations.;Nalaprop|Analyses multilingual text, identifying parts of speech and word frequencies. Useful for examining language while you write.;Dystextia|Transforms Latin text using unusual Unicode characters and decodes it again. Demonstrates how similar-looking text can behave differently in searches.;Apfelstrudel|Displays Unicode normalisation forms for text. Helps investigate character differences that can affect filenames and cross-platform text comparisons.;unorml|Converts text to a chosen Unicode normalisation form from the command line. Useful in scripts that need consistent character representations."),
            ("Rich Text", "delighted-podofyllin", "DelightEd|Edits rich-text documents with control over light and dark appearance. Supports interlinear text for tasks such as comparing translations."),
            ("PDF", "delighted-podofyllin", "Podofyllin|Displays PDFs with page thumbnails, searchable text and inspection tools. Useful for examining document contents rather than editing PDF pages."),
            ("Metadata", "xattred-sandstrip-xattr-tools", "xattred|Inspects and edits extended attributes attached to files and folders. You can copy attributes between items or examine quarantine metadata.;SpotTest|Creates test files and checks whether Spotlight indexes and finds them. Helps diagnose local metadata and content-search problems.;Providable|Examines quarantine and provenance attributes to help identify which application last changed a file.;cmpxat|Compares the extended attributes of two files and reports differences. Useful when checking whether metadata survived a copy.;Metamer|Edits useful Spotlight metadata fields, including text-based attributes. Makes searchable file metadata accessible without manual attribute commands.;Spotcord|Scans folders to collect Spotlight keywords and other text metadata into a vocabulary with occurrence counts. Helps discover useful search terms."),
            ("File integrity", "dintch", "DropSum|Calculates and compares MD5 and SHA-256 checksums. Use it to check a download against a published hash or compare files.;Dintch|Stores SHA-256 integrity tags on files in folders, then checks them later for changes. Designed for larger collections.;Fintch|Tags and verifies individual files, bundles or small folders using SHA-256. Provides a drag-and-drop approach to file integrity checks.;cintch|Provides file-integrity tagging and verification from the command line. Suitable for scripted checks of files and folders."),
            ("iCloud", "cirrus-bailiff", "Cirrus|Investigates iCloud Drive files, transfer activity and related logs. Includes controls for downloading files and removing their local cached copies."),
            ("Version system", "revisionist-deeptools", "Versatility|Archives a document together with its saved versions, then restores that version history to a copy. Helps preserve versions when moving documents.;Revisionist|Inspects and manages macOS document versions. Can preview earlier versions and copy documents while preserving their version history."),
            ("General utilities", "dintch", "Spundle|Creates, resizes and compacts sparse-bundle disk images. Useful for adjusting their capacity or reclaiming unused storage.;Cormorant|Compresses and expands files, folders and apps using AppleArchive and LZFSE. Provides a simple interface for these macOS archive formats.;Stibium|Measures storage read and write performance with configurable file sizes. Analyses results to help compare disks and SSDs."),
            ("General utilities", "taccy-signet-precize-alifix-utiutility-alisma", "Precize|Inspects files, bundles and folders, including disk usage and extended attributes. Also examines persistent file references such as bookmarks and aliases.;Alifix|Finds and refreshes Finder aliases in folders, reporting broken references. Useful after moving or copying large collections of files.;alisma|Creates Finder aliases or resolves an existing alias to its target path from Terminal. Useful for shell scripts that work with aliases.;UTIutility|Lists file type identifiers found in folders and converts between identifiers, filename extensions and MIME types.;Sparsity|Finds APFS sparse and cloned files and reports their storage characteristics. Can also create sparse files for testing."),
            ("Virtualisation", "virtualisation-on-apple-silicon", "Viable|Creates and runs macOS virtual machines on Apple silicon. Lets you configure resources such as memory, processor allocation and display settings.;ViableS|Provides a sandboxed variant of Viable without shared folders or a shared clipboard. Intended for more isolated macOS virtual-machine research.;Vimy|Opens a macOS virtual machine using settings saved by Viable. A lightweight launcher for Apple silicon Macs.;Liviable|Creates and runs Linux virtual machines on Apple silicon from installer images. Provides controls for virtual hardware and host-folder sharing."),
            ("Logs", "consolation-t2m2-and-log-utilities", "LogUI|Browses the macOS unified log and saved log archives. Filters and export tools help isolate and share relevant diagnostic records.;Logistician|Charts log activity over longer periods using macOS statistics files. Helps identify busy subsystems and patterns before examining individual records.;Ulbow|Browses and filters unified-log records and log archives. Offers searchable extracts and export options for troubleshooting.;blowhole|Writes messages into the macOS unified log from Terminal or scripts. Useful for recording when automated tasks run."),
            ("iCloud / General utilities / Logs", "mints-a-multifunction-utility", "Mints|Collects system information, targeted log extracts and diagnostic tools. Includes checks for Spotlight and other macOS features.")
        ]
        let listed = groups.flatMap { category, page, items in
            items.split(separator: ";").map { item in
                let parts = item.split(separator: "|")
                return HelpProduct(name: String(parts[0]), summary: String(parts[1]), category: category,
                                   page: "https://eclecticlight.co/" + page + "/")
            }
        }
        let additional = [
            HelpProduct(name: "SilentKnight 3", summary: "Checks security systems on Apple silicon Macs and offers detailed text or JSON reports. The successor to SilentKnight 2 for supported systems.", category: "Updates & security", page: "https://eclecticlight.co/lockrattler-systhist/"),
            HelpProduct(name: "DeepTools", summary: "Older tools for preserving document versions when copying or archiving files. Includes DeepCopy, DeepArchive and DeepUnarchive; the publisher now recommends Versatility.", category: "Version system", page: "https://eclecticlight.co/revisionist-deeptools/"),
            HelpProduct(name: "Quarant2", summary: "Adjusts quarantine metadata on selected documents that will not open as expected. Works on individually dropped files, excluding apps and bundles.", category: "Metadata", page: "https://eclecticlight.co/2026/06/15/fix-documents-that-wont-open-as-expected-using-quarant2/"),
            HelpProduct(name: "DeltaFree", summary: "Tracks changes in free storage space to help assess how quickly backup storage is filling.", category: "Time Machine", page: "https://eclecticlight.co/2026/08/17/how-long-until-my-backup-storage-is-full-deltafree-can-inform-you/"),
            HelpProduct(name: "AppexIndexer", summary: "Lists app extensions registered with PlugInKit, including their identifiers. Search and sorting help trace an extension back to its application.", category: "General utilities", page: "https://eclecticlight.co/2025/04/14/appexindexer-build-8-has-sort-and-search-features/")
        ]
        return (listed + additional).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    static func product(key: String, name: String) -> HelpProduct? {
        let aliases = ["cirrusmac": "cirrus", "thetimemachinemechanic2": "t2m2",
                       "thetimemachinemechanict2m2": "t2m2", "thetimemachinemechanic": "t2m2",
                       "skintm": "skint", "deeparchive": "deeptools",
                       "deepunarchive": "deeptools", "deepcopy": "deeptools"]
        for candidate in [key, name] {
            let normalized = normalize(candidate)
            let target = aliases[normalized] ?? normalized
            if let product = products.first(where: { normalize($0.name) == target }) { return product }
        }
        return nil
    }

    static func searchURL(for name: String) -> URL {
        var parts = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)!
        parts.path = "/"
        parts.queryItems = [URLQueryItem(name: "s", value: name)]
        return parts.url!
    }

    static func matching(_ query: String) -> [HelpProduct] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return products.filter { query.isEmpty || ($0.name + " " + $0.summary + " " + $0.category)
            .localizedCaseInsensitiveContains(query) }
    }
}



struct ProductInfoButton: View {
    let name: String
    let productKey: String
    @State private var showingDetails = false

    var body: some View {
        Button { showingDetails = true } label: {
            HStack(spacing: 5) {
                Text(name).fontWeight(.medium).multilineTextAlignment(.leading)
                Image(systemName: "info.circle").font(.caption)
            }.foregroundStyle(.tint)
        }
        .buttonStyle(.plain)
        .help("What does \(name) do?")
        .accessibilityLabel("About \(name)")
        .sheet(isPresented: $showingDetails) {
            ProductInfoView(name: name, product: HelpDirectory.product(key: productKey, name: name))
        }
    }
}

struct ProductInfoView: View {
    let name: String
    let product: HelpProduct?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HelpHeading(title: name, symbol: "info.circle.fill", prominent: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let product {
                        Text(product.category + " · " + (product.isTool ? "Command-line tool" : "App"))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if normalize(product.name) != normalize(name) {
                            Text("Part of the \(product.name) family").font(.headline)
                        }
                        Text(product.summary).font(.body).textSelection(.enabled)
                        Link("Read more on Eclectic Light ↗", destination: URL(string: product.page)!)
                        Text("Summary based on the publisher’s website · reviewed \(HelpDirectory.reviewedDate).")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("A description for this app is not included in the bundled directory yet.")
                        Link("Search Eclectic Light for \(name) ↗", destination: HelpDirectory.searchURL(for: name))
                    }
                    Text("For supported macOS versions, check the download’s compatibility information and the publisher’s latest guidance.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Link("Browse all apps on the website", destination: HelpDirectory.sourceURL)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 540, height: 370)
    }
}

struct HelpHeading: View {
    let title: String
    var symbol = "book.closed.fill"
    var prominent = false
    private var tint: Color {
        if title.localizedCaseInsensitiveContains("install") { return .indigo }
        if title.localizedCaseInsensitiveContains("log") { return .purple }
        if title.localizedCaseInsensitiveContains("compatib") { return .teal }
        return .blue
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(prominent ? .largeTitle.bold() : .title3.bold())
            .foregroundStyle(tint)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(prominent ? 18 : 10)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct HelpGuideSection: Identifiable {
    var id: String { title }
    let title: String
    var paragraphs: [String]

    static func parse(_ text: String) -> [HelpGuideSection] {
        let headings: Set<String> = ["Help directory", "Install apps", "Command-line tools", "Compatibility",
                                     "Update and organize", "Installomator", "Munki export", "Logs and errors"]
        var sections = [HelpGuideSection(title: "Getting started", paragraphs: [])]
        for block in text.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n")
            let title = lines.first ?? ""
            if title.hasPrefix("Eclectic Light Updater ") { continue }
            if headings.contains(title) {
                sections.append(HelpGuideSection(title: title,
                    paragraphs: lines.count > 1 ? [lines.dropFirst().joined(separator: "\n")] : []))
            } else if !block.isEmpty {
                sections[sections.count - 1].paragraphs.append(block)
            }
        }
        return sections
    }
}

struct UpdaterHelpView: View {
    @State private var tab = "Guide"
    @State private var search = ""
    private var products: [HelpProduct] { HelpDirectory.matching(search) }
    private var categories: [String] {
        Array(Set(products.flatMap { $0.category.components(separatedBy: " / ") })).sorted()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HelpHeading(title: "Eclectic Light Updater Help", symbol: "books.vertical.fill", prominent: true)
            Text("Learn the workflows, discover an app, or visit its publisher’s page.")
                .foregroundStyle(.secondary)
            Picker("Help section", selection: $tab) {
                Text("Guide").tag("Guide")
                Text("Apps A–Z").tag("Apps A–Z")
                Text("By Category").tag("By Category")
            }.pickerStyle(.segmented)
            if tab == "Guide" {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(HelpGuideSection.parse(EclecticLightUpdaterApp.helpText)) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                HelpHeading(title: section.title)
                                ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                    Text(paragraph).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                TextField("Search names, descriptions and categories", text: $search)
                Text("\(products.count) apps and tools · reviewed \(HelpDirectory.reviewedDate). Descriptions are available offline; website links require a connection.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Source: Eclectic Light Free Software Menu", destination: HelpDirectory.sourceURL)
                List {
                    if products.isEmpty {
                        Text("No matching apps or tools. Try another name or purpose.").foregroundStyle(.secondary)
                    } else if tab == "Apps A–Z" {
                        ForEach(products) { product in productRow(product) }
                    } else {
                        ForEach(categories, id: \.self) { category in
                            Section {
                                ForEach(products.filter { $0.category.components(separatedBy: " / ").contains(category) }) {
                                    product in productRow(product)
                                }
                            } header: { HelpHeading(title: category) }
                        }
                    }
                }
            }
        }.padding(24).frame(minWidth: 700, minHeight: 600)
    }

    private func productRow(_ product: HelpProduct) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProductInfoButton(name: product.name, productKey: normalize(product.name))
                Spacer()
                Text(product.isTool ? "Command-line tool" : "App").font(.caption).foregroundStyle(.secondary)
                Link("Product Page ↗", destination: URL(string: product.page)!)
            }
            Text(product.summary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.padding(.vertical, 8)
    }
}
