import Darwin
import Foundation

/// Forcibly restarts the Universal Control agent (UniversalControl.app,
/// launchd job com.apple.ensemble). Killing it is the only unprivileged way
/// to make it release a pointer it has routed to another Mac: SIP blocks
/// `launchctl kickstart` for Apple services, and the process ignores
/// SIGTERM, so SIGKILL it is. launchd respawns it immediately and Universal
/// Control reconnects on the next edge-push.
enum UniversalControlKicker {

    @discardableResult
    static func kick() -> Bool {
        guard let pid = findPid() else {
            MTLog.log("UC: UniversalControl process not found")
            return false
        }
        let result = kill(pid, SIGKILL)
        if result == 0 {
            MTLog.log("UC: killed UniversalControl pid=\(pid)")
            return true
        }
        MTLog.log("UC: kill(\(pid), SIGKILL) failed errno=\(errno) (\(String(cString: strerror(errno))))")
        return false
    }

    private static func findPid() -> pid_t? {
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return nil }

        var pathBuffer = [CChar](repeating: 0, count: 4 * 1024)
        for pid in pids.prefix(Int(count)) where pid > 0 {
            guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else { continue }
            let path = String(cString: pathBuffer)
            if path.hasSuffix("/UniversalControl.app/Contents/MacOS/UniversalControl") {
                return pid
            }
        }
        return nil
    }
}
