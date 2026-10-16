import SwiftUI

struct WorkspacePresentationModeContentTopPaddingModifier: ViewModifier {
    let isFullScreen: Bool
    let runtimeCache: WorkspacePresentationModeRuntimeCache

    @AppStorage(WorkspacePresentationModeSettings.modeKey)
    private var workspacePresentationMode = WorkspacePresentationModeSettings.defaultMode.rawValue

    private var isMinimalMode: Bool {
        WorkspacePresentationModeSettings.mode(for: workspacePresentationMode) == .minimal
    }

    func body(content: Content) -> some View {
        // HyprMux: the top bar owns the titlebar strip, so the terminals start right
        // under it -- no extra titlebar-height padding above them.
        content
    }
}
