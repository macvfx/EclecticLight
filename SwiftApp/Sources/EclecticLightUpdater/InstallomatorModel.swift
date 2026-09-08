import Foundation

func installomatorLabels(from output: String) -> [String] {
    Array(Set(output.split(separator: "\n").map(String.init).filter {
        $0.range(of: #"^[a-z0-9][a-z0-9_-]*$"#, options: .regularExpression) != nil
            && !["version", "longversion", "valuesfromarguments"].contains($0)
            && !$0.hasPrefix("broken")
    })).sorted()
}

@MainActor
final class InstallomatorModel: ObservableObject {
    static let shared = InstallomatorModel()
    private let adminRunner: (String) async -> Bool
    init(adminRunner: @escaping (String) async -> Bool = { await Shell.runAdmin(script: $0) }) {
        self.adminRunner = adminRunner
    }

    @Published var labels: [String] = []
    @Published var selected: Set<String> = []
    @Published var busy = false
    @Published var status = "Refresh to inspect the installed copy of Installomator."
    @Published var path: String?
    @Published var output = ""
    @Published var stopRequested = false

    private func record(_ text: String) {
        output += text + "\n"
        ActivityLog.shared.append(text)
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        await inspect()
    }

    private func inspect() async {
        labels = []
        path = findInstallomator()
        guard let path else { status = "Installomator is not installed. Choose Install Installomator to set it up."; return }
        status = "Reading labels from " + path
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let code = await runLoggedProcess("/bin/zsh", arguments: ["--no-rcs", path], output: file)
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        record("Installomator label discovery exit=\(code)\n" + text)
        guard code == 0 else { status = "Installed Installomator could not list labels. See output."; return }
        labels = installomatorLabels(from: text)
        selected.formIntersection(labels)
        status = "\(labels.count) labels available from the installed copy."
    }

    func setup() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        status = "Looking up the latest official Installomator release…"
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("elu-installomator-" + UUID().uuidString)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let (data, response) = try await URLSession.shared.data(from: URL(string: "https://api.github.com/repos/Installomator/Installomator/releases/latest")!)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let release = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assets = release["assets"] as? [[String: Any]] else { throw ExportError.invalidDownload }
            let packages = assets.filter { ($0["name"] as? String)?.hasSuffix(".pkg") == true }
            guard packages.count == 1, let source = packages[0]["browser_download_url"] as? String,
                  source.hasPrefix("https://github.com/Installomator/Installomator/releases/download/"),
                  let url = URL(string: source) else { throw ExportError.invalidDownload }
            status = "Downloading official Installomator package…"
            record("Installomator setup source: " + source)
            let (packageData, packageResponse) = try await URLSession.shared.data(from: url)
            guard (packageResponse as? HTTPURLResponse)?.statusCode == 200 else { throw ExportError.invalidDownload }
            let package = root.appendingPathComponent("Installomator.pkg")
            try packageData.write(to: package)
            let check = root.appendingPathComponent("signature.log")
            let signature = await runLoggedProcess("/usr/sbin/pkgutil", arguments: ["--check-signature", package.path], output: check)
            record((try? String(contentsOf: check, encoding: .utf8)) ?? "No package signature output")
            guard signature == 0 else { throw ExportError.validationFailed }
            let log = root.appendingPathComponent("installer.log")
            try Data().write(to: log)
            status = "Waiting for administrator permission to install Installomator…"
            let ok = await Shell.runAdmin(script: "/usr/sbin/installer -pkg " + Shell.quote(package.path) + " -target / > " + Shell.quote(log.path) + " 2>&1")
            record((try? String(contentsOf: log, encoding: .utf8)) ?? "No installer output")
            guard ok else { status = "Installomator setup failed or was cancelled."; record(status); return }
            await inspect()
            status = labels.isEmpty ? "Package ran, but label discovery failed. See output." : "Installomator setup verified: \(labels.count) labels available."
            record(status)
            NotificationCenter.default.post(name: .init("InstallomatorChanged"), object: nil)
        } catch { status = "Setup failed: \(error.localizedDescription)"; record(status) }
    }

    private func runWithLiveOutput(_ script: String, log: URL) async -> Bool {
        var previous = ""
        let monitor = Task { @MainActor in
            while !Task.isCancelled {
                let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                if text.hasPrefix(previous), text.count > previous.count {
                    record(String(text.dropFirst(previous.count)))
                    previous = text
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        let ok = await adminRunner(script)
        monitor.cancel()
        await monitor.value
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        if text.hasPrefix(previous), text.count > previous.count { record(String(text.dropFirst(previous.count))) }
        return ok
    }

    func installSelected() async {
        guard !busy, let path else { return }
        let chosen = selected.intersection(Set(labels)).sorted()
        guard !chosen.isEmpty else { return }
        busy = true
        stopRequested = false
        defer { busy = false }
        var succeeded = 0
        for (index, label) in chosen.enumerated() {
            if stopRequested { break }
            status = "Running \(label) (\(index + 1)/\(chosen.count)) — administrator permission may be requested"
            record(status)
            let log = FileManager.default.temporaryDirectory.appendingPathComponent("elu-label-" + UUID().uuidString + ".log")
            do { try Data().write(to: log) } catch { record(error.localizedDescription); break }
            let script = "/bin/zsh --no-rcs " + Shell.quote(path) + " " + Shell.quote(label)
                + " DEBUG=0 NOTIFY=silent BLOCKING_PROCESS_ACTION=prompt_user > " + Shell.quote(log.path) + " 2>&1"
            let ok = await runWithLiveOutput(script, log: log)

            record(label + (ok ? ": Installomator reported success." : ": failed or cancelled; stopping queue."))
            if !ok { break }
            succeeded += 1
        }
        status = "Installomator: \(succeeded)/\(chosen.count) reported success. See output for installation or already-current results."
        record(status)
    }
}
