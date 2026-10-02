import Foundation
import AppKit
import Darwin

enum ListMode: String, CaseIterable, Codable {
    case blocklist = "Blocklist"
    case allowlist = "Allowlist"
}

class AppBlocker {
    static let shared = AppBlocker()

    // Always allowed to run. 
    private let safeBundleIDs: Set<String> = ["com.apple.finder", "com.apple.systempreferences"]

    // Tools that could end or undo a session. Blocked in every mode, unless explicitly allowlisted.
    private let tamperToolIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "org.alacritty",
        "net.kovidgoyal.kitty", "com.github.wez.wezterm", "com.apple.ActivityMonitor",
        "com.apple.ScriptEditor2", "com.apple.Automator", "com.apple.shortcuts"
    ]

    // Browsers whose tabs can't be read or closed, so they can't be filtered by website.
    // Blocked whenever a website list is active, unless explicitly allowlisted.
    private let unfilterableBrowserIDs: Set<String> = [
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "app.zen-browser.zen", "org.torproject.torbrowser", "com.duckduckgo.macos.browser", "com.kagi.kagimacos"
    ]

    private var mode: ListMode = .blocklist
    private var appSet: Set<String> = []
    private var blockUnfilterableBrowsers = false
    private var pendingKills: Set<pid_t> = []

    func configure(mode: ListMode, apps: [String], blockUnfilterableBrowsers: Bool) {
        self.mode = mode
        appSet = Set(apps.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
        self.blockUnfilterableBrowsers = blockUnfilterableBrowsers
    }

    /// Full sweep over everything currently running
    func enforce() {
        if mode == .allowlist && appSet.isEmpty { return }   // an empty allowlist never kills anything
        for app in NSWorkspace.shared.runningApplications { check(app) }
    }

    /// Checks a single app. Also called the moment an app launches.
    func check(_ app: NSRunningApplication) {
        if app.isTerminated || app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        if mode == .allowlist && appSet.isEmpty { return }

        let bundleID = app.bundleIdentifier ?? ""
        if safeBundleIDs.contains(bundleID), app.bundleURL?.path.hasPrefix("/System/") == true { return }

        var namesToCheck: Set<String> = []
        if let localized = app.localizedName?.lowercased().trimmingCharacters(in: .whitespaces) {
            namesToCheck.insert(localized)
        }
        if let bundleName = app.bundleURL?.deletingPathExtension().lastPathComponent.lowercased().trimmingCharacters(in: .whitespaces) {
            namesToCheck.insert(bundleName)
        }
        if let execName = app.executableURL?.lastPathComponent.lowercased().trimmingCharacters(in: .whitespaces) {
            namesToCheck.insert(execName)
        }
        guard !namesToCheck.isEmpty else { return }

        let isMatch = !namesToCheck.isDisjoint(with: appSet)

        // Anything that could undo the session is blocked in both mode. Only an allowlist lets it through
        let restricted = tamperToolIDs.contains(bundleID)
            || (blockUnfilterableBrowsers && unfilterableBrowserIDs.contains(bundleID))
        if restricted {
            if !(mode == .allowlist && isMatch) { killProcess(app) }
            return
        }

        switch mode {
        case .blocklist:
            if isMatch { killProcess(app) }
        case .allowlist:
            // Regular apps are always candidates. Accessory/prohibited apps (launchers, some game clients)
            // only count if they are a top-level .app in an Applications folder, so helper processes
            // nested inside allowed apps (e.g. Chrome helpers) are left alone.
            guard app.activationPolicy == .regular || isTopLevelUserApp(app) else { return }
            // Browsers we can filter by website are exempt; the website blocker handles them instead
            if !WebsiteBlocker.isScriptableBrowser(app) && !isMatch { killProcess(app) }
        }
    }

    /// True for a top-level .app bundle in /Applications or ~/Applications,
    /// excluding system locations and apps nested inside other bundles.
    private func isTopLevelUserApp(_ app: NSRunningApplication) -> Bool {
        guard let path = app.bundleURL?.path, path.hasSuffix(".app"),
              !path.hasPrefix("/System/"), path.contains("/Applications/") else { return false }
        // Exactly one ".app" component means it isn't nested inside another app
        return path.components(separatedBy: "/").filter { $0.hasSuffix(".app") }.count == 1
    }

    /// forceTerminate() returning true only means the request was sent, not that the process died,
    /// so verify shortly after and escalate to a direct SIGKILL if it's still alive.
    private func killProcess(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard !pendingKills.contains(pid) else { return }
        pendingKills.insert(pid)
        _ = app.forceTerminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.pendingKills.remove(pid)
            if !app.isTerminated { _ = kill(pid, SIGKILL) }
        }
    }
}