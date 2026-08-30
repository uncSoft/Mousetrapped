import AppKit
import QuartzCore

/// A short-lived, click-through overlay window that pulses a ring at the
/// center of a screen so the user can find the freshly rescued cursor.
enum LocatorOverlay {

    private static var window: NSWindow?

    static func flash(on screen: NSScreen) {
        window?.orderOut(nil)

        let size: CGFloat = 240
        let frame = NSRect(
            x: screen.frame.midX - size / 2,
            y: screen.frame.midY - size / 2,
            width: size, height: size
        )

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        panel.contentView = view

        for (delay, startScale) in [(0.0, 0.15), (0.25, 0.15)] {
            let ring = CAShapeLayer()
            let inset: CGFloat = 6
            ring.path = CGPath(ellipseIn: CGRect(x: inset, y: inset,
                                                 width: size - inset * 2,
                                                 height: size - inset * 2),
                               transform: nil)
            ring.fillColor = NSColor.clear.cgColor
            ring.strokeColor = NSColor.systemRed.cgColor
            ring.lineWidth = 5
            ring.frame = view.bounds
            ring.opacity = 0
            view.layer?.addSublayer(ring)

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = startScale
            scale.toValue = 1.0
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 1.0
            fadeIn.toValue = 0.0

            let group = CAAnimationGroup()
            group.animations = [scale, fadeIn]
            group.duration = 0.7
            group.beginTime = CACurrentMediaTime() + delay
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.isRemovedOnCompletion = true
            ring.add(group, forKey: "pulse")
        }

        panel.orderFrontRegardless()
        window = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak panel] in
            panel?.orderOut(nil)
            if window === panel { window = nil }
        }
    }
}
