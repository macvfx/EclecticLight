import SwiftUI

@main
struct EclecticLightUpdaterApp: App {
    init() {
        if CommandLine.arguments.contains("--dump") {
            Headless.dump()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1000, height: 680)
        .commands { UpdaterHelpCommands() }
        Window("Eclectic Light Updater Help", id: "updater-help") {
            ScrollView {
                Text(Self.helpText).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }.frame(minWidth: 580, minHeight: 480)
        }
        Window("Make Munki Ready", id: "munki-export") { MunkiExportView() }
        Window("Activity Log", id: "updater-log") {
            ActivityLogView()
        }
    }
}

extension EclecticLightUpdaterApp {
    static let helpText = """
    Eclectic Light Updater

    Refresh scans /Applications, ~/Applications and ~/Downloads, then fetches the download catalog. It finds extracted app bundles, not ZIP archives.

    Install apps
    Choose Not downloaded to browse or search missing apps. Install downloads one app. Install All includes every missing catalog app. Install All Compatible includes only apps whose latest description matches your macOS, regardless of the search filter.

    Command-line tools
    The separate command-line tools section offers Install Package and download links. Install Package downloads the archive, selects the expected installer, and runs the macOS installer with administrator permission. Installer output and success/failure are recorded in Show Log. These tools are excluded from both Install All actions; their successful package versions are remembered across launches. Installed buttons are disabled for that version; Install All Packages skips them. External installations or removals are not detected.

    Installation results report verified app versions at the destination, with success and failure counts.

    Compatibility
    Green means the publisher’s description lists your macOS or a matching range. Orange means it may not be compatible. Unknown means the description is missing or unclear. This is an OS description check, not a hardware check or a guarantee that the app will run.

    Update and organize
    Update All updates out-of-date apps. Downloads are installed under /Applications/EclecticLight. Organize flattens app folders and collects PDF/RTF documents into ReadMe. Clean up moves stale installed copies to Trash. File operations may request an administrator password.

    Munki export
    Tools → Make Munki Ready lets you select catalog downloads and an output folder. Each selected app is exported as a separate validated DMG; CLI tools keep their original installer package. Downloads shared by suite apps are reused during the run. Exports are independent of local installation and OS compatibility. Select All includes entries hidden by search.
    Export filenames retain the version dots, for example logui-1.1.dmg.
    Read export-report.txt and SHA256SUMS.txt in the output folder. Import successful files using MunkiAdmin or munkiimport and configure deployment there. No software is installed and no Munki repository is changed by export.

    Logs and errors
    Help → Show Log displays timestamped activity retained across launches. Reveal Log in Finder opens its location under ~/Library/Logs/EclecticLightUpdater. The log can contain local paths; review it before sharing.

    “Prepared for installation” means file operations may still be pending. Check subsequent completion and error messages.

    “No matching app found” means the archive did not contain the expected co.eclecticlight app bundle. It can be a command-line tool or a catalog mapping mismatch. Do not treat it as successful installation or as a macOS compatibility result.

    Download or extraction failures: check the log and your network connection, refresh, then retry the individual app. A cancelled password prompt can leave installation incomplete.

    Persistent logging was introduced in version 1.1; earlier sessions cannot be recovered from it. The log retains the latest approximately 2 MB plus one previous file.
    """
}

struct UpdaterHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandMenu("Tools") {
            Button("Make Munki Ready…") { openWindow(id: "munki-export") }
        }
        CommandGroup(replacing: .help) {
            Button("Eclectic Light Updater Help") { openWindow(id: "updater-help") }
            Button("Show Log") { openWindow(id: "updater-log") }
            Button("Reveal Log in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([ActivityLog.shared.url])
            }
        }
    }
}

@MainActor
final class ActivityLog: ObservableObject {
    static let shared = ActivityLog()
    @Published private(set) var text = ""
    @Published private(set) var errorMessage = ""
    let url: URL

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/EclecticLightUpdater")) {
        url = directory.appendingPathComponent("activity.log")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            append("Session opened — " + OSCompatibility.systemDescription)
        } catch { errorMessage = "Cannot create log: \(error.localizedDescription)" }
    }

    func append(_ message: String) {
        guard !message.isEmpty else { return }
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        do {
            if text.utf8.count > 2_000_000 {
                try text.write(to: url.deletingLastPathComponent().appendingPathComponent("activity.previous.log"), atomically: true, encoding: .utf8)
                try Data().write(to: url)
                text = ""
            }
            if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            text += line
            errorMessage = ""
        } catch {
            text += line
            errorMessage = "Log could not be saved: \(error.localizedDescription)"
        }
    }
}

