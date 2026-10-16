import AppKit
import UniformTypeIdentifiers
import Combine
import Bonsplit
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
    let name: String        // the workspace name (bar.toml `Badge`)
    let key: String
    let color: String
    var text: String? = nil // the button's label (bar.toml `Text`)
    var icon: String? = nil // icons/<icon>.svg|png beside bar.toml
    var id: String { name }

    /// The workspace title for sub-workspace 1, as Hyprland names it.
    var workspaceTitle: String { name + ".1" }
}

struct AgenticMachine { let name: String; let host: String; let color: String }

struct AgenticCommandButton { let text: String; let icon: String?; let exec: String; let key: String }

/// The personal profile (agentic-profile): ~/.config/agentic-laptop/bar.toml, the
/// same file the Linux dock reads. Projects, customers, machines and the
/// tool buttons all come from it; without it the placeholder table applies.
enum AgenticProfile {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/agentic-laptop")

    private struct Parsed {
        var projects: [AgenticProject] = []
        var customers: [AgenticProject] = []
        var machines: [AgenticMachine] = []
        var commands: [AgenticCommandButton] = []
    }

    private static let parsed: Parsed = {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("bar.toml"), encoding: .utf8)
        else { return Parsed() }
        return parse(text)
    }()

    private static func field(_ name: String, in line: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*\"([^\"]*)\""
        guard let r = line.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(line[r])
        guard let q = match.firstIndex(of: "\"") else { return nil }
        return String(match[match.index(after: q)...].dropLast())
    }

    private static func actionKey(in line: String) -> String? {
        guard let r = line.range(of: "Action\\s*=\\s*\\[[^\\]]*\\]", options: .regularExpression) else { return nil }
        let items = line[r].components(separatedBy: "\"").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        return items.last?.lowercased()
    }

    private static func parse(_ text: String) -> Parsed {
        var out = Parsed()
        var section = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }
            if let eq = line.range(of: "^[A-Za-z]+\\s*=\\s*\\[\\s*$", options: .regularExpression) {
                section = String(line[eq]).components(separatedBy: "=")[0].trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("]") { section = ""; continue }
            guard line.hasPrefix("{"), let label = field("Text", in: line) else { continue }
            let color = field("Color", in: line) ?? "surface"
            let icon = field("Icon", in: line)
            switch section {
            case "PrimaryLayerKeys", "MediaLayerKeys":
                if let badge = field("Badge", in: line), let key = actionKey(in: line) {
                    let project = AgenticProject(name: badge, key: key, color: color, text: label, icon: icon)
                    if section == "PrimaryLayerKeys" { out.projects.append(project) } else { out.customers.append(project) }
                } else if section == "PrimaryLayerKeys", let exec = field("Exec", in: line) {
                    out.commands.append(AgenticCommandButton(
                        text: label, icon: icon,
                        exec: exec.replacingOccurrences(of: "$HOME", with: NSHomeDirectory()),
                        key: actionKey(in: line) ?? ""
                    ))
                }
            case "machines":
                if let host = field("Host", in: line) {
                    out.machines.append(AgenticMachine(name: field("Workspace", in: line) ?? label, host: host, color: color))
                }
            default: break
            }
        }
        return out
    }

    static let projects: [AgenticProject] = parsed.projects.isEmpty ? [
        AgenticProject(name: "alpha", key: "o", color: "blue"),
        AgenticProject(name: "beta", key: "v", color: "mauve"),
        AgenticProject(name: "gamma", key: "d", color: "peach"),
        AgenticProject(name: "delta", key: "s", color: "green"),
        AgenticProject(name: "epsilon", key: "h", color: "red"),
        AgenticProject(name: "zeta", key: "l", color: "teal"),
        AgenticProject(name: "lambda", key: "e", color: "yellow"),
    ] : parsed.projects

    static let customers: [AgenticProject] = parsed.customers
    static let machines: [AgenticMachine] = parsed.machines
    static let commands: [AgenticCommandButton] = parsed.commands

    /// `icons/<name>.svg` or `.png` beside bar.toml.
    static func icon(named name: String?) -> NSImage? {
        guard let name else { return nil }
        for ext in ["svg", "png"] {
            let url = directory.appendingPathComponent("icons/\(name).\(ext)")
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }

    /// The first node in the fleet file, or $AGENTIC_REMOTE: where `r` attaches.
    static var remoteHost: String? {
        if let env = ProcessInfo.processInfo.environment["AGENTIC_REMOTE"], !env.isEmpty { return env }
        let fleet = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/claude-badged/fleet")
        return (try? String(contentsOf: fleet, encoding: .utf8))?
            .split(separator: "\n").first.map(String.init)
    }

    /// `r <session>`: attach to (or create) a tmux session on the fleet's first node.
    static func attachCommand(_ session: String) -> String {
        guard let host = remoteHost else { return "tmux new -A -s '\(session)'" }
        return "ssh -t \(host) \"tmux new -A -s '\(session)'\""
    }
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
        // Three terminals on the project's tmux sessions (`name`, `name1`, `name2`),
        // tiled as Hyprland's workspace-terminals.sh does: column, then a row.
        guard let ws = tabManager.addWorkspace(
            title: project.workspaceTitle,
            initialTerminalInput: AgenticProfile.attachCommand(project.name) + "\n"
        ) as Workspace?, let first = ws.focusedPanelId else { return }
        if let second = ws.newTerminalSplit(
            from: first, orientation: SplitDirection.right.orientation,
            initialInput: AgenticProfile.attachCommand(project.name + "1") + "\n"
        ) {
            _ = ws.newTerminalSplit(
                from: second.id, orientation: SplitDirection.down.orientation,
                initialInput: AgenticProfile.attachCommand(project.name + "2") + "\n"
            )
        }
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

    /// Numbered workspaces are keyed by their number, not by position: workspace "3"
    /// is "3" whatever else exists, and SUPER+3 creates it when absent.
    static func numbered(_ ws: Workspace) -> Int? {
        guard let title = ws.customTitle, let n = Int(title), n > 0 else { return nil }
        return n
    }

    static func focusNumbered(_ n: Int, in tabManager: TabManager) {
        if let ws = tabManager.tabs.first(where: { numbered($0) == n }) {
            tabManager.selectWorkspace(ws)
        } else {
            newEmptyWorkspace(title: String(n), in: tabManager)
        }
    }

    static func newEmptyWorkspace(title: String?, in tabManager: TabManager) {
        let ws = tabManager.addWorkspace(title: title)
        AgenticEmpty.shared.mark(ws.id)
    }

    /// A workspace nobody has named (it carries the shell's title) becomes the lowest
    /// free number, so every workspace is either numbered or named.
    static func adoptUnnamed(in tabManager: TabManager) {
        for ws in tabManager.tabs where ws.customTitle == nil {
            var n = 1
            while tabManager.tabs.contains(where: { numbered($0) == n }) { n += 1 }
            tabManager.setCustomTitle(tabId: ws.id, title: String(n))
        }
    }

    /// Hyprland's order: numbered ascending, then named in creation order.
    static func ordered(_ tabs: [Workspace]) -> [Workspace] {
        let nums = tabs.filter { numbered($0) != nil }.sorted { numbered($0)! < numbered($1)! }
        return nums + tabs.filter { numbered($0) == nil }
    }

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
                newEmptyWorkspace(title: "\(base).2", in: tabManager)
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
        guard let ws = tabManager.selectedWorkspace, let u = URL(string: url) else { return }
        let wasEmpty = AgenticEmpty.shared.isEmpty(ws.id)
        AgenticEmpty.shared.fill(ws.id)
        guard let panel = ws.focusedPanelId else { return }
        if wasEmpty {
            // The hidden first terminal gives way to the browser: the browser is the first window.
            _ = tabManager.newBrowserSplit(tabId: ws.id, fromPanelId: panel, orientation: .horizontal, url: u)
            return
        }
        var orientation: SplitOrientation = .horizontal
        if let pane = ws.paneId(forPanelId: panel),
           let g = ws.bonsplitController.layoutSnapshot().panes.first(where: { $0.paneId == pane.id.uuidString }) {
            orientation = g.frame.width >= g.frame.height ? .horizontal : .vertical
        }
        _ = tabManager.newBrowserSplit(tabId: ws.id, fromPanelId: panel, orientation: orientation, url: u)
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
                AgenticActions.focusNumbered(n, in: tabManager)
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

        if code == Code.space, flags == [cmd, .control] { AgenticWallpaper.showMenu(); return true }
        if code == Code.space, flags == [cmd, .control, .option] { AgenticWallpaper.cycle(random: false); return true }
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
            .onAppear { AgenticActions.adoptUnnamed(in: tabManager) }
            .onChange(of: tabManager.tabs.count) { _ in AgenticActions.adoptUnnamed(in: tabManager) }
    }

    private var bar: some View {
        HStack(spacing: 0) {
            // Clear the traffic lights.
            Spacer().frame(width: 78)
            HStack(spacing: 2) {
                ForEach(AgenticActions.ordered(tabManager.tabs), id: \.id) { workspace in
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
                    var n = 1
                    while tabManager.tabs.contains(where: { AgenticActions.numbered($0) == n }) { n += 1 }
                    AgenticActions.newEmptyWorkspace(title: String(n), in: tabManager)
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
        let label = AgenticActions.label(workspace)
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
    var icon: String? = nil
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
            AgenticDockButton(label: $0.text ?? $0.name, hint: "⇧⌘" + $0.key.uppercased(), color: $0.color, kind: .project($0), icon: $0.icon)
        }
        // tasks / accounts: shown once their tools exist on this machine.
        for c in AgenticProfile.commands where FileManager.default.isExecutableFile(atPath: c.exec) {
            primary.append(AgenticDockButton(label: c.text, hint: "⇧⌘" + c.key.uppercased(), color: "surface", kind: .command(c.exec), icon: c.icon))
        }
        out.append(AgenticDockLayer(name: "projects", buttons: primary))
        if !AgenticProfile.customers.isEmpty {
            out.append(AgenticDockLayer(name: "customers", buttons: AgenticProfile.customers.map {
                AgenticDockButton(label: $0.text ?? $0.name, hint: "⇧⌘" + $0.key.uppercased(), color: $0.color, kind: .project($0), icon: $0.icon)
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
            _ = tabManager.addWorkspace(title: title, initialTerminalInput: "ssh \(host)\n")
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
        case .machine(let host): workspace = tabManager.tabs.first { AgenticActions.label($0) == AgenticProfile.machines.first { $0.host == host }.map { $0.name + ".1" } }
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
                    if let image = AgenticProfile.icon(named: button.icon) {
                        Image(nsImage: image)
                            .resizable().scaledToFit()
                            .frame(height: 20)
                            .help(button.label)
                    } else {
                        Text(button.label)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(button.color == "surface" ? AgenticPalette.text : tint)
                    }
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
        if let id = tabManager.selectedTabId, AgenticEmpty.shared.isEmpty(id) {
            AgenticEmpty.shared.fill(id)   // the first window of an empty workspace
            return
        }
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

    /// SUPER+CTRL+SPACE: the background menu -- the library, or any image file.
    @MainActor static func showMenu() {
        let menu = NSMenu()
        let handler = MenuHandler.shared
        for path in list() {
            let item = NSMenuItem(title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                                  action: #selector(MenuHandler.pick(_:)), keyEquivalent: "")
            item.target = handler
            item.representedObject = path
            item.state = path == UserDefaults.standard.string(forKey: key) ? .on : .off
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let choose = NSMenuItem(title: "Choose Image…", action: #selector(MenuHandler.choose), keyEquivalent: "")
        choose.target = handler
        menu.addItem(choose)
        let reset = NSMenuItem(title: "Default Background", action: #selector(MenuHandler.reset), keyEquivalent: "")
        reset.target = handler
        menu.addItem(reset)
        let frame = NSApp.keyWindow?.frame ?? NSScreen.main?.frame ?? .zero
        menu.popUp(positioning: nil, at: NSPoint(x: frame.midX - 90, y: frame.midY + 60), in: nil)
    }

    final class MenuHandler: NSObject {
        static let shared = MenuHandler()
        @objc func pick(_ sender: NSMenuItem) {
            if let path = sender.representedObject as? String { UserDefaults.standard.set(path, forKey: AgenticWallpaper.key) }
        }
        @objc func choose() {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.directoryURL = AgenticWallpaper.library
            if panel.runModal() == .OK, let url = panel.url {
                UserDefaults.standard.set(url.path, forKey: AgenticWallpaper.key)
            }
        }
        @objc func reset() { UserDefaults.standard.removeObject(forKey: AgenticWallpaper.key) }
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
            for delay in [0.3, 1.0, 3.0] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.hideControls(); self?.dump() } }
        }
        func dump() {
            guard let w = window else { return }
            var out = "title=\(w.title) style=\(w.styleMask.rawValue) titleVis=\(w.titleVisibility.rawValue)\n"
            for a in w.titlebarAccessoryViewControllers {
                out += "accessory id=\(a.view.identifier?.rawValue ?? "nil") layout=\(a.layoutAttribute.rawValue) hidden=\(a.isHidden) frame=\(a.view.frame)\n"
            }
            func walk(_ v: NSView, _ d: Int) {
                out += String(repeating: " ", count: d) + "\(type(of: v)) \(v.frame) hidden=\(v.isHidden)\n"
                if d < 5 { v.subviews.forEach { walk($0, d + 1) } }
            }
            if let c = w.standardWindowButton(.closeButton)?.superview { walk(c.superview ?? c, 0) }
            try? out.write(toFile: "/tmp/agentic-titlebar.log", atomically: true, encoding: .utf8)
        }
        func hideControls() {
            let id = NSUserInterfaceItemIdentifier("cmux.titlebarControls")
            guard let window else { return }
            // Remove outright: hiding is undone whenever cmux re-applies its chrome.
            for (i, accessory) in window.titlebarAccessoryViewControllers.enumerated().reversed()
            where accessory.view.identifier == id {
                window.removeTitlebarAccessoryViewController(at: i)
            }
        }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) { view.hideControls() }
}

// MARK: - Empty workspaces

/// A new numbered workspace starts empty -- just the wallpaper, as in Hyprland --
/// and fills in when the first window is asked for (SUPER+Return, a browser, ...).
@MainActor
final class AgenticEmpty: ObservableObject {
    static let shared = AgenticEmpty()
    @Published private(set) var ids: Set<UUID> = []

    func mark(_ id: UUID) { ids.insert(id) }
    func fill(_ id: UUID?) { if let id, ids.contains(id) { ids.remove(id) } }
    func isEmpty(_ id: UUID) -> Bool { ids.contains(id) }
}
