import AppKit

/// Detects a rapid left-right mouse shake. Horizontal deltas are fed in
/// either from an NSEvent global monitor (no permissions, but blind while
/// another device has the pointer) or from RawInputMonitor's HID stream
/// (sees everything).
///
/// What separates a shake from ordinary mousing is TEMPO and AXIS, not
/// size: shake reversals arrive metronomically fast (every 60-150ms) and
/// almost purely horizontally, while normal mousing alternates slowly,
/// irregularly, and diagonally. So a reversal only extends the chain if it
/// lands within `maxReversalGap` of the previous one, and a stroke only
/// counts if its horizontal travel dominates its vertical travel.
final class ShakeDetector {

    static let enabledDefaultsKey = "shakeToRescue"
    static let sensitivityDefaultsKey = "shakeSensitivity"
    static let defaultSensitivity = 0.45

    var onShake: (() -> Void)?

    private var monitor: Any?

    // Same-direction movement accumulates into a "stroke" (run).
    private var runDirection = 0
    private var runX: CGFloat = 0
    private var runY: CGFloat = 0

    // Chain of rapid alternating strokes.
    private var lastStrokeDirection = 0
    private var chainedReversals = 0
    private var lastReversalTime: TimeInterval = 0

    private var lastFeedTime: TimeInterval = 0
    private var lastTrigger: TimeInterval = 0
    private var lastSliderActivity: TimeInterval = 0

    /// Sensitivity-scaled tunables (see apply(sensitivity:)).
    private var requiredReversals = 5
    private var minStroke: CGFloat = 94

    /// Fixed tunables. maxReversalGap is the tempo gate: human shake
    /// cadence is 60-150ms per reversal, ordinary mousing alternates far
    /// slower — 0.35s sits between them with margin on both sides.
    private let maxReversalGap: TimeInterval = 0.35
    private let cooldown: TimeInterval = 2.0
    private let idleReset: TimeInterval = 0.4

    /// Extra per-stroke logging, enabled with
    /// `defaults write dev.mousetrapped.Mousetrapped shakeDebug -bool true`.
    private var debug: Bool { UserDefaults.standard.bool(forKey: "shakeDebug") }

    var isRunning: Bool { monitor != nil }

    /// Dragging the sensitivity slider is itself a horizontal shake; feeds
    /// are ignored until the slider has been quiet for a moment.
    func noteSliderActivity() {
        lastSliderActivity = ProcessInfo.processInfo.systemUptime
        reset()
    }

    /// Maps sensitivity 0...1 onto the two per-level knobs: how many rapid
    /// reversals (3 at the hair-trigger end, 7 at the deliberate end) and
    /// the per-stroke horizontal travel floor (25 to 150 HID counts, inside
    /// the measured 100-300 range of real vigorous strokes — people shake
    /// FAST, not wide, so demanding huge strokes just rejects real shakes).
    /// The tempo and axis gates are fixed; they are what reject ordinary
    /// mousing at every sensitivity.
    func apply(sensitivity: Double) {
        let t = min(max(sensitivity, 0), 1)
        requiredReversals = 3 + Int((4 * (1 - t)).rounded())
        minStroke = CGFloat(25 + 125 * (1 - t))
        MTLog.log("Shake: sensitivity=\(String(format: "%.2f", t)) reversals=\(requiredReversals) minStroke=\(Int(minStroke)) maxGap=\(maxReversalGap)s")
    }

    /// Starts the NSEvent-based fallback monitor (used when raw HID
    /// monitoring isn't available).
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            self?.feed(deltaX: event.deltaX, deltaY: event.deltaY)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        reset()
    }

    func feed(deltaX: CGFloat, deltaY: CGFloat) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSliderActivity > 0.7 else { return }

        // A pause means the shake (if any) ended; start fresh.
        if now - lastFeedTime > idleReset { reset() }
        lastFeedTime = now

        runY += abs(deltaY)
        guard deltaX != 0 else { return }

        let direction = deltaX > 0 ? 1 : -1
        if direction == runDirection {
            runX += abs(deltaX)
        } else {
            closeRun(at: now)
            runDirection = direction
            runX = abs(deltaX)
            runY = abs(deltaY)
        }
    }

    private func closeRun(at now: TimeInterval) {
        defer { runX = 0; runY = 0 }
        guard runDirection != 0 else { return }

        // Too small to mean anything: jitter fragment or fine positioning.
        // Ignored entirely — it neither chains nor breaks a chain.
        guard runX >= minStroke else { return }

        // Big but diagonal: that's navigation, not shaking. Break the chain.
        guard runX >= 2 * runY else {
            if debug, chainedReversals > 0 {
                MTLog.log("Shake: chain broken by diagonal stroke (x=\(Int(runX)) y=\(Int(runY)))")
            }
            lastStrokeDirection = 0
            chainedReversals = 0
            return
        }

        if lastStrokeDirection != 0, runDirection != lastStrokeDirection {
            // Tempo gate: a reversal that arrives late starts a new chain.
            if chainedReversals > 0, now - lastReversalTime > maxReversalGap {
                if debug {
                    MTLog.log("Shake: chain restarted, reversal too slow (+\(String(format: "%.2f", now - lastReversalTime))s)")
                }
                chainedReversals = 0
            }
            chainedReversals += 1
            lastReversalTime = now
            if debug {
                MTLog.log("Shake: reversal dir=\(runDirection) x=\(Int(runX)) y=\(Int(runY)) chain=\(chainedReversals)/\(requiredReversals)")
            }
            if chainedReversals >= requiredReversals {
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
        }
        lastStrokeDirection = runDirection
    }

    private func reset() {
        runDirection = 0
        runX = 0
        runY = 0
        lastStrokeDirection = 0
        chainedReversals = 0
    }
}
