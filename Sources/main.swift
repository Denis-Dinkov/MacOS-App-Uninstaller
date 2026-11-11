import Foundation

// Hidden diagnostic mode: `AppSweeper --scan /Applications/Foo.app` prints what would be removed.
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--scan"), arguments.count > flag + 1 {
    let url = URL(fileURLWithPath: arguments[flag + 1])
    guard let app = Scanner.appInfo(at: url) else {
        print("Not an app bundle: \(url.path)")
        exit(1)
    }
    let others = Set(Scanner.loadApps().map(\.bundleID)).subtracting([app.bundleID])
    for item in Scanner.findLeftovers(for: app, otherBundleIDs: others) {
        print("[\(item.category)] \(item.url.path) — \(Scanner.format(item.size))")
    }
    exit(0)
}

AppSweeperApp.main()
