import AppKit
import CoreGraphics

/// Performs the actual rescue: re-associates the mouse with the on-screen
/// cursor, warps it to the center of the target display, and nudges the
/// event stream so apps that hid the cursor are forced to re-show it.
enum CursorRescue {

    static let targetDefaultsKey = "targetDisplayUUID"

    /// The display the cursor should be rescued to. `nil` means the primary
    /// display (the one with the menu bar at (0,0) in global coordinates).
    static var targetDisplayUUID: String? {
        get { UserDefaults.standard.string(forKey: targetDefaultsKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: targetDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: targetDefaultsKey)
            }
        }
    }

    static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    static func uuidString(for display: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    static func name(for display: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               number.uint32Value == display {
                return screen.localizedName
            }
        }
        return "Display \(display)"
    }

    static func resolveTargetDisplay() -> CGDirectDisplayID {
        if let wanted = targetDisplayUUID {
            for display in activeDisplays() where uuidString(for: display) == wanted {
                return display
            }
        }
        return CGMainDisplayID()
    }

    static let rescueCountKey = "rescueCount"

    private static var lastRescue: TimeInterval = 0

    /// Rescue the cursor to the center of the configured display.
    static func rescue(trigger: String) {
        // The same physical keypress/shake can arrive via two detection paths
        // (Carbon hotkey + raw HID chord); collapse them into one rescue.
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastRescue > 0.4 else {
            MTLog.log("Rescue: deduped trigger=\(trigger)")
            return
        }
        lastRescue = now

        // Lifetime counter for the About window. The post-restart pass is
        // the tail of one rescue, not a second one.
        if trigger != "post-uc-restart" {
            let defaults = UserDefaults.standard
            defaults.set(defaults.integer(forKey: rescueCountKey) + 1, forKey: rescueCountKey)
        }

        let display = resolveTargetDisplay()
        let bounds = CGDisplayBounds(display)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let before = CGEvent(source: nil)?.location ?? .zero
        MTLog.log("Rescue: trigger=\(trigger) display=\(display) center=(\(Int(center.x)),\(Int(center.y))) cursorBefore=(\(Int(before.x)),\(Int(before.y)))")

        // 1. Undo any cursor capture. Remote-control and screen-sharing tools
        //    (and games) disassociate the mouse from the cursor; if they die or
        //    lose track of state, the cursor is stranded. This restores it.
        CGAssociateMouseAndMouseCursorPosition(1)

        // 2. Move the cursor to the target display's center.
        CGWarpMouseCursorPosition(center)

        // 3. Post a real (synthetic) mouse-moved event through the HID event
        //    tap. Warping alone doesn't generate events, so apps tracking the
        //    cursor never notice; a posted move forces the window server and
        //    frontmost app to re-evaluate cursor visibility.
        if let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                              mouseCursorPosition: center, mouseButton: .left) {
            move.post(tap: .cghidEventTap)
        }

        // 4. Best-effort unhide. These only balance hides made by our own
        //    process on modern macOS, but they are harmless and help in the
        //    cases where the window server honors them.
        for _ in 0..<8 { CGDisplayShowCursor(display) }
        NSCursor.unhide()

        // 5. Show the locator ring so the user can spot the cursor.
        if let screen = nsScreen(for: display) {
            LocatorOverlay.flash(on: screen)
        }

        let after = CGEvent(source: nil)?.location ?? .zero
        MTLog.log("Rescue: done, cursorAfter=(\(Int(after.x)),\(Int(after.y)))")

        escalateIfPointerIsRemote(trigger: trigger, cursorPosition: before)
    }

    /// If the POINTER is being routed to another Mac, warping the local
    /// cursor doesn't help — restart Universal Control to force it to let
    /// go, then rescue again once the pointer is back.
    ///
    /// Remoteness cannot be inferred from which trigger fired: Universal
    /// Control routes the keyboard by focus, so the Carbon hotkey can fire
    /// locally while the mouse is remote. Instead: the local session hasn't
    /// seen mouse movement, AND either the raw HID layer says the physical
    /// mouse moved recently (device active, events going elsewhere) or the
    /// local cursor is parked at a display edge (where Universal Control
    /// leaves it after crossing over).
    private static func escalateIfPointerIsRemote(trigger: String, cursorPosition: CGPoint) {
        // Triggers that prove the pointer is local (menu needs a working
        // mouse; the NSEvent shake fallback only sees local events), and the
        // post-escalation pass, never escalate.
        guard ["hotkey", "raw-chord", "shake-raw"].contains(trigger) else { return }

        let mouseIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                                eventType: .mouseMoved)
        let now = ProcessInfo.processInfo.systemUptime
        let rawMouseAge = RawInputMonitor.lastRawMouseActivity > 0
            ? now - RawInputMonitor.lastRawMouseActivity : .infinity
        let atEdge = cursorIsAtDisplayEdge(cursorPosition)
        MTLog.log("Rescue: remote check localMouseIdle=\(String(format: "%.2f", mouseIdle))s rawMouseAge=\(String(format: "%.2f", rawMouseAge))s atEdge=\(atEdge)")

        let pointerIsRemote = mouseIdle > 0.5 && (rawMouseAge < 2.0 || atEdge)
        guard pointerIsRemote else { return }

        MTLog.log("Rescue: pointer appears to be on another Mac — restarting Universal Control")
        guard UniversalControlKicker.kick() else { return }

        // Give launchd a moment to respawn it and the pointer to come home,
        // then finish the job. "post-uc-restart" never re-escalates.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            rescue(trigger: "post-uc-restart")
        }
    }

    /// Universal Control parks the local cursor on the edge it crossed.
    private static func cursorIsAtDisplayEdge(_ point: CGPoint) -> Bool {
        for display in activeDisplays() {
            let b = CGDisplayBounds(display)
            guard b.insetBy(dx: -1, dy: -1).contains(point) else { continue }
            if point.x <= b.minX + 2 || point.x >= b.maxX - 2 ||
               point.y <= b.minY + 2 || point.y >= b.maxY - 2 {
                return true
            }
        }
        return false
    }

    static func nsScreen(for display: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == display
        }
    }
}
