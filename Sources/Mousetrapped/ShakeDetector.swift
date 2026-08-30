import AppKit

/// Detects a rapid left-right mouse shake. Horizontal deltas are fed in
/// either from an NSEvent global monitor (no permissions, but blind while
/// another Mac has the pointer) or from RawInputMonitor's HID stream (sees
/// everything). Same-direction movement is accumulated into "strokes";
/// enough stroke reversals inside a short window is a shake. Stroke
/// accumulation makes the detector rate-independent: NSEvent delivers few
/// large deltas, raw HID delivers many tiny ones.
final class ShakeDetector {

    static let enabledDefaultsKey = "shakeToRescue"
    static let sensitivityDefaultsKey = "shakeSensitivity"
    /// User-calibrated 2026-08-30: 5 reversals of >=169-count strokes in
    /// 2.35s — rejects light jiggles and tight fast wiggles, fires on a
    /// deliberate medium-arc shake.
    static let defaultSensitivity = 0.30

    var onShake: (() -> Void)?

    private var monitor: Any?

    // Stroke accumulation state.
    private var runDirection = 0
    private var runDistance: CGFloat = 0
    private var lastStrokeDirection = 0
    private var reversalTimes: [TimeInterval] = []
    private var lastFeedTime: TimeInterval = 0
    private var lastTrigger: TimeInterval = 0

    /// Tunables, derived from the sensitivity setting: a stroke must cover
    /// >= minStroke points; `requiredReversals` reversals within `window`
    /// seconds fire a rescue, then a cooldown eats the tail of the shake.
    private var minStroke: CGFloat = 30
    private var window: TimeInterval = 0.7
    private var requiredReversals = 4
    private let cooldown: TimeInterval = 2.0
    private let idleReset: TimeInterval = 0.4

    /// Dragging the sensitivity slider is itself a horizontal shake; feeds
    /// are ignored until the slider has been quiet for a moment, so slider
    /// adjustment can't fire a rescue but shake-testing with the menu open
    /// works the instant the drag ends.
    private var lastSliderActivity: TimeInterval = 0

    func noteSliderActivity() {
        lastSliderActivity = ProcessInfo.processInfo.systemUptime
        reset()
    }

    /// Extra per-stroke logging, enabled with
    /// `defaults write dev.mousetrapped.Mousetrapped shakeDebug -bool true`.
    private var debug: Bool { UserDefaults.standard.bool(forKey: "shakeDebug") }

    /// Maps sensitivity 0...1 onto two axes of shake difficulty:
    ///
    /// - Reversal count (3 → 10): how LONG you must keep shaking.
    /// - Stroke distance (25 → 125 HID counts): how VIGOROUS each stroke
    ///   must be. This is the axis that separates a light millimeter
    ///   fingertip jiggle (small strokes, fires only at the sensitive end)
    ///   from a real arm-driven shake (100-250+ counts per stroke, fires at
    ///   every level).
    ///
    /// The per-reversal time budget stays a comfortable 0.3s at every
    /// level: a human can't be asked to shake FASTER, only longer and
    /// harder. Sub-threshold strokes are ignored entirely — they neither
    /// count as reversals nor break an alternation streak.
    ///
    /// Calibration (2026-08-30, measured against macOS shake-to-locate):
    /// the system's cursor-enlarge fires after roughly 8-12 reversals of
    /// sustained vigorous shaking (~1s at a 60-90ms reversal cadence),
    /// with measured stroke distances of 60-666 counts, mostly 100-250.
    /// Measured stroke reality (same user, same mouse): a light fingertip
    /// jiggle produces 130-290 counts per stroke, a vigorous tight shake
    /// mostly 100-300 — the two overlap, so mid-scale can't separate them
    /// by amplitude alone (count + amplitude together do). Only wide
    /// sweeping arcs exceed ~400. Hence the cubic: the top half of the
    /// slider moves the floor gently (25→100), and the deep end climbs
    /// steeply to 450 so far-left demands genuinely big arcs. The
    /// per-reversal budget grows with stroke size — wide arcs are slower
    /// than jiggles.
    func apply(sensitivity: Double) {
        let t = min(max(sensitivity, 0), 1)
        requiredReversals = Int((6 - 3 * t).rounded())
        minStroke = CGFloat(25 + 425 * pow(1 - t, 3))
        window = Double(requiredReversals) * (0.30 + Double(minStroke) / 1000)
        MTLog.log("Shake: sensitivity=\(String(format: "%.2f", t)) reversals=\(requiredReversals) window=\(String(format: "%.2f", window))s minStroke=\(Int(minStroke))")
    }

    var isRunning: Bool { monitor != nil }

    /// Starts the NSEvent-based fallback monitor (used when raw HID
    /// monitoring isn't available).
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            self?.feed(deltaX: event.deltaX)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        reset()
    }

    func feed(deltaX: CGFloat) {
        guard deltaX != 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSliderActivity > 0.7 else { return }

        // A pause means the shake (if any) ended; start fresh.
        if now - lastFeedTime > idleReset { reset() }
        lastFeedTime = now

        let direction = deltaX > 0 ? 1 : -1
        if direction == runDirection {
            runDistance += abs(deltaX)
        } else {
            closeRun(at: now)
            runDirection = direction
            runDistance = abs(deltaX)
        }
    }

    private func closeRun(at now: TimeInterval) {
        defer { runDirection = 0; runDistance = 0 }
        guard runDirection != 0, runDistance >= minStroke else { return }

        if lastStrokeDirection != 0, runDirection != lastStrokeDirection {
            reversalTimes.append(now)
            reversalTimes.removeAll { now - $0 > window }
            if debug {
                MTLog.log("Shake: stroke dir=\(runDirection) dist=\(Int(runDistance)) reversals=\(reversalTimes.count)/\(requiredReversals)")
            }
            if reversalTimes.count >= requiredReversals {
                if now - lastTrigger > cooldown {
                    lastTrigger = now
                    reset()
                    MTLog.log("Shake: detected")
                    onShake?()
                } else {
                    reset()
                    MTLog.log("Shake: detected but in cooldown (\(String(format: "%.1f", cooldown - (now - lastTrigger)))s left)")
                }
                return
            }
        } else if debug {
            MTLog.log("Shake: stroke dir=\(runDirection) dist=\(Int(runDistance)) (same direction, not a reversal)")
        }
        lastStrokeDirection = runDirection
    }

    private func reset() {
        runDirection = 0
        runDistance = 0
        lastStrokeDirection = 0
        reversalTimes.removeAll()
    }
}
