import AppKit
import Foundation

struct AppInfo: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleName: String
    let bundleID: String
    let version: String
    var id: URL { url }

    static func == (a: AppInfo, b: AppInfo) -> Bool { a.url == b.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

struct Leftover: Identifiable {
    let url: URL
    let category: String
    let order: Int
    let size: Int64
    let isApp: Bool
    var selected: Bool
    var id: URL { url }
}

enum Scanner {
    private static let fm = FileManager.default

    // MARK: - Installed apps

    static func appInfo(at url: URL) -> AppInfo? {
        guard url.pathExtension == "app", let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = url.deletingPathExtension().lastPathComponent
        return AppInfo(
            url: url.standardizedFileURL,
            name: name,
            bundleName: (info["CFBundleName"] as? String) ?? name,
            bundleID: bundle.bundleIdentifier ?? "",
            version: (info["CFBundleShortVersionString"] as? String) ?? ""
        )
    }

    static func loadApps() -> [AppInfo] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        var result: [URL: AppInfo] = [:]
        let own = Bundle.main.bundleURL.standardizedFileURL

        func walk(_ dir: URL, depth: Int) {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            else { return }
            for entry in entries {
                if entry.pathExtension == "app" {
                    if isRestricted(entry) { continue }
                    if let info = appInfo(at: entry), info.url != own { result[info.url] = info }
                } else if depth < 2,
                    (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                {
                    walk(entry, depth: depth + 1)
                }
            }
        }
        roots.forEach { walk($0, depth: 0) }
        return result.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// SIP-protected items (system apps such as Safari) carry the "restricted" file flag.
    static func isRestricted(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_flags & UInt32(SF_RESTRICTED) != 0
    }

    // MARK: - Leftover search

    private struct Location {
        let label: String
        let path: String
        // Loose mode also accepts "<AppName>_..." / "<AppName>-..." (crash reports).
        var loose = false
    }

    private static var locations: [Location] {
        let home = fm.homeDirectoryForCurrentUser.path + "/Library/"
        let user = [
            "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Logs",
            "Saved Application State", "Containers", "Group Containers", "Application Scripts",
            "HTTPStorages", "WebKit", "Cookies", "LaunchAgents",
        ].map { Location(label: $0, path: home + $0) }
        let userLoose = [
            "Application Support/CrashReporter", "Logs/DiagnosticReports", "Logs/CrashReporter",
            "Logs/HangReporter",
        ].map { Location(label: "Crash Reports", path: home + $0, loose: true) }
            + [Location(label: "Crash Reports", path: "/Library/Logs/DiagnosticReports", loose: true)]
        // Per-user cache and temp folders under /private/var/folders.
        let darwinRoot = URL(fileURLWithPath: NSTemporaryDirectory()).deletingLastPathComponent().path
        let darwin = ["C", "T"].map {
            Location(label: "Temporary Files", path: darwinRoot + "/" + $0)
        }
        let system = [
            "Application Support", "Caches", "Preferences", "Logs", "LaunchAgents",
            "LaunchDaemons", "PrivilegedHelperTools",
        ].map { Location(label: "/Library/" + $0, path: "/Library/" + $0) }
        let receipts = [Location(label: "Installer Receipts", path: "/private/var/db/receipts")]
        return user + userLoose + darwin + system + receipts
    }

    private static let strippedExtensions = [
        ".plist", ".savedstate", ".binarycookies", ".log", ".bom", ".sfl2", ".sfl3",
    ]

    /// True when `needle` occurs in `haystack` and is not glued to other letters/digits,
    /// so "com.foo.app" matches "group.com.foo.app.plist" but not "com.foo.application".
    static func boundaryContains(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        var start = haystack.startIndex
        while let range = haystack.range(of: needle, range: start..<haystack.endIndex) {
            let beforeOK =
                range.lowerBound == haystack.startIndex
                || !isWordChar(haystack[haystack.index(before: range.lowerBound)])
            let afterOK = range.upperBound == haystack.endIndex || !isWordChar(haystack[range.upperBound])
            if beforeOK && afterOK { return true }
            start = haystack.index(after: range.lowerBound)
        }
        return false
    }

    private static func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    /// Bundle identifiers of helpers, extensions and login items shipped inside the app.
    /// Only identifiers from the same vendor prefix are kept, so shared third-party
    /// components (updaters etc.) never widen the search.
    static func embeddedBundleIDs(of app: AppInfo) -> [String] {
        let parts = app.bundleID.lowercased().split(separator: ".")
        guard parts.count >= 2 else { return [] }
        let vendor = parts.prefix(2).joined(separator: ".") + "."
        let folders = ["PlugIns", "XPCServices", "Library/LoginItems", "Extensions", "Helpers", "MacOS"]
        var ids: Set<String> = []
        for folder in folders {
            let dir = app.url.appendingPathComponent("Contents/" + folder)
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            else { continue }
            for entry in entries where ["appex", "xpc", "app"].contains(entry.pathExtension) {
                if let id = Bundle(url: entry)?.bundleIdentifier?.lowercased(), id.hasPrefix(vendor) {
                    ids.insert(id)
                }
            }
        }
        return Array(ids)
    }

    /// True when a launchd plist starts a program that lives inside the app bundle.
    static func launchPlistPointsInto(_ app: AppInfo, plist: URL) -> Bool {
        guard plist.pathExtension == "plist", let data = try? Data(contentsOf: plist),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        else { return false }
        var programs = dict["ProgramArguments"] as? [String] ?? []
        if let program = dict["Program"] as? String { programs.append(program) }
        let prefix = app.url.path + "/"
        return programs.contains { $0.hasPrefix(prefix) }
    }

    static func matches(
        fileName: String, app: AppInfo, ids: [String], otherBundleIDs: [String], loose: Bool
    ) -> Bool {
        let lower = fileName.lowercased()

        // Bundle identifier match (only for reasonably specific identifiers).
        for bid in ids where bid.count >= 6 && bid.contains(".") && boundaryContains(lower, bid) {
            // Skip files that belong to another installed app with a longer identifier,
            // e.g. "com.foo.app.beta" while removing "com.foo.app".
            let ownedByOther = otherBundleIDs.contains {
                $0.count > bid.count && $0.contains(bid) && boundaryContains(lower, $0)
            }
            if !ownedByOther { return true }
        }

        // Exact name match (after stripping well-known extensions).
        var stem = lower
        if let ext = strippedExtensions.first(where: { stem.hasSuffix($0) }) {
            stem = String(stem.dropLast(ext.count))
        }
        let names = Set([app.name, app.bundleName].map { $0.lowercased() }).filter { $0.count >= 3 }
        for name in names {
            if stem == name || stem == name.replacingOccurrences(of: " ", with: "") { return true }
            if loose, lower.hasPrefix(name + "_") || lower.hasPrefix(name + "-") { return true }
        }
        return false
    }

    static func findLeftovers(for app: AppInfo, otherBundleIDs: Set<String>) -> [Leftover] {
        let others = otherBundleIDs.map { $0.lowercased() }.filter { !$0.isEmpty }
        var result = [
            Leftover(
                url: app.url, category: "Application", order: 0, size: size(of: app.url),
                isApp: true, selected: true)
        ]
        var seen: Set<String> = [app.url.path]

        let ids = Array(Set([app.bundleID.lowercased()] + embeddedBundleIDs(of: app)))
            .filter { !others.contains($0) }

        for (index, location) in locations.enumerated() {
            guard let names = try? fm.contentsOfDirectory(atPath: location.path) else { continue }
            let isLaunchd = location.path.hasSuffix("/LaunchAgents") || location.path.hasSuffix("/LaunchDaemons")
            for name in names {
                let url = URL(fileURLWithPath: location.path).appendingPathComponent(name)
                guard
                    matches(fileName: name, app: app, ids: ids, otherBundleIDs: others, loose: location.loose)
                        || (isLaunchd && launchPlistPointsInto(app, plist: url))
                else { continue }
                guard seen.insert(url.path).inserted else { continue }
                result.append(
                    Leftover(
                        url: url, category: location.label, order: index + 1, size: size(of: url),
                        isApp: false, selected: true))
            }
        }
        return result
    }

    // MARK: - Permissions

    /// Full Disk Access check: the user's TCC database is only readable when it is granted.
    /// Full Disk Access also covers the "App Management" permission needed to remove apps.
    static func hasFullDiskAccess() -> Bool {
        let home = fm.homeDirectoryForCurrentUser.path
        let probes = [
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Safari/Bookmarks.plist",
        ]
        for path in probes where fm.fileExists(atPath: path) {
            if let handle = FileHandle(forReadingAtPath: path) {
                try? handle.close()
                return true
            }
            return false
        }
        // No probe file exists; fall back to listing a protected folder.
        return (try? fm.contentsOfDirectory(atPath: home + "/Library/Safari")) != nil
    }

    // MARK: - Sizes

    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let enumerator = fm.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [],
            errorHandler: { _, _ in true })
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let v = try? file.resourceValues(forKeys: keys), v.isDirectory != true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Removal

    /// Permanently removes root-owned items after asking for an administrator password.
    static func removeWithAdmin(_ urls: [URL]) -> Bool {
        // Never touch anything shallower than /<root>/<item>.
        let safe = urls.filter { $0.pathComponents.count >= 3 && !$0.path.hasPrefix("/System") }
        guard !safe.isEmpty else { return false }
        let quoted = safe.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let shell = "/bin/rm -rf -- " + quoted.joined(separator: " ")
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?
            .executeAndReturnError(&error)
        return error == nil
    }
}
