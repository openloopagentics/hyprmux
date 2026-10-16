import AppKit
import Combine
import CmuxPanes
import SwiftUI

// Agentic shell: the Hyprland + waybar + Touch Bar dock experience from
// openloopagentics/agentic-laptop, hosted inside cmux. A top bar (waybar), a
// bottom dock (the Touch Bar's project row), and Super-style chords that
// drive cmux workspaces the way Hyprland drives its own.

// MARK: - Palette (Catppuccin Mocha, as in waybar/style.css and bar.toml)

enum AgenticPalette {
    static let base = Color(red: 0x1e / 255, green: 0x1e / 255, blue: 0x2e / 255)
    static let surface0 = Color(red: 0x31 / 255, green: 0x32 / 255, blue: 0x44 / 255)
    static let surface1 = Color(red: 0x45 / 255, green: 0x47 / 255, blue: 0x5a / 255)
    static let overlay0 = Color(red: 0x6c / 255, green: 0x70 / 255, blue: 0x86 / 255)
    static let subtext = Color(red: 0xa6 / 255, green: 0xad / 255, blue: 0xc8 / 255)
    static let text = Color(red: 0xcd / 255, green: 0xd6 / 255, blue: 0xf4 / 255)
    static let blue = Color(red: 0x89 / 255, green: 0xb4 / 255, blue: 0xfa / 255)
    static let mauve = Color(red: 0xcb / 255, green: 0xa6 / 255, blue: 0xf7 / 255)
    static let peach = Color(red: 0xfa / 255, green: 0xb3 / 255, blue: 0x87 / 255)
    static let green = Color(red: 0xa6 / 255, green: 0xe3 / 255, blue: 0xa1 / 255)
    static let red = Color(red: 0xf3 / 255, green: 0x8b / 255, blue: 0xa8 / 255)
    static let teal = Color(red: 0x94 / 255, green: 0xe2 / 255, blue: 0xd5 / 255)
    static let yellow = Color(red: 0xf9 / 255, green: 0xe2 / 255, blue: 0xaf / 255)

    static func named(_ name: String) -> Color {
        switch name {
        case "blue": return blue
        case "mauve": return mauve
        case "peach": return peach
        case "green": return green
        case "red": return red
        case "teal": return teal
        case "yellow": return yellow
        default: return surface1
        }
    }
}

// MARK: - Projects

/// One named project: a workspace, its chord (Cmd+Shift+<key>) and a colour.
struct AgenticProject: Identifiable, Equatable {
    let name: String
    let key: String
    let color: String
    var id: String { name }

    /// The workspace title for sub-workspace 1, as Hyprland names it.
    var workspaceTitle: String { name + ".1" }
}

enum AgenticProfile {
    /// Same placeholder table as agentic-laptop's examples/profile/bar.toml.
    /// ~/.config/agentic/projects.json ([{"name","key","color"}]) replaces it.
    static let projects: [AgenticProject] = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/agentic/projects.json")
        if let data = try? Data(contentsOf: url),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            let loaded = raw.compactMap { row -> AgenticProject? in
                guard let name = row["name"], let key = row["key"] else { return nil }
                return AgenticProject(name: name, key: key.lowercased(), color: row["color"] ?? "blue")
            }
            if !loaded.isEmpty { return loaded }
        }
        return [
            AgenticProject(name: "alpha", key: "o", color: "blue"),
            AgenticProject(name: "beta", key: "v", color: "mauve"),
            AgenticProject(name: "gamma", key: "d", color: "peach"),
            AgenticProject(name: "delta", key: "s", color: "green"),
            AgenticProject(name: "epsilon", key: "h", color: "red"),
            AgenticProject(name: "zeta", key: "l", color: "teal"),
            AgenticProject(name: "lambda", key: "e", color: "yellow"),
        ]
    }()
}

struct AgenticMachine { let name: String; let host: String; let color: String }

extension AgenticProfile {
    /// Second dock level, a workspace each like projects (bar.toml MediaLayerKeys).
    static let customers: [AgenticProject] = [
        AgenticProject(name: "eta", key: "c", color: "yellow"),
        AgenticProject(name: "theta", key: "k", color: "blue"),
        AgenticProject(name: "iota", key: "q", color: "mauve"),
        AgenticProject(name: "kappa", key: "j", color: "green"),
    ]

