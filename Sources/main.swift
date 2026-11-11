import Foundation

// Hidden diagnostic mode: `AppSweeper --scan /Applications/Foo.app` prints what would be removed.
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--scan"), arguments.count > flag + 1 {
    let url = URL(fileURLWithPath: arguments[flag + 1])
    let agents = Scanner.loadAgents(apps: Scanner.loadApps())
    guard let app = Scanner.appInfo(at: url) ?? agents.first(where: { $0.url == url.standardizedFileURL })
    else {
        print("Not an app bundle or background item: \(url.path)")
        exit(1)
    }
    let others = Set(Scanner.loadApps().map(\.bundleID)).subtracting([app.bundleID])
    for item in Scanner.findLeftovers(for: app, otherBundleIDs: others) {
        print("[\(item.category)] \(item.url.path) — \(Scanner.format(item.size))")
    }
    exit(0)
}

// `AppSweeper --junk` prints what the Free Up Space scan would offer.
if arguments.contains("--junk") {
    var totals: [String: (count: Int, size: Int64, selected: Bool)] = [:]
    var order: [String] = []
    for item in Scanner.findJunk() {
        if totals[item.category] == nil { order.append(item.category) }
        let current = totals[item.category] ?? (0, 0, item.selected)
        totals[item.category] = (current.count + 1, current.size + item.size, item.selected)
    }
    for name in order {
        let entry = totals[name]!
        print("\(name): \(entry.count) items, \(Scanner.format(entry.size))")
    }
    exit(0)
}

AppSweeperApp.main()
