import Foundation

/// DIAGNOSTIC ONLY (perf round 5 measurement build, never landed): env switches that turn one
/// suspect off, so one Release build measures each suspect's share of the scroll hitches.
public nonisolated enum PerfDiag {
    public static let noFade = flag("CMUX_PERF_NO_FADE")
    public static let staticFade = flag("CMUX_PERF_STATIC_FADE")
    public static let noScrollHover = flag("CMUX_PERF_NO_SCROLL_HOVER")
    public static let noLoops = flag("CMUX_PERF_NO_LOOPS")
    public static let noPark = flag("CMUX_PERF_NO_PARK")
    public static let listUpdateLayer = flag("CMUX_PERF_LIST_UPDATE_LAYER")
    public static let hoverSnap = flag("CMUX_PERF_HOVER_SNAP")
    private static func flag(_ name: String) -> Bool { ProcessInfo.processInfo.environment[name] == "1" }
}