    /// Third level, from ~/.config/agentic/machines.json: [{"name","host","color"}].
    static let machines: [AgenticMachine] = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/agentic/machines.json")
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return [] }
        return raw.compactMap { row in
            guard let name = row["name"], let host = row["host"] else { return nil }
            return AgenticMachine(name: name, host: host, color: row["color"] ?? "blue")
        }
    }()
}

// MARK: - Actions

@MainActor
enum AgenticActions {
    /// Jump to a project's workspace, creating it (with a terminal attached to
    /// its tmux session via `r`) the first time -- Hyprland's
    /// `focus workspace name:<project>.1`.
    static func open(_ project: AgenticProject, in tabManager: TabManager) {
        if let existing = tabManager.tabs.first(where: { ($0.customTitle ?? $0.title) == project.workspaceTitle }) {
            tabManager.selectWorkspace(existing)
            return
        }
        _ = tabManager.addWorkspace(
            title: project.workspaceTitle,
            initialTerminalCommand: "r \(project.name)-1"
        )
    }

    static func select(_ workspace: Workspace, in tabManager: TabManager) {
        tabManager.selectWorkspace(workspace)
    }
}

// MARK: - Workspace history (SUPER+ALT+Left/Right)

@MainActor
final class AgenticHistory {
    static let shared = AgenticHistory()
    private var visited: [UUID] = []
    private var cursor = -1
    private var navigating = false

    func record(_ id: UUID?) {
        guard let id, !navigating, visited[safe: cursor] != id else { return }
        visited = Array(visited.prefix(cursor + 1)) + [id]
        cursor = visited.count - 1
    }

