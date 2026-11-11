import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Theme

enum Theme {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.09, green: 0.07, blue: 0.24),
            Color(red: 0.21, green: 0.09, blue: 0.34),
            Color(red: 0.05, green: 0.21, blue: 0.36),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let pink = Color(red: 1.0, green: 0.36, blue: 0.56)
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.38)
    static let accent = LinearGradient(
        colors: [pink, orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let card = Color.white.opacity(0.07)
    static let stroke = Color.white.opacity(0.10)
}

struct FileIcon: View {
    let path: String
    let size: CGFloat
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .frame(width: size, height: size)
    }
}

struct GlassCard: ViewModifier {
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

extension View {
    func glassCard(radius: CGFloat = 16) -> some View { modifier(GlassCard(radius: radius)) }
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        ZStack {
            Theme.background
            // Soft glows for depth.
            Circle().fill(Theme.pink.opacity(0.22)).frame(width: 420).blur(radius: 120)
                .offset(x: 320, y: -260)
            Circle().fill(Color.cyan.opacity(0.16)).frame(width: 380).blur(radius: 120)
                .offset(x: -120, y: 300)
            HStack(spacing: 0) {
                Sidebar()
                DetailView()
            }
        }
        .ignoresSafeArea()
        .overlay { if !model.hasFullDiskAccess { PermissionOverlay() } }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.recheckPermissions()
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { model.handleDrop($0) }
        .alert("Done", isPresented: $model.showResult) {
            Button("OK") {}
        } message: {
            Text(model.resultMessage)
        }
    }
}

// MARK: - Permission error

struct PermissionOverlay: View {
    @EnvironmentObject var model: Model

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)
                Text("Full Disk Access is not granted")
                    .font(.system(size: 22, weight: .semibold))
                Text(
                    "AppSweeper cannot see or remove app containers, caches and other leftovers "
                        + "without it. Open System Settings → Privacy & Security → Full Disk Access, "
                        + "enable AppSweeper, then reopen the app.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                HStack(spacing: 10) {
                    Button("Open System Settings") { model.openFullDiskAccessSettings() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.pink)
                    Button("Check Again") { model.recheckPermissions() }
                    Button("Relaunch") { model.relaunch() }
                }
                .controlSize(.large)
                .padding(.top, 6)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 40)
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Applications").font(.title3.weight(.semibold))
                Text("\(model.apps.count)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.white.opacity(0.12), in: Capsule())
                Spacer()
                Button {
                    model.reloadApps()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh list")
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $model.search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.filteredApps) { app in
                        AppRow(app: app, selected: model.selectedID == app.id)
                            .onTapGesture { model.selectedID = app.id }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.top, 46)
        .padding(.horizontal, 12)
        .frame(width: 270)
        .background(.black.opacity(0.24))
    }
}

struct AppRow: View {
    let app: AppInfo
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            FileIcon(path: app.url.path, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                if !app.version.isEmpty {
                    Text(app.version).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(selected ? 0.16 : (hovering ? 0.06 : 0))))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Detail

struct DetailView: View {
    @EnvironmentObject var model: Model
    @State private var confirming = false

    var body: some View {
        Group {
            if let app = model.selected {
                VStack(spacing: 0) {
                    header(app)
                    if model.scanning {
                        Spacer()
                        ProgressView().controlSize(.large)
                        Text("Looking for leftovers…").foregroundStyle(.secondary).padding(.top, 10)
                        Spacer()
                    } else {
                        itemList
                    }
                    footer(app)
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.accent).frame(width: 130, height: 130)
                    .shadow(color: Theme.pink.opacity(0.55), radius: 40)
                Image(systemName: "sparkles")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text("Select an app").font(.system(size: 26, weight: .semibold))
            Text("or drop an .app file into the window to remove it together with all of its leftovers")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
    }

    private func header(_ app: AppInfo) -> some View {
        HStack(spacing: 18) {
            FileIcon(path: app.url.path, size: 76)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.system(size: 26, weight: .semibold)).lineLimit(1)
                Text(app.bundleID.isEmpty ? "No bundle identifier" : app.bundleID)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
            Spacer()
            if !model.scanning {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Scanner.format(model.items.reduce(0) { $0 + $1.size }))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                    Text("\(model.items.count) items found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 44)
        .padding(.bottom, 18)
    }

    private var groups: [(category: String, items: [Leftover])] {
        Dictionary(grouping: model.items, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { $0.1[0].order < $1.1[0].order }
    }

    private func symbol(for category: String) -> String {
        let table: [(String, String)] = [
            ("Application", "app.fill"), ("Caches", "bolt.fill"),
            ("Preferences", "slider.horizontal.3"), ("Logs", "doc.text.fill"),
            ("Crash", "doc.text.fill"), ("Containers", "shippingbox.fill"),
            ("Launch", "gearshape.2.fill"), ("Helper", "gearshape.2.fill"),
            ("Cookies", "globe"), ("HTTPStorages", "globe"), ("WebKit", "globe"),
            ("Receipts", "shippingbox.fill"),
        ]
        return table.first { category.contains($0.0) }?.1 ?? "folder.fill"
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(groups, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: symbol(for: group.category))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 20)
                            Text(group.category).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(Scanner.format(group.items.reduce(0) { $0 + $1.size }))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
                        ForEach(group.items) { item in
                            ItemRow(item: item, isOn: model.toggle(item.id))
                        }
                        Spacer().frame(height: 6)
                    }
                    .glassCard()
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
    }

    private func footer(_ app: AppInfo) -> some View {
        let disabled = model.selectedItems.isEmpty || model.scanning || model.working
        return ZStack {
            HStack {
                Button("Select all") { model.setAll(true) }
                Button("Deselect all") { model.setAll(false) }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Scanner.format(model.selectedSize))
                        .font(.headline)
                        .monospacedDigit()
                    Text("\(model.selectedItems.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.75))

            Button {
                confirming = true
            } label: {
                ZStack {
                    Circle().fill(Theme.accent)
                        .shadow(color: Theme.pink.opacity(0.6), radius: 22)
                    Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5).padding(6)
                    if model.working {
                        ProgressView().controlSize(.regular)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "trash.fill").font(.title2)
                            Text("Uninstall").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                    }
                }
                .frame(width: 104, height: 104)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled && !model.working ? 0.4 : 1)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .confirmationDialog(
            "Uninstall \(app.name)?", isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) { model.uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "\(model.selectedItems.count) items (\(Scanner.format(model.selectedSize))) "
                    + "will be deleted permanently. This cannot be undone. The app will be quit if it is running.")
        }
    }
}

struct ItemRow: View {
    let item: Leftover
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17))
                .foregroundStyle(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            FileIcon(path: item.url.path, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(item.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if hovering {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Show in Finder")
            }
            Text(Scanner.format(item.size))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.white.opacity(hovering ? 0.05 : 0))
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .onHover { hovering = $0 }
    }
}

// MARK: - App

struct AppSweeperApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        WindowGroup("AppSweeper") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
