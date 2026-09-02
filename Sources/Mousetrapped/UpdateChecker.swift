import AppKit

/// Lightweight update check: one unauthenticated GET to GitHub's
/// releases/latest API, compares the tag to the running bundle version.
/// No Sparkle, no auto-download — it only points the user at the brew
/// command or the release page. The whole thing is opt-out (a menu toggle)
/// and throttled to once a day.
enum UpdateChecker {

    static let latestAPI = "https://api.github.com/repos/uncSoft/Mousetrapped/releases/latest"
    static let releasesPage = "https://github.com/uncSoft/Mousetrapped/releases/latest"
    static let brewCommand = "brew upgrade --cask mousetrapped"

    private static let lastCheckKey = "updateLastCheck"
    private static let skippedVersionKey = "updateSkippedVersion"
    static let autoCheckKey = "updateCheckAutomatically"

    /// The newer version string once a check has found one (nil otherwise).
    /// Drives the menu's "Update available" item.
    private(set) static var availableVersion: String?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var autoCheckEnabled: Bool {
        UserDefaults.standard.object(forKey: autoCheckKey) == nil
            ? true : UserDefaults.standard.bool(forKey: autoCheckKey)
    }

    /// Fetch the latest release tag, off the main thread. `completion` runs
    /// on the main queue with the newer version string, or nil. When `force`
    /// is false the daily throttle and the auto-check toggle both apply.
    static func check(force: Bool, completion: @escaping (String?) -> Void) {
        if !force {
            guard autoCheckEnabled else { completion(nil); return }
            let now = Date().timeIntervalSince1970
            let last = UserDefaults.standard.double(forKey: lastCheckKey)
            if now - last < 24 * 60 * 60 {
                completion(availableVersion)
                return
            }
        }

        guard let url = URL(string: latestAPI) else { completion(nil); return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, _, error in
            var newer: String?
            defer { DispatchQueue.main.async { completion(newer) } }

            if let error {
                MTLog.log("Update: check failed — \(error.localizedDescription)")
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                MTLog.log("Update: unexpected response")
                return
            }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            if isVersion(latest, newerThan: currentVersion) {
                newer = latest
                availableVersion = latest
                MTLog.log("Update: \(latest) available (running \(currentVersion))")
            } else {
                availableVersion = nil
                MTLog.log("Update: up to date (\(currentVersion), latest \(latest))")
            }
        }.resume()
    }

    /// Dotted numeric comparison; missing components read as 0.
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func isSkipped(_ version: String) -> Bool {
        UserDefaults.standard.string(forKey: skippedVersionKey) == version
    }

    static func skip(_ version: String) {
        UserDefaults.standard.set(version, forKey: skippedVersionKey)
    }

    static func openReleasePage() {
        if let url = URL(string: releasesPage) { NSWorkspace.shared.open(url) }
    }

    static func copyBrewCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(brewCommand, forType: .string)
    }

    /// The one-time nudge shown on launch when a non-skipped newer version
    /// is found. The suppression checkbox is the "skip this version" control.
    static func presentUpdatePrompt(version: String, respectSkip: Bool = true) {
        if respectSkip, isSkipped(version) { return }

        let alert = NSAlert()
        alert.messageText = "Mousetrapped \(version) is available"
        alert.informativeText = """
        You're running \(currentVersion).

        Update with Homebrew:
            \(brewCommand)

        or download the notarized build from the releases page.
        """
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Copy Brew Command")
        alert.addButton(withTitle: "Later")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't remind me about this version"

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if alert.suppressionButton?.state == .on { skip(version) }

        switch response {
        case .alertFirstButtonReturn: openReleasePage()
        case .alertSecondButtonReturn: copyBrewCommand()
        default: break
        }
    }
}
