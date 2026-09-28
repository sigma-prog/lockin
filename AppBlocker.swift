import Foundation
import AppKit
import Darwin

enum ListMode: String, CaseIterable {
    case blocklist = "Blocklist"
    case allowlist = "Allowlist"
}

class AppBlocker {
    static let shared = AppBlocker()

    // Allow these
    private let safeSystemApps: Set<String> = [
    "finder",          
    "terminal",        
    "iterm2",        
    "system settings",  
]

    func enforce(mode: ListMode, apps: [String]) {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let appSet = Set(apps.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })

        // Never kill all apps if the Allowlist is empty
        if mode == .allowlist && appSet.isEmpty {
            return
        }

        for app in NSWorkspace.shared.runningApplications {
            if app.processIdentifier == currentPID { continue }

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

            guard !namesToCheck.isEmpty else { continue }
            if !namesToCheck.isDisjoint(with: safeSystemApps) { continue }

            let isMatch = !namesToCheck.isDisjoint(with: appSet)

            if mode == .blocklist {
                if isMatch { killProcess(app) }
            } else if mode == .allowlist {
                guard app.activationPolicy == .regular else { continue }
                let isBrowser = namesToCheck.contains("safari") || namesToCheck.contains("google chrome")
                if !isBrowser && !isMatch {
                    killProcess(app)
                }
            }
        }
    }

    private func killProcess(_ app: NSRunningApplication) {
        if !app.forceTerminate() {
            kill(app.processIdentifier, SIGKILL)
        }
    }
}