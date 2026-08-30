import AppKit

/// Simple About window: art, version, byline, GitHub links, and the
/// lifetime rescue counter. Clicking the artwork demos the locator ring.
enum AboutWindow {

    private static var window: NSWindow?

    static func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let width: CGFloat = 340
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        var y: CGFloat = 20

        func addLabel(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = font
            label.textColor = color
            label.alignment = .center
            label.sizeToFit()
            label.frame = NSRect(x: 0, y: y, width: width, height: label.frame.height)
            content.addSubview(label)
            y += label.frame.height + 6
            return label
        }

        func addLink(_ title: String, url: String) {
            let button = NSButton(title: title, target: nil, action: nil)
            button.isBordered = false
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: NSColor.linkColor,
                .font: NSFont.systemFont(ofSize: 13),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ])
            button.sizeToFit()
            button.frame = NSRect(x: (width - button.frame.width) / 2, y: y,
                                  width: button.frame.width, height: button.frame.height)
            button.target = LinkOpener.shared
            button.action = #selector(LinkOpener.open(_:))
            button.toolTip = url
            LinkOpener.shared.urls[ObjectIdentifier(button)] = url
            content.addSubview(button)
            y += button.frame.height + 4
        }

        // Built bottom-up.
        let license = addLabel("PolyForm Noncommercial 1.0.0 — free, but never for sale",
                               font: .systemFont(ofSize: 10), color: .tertiaryLabelColor)
        _ = license
        y += 6

        addLink("uncSoft/Mousetrapped", url: "https://github.com/uncSoft/Mousetrapped")
        addLink("github.com/uncSoft", url: "https://github.com/uncSoft")
        y += 6

        let rescues = UserDefaults.standard.integer(forKey: CursorRescue.rescueCountKey)
        _ = addLabel("🪤 \(rescues) cursor\(rescues == 1 ? "" : "s") rescued so far",
                     font: .systemFont(ofSize: 13))
        y += 6

        _ = addLabel("by JT @ uncSoft", font: .systemFont(ofSize: 13),
                     color: .secondaryLabelColor)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "dev"
        _ = addLabel("Version \(version)", font: .systemFont(ofSize: 11),
                     color: .secondaryLabelColor)
        _ = addLabel("Mousetrapped", font: .boldSystemFont(ofSize: 18))
        y += 8

        // Artwork — click it to demo the locator ring.
        let artSize: CGFloat = 220
        let imageView = NSImageView(frame: NSRect(x: (width - artSize) / 2, y: y,
                                                  width: artSize, height: artSize))
        if let path = Bundle.main.path(forResource: "AboutArt", ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            imageView.image = image
        } else {
            imageView.image = NSImage(systemSymbolName: "cursorarrow.rays",
                                      accessibilityDescription: nil)
        }
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.toolTip = "Click me!"
        let click = NSClickGestureRecognizer(target: LinkOpener.shared,
                                             action: #selector(LinkOpener.demoRing))
        imageView.addGestureRecognizer(click)
        content.addSubview(imageView)
        y += artSize + 16

        content.frame = NSRect(x: 0, y: 0, width: width, height: y)

        let panel = NSWindow(contentRect: content.frame,
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
        panel.title = "About Mousetrapped"
        panel.contentView = content
        panel.isReleasedWhenClosed = false
        panel.center()
        window = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

/// Target object for About-window controls (an enum can't be a selector
/// target).
final class LinkOpener: NSObject {
    static let shared = LinkOpener()
    var urls: [ObjectIdentifier: String] = [:]

    @objc func open(_ sender: NSButton) {
        if let urlString = urls[ObjectIdentifier(sender)], let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func demoRing() {
        if let screen = NSScreen.main {
            LocatorOverlay.flash(on: screen)
        }
    }
}
