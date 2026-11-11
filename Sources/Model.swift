import AppKit
import SwiftUI

@MainActor
final class Model: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var search = ""
    @Published var selectedID: URL? { didSet { if selectedID != oldValue { scan() } } }
    @Published var items: [Leftover] = []
    @Published var scanning = false
    @Published var working = false
    @Published var showResult = false
    @Published var resultMessage = ""

    enum Mode { case uninstall, cleanup }
    /// Which sidebar entry is active.
    enum Section { case apps, background, cleanup }
    @Published var section: Section = .apps
    @Published var mode: Mode = .uninstall

    @Published var hasFullDiskAccess = Scanner.hasFullDiskAccess()

    private var scanToken = 0

    func recheckPermissions() {
        let granted = Scanner.hasFullDiskAccess()
        guard granted != hasFullDiskAccess else { return }
        hasFullDiskAccess = granted
        if granted { scan() }
    }

    func openFullDiskAccessSettings() {
        let link = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
    private var failed: [Leftover] = []
    private var freed: Int64 = 0
    private var removedCount = 0

    init() {
        reloadApps()
        // Optional: `AppSweeper --select /Applications/Foo.app` opens with that app selected.
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--select"), args.count > flag + 1 {
            addApp(URL(fileURLWithPath: args[flag + 1]))
        }
        // `AppSweeper --cleanup` opens directly in Free Up Space mode.
        if args.contains("--cleanup") { showCleanup() }
    }

    var selected: AppInfo? { apps.first { $0.id == selectedID } }

    var filteredApps: [AppInfo] {
        guard !search.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.bundleID.localizedCaseInsensitiveContains(search)
        }
    }

    var selectedItems: [Leftover] { items.filter(\.selected) }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var failedCount: Int { failed.count }

    func reloadApps() {
        // Keep manually dropped apps that live outside the standard folders.
        let extra = apps.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        var merged = Dictionary(uniqueKeysWithValues: extra.map { ($0.url, $0) })
        for app in Scanner.loadApps() { merged[app.url] = app }
        let installed = merged.values.filter { $0.agentLabel == nil }
        for agent in Scanner.loadAgents(apps: installed) { merged[agent.url] = agent }
        apps = merged.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func addApp(_ url: URL) {
        guard !url.path.hasPrefix("/System"), let info = Scanner.appInfo(at: url),
            info.url != Bundle.main.bundleURL.standardizedFileURL
        else { return }
        if !apps.contains(info) {
            apps.append(info)
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        search = ""
        select(info)
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.pathExtension == "app" else { return }
            Task { @MainActor in self.addApp(url) }
        }
        return true
    }

    func go(_ target: Section) {
        search = ""
        section = target
        if target == .cleanup {
            showCleanup()
            return
        }
        if mode != .uninstall {
            mode = .uninstall
            scanToken += 1
            items = []
            scanning = false
        }
        selectedID = nil
    }

    func back() { selectedID = nil }

    func showCleanup() {
        section = .cleanup
        guard mode != .cleanup else { return }
        mode = .cleanup
        // Clearing the selection triggers scan(), which now runs the junk scan.
        if selectedID != nil { selectedID = nil } else { scan() }
    }

    func select(_ app: AppInfo) {
        if mode != .uninstall {
            mode = .uninstall
            scanToken += 1
            items = []
            scanning = false
        }
        section = app.agentLabel == nil ? .apps : .background
        selectedID = app.id
    }

    func setCategory(_ category: String, _ value: Bool) {
        for index in items.indices where items[index].category == category {
            items[index].selected = value
        }
    }

    func scan() {
        scanToken += 1
        let token = scanToken
        items = []
        if mode == .cleanup {
            scanning = true
            Task.detached(priority: .userInitiated) {
                let found = Scanner.findJunk()
                await MainActor.run {
                    guard token == self.scanToken else { return }
                    self.items = found
                    self.scanning = false
                }
            }
            return
        }
        guard let app = selected else {
            scanning = false
            return
        }
        scanning = true
        let others = Set(apps.map(\.bundleID)).subtracting([app.bundleID])
        Task.detached(priority: .userInitiated) {
            let found = Scanner.findLeftovers(for: app, otherBundleIDs: others)
            await MainActor.run {
                guard token == self.scanToken else { return }
                self.items = found
                self.scanning = false
            }
        }
    }

    func setAll(_ value: Bool) {
        for index in items.indices { items[index].selected = value }
    }

    func toggle(_ id: URL) -> Binding<Bool> {
        Binding(
            get: { self.items.first { $0.id == id }?.selected ?? false },
            set: { value in
                if let index = self.items.firstIndex(where: { $0.id == id }) {
                    self.items[index].selected = value
                }
            })
    }

    // MARK: - Uninstall

    func uninstall() {
        guard !working, mode == .cleanup || selected != nil else { return }
        recheckPermissions()
        guard hasFullDiskAccess else { return }
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        working = true
        // Cleanup mode has no owning app to stop first.
        let app = mode == .uninstall ? selected : nil
        let quitFirst = targets.contains(where: \.isApp) && !(app?.bundleID.isEmpty ?? true)
        let bundleID = app?.bundleID ?? ""
        let agentLabel = app?.agentLabel

        Task.detached(priority: .userInitiated) {
            if quitFirst {
                if let agentLabel { Self.stopAgent(label: agentLabel) } else { Self.quit(bundleID: bundleID) }
            }
            var freed: Int64 = 0
            var removed = 0
            var failed: [Leftover] = []
            for target in targets {
                do {
                    try Self.removeDirectly(target.url)
                    freed += target.size
                    removed += 1
                } catch {
                    // Already gone counts as success; everything else needs elevation.
                    if FileManager.default.fileExists(atPath: target.url.path) { failed.append(target) }
                }
            }
            let result = (freed, removed, failed)
            await MainActor.run {
                self.freed = result.0
                self.removedCount = result.1
                self.failed = result.2
                // Anything still left is root-owned: remove it with one password prompt.
                if result.2.isEmpty { self.finish() } else { self.removeFailedWithAdmin() }
            }
        }
    }

    /// Deletes an item immediately. Locked items get their immutable flag cleared first.
    nonisolated private static func removeDirectly(_ url: URL) throws {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: url)
        } catch {
            try? fm.setAttributes([.immutable: false], ofItemAtPath: url.path)
            try fm.removeItem(at: url)
        }
    }

    /// Unloads a launch agent so launchd stops (and no longer restarts) its process.
    nonisolated private static func stopAgent(label: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    nonisolated private static func quit(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        for _ in 0..<15 where running.contains(where: { !$0.isTerminated }) {
            Thread.sleep(forTimeInterval: 0.2)
        }
        running.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        Thread.sleep(forTimeInterval: 0.3)
    }

    func removeFailedWithAdmin() {
        let pending = failed
        if Scanner.removeWithAdmin(pending.map(\.url)) {
            let gone = pending.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
            freed += gone.reduce(0) { $0 + $1.size }
            removedCount += gone.count
            failed = pending.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        }
        finish()
    }

    func finish() {
        working = false
        var message = "Items removed: \(removedCount)\nSpace freed: \(Scanner.format(freed))"
        if !failed.isEmpty {
            message += "\n\nCould not be removed (\(failed.count)):\n"
                + failed.prefix(8).map(\.url.path).joined(separator: "\n")
        }
        resultMessage = message
        failed = []
        showResult = true

        if mode == .cleanup {
            scan()
            return
        }
        let current = selectedID
        reloadApps()
        if let current, apps.contains(where: { $0.id == current }) {
            scan()
        } else {
            selectedID = nil
        }
    }
}
