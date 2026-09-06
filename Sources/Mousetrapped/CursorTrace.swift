import AppKit
import CoreGraphics

/// Continuous state sampler for diagnosing cursor traps. Off by default;
/// enable with:
///   defaults write dev.mousetrapped.Mousetrapped cursorTrace -bool true
///
/// Samples the cursor position from two independent sources, whether that
/// position lands on any real display, the frontmost app, and how long the
/// session and the raw HID layer have been silent. Run it on both Macs and
/// the timelines can be lined up by wall clock to see exactly what changes
/// at the moment the pointer disappears.
enum CursorTrace {

    static let enabledKey = "cursorTrace"
    private static var timer: Timer?
    private static var lastKeyState = ""

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static func startIfEnabled() {
        guard isEnabled, timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in sample() }
        // commonModes so sampling continues while menus track.
        RunLoop.main.add(t, forMode: .common)
        timer = t
        MTLog.log("Trace: started (200ms) — host=\(Host.current().localizedName ?? "?")")
    }

    private static func sample() {
        // Two independent reads: CoreGraphics (top-left origin) and AppKit
        // (bottom-left origin). If they disagree, the pointer state is
        // inconsistent — worth seeing.
        let cg = CGEvent(source: nil)?.location ?? .zero
        let ns = NSEvent.mouseLocation

        // Does the CG position land on a real display? In the "cursor is
        // nowhere" state we expect this to be false, or pinned to an edge.
        var onDisplay = "none"
        for display in CursorRescue.activeDisplays() where CGDisplayBounds(display).contains(cg) {
            onDisplay = "\(display)"
            break
        }

        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        let mouseIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                                eventType: .mouseMoved)
        let keyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                              eventType: .keyDown)
        let rawAge = RawInputMonitor.lastRawMouseActivity > 0
            ? ProcessInfo.processInfo.systemUptime - RawInputMonitor.lastRawMouseActivity
            : Double.infinity

        // Flag transitions loudly: landing on no display, or the frontmost
        // app changing, are the events we care about.
        let keyState = "\(onDisplay)|\(front)"
        let changed = keyState != lastKeyState
        lastKeyState = keyState

        let line = "cg=(\(Int(cg.x)),\(Int(cg.y))) ns=(\(Int(ns.x)),\(Int(ns.y)))"
            + " onDisplay=\(onDisplay) front=\(front)"
            + " mouseIdle=\(String(format: "%.1f", mouseIdle))s"
            + " keyIdle=\(String(format: "%.1f", keyIdle))s"
            + " rawAge=\(rawAge == .infinity ? "inf" : String(format: "%.1f", rawAge))s"
        MTLog.log("Trace: \(line)\(changed ? "  <<< CHANGED" : "")")
    }
}
