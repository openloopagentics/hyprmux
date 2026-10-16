import AppKit
import Combine
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

// MARK: - Keymap

/// Hyprland-style chords. Super is Cmd. Returns true when the event is consumed.
@MainActor
enum AgenticKeymap {
    static func handle(event: NSEvent, tabManager: TabManager?) -> Bool {
        guard let tabManager else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        // SUPER + SHIFT + <letter>: the project workspaces.
        if flags == [.command, .shift],
           let key = event.charactersIgnoringModifiers?.lowercased(),
           let project = AgenticProfile.projects.first(where: { $0.key == key }) {
            AgenticActions.open(project, in: tabManager)
            return true
        }
        return false
    }
}

// MARK: - Top bar (waybar)

struct AgenticTopBar: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject private var notifications = TerminalNotificationStore.shared

    static let height: CGFloat = 34

    var body: some View {
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
            AgenticClock()
                .padding(.trailing, 10)
        }
        .frame(height: Self.height)
        .background(AgenticPalette.base.opacity(0.92))
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

// MARK: - Bottom dock (the Touch Bar's project row)

struct AgenticBottomBar: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject private var notifications = TerminalNotificationStore.shared

    static let height: CGFloat = 44

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AgenticProfile.projects) { project in
                projectButton(project)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(Color.black.opacity(0.92))
    }

    private func projectButton(_ project: AgenticProject) -> some View {
        let workspace = tabManager.tabs.first { ($0.customTitle ?? $0.title) == project.workspaceTitle }
        let unread = workspace.map { notifications.unreadCount(forTabId: $0.id) } ?? 0
        let tint = AgenticPalette.named(project.color)
        return Button {
            AgenticActions.open(project, in: tabManager)
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(project.name)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(tint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(workspace?.id == tabManager.selectedTabId ? AgenticPalette.surface1 : AgenticPalette.surface0.opacity(0.6))
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