    func step(_ delta: Int, in tabManager: TabManager) {
        visited.removeAll { id in !tabManager.tabs.contains { $0.id == id } }
        cursor = min(cursor, visited.count - 1)
        let target = cursor + delta
        guard visited.indices.contains(target),
              let ws = tabManager.tabs.first(where: { $0.id == visited[target] }) else { return }
        navigating = true
        cursor = target
        tabManager.selectWorkspace(ws)
        navigating = false
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Actions (continued)

extension AgenticActions {
    static func label(_ ws: Workspace) -> String { ws.customTitle ?? ws.title }

    static let topBarHiddenKey = "agentic.topBarHidden"

    /// Cycle through the selected project's sub-workspaces (`alpha.1`, `alpha.2`, ...),
    /// creating the next one when there is only one.
    static func cycleSub(_ step: Int, in tabManager: TabManager) {
        guard let current = tabManager.selectedWorkspace else { return }
        let name = label(current)
        let base = name.split(separator: ".").first.map(String.init) ?? name
        let siblings = tabManager.tabs.filter {
            let l = label($0)
            return l == base || l.hasPrefix(base + ".")
        }
        guard let idx = siblings.firstIndex(where: { $0.id == current.id }) else { return }
        if siblings.count == 1 {
            if step > 0 {
                _ = tabManager.addWorkspace(title: "\(base).2", initialTerminalCommand: "r \(base)-2")
            }
            return
        }
        let next = (idx + step + siblings.count) % siblings.count
        tabManager.selectWorkspace(siblings[next])
    }

    /// SUPER+N: the next workspace with an agent waiting on you.
    static func jumpToAttention(in tabManager: TabManager) {
        let store = TerminalNotificationStore.shared
        let tabs = tabManager.tabs
        let start = tabs.firstIndex { $0.id == tabManager.selectedTabId } ?? -1
        for offset in 1...max(tabs.count, 1) {
            let ws = tabs[(start + offset) % tabs.count]
            if ws.id != tabManager.selectedTabId, store.unreadCount(forTabId: ws.id) > 0 {
                tabManager.selectWorkspace(ws)
                return
            }
        }
    }

    static func openWebapp(_ url: String, in tabManager: TabManager) {
        guard let ws = tabManager.selectedWorkspace, let panel = ws.focusedPanelId,
              let u = URL(string: url) else { return }
        _ = tabManager.newBrowserSplit(tabId: ws.id, fromPanelId: panel, orientation: .horizontal, url: u)
    }

    static func closeFocused(in tabManager: TabManager) {
        guard let ws = tabManager.selectedWorkspace else { return }
        if let panel = ws.focusedPanelId {
            tabManager.closePanelWithConfirmation(tabId: ws.id, surfaceId: panel)
        } else {
            _ = tabManager.closeWorkspaceWithConfirmation(ws)
        }
    }

    static func resize(_ dir: ResizeDirection, in tabManager: TabManager) {
        guard let ws = tabManager.selectedWorkspace, let panel = ws.focusedPanelId else { return }
        _ = tabManager.resizeSplit(tabId: ws.id, surfaceId: panel, direction: dir, amount: 100)
    }
}

// MARK: - Keymap

/// Hyprland's binds, with Super as Cmd. Returns true when the event is consumed.
/// Where a bind collides with a cmux or macOS shortcut, Hyprland wins.
@MainActor
enum AgenticKeymap {
    private enum Code {
        static let tab: UInt16 = 48, ret: UInt16 = 36, space: UInt16 = 49
        static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
        static let minus: UInt16 = 27, equal: UInt16 = 24, lbracket: UInt16 = 33, rbracket: UInt16 = 30
    }

    static func handle(event: NSEvent, tabManager: TabManager?) -> Bool {
        if let h = FileHandle(forWritingAtPath: "/tmp/agentic-keys.log") ?? {
            FileManager.default.createFile(atPath: "/tmp/agentic-keys.log", contents: nil)
            return FileHandle(forWritingAtPath: "/tmp/agentic-keys.log")
        }() {
            h.seekToEndOfFile()
            h.write("key \(event.keyCode) flags=\(event.modifierFlags.rawValue) tm=\(tabManager != nil)\n".data(using: .utf8)!)
            h.closeFile()
        }
        guard let tabManager else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        let code = event.keyCode
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let cmd: NSEvent.ModifierFlags = .command

        // SUPER + SHIFT + <letter>: project workspaces.
        if flags == [cmd, .shift],
           let project = (AgenticProfile.projects + AgenticProfile.customers).first(where: { $0.key == key }) {
            AgenticActions.open(project, in: tabManager)
            return true
        }

        // Ctrl+Tab / Ctrl+Shift+Tab: next / previous workspace (SUPER+Tab is the OS app switcher).
        if code == Code.tab, flags == .control { tabManager.selectNextTab(); return true }
        if code == Code.tab, flags == [.control, .shift] { tabManager.selectPreviousTab(); return true }
        if code == Code.tab, flags == [cmd, .control] {
            AgenticHistory.shared.step(-1, in: tabManager); return true
        }

        if flags == cmd {
            if let n = Int(key), (1...9).contains(n) {
                if let ws = tabManager.tabs[safe: n - 1] { tabManager.selectWorkspace(ws) }
                return true
            }
            switch code {
            case Code.left: tabManager.movePaneFocus(direction: .left); return true
            case Code.right: tabManager.movePaneFocus(direction: .right); return true
            case Code.up: tabManager.movePaneFocus(direction: .up); return true
            case Code.down: tabManager.movePaneFocus(direction: .down); return true
            case Code.ret: AgenticActions.dwindleSplit(in: tabManager); return true
            case Code.minus: AgenticActions.resize(.left, in: tabManager); return true
            case Code.equal: AgenticActions.resize(.right, in: tabManager); return true
            case Code.lbracket: AgenticActions.cycleSub(-1, in: tabManager); return true
            case Code.rbracket: AgenticActions.cycleSub(1, in: tabManager); return true
            default: break
            }
            switch key {
            case "w": AgenticActions.closeFocused(in: tabManager); return true
            case "f": _ = tabManager.toggleFocusedSplitZoom(); return true
            case "n": AgenticActions.jumpToAttention(in: tabManager); return true
            default: break
            }
        }

        // Dock: SUPER+CTRL + arrows / Return (next level, previous level, select, go).
        if flags == [cmd, .control] {
            let dock = AgenticDock.shared
            switch code {
            case Code.down: dock.moveLayer(1); return true
            case Code.up: dock.moveLayer(-1); return true
            case Code.left: dock.moveSelection(-1); return true
            case Code.right: dock.moveSelection(1); return true
            case Code.ret: dock.activateSelected(in: tabManager); return true
            default: break
            }
        }
        // SUPER+ALT+<digit>: machines.
        if flags == [cmd, .option], let n = Int(key), (1...9).contains(n),
           let m = AgenticProfile.machines[safe: n - 1] {
            AgenticActions.openMachine(m.name, host: m.host, in: tabManager)
            return true
        }

        if code == Code.space, flags == [cmd, .control] { AgenticWallpaper.cycle(random: false); return true }
        if code == Code.space, flags == [cmd, .control, .shift] { AgenticWallpaper.cycle(random: true); return true }

        if flags == [cmd, .option] {
            switch code {
            case Code.left: AgenticHistory.shared.step(-1, in: tabManager); return true
            case Code.right: AgenticHistory.shared.step(1, in: tabManager); return true
            default: break
            }
        }

        if flags == [cmd, .shift] {
            switch code {
            case Code.minus: AgenticActions.resize(.up, in: tabManager); return true
            case Code.equal: AgenticActions.resize(.down, in: tabManager); return true
            case Code.ret: AgenticActions.openWebapp("https://www.google.com", in: tabManager); return true
            case Code.space:
                let d = UserDefaults.standard
                d.set(!d.bool(forKey: AgenticActions.topBarHiddenKey), forKey: AgenticActions.topBarHiddenKey)
                return true
            default: break
            }
            let apps: [String: String] = [
                "b": "https://www.google.com", "a": "https://chatgpt.com", "y": "https://youtube.com/",
                "x": "https://x.com/", "p": "https://photos.google.com/",
            ]
            if let url = apps[key] { AgenticActions.openWebapp(url, in: tabManager); return true }
        }
        return false
    }
}

// MARK: - Top bar (waybar)

struct AgenticTopBar: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject private var notifications = TerminalNotificationStore.shared

    static let height: CGFloat = 34
    @AppStorage(AgenticActions.topBarHiddenKey) private var hidden = false

    var body: some View {
        Group { if !hidden { bar } }
            .onReceive(tabManager.selectedTabIdPublisher) { AgenticHistory.shared.record($0) }
    }

    private var bar: some View {
        HStack(spacing: 0) {
            // Clear the traffic lights.
            Spacer().frame(width: 78)
            HStack(spacing: 2) {
                ForEach(tabManager.tabs, id: \.id) { workspace in
                    workspaceButton(workspace)
                }
            }
            Spacer(minLength: 12)
            Text(tabManager.selectedWorkspace?.title ?? "")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(AgenticPalette.subtext)
                .lineLimit(1)
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                iconButton(unread > 0 ? "bell.badge.fill" : "bell", tint: unread > 0 ? AgenticPalette.red : AgenticPalette.subtext) {
                    AppDelegate.shared?.toggleNotificationsPopover()
                }
                iconButton("plus", tint: AgenticPalette.subtext) {
                    _ = tabManager.addWorkspace()
                }
                AgenticClock()
            }
            .padding(.trailing, 10)
        }
        .frame(height: Self.height)
        .background(AgenticTitlebarHost().background(AgenticPalette.base.opacity(0.92)))
    }

