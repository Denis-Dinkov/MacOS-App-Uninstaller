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
    static let gutter: CGFloat = 32
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

/// Rounded gradient tile with an SF Symbol, used where there is no bundle icon.
struct SymbolTile: View {
    let symbol: String
    let size: CGFloat
    var filled = true
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(filled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.12)))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(filled ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.accent))
            )
            .frame(width: size, height: size)
    }
}

/// App bundle icon, or a gear tile for background items that have no bundle.
struct AppIcon: View {
    let app: AppInfo
    let size: CGFloat
    var body: some View {
        if app.agentLabel == nil {
            FileIcon(path: app.url.path, size: size)
        } else {
            SymbolTile(symbol: "gearshape.2.fill", size: size * 0.86, filled: false)
                .frame(width: size, height: size)
        }
    }
}

struct GlassCard: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

extension View {
    func glassCard(radius: CGFloat = 14) -> some View { modifier(GlassCard(radius: radius)) }
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        ZStack {
            Theme.background
            // Soft glows for depth.
            Circle().fill(Theme.pink.opacity(0.20)).frame(width: 420).blur(radius: 120)
                .offset(x: 320, y: -260)
            Circle().fill(Color.cyan.opacity(0.14)).frame(width: 380).blur(radius: 120)
                .offset(x: -120, y: 300)
            HStack(spacing: 0) {
                Sidebar()
                Group {
                    if model.section == .cleanup || model.selected != nil {
                        ItemsScreen()
                    } else {
                        AppListScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Sidebar (navigation only)

struct Sidebar: View {
    @EnvironmentObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AppSweeper")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            NavRow(
                title: "Applications", symbol: "square.grid.2x2.fill",
                badge: "\(model.apps.filter { $0.agentLabel == nil }.count)", section: .apps)
            NavRow(
                title: "Background Items", symbol: "gearshape.2.fill",
                badge: "\(model.apps.filter { $0.agentLabel != nil }.count)", section: .background)
            NavRow(title: "Free Up Space", symbol: "sparkles", badge: nil, section: .cleanup)
            Spacer()
        }
        .padding(.top, 52)
        .padding(.horizontal, 10)
        .frame(width: 216)
        .background(.black.opacity(0.24))
    }
}

struct NavRow: View {
    @EnvironmentObject var model: Model
    let title: String
    let symbol: String
    let badge: String?
    let section: Model.Section
    @State private var hovering = false

    var body: some View {
        let active = model.section == section
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .frame(width: 20)
            Text(title).fontWeight(active ? .semibold : .regular)
            Spacer(minLength: 0)
            if let badge {
                Text(badge).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(active ? 0.14 : (hovering ? 0.06 : 0))))
        .contentShape(Rectangle())
        .onTapGesture { model.go(section) }
        .onHover { hovering = $0 }
    }
}

// MARK: - Screen header

struct ScreenHeader<Icon: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 24, weight: .semibold)).lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 18)
    }
}

// MARK: - App list screen

struct AppListScreen: View {
    @EnvironmentObject var model: Model

    private var isBackground: Bool { model.section == .background }
    private var entries: [AppInfo] {
        model.filteredApps.filter { ($0.agentLabel != nil) == isBackground }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: isBackground ? "Background Items" : "Applications",
                subtitle: isBackground
                    ? "Scripts and tools that macOS starts automatically, without an app"
                    : "Choose an app to remove it together with all of its files"
            ) {
                EmptyView()
            } trailing: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $model.search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(width: 220)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.top, 48)

            if entries.isEmpty {
                Spacer()
                Text(model.search.isEmpty ? "Nothing here" : "No results for “\(model.search)”")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, app in
                            if index > 0 { Divider().opacity(0.4).padding(.leading, 60) }
                            AppListRow(app: app).onTapGesture { model.select(app) }
                        }
                    }
                    .glassCard()
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

