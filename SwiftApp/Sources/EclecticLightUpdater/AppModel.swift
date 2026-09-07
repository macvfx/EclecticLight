import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private var installedToolVersions = UserDefaults.standard.dictionary(forKey: "installedToolVersions") as? [String: String] ?? [:]

    func isToolInstalled(_ entry: CatalogEntry) -> Bool {
        guard let version = entry.latest?.version else { return false }
        return installedToolVersions[entry.key] == version
    }

    var pendingTools: [CatalogEntry] { commandLineTools.filter { !isToolInstalled($0) } }

    @Published var commandLineTools: [CatalogEntry] = []
    @Published var available: [CatalogEntry] = []
    @Published var rows: [GroupRow] = []
    @Published var staleCopies: [AppInfo] = []
    @Published var looseCopies: [AppInfo] = []
    @Published var organizationCleanupNeeded = false
    @Published var scanProgress: [String] = []
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
        scanProgress = []
        busyAction = "Refreshing…"
        statusMessage = "Scanning…"
        do {
            let dirs = [
                "/Applications",
                NSHomeDirectory() + "/Applications",
                NSHomeDirectory() + "/Downloads",
            ]
            var apps: [AppInfo] = []
            for (index, directory) in dirs.enumerated() {
                let displayPath = (directory as NSString).abbreviatingWithTildeInPath
                busyAction = "Scanning \(displayPath) (\(index + 1)/\(dirs.count))…"
                statusMessage = busyAction
                let found = await Task.detached(priority: .userInitiated) {
                    scanApps(dirs: [directory])
                }.value
                apps += found
                let completed = "\(displayPath): checked, \(found.count) app copies found"
                scanProgress.append(completed)
                ActivityLog.shared.append(completed)
            }
            busyAction = "Checking organization in /Applications/EclecticLight…"
            statusMessage = busyAction
            let cleanupNeeded = await Task.detached { hasOrganizationCleanupWork() }.value
            statusMessage = "Fetching catalog…"
            busyAction = "Checking downloads at eclecticlight.co and Installomator labels…"
            let newCatalog = try await CatalogFetcher.fetchCatalog()
            busyAction = "Checking catalog compatibility with " + OSCompatibility.systemDescription
            await Task.yield()
            catalog = newCatalog
            commandLineTools = newCatalog.entries.values.filter { CatalogFetcher.commandLineKeys.contains($0.key) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            available = availableApps(apps: apps, catalog: newCatalog)
            installomatorPath = findInstallomator()
            apply(analyzeGroups(apps: apps, catalog: newCatalog), cleanupNeeded: cleanupNeeded)
            statusMessage = "Checked /Applications, ~/Applications and ~/Downloads: \(apps.count) app copies, \(outdatedGroups.count) out of date"
        } catch {
            statusMessage = "Refresh failed: \(error.localizedDescription)"
            log = "Error: \(error)"
        }
        busy = false
        busyAction = ""
        scanProgress = []
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

    func installTool(_ entry: CatalogEntry) async {
        await installTools([entry])
    }

    func installAllTools() async {
        await installTools(pendingTools)
    }

    private func installTools(_ entries: [CatalogEntry]) async {
        guard !busy else { return }
        let pending = entries.filter { !isToolInstalled($0) }
        guard !pending.isEmpty else { return }
        busy = true
        var succeeded = 0
        for (index, entry) in pending.enumerated() {
            busyAction = "Installing \(entry.name) (\(index + 1)/\(pending.count))"
            let success = await service.installTool(entry)
            if success, let version = entry.latest?.version {
                installedToolVersions[entry.key] = version
                UserDefaults.standard.set(installedToolVersions, forKey: "installedToolVersions")
                succeeded += 1
            }
        }
        busy = false
        busyAction = ""
        statusMessage = "Package installation: \(succeeded) succeeded, \(pending.count - succeeded) failed or cancelled."
    }

    func install(_ entries: [CatalogEntry]) async {
        guard !busy, !entries.isEmpty else { return }
        let apps = entries.filter { !CatalogFetcher.commandLineKeys.contains($0.key) }
        guard !apps.isEmpty else { return }
        performWithFolderSetup { await self.performInstall(apps) }
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
        if !ok { lines.append("Privileged operations failed or were cancelled; verifying installed apps.") }
        // Verify locally, independently of catalog refresh or stale UI state.
        let installed = await Task.detached {
            scanApps(dirs: [BundlePrefix.appsFolder])
        }.value
        let succeeded = entries.filter { installationSucceeded($0, installed: installed) }
        for entry in entries {
            let success = installationSucceeded(entry, installed: installed)
            lines.append("\(entry.name): " + (success ? "installed version verified." : "FAILED: expected app/version not found at the installation destination; see errors above."))
        }
        let summary = "Installation results: \(succeeded.count) succeeded, \(entries.count - succeeded.count) failed."
        lines.append(summary)
        busy = false
        await refresh()
        statusMessage = summary
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