    private var unread: Int { notifications.unreadNotificationCount }

    private func iconButton(_ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(AgenticPalette.surface0))
        }
        .buttonStyle(.plain)
    }

    private func workspaceButton(_ workspace: Workspace) -> some View {
        let active = workspace.id == tabManager.selectedTabId
        let urgent = !active && notifications.unreadCount(forTabId: workspace.id) > 0
        let label = workspace.customTitle ?? workspace.title
        return Button {
            AgenticActions.select(workspace, in: tabManager)
        } label: {
            Text(label)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .foregroundColor(active || urgent ? AgenticPalette.base : AgenticPalette.overlay0)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active ? AgenticPalette.blue : (urgent ? AgenticPalette.red : Color.clear))
                )
        }
        .buttonStyle(.plain)
    }
}

struct AgenticClock: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(AgenticPalette.text)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(AgenticPalette.surface0))
            .onReceive(timer) { now = $0 }
    }
}

// MARK: - Bottom dock (the Touch Bar's layers)

struct AgenticDockButton: Identifiable {
    enum Kind {
        case project(AgenticProject)
        case machine(host: String)
        case fkey(UInt16)
        case command(String)
    }
    let label: String
    let hint: String
    let color: String
    let kind: Kind
    var id: String { label + hint }
}

struct AgenticDockLayer: Identifiable {
    let name: String
    let buttons: [AgenticDockButton]
    var id: String { name }
}

