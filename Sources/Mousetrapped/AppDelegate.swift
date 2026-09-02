import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let targetMenu = NSMenu()
    private var shakeItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var rawInputItem: NSMenuItem!
    private var hotKey: HotKey?
    private let shakeDetector = ShakeDetector()
    private let rawInput = RawInputMonitor()

    private var shakeEnabled: Bool {
        UserDefaults.standard.bool(forKey: ShakeDetector.enabledDefaultsKey)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MTLog.log("App: launched pid=\(ProcessInfo.processInfo.processIdentifier) bundle=\(Bundle.main.bundlePath)")

        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { _ in
            MTLog.log("App: didBecomeActive")
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { _ in
            MTLog.log("App: didResignActive")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cursorarrow.rays",
                                   accessibilityDescription: "Mousetrapped")
        }

        buildMenu()
        statusItem.menu = menu

        hotKey = HotKey(keyCode: HotKey.savedKeyCode,
                        carbonModifiers: HotKey.savedModifiers) {
            CursorRescue.rescue(trigger: "hotkey")
        }
        if hotKey == nil {
            MTLog.log("App: WARNING hotkey registration FAILED")
        }

        shakeDetector.onShake = { [weak self] in
            guard let self else { return }
            guard self.shakeEnabled else {
                MTLog.log("Shake: rescue is toggled off — not rescuing")
                return
            }
            CursorRescue.rescue(trigger: self.rawInput.isRunning ? "shake-raw" : "shake")
        }
        if UserDefaults.standard.object(forKey: ShakeDetector.enabledDefaultsKey) == nil {
            UserDefaults.standard.set(true, forKey: ShakeDetector.enabledDefaultsKey)
        }
        if UserDefaults.standard.object(forKey: ShakeDetector.sensitivityDefaultsKey) == nil {
            UserDefaults.standard.set(ShakeDetector.defaultSensitivity,
                                      forKey: ShakeDetector.sensitivityDefaultsKey)
        }
        shakeDetector.apply(sensitivity:
            UserDefaults.standard.double(forKey: ShakeDetector.sensitivityDefaultsKey))

        // Always feed the detector — detection (and its debug logging) stays
        // live even when shake-rescue is toggled off; the toggle only gates
        // the rescue action in onShake.
        rawInput.onMouseDelta = { [weak self] dx, dy in
            self?.shakeDetector.feed(deltaX: dx, deltaY: dy)
        }
        // Delay the raw chord slightly: on a LOCAL press the Carbon hotkey
        // fires immediately and the dedupe window then swallows this one, so
        // the remote-pointer escalation can never misfire from local input.
        rawInput.onHotKeyChord = {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                CursorRescue.rescue(trigger: "raw-chord")
            }
        }

        startInputMonitoring()
    }

    /// Prefer raw HID monitoring (works while another Mac has the pointer);
    /// fall back to the NSEvent monitor when Input Monitoring isn't granted.
    /// Never run both — they'd both feed the shake detector.
    private func startInputMonitoring() {
        if RawInputMonitor.hasPermission, rawInput.start() {
            shakeDetector.stop()
            MTLog.log("App: using raw HID input monitoring")
        } else if shakeEnabled {
            shakeDetector.start()
            MTLog.log("App: Input Monitoring not granted, using NSEvent shake fallback")
        }
    }

    // The menu is built exactly once. Rebuilding it in menuNeedsUpdate breaks
    // hover highlighting, because AppKit also calls menuNeedsUpdate during
    // key-equivalent searches while the menu is tracking.
    private func buildMenu() {
        let rescueItem = NSMenuItem(title: "Rescue Cursor Now",
                                    action: #selector(rescueNow), keyEquivalent: "m")
        rescueItem.keyEquivalentModifierMask = [.control, .option, .command]
        rescueItem.target = self
        menu.addItem(rescueItem)

        menu.addItem(.separator())

        let targetItem = NSMenuItem(title: "Rescue To", action: nil, keyEquivalent: "")
        targetMenu.delegate = self
        targetItem.submenu = targetMenu
        menu.addItem(targetItem)

        shakeItem = NSMenuItem(title: "Shake Mouse to Rescue",
                               action: #selector(toggleShake), keyEquivalent: "")
        shakeItem.target = self
        menu.addItem(shakeItem)

        menu.addItem(makeSensitivitySliderItem())

        rawInputItem = NSMenuItem(title: "Work Across Macs…",
                                  action: #selector(enableRawInput), keyEquivalent: "")
        rawInputItem.target = self
        rawInputItem.toolTip = "Watches the physical mouse and keyboard so rescue "
            + "works even while Universal Control has routed input to another Mac. "
            + "Needs the Input Monitoring permission."
        menu.addItem(rawInputItem)

        menu.addItem(.separator())

        loginItem = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About Mousetrapped",
                                   action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem(title: "Quit Mousetrapped",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.delegate = self
    }

    // Refresh toggle states when the root menu opens — no item churn.
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        shakeItem.state = shakeEnabled ? .on : .off
        rawInputItem.state = rawInput.isRunning ? .on : .off
        rawInputItem.title = rawInput.isRunning
            ? "Working Across Macs" : "Work Across Macs…"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // Only the display submenu is rebuilt dynamically, so the list stays
    // fresh as displays come and go.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === targetMenu else { return }
        menu.removeAllItems()

        let selectedUUID = CursorRescue.targetDisplayUUID

        let primaryItem = NSMenuItem(title: "Primary Display",
                                     action: #selector(selectPrimaryDisplay), keyEquivalent: "")
        primaryItem.target = self
        primaryItem.state = selectedUUID == nil ? .on : .off
        menu.addItem(primaryItem)
        menu.addItem(.separator())

        for display in CursorRescue.activeDisplays() {
            guard let uuid = CursorRescue.uuidString(for: display) else { continue }
            var title = CursorRescue.name(for: display)
            if display == CGMainDisplayID() { title += " (primary)" }
            let item = NSMenuItem(title: title,
                                  action: #selector(selectDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = uuid
            item.state = selectedUUID == uuid ? .on : .off
            menu.addItem(item)
        }
    }

    private func makeSensitivitySliderItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 48))

        let label = NSTextField(labelWithString: "Shake Sensitivity")
        label.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 22, y: 28, width: 206, height: 16)
        container.addSubview(label)

        let slider = NSSlider(value: UserDefaults.standard.double(forKey: ShakeDetector.sensitivityDefaultsKey),
                              minValue: 0, maxValue: 1,
                              target: self, action: #selector(sensitivityChanged(_:)))
        slider.isContinuous = true
        slider.numberOfTickMarks = 5
        slider.allowsTickMarkValuesOnly = false
        slider.frame = NSRect(x: 22, y: 4, width: 206, height: 24)
        slider.toolTip = "Right = hair trigger, left = requires a long, vigorous shake"
        container.addSubview(slider)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    @objc private func sensitivityChanged(_ sender: NSSlider) {
        let value = sender.doubleValue
        UserDefaults.standard.set(value, forKey: ShakeDetector.sensitivityDefaultsKey)
        shakeDetector.noteSliderActivity()
        shakeDetector.apply(sensitivity: value)
    }

    @objc private func showAbout() {
        AboutWindow.show()
    }

    @objc private func rescueNow() {
        CursorRescue.rescue(trigger: "menu")
    }

    @objc private func selectPrimaryDisplay() {
        CursorRescue.targetDisplayUUID = nil
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        CursorRescue.targetDisplayUUID = sender.representedObject as? String
    }

    @objc private func toggleShake() {
        let enabling = !shakeEnabled
        UserDefaults.standard.set(enabling, forKey: ShakeDetector.enabledDefaultsKey)
        // In raw HID mode the delta callback checks shakeEnabled itself; the
        // NSEvent monitor only runs as the fallback.
        if rawInput.isRunning {
            shakeDetector.stop()
        } else if enabling {
            shakeDetector.start()
        } else {
            shakeDetector.stop()
        }
    }

    @objc private func enableRawInput() {
        if rawInput.isRunning {
            rawInput.stop()
            startInputMonitoring()
            return
        }
        if RawInputMonitor.hasPermission {
            startInputMonitoring()
            return
        }

        MTLog.log("App: requesting Input Monitoring permission")
        RawInputMonitor.requestPermission()

        let alert = NSAlert()
        alert.messageText = "Input Monitoring Needed"
        alert.informativeText = """
        To rescue the cursor while it's controlling another Mac (Universal \
        Control), Mousetrapped has to watch the physical mouse and keyboard \
        directly — normal input events are routed to the other Mac.

        Enable Mousetrapped under System Settings → Privacy & Security → \
        Input Monitoring, then relaunch Mousetrapped.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = """
            \(error.localizedDescription)

            Launch at Login only works when Mousetrapped runs from a proper \
            .app bundle (e.g. /Applications/Mousetrapped.app), not from the \
            bare build binary.
            """
            alert.runModal()
        }
    }
}
