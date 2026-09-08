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
    // Concise editorial descriptions, based on the publisher's menu, reviewed 2026-09-08.
    static let products: [HelpProduct] = {
        let groups: [(String, String, String)] = [
            ("Updates & security", "lockrattler-systhist", "Skint|Security monitoring;SilentKnight|Firmware checks;SystHist|Update history"),
            ("Security", "consolation-t2m2-and-log-utilities", "XProCheck|XProtect results"),
            ("Time Machine", "consolation-t2m2-and-log-utilities", "T2M2|Backup diagnosis"),
            ("Text", "text-utilities-nalaprop-dystextia-and-others", "Textovert|Text conversion;Disclipper|Clipping recovery;Nalaprop|Language analysis;Dystextia|Unicode encoding;Apfelstrudel|Normalization checks;unorml|Unicode normalization"),
            ("Rich Text", "delighted-podofyllin", "DelightEd|RTF editing"),
            ("PDF", "delighted-podofyllin", "Podofyllin|PDF inspection"),
            ("Metadata", "xattred-sandstrip-xattr-tools", "xattred|Attribute editing;SpotTest|Spotlight testing;Providable|Provenance inspection;cmpxat|Attribute comparison;Metamer|Metadata editing;Spotcord|Keyword discovery"),
            ("File integrity", "dintch", "DropSum|Checksum comparison;Dintch|Folder verification;Fintch|File verification;cintch|Integrity checking"),
            ("iCloud", "cirrus-bailiff", "Cirrus|iCloud diagnosis"),
            ("Version system", "revisionist-deeptools", "Versatility|Version archiving;Revisionist|Version management"),
            ("General utilities", "dintch", "Spundle|Image management;Cormorant|Archive compression;Stibium|Storage benchmarks"),
            ("General utilities", "taccy-signet-precize-alifix-utiutility-alisma", "Precize|File inspection;Alifix|Alias repair;alisma|Alias handling;UTIutility|Type inspection;Sparsity|Sparse files"),
            ("Virtualisation", "virtualisation-on-apple-silicon", "Viable|macOS guests;ViableS|Sandboxed guests;Vimy|Guest launching;Liviable|Linux guests"),
            ("Logs", "consolation-t2m2-and-log-utilities", "LogUI|Log browsing;Logistician|Log statistics;Ulbow|Log browsing;blowhole|Log writing"),
            ("iCloud / General utilities / Logs", "mints-a-multifunction-utility", "Mints|System investigation")
        ]
        return groups.flatMap { category, page, items in
            items.split(separator: ";").map { item in
                let parts = item.split(separator: "|")
                return HelpProduct(name: String(parts[0]), summary: String(parts[1]), category: category,
                                   page: "https://eclecticlight.co/" + page + "/")
            }
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()
}

struct UpdaterHelpView: View {
    @State private var tab = "Guide"
    @State private var search = ""
    private var products: [HelpProduct] {
        HelpDirectory.products.filter { search.isEmpty || ($0.name + " " + $0.summary).localizedCaseInsensitiveContains(search) }
    }
    private var categories: [String] { Array(Set(products.flatMap { $0.category.components(separatedBy: " / ") })).sorted() }
    var body: some View {
        VStack(alignment: .leading) {
            Picker("Help section", selection: $tab) {
                Text("Guide").tag("Guide")
                Text("Apps A–Z").tag("Apps A–Z")
                Text("By Category").tag("By Category")
            }.pickerStyle(.segmented)
            if tab == "Guide" {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(EclecticLightUpdaterApp.helpText.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, text in
                            let lines = text.components(separatedBy: "\n")
                            let title = lines.first ?? ""
                            if title.count < 50 && !title.contains(".") {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(title).font(.headline.bold()).accessibilityAddTraits(.isHeader)
                                    if lines.count > 1 {
                                        Text(lines.dropFirst().joined(separator: "\n")).textSelection(.enabled)
                                    }
                                }
                            } else { Text(text).textSelection(.enabled) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                TextField("Search apps and tools", text: $search)
                Text("Publisher directory · reviewed September 8, 2026. Product summaries do not determine compatibility of a particular download.").font(.caption)
                Link("Source: Eclectic Light Free Software Menu", destination: URL(string: "https://eclecticlight.co/free-software-menu/")!)
                List {
                    if tab == "Apps A–Z" {
                        ForEach(products) { product in productRow(product) }
                    } else {
                        ForEach(categories, id: \.self) { category in
                            Section(category) {
                                ForEach(products.filter { $0.category.components(separatedBy: " / ").contains(category) }) { product in productRow(product) }
                            }
                        }
                    }
                }
            }
        }.padding(24).frame(minWidth: 640, minHeight: 540)
    }

    private func productRow(_ product: HelpProduct) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(product.name).bold()
                Text(product.summary + (product.isTool ? " · Command-line tool" : " · App")).font(.caption)
            }
            Spacer()
            Link("Product Page", destination: URL(string: product.page)!)
        }.padding(.vertical, 3)
    }
}