@MainActor
final class AgenticDock: ObservableObject {
    static let shared = AgenticDock()
    @Published var layerIndex = 0
    @Published var selected = 0

    /// Outermost first, as FnCycle in bar.toml: projects, customers, machines, F-keys.
    let layers: [AgenticDockLayer] = {
        var out: [AgenticDockLayer] = []
        var primary = AgenticProfile.projects.map {
            AgenticDockButton(label: $0.name, hint: "⇧⌘" + $0.key.uppercased(), color: $0.color, kind: .project($0))
        }
        let fm = FileManager.default
        for (label, file) in [("tasks", "agentic-tasks"), ("accounts", "agentic-accounts")] {
            let path = fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/\(file)").path
            if fm.isExecutableFile(atPath: path) {
                primary.append(AgenticDockButton(label: label, hint: "", color: "surface", kind: .command(path)))
            }
        }
        out.append(AgenticDockLayer(name: "projects", buttons: primary))
        if !AgenticProfile.customers.isEmpty {
            out.append(AgenticDockLayer(name: "customers", buttons: AgenticProfile.customers.map {
                AgenticDockButton(label: $0.name, hint: "⇧⌘" + $0.key.uppercased(), color: $0.color, kind: .project($0))
            }))
        }
        if !AgenticProfile.machines.isEmpty {
            out.append(AgenticDockLayer(name: "machines", buttons: AgenticProfile.machines.enumerated().map { i, m in
                AgenticDockButton(label: m.name, hint: "⌥⌘\(i + 1)", color: m.color, kind: .machine(host: m.host))
            }))
        }
        let codes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        out.append(AgenticDockLayer(name: "F1-F12", buttons: codes.enumerated().map { i, c in
            AgenticDockButton(label: "F\(i + 1)", hint: "", color: "surface", kind: .fkey(c))
        }))
        return out
    }()

    var current: AgenticDockLayer { layers[layerIndex] }

    func moveLayer(_ delta: Int) {
        layerIndex = min(max(layerIndex + delta, 0), layers.count - 1)
        selected = 0
    }

    func moveSelection(_ delta: Int) {
        let n = current.buttons.count
        guard n > 0 else { return }
        selected = (selected + delta + n) % n
    }

    func activate(_ button: AgenticDockButton, in tabManager: TabManager) {
        switch button.kind {
        case .project(let p): AgenticActions.open(p, in: tabManager)
        case .machine(let host): AgenticActions.openMachine(button.label, host: host, in: tabManager)
        case .command(let path): Process.launchedProcess(launchPath: path, arguments: [])
        case .fkey(let code):
            for down in [true, false] {
                CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)?
                    .postToPid(ProcessInfo.processInfo.processIdentifier)
            }
        }
    }

    func activateSelected(in tabManager: TabManager) {
        guard current.buttons.indices.contains(selected) else { return }
        activate(current.buttons[selected], in: tabManager)
    }
}

extension AgenticActions {
    /// A machine gets its own workspace, `<name>.1`, with a shell on the host.
    static func openMachine(_ name: String, host: String, in tabManager: TabManager) {
        let title = name + ".1"
        if let ws = tabManager.tabs.first(where: { label($0) == title }) {
            tabManager.selectWorkspace(ws)
        } else {
            _ = tabManager.addWorkspace(title: title, initialTerminalCommand: "ssh \(host)")
        }
    }
}

