import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var available: [CatalogEntry] = []
    @Published var rows: [GroupRow] = []
    @Published var staleCopies: [AppInfo] = []
    @Published var looseCopies: [AppInfo] = []
    @Published var organizationCleanupNeeded = false
    @Published var busy = false
    @Published var busyAction = ""
    @Published var statusMessage = "Ready" { didSet { ActivityLog.shared.append(statusMessage) } }
    @Published var log = "" { didSet { if !log.isEmpty { ActivityLog.shared.append(log) } } }
    @Published var installomatorPath: String?
    @Published var folderPromptVisible = false
    private var pendingFolderAction: (() async -> Void)?

    private var catalog = CatalogData()
    private let service = UpdateService()

    var compatibleAvailable: [CatalogEntry] {
        available.filter { OSCompatibility.evaluate($0.latest?.compat ?? "") == .compatible }
    }

    var outdatedGroups: [GroupRow] {
        rows.filter { $0.status == .outdated || $0.status == .downloadsOnlyOutdated }
    }
    var currentGroups: [GroupRow] {
        rows.filter { $0.status == .current || $0.status == .downloadsOnly }
    }
    var noCatalogGroups: [GroupRow] {
        rows.filter { $0.status == .noCatalog }
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        busyAction = "Refreshing…"
        statusMessage = "Scanning…"
        do {
            let dirs = [
                "/Applications",
                NSHomeDirectory() + "/Applications",
                NSHomeDirectory() + "/Downloads",
            ]
            let scan = await Task.detached(priority: .userInitiated) {
                (scanApps(dirs: dirs), hasOrganizationCleanupWork())
            }.value
            let apps = scan.0
            statusMessage = "Fetching catalog…"
            busyAction = "Fetching catalog…"
            let newCatalog = try await CatalogFetcher.fetchCatalog()
            catalog = newCatalog
            available = availableApps(apps: apps, catalog: newCatalog)
            installomatorPath = findInstallomator()
            apply(analyzeGroups(apps: apps, catalog: newCatalog), cleanupNeeded: scan.1)
            statusMessage = "Scanned \(apps.count) copy/copies, \(outdatedGroups.count) out of date"
        } catch {
            statusMessage = "Refresh failed: \(error.localizedDescription)"
            log = "Error: \(error)"
        }
        busy = false
        busyAction = ""
    }

    private func apply(_ newRows: [GroupRow], cleanupNeeded: Bool) {
        rows = newRows
        staleCopies = findStaleInstalledCopies(in: newRows)
        looseCopies = findLooseCopies(in: newRows)
        organizationCleanupNeeded = cleanupNeeded
    }

    // MARK: - Folder creation prompt

    /// If /Applications/EclecticLight is missing, ask before creating it;
    /// otherwise run the action immediately.
    func performWithFolderSetup(_ action: @escaping () async -> Void) {
        if FileManager.default.fileExists(atPath: BundlePrefix.appsFolder) {
            Task { await action() }
        } else {
            pendingFolderAction = action
            folderPromptVisible = true
        }
    }

    func respondToFolderPrompt(_ create: Bool) {
        folderPromptVisible = false
        guard let action = pendingFolderAction else { return }
        pendingFolderAction = nil
        guard create else { return }
        Task {
            await service.ensureFolderCreated()
            guard FileManager.default.fileExists(atPath: BundlePrefix.appsFolder) else {
                statusMessage = "Folder creation failed or was cancelled."
                return
            }
            await action()
        }
    }

    // MARK: - Actions

    func install(_ entries: [CatalogEntry]) async {
        guard !busy, !entries.isEmpty else { return }
        performWithFolderSetup { await self.performInstall(entries) }
    }

    private func performInstall(_ entries: [CatalogEntry]) async {
        guard !busy else { return }
        busy = true
        var lines = ["=== Install ==="]
        for (index, entry) in entries.enumerated() {
            busyAction = "Installing \(entry.name) (\(index + 1)/\(entries.count))…"
            lines += await service.install(entry)
        }
        busyAction = "Completing installation…"
        let ok = await service.flushPrivileged()
        lines.append(ok ? "Install operations completed; check results below."
                       : "Install operations failed or were cancelled.")
        busy = false
        await refresh()
        let remaining = Set(available.map(\.key))
        for entry in entries where remaining.contains(entry.key) {
            lines.append("\(entry.name): not found after installation; see errors above.")
        }
        log = lines.joined(separator: "\n")
    }

    func updateAll() async {
        await runUpdates(on: outdatedGroups)
    }

    func update(_ group: GroupRow) async {
        await runUpdates(on: [group])
    }

    private func runUpdates(on groups: [GroupRow]) async {
        guard !busy, !groups.isEmpty else { return }
        if groups.contains(where: { $0.action == .download }) {
            performWithFolderSetup { await self.performUpdates(on: groups) }
        } else {
            await performUpdates(on: groups)
        }
    }

    private func performUpdates(on groups: [GroupRow]) async {
        busy = true
        busyAction = "Updating \(groups.count) app(s)…"
        var lines: [String] = ["=== Update ==="]
        for g in groups {
            lines += await service.updateGroup(g, installomatorPath: installomatorPath)
        }
        lines += ["--- completing privileged operations (one password prompt) ---"]
        busyAction = "Waiting for password / completing privileged operations…"
        let ok = await service.flushPrivileged()
        lines.append(ok ? "Privileged operations completed." : "Privileged operations FAILED (or cancelled).")
        log = lines.joined(separator: "\n")
        busy = false
        busyAction = ""
        statusMessage = "Update finished"
        await refresh()
    }

    func cleanupStale() async {
        guard !busy, !staleCopies.isEmpty else { return }
        busy = true
        busyAction = "Cleaning up stale copies…"
        var lines: [String] = ["=== Clean up ==="]
        lines += await service.cleanupStale(staleCopies)
        let ok = await service.flushPrivileged()
        lines.append(ok ? "Trash operations completed." : "Trash operations FAILED (or cancelled).")
        log = lines.joined(separator: "\n")
        busy = false
        busyAction = ""
        statusMessage = "Clean up finished"
        await refresh()
    }

    func organize() async {
        guard !busy, !looseCopies.isEmpty || organizationCleanupNeeded else { return }
        performWithFolderSetup { await self.performOrganize() }
    }

    private func performOrganize() async {
        guard !busy, !looseCopies.isEmpty || organizationCleanupNeeded else { return }
        busy = true
        busyAction = "Organizing…"
        var lines: [String] = ["=== Flatten /Applications/EclecticLight ==="]
        lines += await service.organize(looseCopies)
        let ok = await service.flushPrivileged()
        lines.append(ok ? "Move operations completed." : "Move operations FAILED (or cancelled).")
        log = lines.joined(separator: "\n")
        busy = false
        busyAction = ""
        statusMessage = "Organize finished"
        await refresh()
    }
}
