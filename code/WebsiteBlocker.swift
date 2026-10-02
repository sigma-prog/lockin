import Foundation
import AppKit

class WebsiteBlocker {
    static let shared = WebsiteBlocker()
    private static var hasShownAlert = false

    struct Browser { let name: String; let bundleID: String }

    /// Browsers whose tabs can be read and closed over AppleScript.
    /// Firefox has no tab scripting, so it can't be website filtered and isn't listed.
    /// Arc is included but untested
    static let browsers: [Browser] = [
        Browser(name: "Safari", bundleID: "com.apple.Safari"),
        Browser(name: "Google Chrome", bundleID: "com.google.Chrome"),
        Browser(name: "Brave Browser", bundleID: "com.brave.Browser"),
        Browser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac"),
        Browser(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi"),
        Browser(name: "Opera", bundleID: "com.operasoftware.Opera"),
        Browser(name: "Google Chrome Beta", bundleID: "com.google.Chrome.beta"),
        Browser(name: "Google Chrome Canary", bundleID: "com.google.Chrome.canary"),
        Browser(name: "Chromium", bundleID: "org.chromium.Chromium"),
        Browser(name: "Arc", bundleID: "company.thebrowser.Browser")
    ]

    static func isScriptableBrowser(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return browsers.contains { $0.bundleID == id }
    }

    private struct Rule { let domain: String; let path: String? }

    private var rules: [Rule] = []
    private var mode: ListMode = .blocklist
    private var listScripts: [String: NSAppleScript] = [:]   // compiled once per browser, reused every tick
    private var backoffUntil: [String: Date] = [:]            // browsers that timed out get skipped 

    func configure(mode: ListMode, domains: [String]) {
        self.mode = mode
        rules = domains.compactMap { entry in
            let parts = entry.lowercased().split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            guard let domain = parts.first else { return nil }
            return Rule(domain: String(domain), path: parts.count > 1 ? "/" + parts[1] : nil)
        }
    }

    func enforce() {
        guard !rules.isEmpty else { return }   // an empty list never closes anything
        let now = Date()
        for browser in WebsiteBlocker.browsers where isRunning(bundleID: browser.bundleID) {
            if let until = backoffUntil[browser.bundleID], until > now { continue }
            enforce(browser)
        }
    }

    private func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }


    /// chrome://, about:, file:, new-tab pages etc. are never closed.
    private func shouldClose(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host?.lowercased() else { return false }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        let path = url.path.lowercased()

        let matched = rules.contains { rule in
            guard host == rule.domain || host.hasSuffix("." + rule.domain) else { return false }
            guard let wanted = rule.path else { return true }
            return path.hasPrefix(wanted)
        }
        return mode == .allowlist ? !matched : matched
    }

    private func enforce(_ browser: Browser) {
        guard let script = listScript(for: browser),
              let result = execute(script, browser: browser) else { return }

        let entries = (0..<result.numberOfItems).compactMap { result.atIndex($0 + 1)?.stringValue }
        var targets: [(window: Int, tab: Int, url: String)] = []
        for entry in entries {
            let parts = entry.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let w = Int(parts[0]), let t = Int(parts[1]) else { continue }
            let url = String(parts[2])
            if shouldClose(url) { targets.append((w, t, url)) }
        }
        guard !targets.isEmpty else { return }

        targets.sort { ($0.window, $0.tab) > ($1.window, $1.tab) }

        let body = targets.map {
            "try\nif (URL of tab \($0.tab) of window \($0.window)) is \"\(escape($0.url))\" then close tab \($0.tab) of window \($0.window)\nend try"
        }.joined(separator: "\n")
        let source = """
        with timeout of 2 seconds
        tell application "\(browser.name)"
        \(body)
        end tell
        end timeout
        """
        guard let closeScript = NSAppleScript(source: source) else { return }
        _ = execute(closeScript, browser: browser)
    }

    private func listScript(for browser: Browser) -> NSAppleScript? {
        if let cached = listScripts[browser.bundleID] { return cached }
        let source = """
        with timeout of 2 seconds
        tell application "\(browser.name)"
            set out to {}
            repeat with wi from 1 to (count of windows)
                try
                    repeat with ti from 1 to (count of tabs of window wi)
                        try
                            set end of out to (wi as text) & "|" & (ti as text) & "|" & (URL of tab ti of window wi)
                        end try
                    end repeat
                end try
            end repeat
            return out
        end tell
        end timeout
        """
        let script = NSAppleScript(source: source)
        listScripts[browser.bundleID] = script
        return script
    }

    private func execute(_ script: NSAppleScript, browser: Browser) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error = error {
            switch error[NSAppleScript.errorNumber] as? Int {
            case -1743: DispatchQueue.main.async { self.showPermissionAlert() }   // user clicked "Don't Allow"
            case -1712: backoffUntil[browser.bundleID] = Date().addingTimeInterval(10)  
            default: break
            }
            return nil
        }
        return result
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func showPermissionAlert() {
        guard !Self.hasShownAlert else { return }
        Self.hasShownAlert = true
        let alert = NSAlert()
        alert.messageText = "Automation Permission Required"
        alert.informativeText = "Lockin needs permission to close browser tabs. Please enable it in System Settings → Privacy & Security → Automation."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Dismiss")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}