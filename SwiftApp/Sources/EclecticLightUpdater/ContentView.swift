import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showAvailable = false
    @State private var catalogSearch = ""
    @State private var websiteSearchGroup: GroupRow?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider()
                appList
                Divider()
                footer
            }
            .disabled(model.busy)

            if model.busy {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text(model.busyAction.isEmpty ? "Working…" : model.busyAction)
                        .font(.headline)
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 10)
            }

            if model.folderPromptVisible {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("Create folder?")
                        .font(.headline)
                    Text("\(BundlePrefix.appsFolder) doesn't exist. Create it?")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Cancel") { model.respondToFolderPrompt(false) }
                            .keyboardShortcut(.cancelAction)
                        Button("Create") { model.respondToFolderPrompt(true) }
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 10)
            }
        }
        .frame(minWidth: 920, minHeight: 620)
        .task { await model.refresh() }
        .sheet(item: $websiteSearchGroup) { group in
            SiteSearchView(appName: group.name)
                .frame(minWidth: 820, minHeight: 620)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Eclectic Light Updater")
                    .font(.headline)
                Text(OSCompatibility.systemDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.busy {
                ProgressView()
                    .controlSize(.small)
                Text(model.busyAction.isEmpty ? "Working…" : model.busyAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.installomatorPath == nil {
                Button("Install Installomator") {
                    Task { await model.updateAll() }
                }
            }
            Toggle("Not downloaded (\(model.available.count))", isOn: $showAvailable)
                .toggleStyle(.button)
            Button("Refresh") {
                Task { await model.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: - List

    private var appList: some View {
        List {
            if showAvailable {
                Section {
                    Text("No app bundle found in /Applications, ~/Applications or ~/Downloads. ZIP archives are not tracked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Find an app", text: $catalogSearch)
                    ForEach(model.available.filter {
                        catalogSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(catalogSearch)
                    }, id: \.key) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name).fontWeight(.medium)
                                Text("Version \(entry.latest?.version ?? "—")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            CompatibilityLabel(description: entry.latest?.compat ?? "")
                            Spacer()
                            Button("Install") { Task { await model.install([entry]) } }
                        }
                    }
                    if model.available.isEmpty {
                        Text("No undownloaded apps in the current catalog.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("Not downloaded (\(model.available.count))")
                        Spacer()
                        Button("Install All Compatible (\(model.compatibleAvailable.count))") {
                            Task { await model.install(model.compatibleAvailable) }
                        }
                        .disabled(model.compatibleAvailable.isEmpty)
                        .help("Install missing apps whose latest descriptions match this macOS. Skips unknown compatibility and possible mismatches; includes all matches regardless of the search filter.")
                        Button("Install All (\(model.available.count))") {
                            Task { await model.install(model.available) }
                        }
                        .disabled(model.available.isEmpty)
                    }
                }
            }

            if model.rows.isEmpty && !model.busy {
                Text("No Eclectic Light apps found in /Applications, ~/Applications or ~/Downloads.")
                    .foregroundStyle(.secondary)
                    .padding()
            }

            if !model.outdatedGroups.isEmpty {
                Section {
                    ForEach(model.outdatedGroups) { g in
                        OutdatedRow(group: g) {
                            Task { await model.update(g) }
                        }
                    }
                } header: {
                    HStack {
                        Text("Out of date")
                        Spacer()
                        Button("Update all") { Task { await model.updateAll() } }
                            .controlSize(.small)
                    }
                }
            }

            if !model.staleCopies.isEmpty {
                Section {
                    ForEach(model.staleCopies) { app in
                        CopyRow(app: app, badge: "stale", color: .orange)
                    }
                } header: {
                    HStack {
                        Text("Stale copies (older than the installed version)")
                        Spacer()
                        Button("Clean up") { Task { await model.cleanupStale() } }
                            .controlSize(.small)
                    }
                }
            }

            if !model.looseCopies.isEmpty || model.organizationCleanupNeeded {
                Section {
                    ForEach(model.looseCopies) { app in
                        CopyRow(app: app, badge: "organize", color: .teal)
                    }
                    if model.looseCopies.isEmpty {
                        Text("PDF/RTF documents or empty folders need organization.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("Organization")
                        Spacer()
                        Button("Organize") { Task { await model.organize() } }
                            .controlSize(.small)
                    }
                }
            }

            if !model.currentGroups.isEmpty {
                Section {
                    ForEach(model.currentGroups) { g in
                        CurrentRow(group: g)
                    }
                } header: {
                    Text("Up to date")
                }
            }

            if !model.noCatalogGroups.isEmpty {
                Section {
                    ForEach(model.noCatalogGroups) { g in
                        CurrentRow(group: g) {
                            websiteSearchGroup = g
                        }
                    }
                } header: {
                    Text("No catalog entry")
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(model.busy ? Color.yellow : Color.green)
                    .frame(width: 8, height: 8)
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.installomatorPath != nil {
                    Text("Installomator: \(model.installomatorPath ?? "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView {
                Text(model.log)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        }
        .padding(10)
        .background(.bar)
    }
}

// MARK: - Rows

struct OutdatedRow: View {
    let group: GroupRow
    let onUpdate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).fontWeight(.medium)
                Text("\(group.target.version) → \(group.latest?.version ?? "?")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let compat = group.latest?.compat, !compat.isEmpty {
                    Text(compat)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            CompatibilityLabel(description: group.latest?.compat ?? "")
            Text(actionLabel)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(actionLabel == "Installomator" ? Color.accentColor.opacity(0.15) : Color.blue.opacity(0.15))
                .clipShape(Capsule())
            Button(group.action == .installomator ? "Update" : "Download") {
                onUpdate()
            }
        }
        .padding(.vertical, 2)
    }

    private var actionLabel: String {
        switch group.action {
        case .installomator: return "Installomator"
        case .download: return "Download"
        case .none: return ""
        }
    }
}

struct CopyRow: View {
    let app: AppInfo
    let badge: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).fontWeight(.medium)
                Text(app.version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(badge)
                .font(.caption2)
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
            Text(app.path)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}

struct CurrentRow: View {
    let group: GroupRow
    var onSearch: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).fontWeight(.medium)
                Text("installed \(group.newestInstalled?.version ?? group.target.version) · latest \(group.latest?.version ?? "—")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CompatibilityLabel(description: group.latest?.compat ?? "")
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let onSearch {
                Button("Search Website", action: onSearch)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusLabel: String {
        switch group.status {
        case .downloadsOnly: return "in Downloads"
        case .noCatalog: return "no catalog"
        default: return "up to date"
        }
    }
}


struct CompatibilityLabel: View {
    let description: String
    private var result: OSCompatibility { OSCompatibility.evaluate(description) }
    private var color: Color {
        switch result {
        case .compatible: return .green
        case .possibleMismatch: return .orange
        case .unknown: return .secondary
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(result.rawValue, systemImage: result == .compatible ? "checkmark.circle" : "questionmark.circle")
                .foregroundStyle(color)
            if !description.isEmpty {
                Text(description).foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .frame(maxWidth: 280, alignment: .leading)
        .help("Compared with " + OSCompatibility.systemDescription + ". Based on the latest catalog description; not a runtime or hardware compatibility test.")
    }
}