struct AgenticBottomBar: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject private var dock = AgenticDock.shared
    @ObservedObject private var notifications = TerminalNotificationStore.shared

    static let height: CGFloat = 48

    var body: some View {
        HStack(spacing: 6) {
            arrow("chevron.left", enabled: dock.layerIndex > 0) { dock.moveLayer(-1) }
            ForEach(Array(dock.current.buttons.enumerated()), id: \.element.id) { index, button in
                dockButton(button, selected: index == dock.selected)
            }
            arrow("chevron.right", enabled: dock.layerIndex < dock.layers.count - 1) { dock.moveLayer(1) }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(Color.black.opacity(0.92))
        .overlay(alignment: .topTrailing) {
            Text(dock.current.name)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(AgenticPalette.overlay0)
                .padding(.trailing, 10).padding(.top, 2)
        }
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(enabled ? AgenticPalette.subtext : AgenticPalette.surface1)
                .frame(width: 26, height: 34)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func dockButton(_ button: AgenticDockButton, selected: Bool) -> some View {
        var workspace: Workspace?
        switch button.kind {
        case .project(let p): workspace = tabManager.tabs.first { AgenticActions.label($0) == p.workspaceTitle }
        case .machine: workspace = tabManager.tabs.first { AgenticActions.label($0) == button.label + ".1" }
        default: break
        }
        let unread = workspace.map { notifications.unreadCount(forTabId: $0.id) } ?? 0
        let isCurrent = workspace?.id == tabManager.selectedTabId
        let tint = AgenticPalette.named(button.color)
        return Button {
            dock.activate(button, in: tabManager)
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    Text(button.label)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(button.color == "surface" ? AgenticPalette.text : tint)
                    if !button.hint.isEmpty {
                        Text(button.hint)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(AgenticPalette.overlay0)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isCurrent ? AgenticPalette.surface1 : AgenticPalette.surface0.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? tint : Color.clear, lineWidth: 1.5)
                )
                if unread > 0 {
                    Text("\(unread)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AgenticPalette.base)
                        .padding(.horizontal, 5)
                        .background(Capsule().fill(AgenticPalette.red))
                        .offset(x: -4, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dwindle splits (Hyprland's default layout)

extension AgenticActions {
    /// A new terminal splits the focused one: side by side when it is wider than
    /// tall, stacked otherwise -- so the first split is a column and the next
    /// one, inside the new pane, is a row.
    static func dwindleSplit(in tabManager: TabManager) {
        var direction: SplitDirection = .right
        if let ws = tabManager.selectedWorkspace,
           let panel = ws.focusedPanelId,
           let pane = ws.paneId(forPanelId: panel),
           let geometry = ws.bonsplitController.layoutSnapshot().panes
               .first(where: { $0.paneId == pane.id.uuidString }) {
            direction = geometry.frame.width >= geometry.frame.height ? .right : .down
        }
        _ = tabManager.createSplitOutcome(direction: direction)
    }
}

// MARK: - Wallpaper (hyprpaper)

/// Library: ~/Pictures/wallpapers, as agentic-laptop's wallpaper.sh. With none,
/// a Catppuccin gradient stands in.
enum AgenticWallpaper {
    static let key = "agentic.wallpaperPath"
    static let library = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/wallpapers")

    static func list() -> [String] {
        let exts: Set<String> = ["png", "jpg", "jpeg", "webp", "heic"]
        let files = (try? FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)) ?? []
        return files.filter { exts.contains($0.pathExtension.lowercased()) }.map(\.path).sorted()
    }

    static func cycle(random: Bool) {
        let all = list()
        guard !all.isEmpty else { return }
        let current = UserDefaults.standard.string(forKey: key)
        let next: String
        if random {
            next = all.filter { $0 != current }.randomElement() ?? all[0]
        } else {
            let i = current.flatMap { all.firstIndex(of: $0) } ?? -1
            next = all[(i + 1) % all.count]
        }
        UserDefaults.standard.set(next, forKey: key)
    }
}

struct AgenticWallpaperView: View {
    @AppStorage(AgenticWallpaper.key) private var path = ""

    var body: some View {
        Group {
            if let image = resolvedImage {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(
                    colors: [AgenticPalette.base, Color(red: 0.19, green: 0.17, blue: 0.30), AgenticPalette.surface0],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var resolvedImage: NSImage? {
        if !path.isEmpty, let img = NSImage(contentsOfFile: path) { return img }
        if let first = AgenticWallpaper.list().first { return NSImage(contentsOfFile: first) }
        return nil
    }
}

// MARK: - Titlebar host

/// Backs the top bar: drags the window, and keeps cmux's own titlebar icons
/// (they now live in the bar's right corner) from drawing over the pills.
struct AgenticTitlebarHost: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hideControls()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.hideControls() }
        }
        func hideControls() {
            let id = NSUserInterfaceItemIdentifier("cmux.titlebarControls")
            for accessory in window?.titlebarAccessoryViewControllers ?? [] where accessory.view.identifier == id {
                accessory.isHidden = true
                accessory.view.alphaValue = 0
            }
        }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) { view.hideControls() }
}