struct ActivityLogView: View {
    @ObservedObject private var log = ActivityLog.shared
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button("Copy Log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.text, forType: .string)
                }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([log.url]) }
            }
            if !log.errorMessage.isEmpty { Text(log.errorMessage).foregroundStyle(.red) }
            ScrollView {
                Text(log.text).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding().frame(minWidth: 760, minHeight: 480)
    }
}

// MARK: - Headless CLI mode (./EclecticLightUpdater --dump)

enum Headless {
    static func dump() -> Never {
        let apps = scanApps(dirs: [
            "/Applications",
            NSHomeDirectory() + "/Applications",
            NSHomeDirectory() + "/Downloads",
        ])
        var lines: [String] = ["SCAN \(apps.count) copies"]
        var catalog = CatalogData()
        do {
            catalog = try syncFetchCatalog()
        } catch {
            lines.append("CATALOG_ERROR \(error)")
        }
        let rows = analyzeGroups(apps: apps, catalog: catalog)
        for g in rows {
            let target = g.target
            let latest = g.latest?.version ?? "-"
            let status: String
            switch g.status {
            case .outdated: status = "OUTDATED"
            case .downloadsOnlyOutdated: status = "OUTDATED(dl)"
            case .current: status = "current"
            case .downloadsOnly: status = "downloads"
            case .noCatalog: status = "nocatalog"
            }
            var action = ""
            switch g.action {
            case .installomator: action = "label=\(g.key)"
            case .download: action = "download"
            case .none: action = ""
            }
            print("\(g.key)\t\(g.name)\t\(target.version)\t\(latest)\t\(status)\t\(action)")
            for c in g.copies {
                print("  copy\t\(c.version)\t\(c.location.rawValue)\t\(c.path)")
            }
        }
        let stale = findStaleInstalledCopies(in: rows)
        let loose = findLooseCopies(in: rows)
        print("STALE \(stale.count)")
        for c in stale { print("  \(c.path)") }
        print("LOOSE \(loose.count)")
        for c in loose { print("  \(c.path)") }
        exit(0)
    }

    static func syncFetchCatalog() throws -> CatalogData {
        let page = try String(contentsOf: URL(string: CatalogFetcher.siteURL)!, encoding: .utf8)
        let labels = try String(contentsOf: URL(string: CatalogFetcher.labelsURL)!, encoding: .utf8)
        var catalog = CatalogData()
        catalog.entries = CatalogFetcher.parseDownloadsPage(page)
        catalog.installomatorLabels = Set(
            labels.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        catalog.installomatorMatches = CatalogFetcher.matchLabels(catalog)
        return catalog
    }
}
struct MunkiExportView: View {
    @StateObject private var exporter = MunkiExporter()
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Make Munki Ready").font(.title2)
            Text("Export one app per DMG or the original CLI installer package. Nothing is installed or imported into a Munki repository.")
            HStack {
                Button("Refresh Catalog") { Task { await exporter.load() } }
                Button("Select All") { exporter.selected = Set(exporter.entries.map(\.key)) }
                Button("Select None") { exporter.selected = [] }
                TextField("Search catalog", text: $search)
            }.disabled(exporter.busy)
            List(exporter.entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }, id: \.key) { entry in
                Toggle(isOn: Binding(get: { exporter.selected.contains(entry.key) }, set: { chosen in
                    if chosen { exporter.selected.insert(entry.key) } else { exporter.selected.remove(entry.key) }
                })) {
                    VStack(alignment: .leading) {
                        Text(entry.name + " " + (entry.latest?.version ?? ""))
                        Text((CatalogFetcher.commandLineKeys.contains(entry.key) ? "PKG · " : "DMG · ") + (entry.latest?.compat ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(exporter.busy)
            }
            Text(exporter.status).textSelection(.enabled)
            HStack {
                if exporter.busy { ProgressView().controlSize(.small) }
                Button("Export Selected (\(exporter.selected.count))…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Export Here"
                    if panel.runModal() == .OK, let folder = panel.url { Task { await exporter.export(to: folder) } }
                }.disabled(exporter.busy || exporter.selected.isEmpty)
                if let output = exporter.output {
                    Button("Show Output") { NSWorkspace.shared.open(output) }
                }
            }
        }.padding().frame(minWidth: 780, minHeight: 600)
        .task { await exporter.load() }
    }
}
