import Foundation
import IOKit.hid
import CoreGraphics

/// Watches the physical mouse and keyboard at the HID device level via
/// IOHIDManager. This sits BELOW the layer where Universal Control /
/// screen-sharing tools capture and forward input to another Mac, so shake
/// and hotkey detection keep working even while all normal input events are
/// being routed away from this machine.
///
/// Requires the Input Monitoring permission (System Settings → Privacy &
/// Security → Input Monitoring).
final class RawInputMonitor {

    /// Called per HID value with the axis that moved (the other is 0).
    var onMouseDelta: ((_ dx: CGFloat, _ dy: CGFloat) -> Void)?
    var onHotKeyChord: (() -> Void)?

    /// When the physical mouse last produced any motion, regardless of where
    /// macOS routed the resulting events. Compared against the local
    /// session's counters to detect "device moving, but events going to
    /// another Mac".
    private(set) static var lastRawMouseActivity: TimeInterval = 0

    private var manager: IOHIDManager?

    // Raw modifier state, tracked from HID usages.
    private var control = false
    private var option = false
    private var command = false

    var isRunning: Bool { manager != nil }

    static var hasPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Triggers the system Input Monitoring prompt (first time only).
    @discardableResult
    static func requestPermission() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Whether the running manager currently has a physical mouse/pointer
    /// device matched. Used to tell a stale Input Monitoring grant (a mouse
    /// is attached but no values arrive) apart from a trackpad-only Mac
    /// (nothing matched, so silence is expected). Device enumeration is not
    /// gated by Input Monitoring; only value delivery is.
    var hasMatchedPointingDevice: Bool {
        guard let manager,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return false
        }
        for device in devices {
            let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int
            if usage == kHIDUsage_GD_Mouse || usage == kHIDUsage_GD_Pointer {
                return true
            }
        }
        return false
    }

    @discardableResult
    func start() -> Bool {
        guard manager == nil else { return true }

        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(m, matches as CFArray)

        IOHIDManagerRegisterInputValueCallback(m, { context, _, _, value in
            guard let context else { return }
            Unmanaged<RawInputMonitor>.fromOpaque(context)
                .takeUnretainedValue()
                .handle(value: value)
        }, Unmanaged.passUnretained(self).toOpaque())

        // commonModes, NOT defaultMode: menu tracking runs the loop in a
        // non-default mode, and detection must keep working while our own
        // menu (with the sensitivity slider) is open.
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(),
                                        CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            MTLog.log("RawInput: IOHIDManagerOpen failed status=0x\(String(UInt32(bitPattern: result), radix: 16))")
            IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(),
                                              CFRunLoopMode.commonModes.rawValue)
            return false
        }

        manager = m
        MTLog.log("RawInput: monitoring started")
        return true
    }

    func stop() {
        guard let m = manager else { return }
        IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(),
                                          CFRunLoopMode.commonModes.rawValue)
        manager = nil
        control = false; option = false; command = false
        MTLog.log("RawInput: monitoring stopped")
    }

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let intValue = IOHIDValueGetIntegerValue(value)

        if page == kHIDPage_GenericDesktop, usage == kHIDUsage_GD_X || usage == kHIDUsage_GD_Y {
            if intValue != 0 {
                Self.lastRawMouseActivity = ProcessInfo.processInfo.systemUptime
                if usage == kHIDUsage_GD_X {
                    onMouseDelta?(CGFloat(intValue), 0)
                } else {
                    onMouseDelta?(0, CGFloat(intValue))
                }
            }
            return
        }

        guard page == kHIDPage_KeyboardOrKeypad else { return }
        let down = intValue != 0
        switch usage {
        case kHIDUsage_KeyboardLeftControl, kHIDUsage_KeyboardRightControl:
            control = down
        case kHIDUsage_KeyboardLeftAlt, kHIDUsage_KeyboardRightAlt:
            option = down
        case kHIDUsage_KeyboardLeftGUI, kHIDUsage_KeyboardRightGUI:
            command = down
        case kHIDUsage_KeyboardM:
            if down, control, option, command {
                MTLog.log("RawInput: hotkey chord detected")
                onHotKeyChord?()
            }
        default:
            break
        }
    }

    deinit { stop() }
}