struct AppListRow: View {
    let app: AppInfo
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(app: app, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                if !app.version.isEmpty {
                    Text(app.version).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.white.opacity(hovering ? 0.06 : 0))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Items screen (one app, one background item, or the cleanup scan)

struct ItemsScreen: View {
    @EnvironmentObject var model: Model
    @State private var confirming = false
    /// Groups whose expansion differs from the default for the current mode.
    @State private var flipped: Set<String> = []

    private var isCleanup: Bool { model.section == .cleanup }
    private var totalSize: Int64 { model.items.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            header
            if model.scanning {
                Spacer()
                ProgressView().controlSize(.large)
                Text(isCleanup ? "Measuring files…" : "Looking for leftovers…")
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                Spacer()
            } else if model.items.isEmpty {
                Spacer()
                Text("Nothing to remove").foregroundStyle(.secondary)
                Spacer()
            } else {
                groupList
            }
            bottomBar
        }
        .onChange(of: model.selectedID) { _ in flipped = [] }
    }

    // Back link and rescan live on one quiet row above the header.
    private var topBar: some View {
        HStack {
            if !isCleanup {
                Button {
                    model.back()
                } label: {
                    Label(
                        model.section == .background ? "Background Items" : "Applications",
                        systemImage: "chevron.left")
                }
            }
            Spacer()
            Button {
                model.scan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(model.scanning || model.working)
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder private var header: some View {
        let total = VStack(alignment: .trailing, spacing: 0) {
            Text(Scanner.format(totalSize))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
            Text("found in \(model.items.count) items").font(.caption).foregroundStyle(.secondary)
        }
        .opacity(model.scanning ? 0 : 1)

        if isCleanup {
            ScreenHeader(
                title: "Free Up Space", subtitle: "Files that apps recreate when they need them"
            ) {
                SymbolTile(symbol: "sparkles", size: 56)
            } trailing: {
                total
            }
        } else if let app = model.selected {
            ScreenHeader(title: app.name, subtitle: app.agentLabel == nil ? app.bundleID : shortPath(app.url)) {
                AppIcon(app: app, size: 56)
            } trailing: {
                total
            }
        }
    }

    private var groups: [(category: String, items: [Leftover])] {
        Dictionary(grouping: model.items, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { $0.1[0].order < $1.1[0].order }
    }

    private func isExpanded(_ category: String) -> Bool {
        // Uninstall lists are short, so they start open; cleanup groups start closed.
        (!isCleanup) != flipped.contains(category)
    }

    private var groupList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(groups, id: \.category) { group in
                    GroupCard(
                        category: group.category, items: group.items,
                        expanded: isExpanded(group.category)
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            flipped.formSymmetricDifference([group.category])
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 16)
        }
    }

    private var bottomBar: some View {
        let selected = model.selectedItems
        let disabled = selected.isEmpty || model.scanning || model.working
        let allOn = !model.items.isEmpty && selected.count == model.items.count
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Scanner.format(model.selectedSize)).font(.title3.weight(.semibold)).monospacedDigit()
                Text("\(selected.count) of \(model.items.count) items selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(allOn ? "Deselect All" : "Select All") { model.setAll(!allOn) }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .disabled(model.items.isEmpty)
            Spacer()
            Button {
                confirming = true
            } label: {
                HStack(spacing: 8) {
                    if model.working {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isCleanup ? "sparkles" : "trash.fill")
                    }
                    Text(isCleanup ? "Clean" : "Uninstall").fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 26).padding(.vertical, 11)
                .background(Theme.accent, in: Capsule())
                .shadow(color: Theme.pink.opacity(disabled ? 0 : 0.5), radius: 14)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled && !model.working ? 0.4 : 1)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 14)
        .background(.black.opacity(0.22))
        .confirmationDialog(
            isCleanup ? "Clean the selected items?" : "Uninstall \(model.selected?.name ?? "")?",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) { model.uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "\(selected.count) items (\(Scanner.format(model.selectedSize))) will be deleted "
                    + "permanently. This cannot be undone."
                    + (isCleanup ? "" : " It will be quit first if it is running."))
        }
    }
}

/// Shortens a path by replacing the home directory with "~".
func shortPath(_ url: URL) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let path = url.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

// MARK: - Group card

struct GroupCard: View {
    @EnvironmentObject var model: Model
    let category: String
    let items: [Leftover]
    let expanded: Bool
    let toggleExpanded: () -> Void

    private var symbol: String {
        let table: [(String, String)] = [
            ("Application", "app.fill"), ("Trash", "trash.fill"), ("Xcode", "hammer.fill"),
            ("Simulator", "hammer.fill"), ("Developer", "hammer.fill"), ("Backups", "iphone"),
            ("Program", "folder.fill"), ("Caches", "bolt.fill"),
            ("Preferences", "slider.horizontal.3"), ("Logs", "doc.text.fill"),
            ("Crash", "doc.text.fill"), ("Containers", "shippingbox.fill"),
            ("Launch", "gearshape.2.fill"), ("Helper", "gearshape.2.fill"),
            ("Cookies", "globe"), ("HTTPStorages", "globe"), ("WebKit", "globe"),
            ("Receipts", "shippingbox.fill"),
        ]
        return table.first { category.contains($0.0) }?.1 ?? "folder.fill"
    }

    var body: some View {
        let selectedCount = items.filter(\.selected).count
        let checkSymbol =
            selectedCount == 0
            ? "circle" : (selectedCount == items.count ? "checkmark.circle.fill" : "minus.circle.fill")
        let note = items.first?.note ?? ""

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: checkSymbol)
                    .font(.system(size: 17))
                    .foregroundStyle(selectedCount > 0 ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .contentShape(Rectangle())
                    .onTapGesture { model.setCategory(category, selectedCount != items.count) }
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category).fontWeight(.medium)
                    if !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Text("\(items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.white.opacity(0.08), in: Capsule())
                Text(Scanner.format(items.reduce(0) { $0 + $1.size }))
                    .monospacedDigit()
                    .frame(minWidth: 76, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 10)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleExpanded)

            if expanded {
                Divider().opacity(0.4)
                ForEach(items) { item in
                    ItemRow(item: item, isOn: model.toggle(item.id))
                }
                Spacer().frame(height: 4)
            }
        }
        .glassCard()
    }
}

struct ItemRow: View {
    let item: Leftover
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .frame(width: 20)
            FileIcon(path: item.url.path, size: 20)
            Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            Text(shortPath(item.url.deletingLastPathComponent()))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 8)
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
                .frame(minWidth: 76, alignment: .trailing)
            // Keeps sizes aligned with the group header's chevron column.
            Color.clear.frame(width: 10, height: 1)
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
