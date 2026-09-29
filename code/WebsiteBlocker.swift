import Foundation
import AppKit

class WebsiteBlocker {
    static let shared = WebsiteBlocker()
    private static var hasShownAlert = false

    func enforce(mode: ListMode, domains: [String]) {
        guard !domains.isEmpty else { return }
        let isAllow = (mode == .allowlist)

        if isRunning(bundleID: "com.apple.Safari") {
            enforceSafari(domains: domains, isAllowlist: isAllow)
        }
        if isRunning(bundleID: "com.google.Chrome") {
            enforceChrome(domains: domains, isAllowlist: isAllow)
        }
    }

    private func isRunning(bundleID: String) -> Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func enforceSafari(domains: [String], isAllowlist: Bool) {
        let conditions = domains.map { "currentURL contains \"\($0)\"" }.joined(separator: " or ")
        let check = isAllowlist ? "not (\(conditions))" : conditions

        let script = """
        tell application "Safari"
            repeat with w in windows
                repeat with t in (tabs of w)
                    try
                        set currentURL to URL of t
                        if \(check) then tell w to close t
                    end try
                end repeat
            end repeat
        end tell
        """
        runScript(script)
    }

    private func enforceChrome(domains: [String], isAllowlist: Bool) {
        let conditions = domains.map { "tabURL contains \"\($0)\"" }.joined(separator: " or ")
        let check = isAllowlist ? "not (\(conditions))" : conditions

        let script = """
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in (tabs of w)
                    try
                        set tabURL to URL of t
                        if \(check) then tell w to close t
                    end try
                end repeat
            end repeat
        end tell
        """
        runScript(script)
    }

    private func runScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            
            // Error -1743 = errAEEventNotPermitted (User clicked "Don't Allow")
            if let errNum = error?[NSAppleScript.errorNumber] as? Int, errNum == -1743 {
                DispatchQueue.main.async {
                    self.showPermissionAlert()
                }
            }
        }
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
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}