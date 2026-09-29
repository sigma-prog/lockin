import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Darwin

// Time checking
func getMonotonicTime() -> Double {
    var info = mach_timebase_info()
    mach_timebase_info(&info)
    return (Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom)) / 1_000_000_000.0
}

// Open back up 
class PersistenceManager {
    static let label = "com.lockin.app"

    static func installSupervisor() {
        guard let execPath = Bundle.main.executablePath ?? CommandLine.arguments.first else { return }
        let fullPath = execPath.hasPrefix("/") ? execPath : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(execPath).standardized.path

        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        let plistURL = launchAgentsDir.appendingPathComponent("\(label).plist")
        try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(fullPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ThrottleInterval</key>
            <integer>1</integer>
        </dict>
        </plist>
        """

        try? plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
        let uid = "\(getuid())"

        let bootstrap = Process()
        bootstrap.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootstrap.arguments = ["bootstrap", "gui/\(uid)", plistURL.path]
        try? bootstrap.run()
        bootstrap.waitUntilExit()
    }

    static func removeSupervisor() {
        let uid = "\(getuid())"
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "gui/\(uid)/\(label)"]
        try? bootout.run()
        bootout.waitUntilExit()

        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        let plistURL = launchAgentsDir.appendingPathComponent("\(label).plist")
        try? FileManager.default.removeItem(at: plistURL)
    }
}

// Intercepter
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "q" {
                if UserDefaults.standard.bool(forKey: "lockin_is_locked") {
                    NSSound.beep()
                    return nil
                }
            }
            return event
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if UserDefaults.standard.bool(forKey: "lockin_is_locked") {
            NSSound.beep()
            return .terminateCancel
        }
        return .terminateNow
    }
}

// Removes close button
struct WindowAccessor: NSViewRepresentable {
    var isLocked: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { update(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        update(nsView.window)
    }

    private func update(_ window: NSWindow?) {
        guard let window = window else { return }
        window.standardWindowButton(.closeButton)?.isEnabled = !isLocked
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = !isLocked
    }
}

// Button Style and Engine
struct HoverBtn: ButtonStyle {
    var disabled = false
    var w: CGFloat? = nil
    var h: CGFloat? = nil
    var size: CGFloat = 10
    var bold = false
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: bold ? .semibold : .medium))
            .foregroundColor(disabled ? .secondary : (hovered ? .black : .primary))
            .frame(width: w, height: h)
            .padding(.horizontal, w == nil ? 8 : 0)
            .padding(.vertical, h == nil ? 3 : 0)
            .background(Color.white.opacity(disabled ? 0.45 : (hovered ? 1.0 : 0.92)))
            .cornerRadius(5)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(hovered && !disabled ? Color.gray.opacity(0.6) : Color.gray.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(hovered && !disabled ? 0.08 : 0.03), radius: hovered ? 2 : 1, y: 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .onHover { if !disabled { hovered = $0 } }
    }
}

class BlockerEngine {
    static let shared = BlockerEngine()
    private var timer: Timer?
    private(set) var isRunning = false

    func start(mode: ListMode, apps: [String], siteMode: ListMode, sites: [String]) {
        stop()
        isRunning = true
        let tick = { [weak self] in
            guard let self = self, self.isRunning else { return }
            AppBlocker.shared.enforce(mode: mode, apps: apps)
            WebsiteBlocker.shared.enforce(mode: siteMode, domains: sites)
        }
        tick()
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in tick() }
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
}

// stuff
struct AppIconView: View {
    let appName: String
    var body: some View {
        let paths = ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"].map { "\($0)/\(appName).app" }
        let path = paths.first { FileManager.default.fileExists(atPath: $0) }
        let icon = path != nil ? NSWorkspace.shared.icon(forFile: path!) : NSWorkspace.shared.icon(for: .application)
        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
    }
}

struct TimeBox: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    var hasError: Bool
    var onChange: () -> Void

    var body: some View {
        TextField("0", text: $text)
            .focused($focused).textFieldStyle(.plain).multilineTextAlignment(.center)
            .font(.system(size: 12, weight: .medium)).frame(width: 32, height: 20)
            .background(Color(NSColor.controlBackgroundColor)).cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(hasError ? Color.red : (focused ? Color.accentColor : Color.gray.opacity(0.35)), lineWidth: 1))
            .onChange(of: text) { _, v in text = String(v.filter(\.isNumber).prefix(3)); onChange() }
            .onSubmit { if text.isEmpty { text = "0" }; focused = false; onChange() }
    }
}

struct ListEditorSheet: View {
    let title: String
    let placeholder: String
    let subtitle: (ListMode) -> String
    @Binding var isPresented: Bool
    @Binding var mode: ListMode
    @Binding var items: [String]
    var isWeb: Bool = false
    var onSave: () -> Void

    @State private var input = ""

    func addItem(_ val: String) {
        let clean = isWeb ? val.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "www.", with: "").lowercased() : val
        if !clean.isEmpty && !items.contains(clean) { items.append(clean); input = ""; onSave() }
    }

    func pickApp() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]; p.directoryURL = URL(fileURLWithPath: "/Applications"); p.allowsMultipleSelection = true
        if p.runModal() == .OK { p.urls.forEach { addItem($0.deletingPathExtension().lastPathComponent) } }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Picker("Mode", selection: $mode) { ForEach(ListMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).frame(width: 220).onChange(of: mode) { _, _ in onSave() }
            Text(subtitle(mode)).font(.system(size: 10)).foregroundColor(.secondary).multilineTextAlignment(.center)

            if isWeb {
                HStack(spacing: 8) {
                    TextField(placeholder, text: $input).textFieldStyle(.roundedBorder).font(.system(size: 12)).onSubmit { addItem(input) }
                    Button("Add") { addItem(input) }.buttonStyle(.bordered).controlSize(.small).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            List {
                if items.isEmpty { Text("No items added yet.").font(.system(size: 11)).foregroundColor(.secondary).padding(.vertical, 8) }
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 8) {
                        if isWeb { Image(systemName: "globe").font(.system(size: 12)).foregroundColor(.secondary) } else { AppIconView(appName: item) }
                        Text(item).font(.system(size: 12))
                        Spacer()
                        Button { items.removeAll { $0 == item }; onSave() } label: { Image(systemName: "trash").font(.system(size: 10)).foregroundColor(.red.opacity(0.8)) }.buttonStyle(.plain)
                    }
                }
            }.listStyle(.inset).frame(height: 140).cornerRadius(6)

            HStack {
                if !isWeb { Button("+ Add App...", action: pickApp).buttonStyle(.bordered).controlSize(.small) }
                Spacer()
                Button("Done") { isPresented = false }.buttonStyle(.borderedProminent).controlSize(.small)
            }
        }.padding(16).frame(width: 360, height: isWeb ? 315 : 270).background(Color(NSColor.windowBackgroundColor))
    }
}

// Main View
struct ContentView: View {
    @State private var totalMinutes: Double = 90
    @State private var hoursText: String = "1"
    @State private var minsText: String = "30"
    @State private var errorMessage: String? = nil
    @State private var isLocked: Bool = false
    @State private var remainingSeconds: Int = 0
    @State private var sessionStartSeconds: Int = 1
    @State private var targetMonotonicTime: Double = 0
    @State private var showApps: Bool = false
    @State private var showSites: Bool = false

    @State private var listMode: ListMode = ListMode(rawValue: UserDefaults.standard.string(forKey: "lockin_mode") ?? "") ?? .blocklist
    @State private var websiteMode: ListMode = ListMode(rawValue: UserDefaults.standard.string(forKey: "lockin_website_mode") ?? "") ?? .blocklist
    @State private var selectedApps: [String] = UserDefaults.standard.stringArray(forKey: "lockin_apps") ?? []
    @State private var blockedDomains: [String] = UserDefaults.standard.stringArray(forKey: "lockin_blocked_domains") ?? []

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var statusSummary: String {
        let fmt = { (list: [String], mode: ListMode, def: String) in
            list.isEmpty ? (mode == .blocklist ? "none" : def) : (list.count <= 2 ? list.joined(separator: ", ") : "\(list.prefix(2).joined(separator: ", ")), +\(list.count - 2)")
        }
        return "\(listMode == .blocklist ? "Blocking" : "Allowing") apps: \(fmt(selectedApps, listMode, "Safari & Chrome only"))  •  \(websiteMode == .blocklist ? "Blocking" : "Allowing") sites: \(fmt(blockedDomains, websiteMode, "none"))"
    }

    var countdownStr: String {
        let h = remainingSeconds / 3600, m = (remainingSeconds % 3600) / 60, s = remainingSeconds % 60
        return h > 0 ? String(format: "%d hr %02d min %02d sec remaining", h, m, s) : String(format: "%02d min %02d sec remaining", m, s)
    }

    var progressFraction: CGFloat {
        guard sessionStartSeconds > 0 else { return 0 }
        let fraction = CGFloat(Double(remainingSeconds) / Double(sessionStartSeconds))
        return min(max(fraction, 0.0), 1.0)
    }

    func save() {
        UserDefaults.standard.set(selectedApps, forKey: "lockin_apps")
        UserDefaults.standard.set(listMode.rawValue, forKey: "lockin_mode")
        UserDefaults.standard.set(blockedDomains, forKey: "lockin_blocked_domains")
        UserDefaults.standard.set(websiteMode.rawValue, forKey: "lockin_website_mode")
    }

    func validate() {
        let t = ((Int(hoursText) ?? 0) * 60) + (Int(minsText) ?? 0)
        errorMessage = t < 1 ? "Invalid (min 1m)" : (t > 720 ? "Invalid (max 12h)" : nil)
        if errorMessage == nil { totalMinutes = Double(t) }
    }

    func start() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        validate()
        guard errorMessage == nil else { return }

        let secs = Int(totalMinutes * 60)
        let nowMono = getMonotonicTime()
        targetMonotonicTime = nowMono + Double(secs)

        UserDefaults.standard.set(true, forKey: "lockin_is_locked")
        UserDefaults.standard.set(targetMonotonicTime, forKey: "lockin_target_mono")
        UserDefaults.standard.set(secs, forKey: "lockin_total_sec")
        UserDefaults.standard.set(Date().timeIntervalSince1970 + Double(secs), forKey: "lockin_wall_end")

        remainingSeconds = secs
        sessionStartSeconds = secs
        isLocked = true

        PersistenceManager.installSupervisor()
        BlockerEngine.shared.start(mode: listMode, apps: selectedApps, siteMode: websiteMode, sites: blockedDomains)
    }

    func addTime() {
        targetMonotonicTime += 900
        UserDefaults.standard.set(targetMonotonicTime, forKey: "lockin_target_mono")
        let currentWall = UserDefaults.standard.double(forKey: "lockin_wall_end")
        UserDefaults.standard.set(currentWall + 900, forKey: "lockin_wall_end")
        remainingSeconds = min(remainingSeconds + 900, 43200)
        sessionStartSeconds = max(sessionStartSeconds, remainingSeconds)
        UserDefaults.standard.set(sessionStartSeconds, forKey: "lockin_total_sec")
    }

    func endSession() {
        isLocked = false
        remainingSeconds = 0
        UserDefaults.standard.set(false, forKey: "lockin_is_locked")
        UserDefaults.standard.removeObject(forKey: "lockin_target_mono")
        UserDefaults.standard.removeObject(forKey: "lockin_total_sec")
        UserDefaults.standard.removeObject(forKey: "lockin_wall_end")
        
        PersistenceManager.removeSupervisor()
        BlockerEngine.shared.stop()
    }

    func checkActiveSession() {
        guard UserDefaults.standard.bool(forKey: "lockin_is_locked") else {
            endSession()
            return
        }

        let savedTotal = UserDefaults.standard.integer(forKey: "lockin_total_sec")
        let savedMono = UserDefaults.standard.double(forKey: "lockin_target_mono")
        let nowMono = getMonotonicTime()

        var left = Int(savedMono - nowMono)

        if left < 0 || nowMono < (savedMono - Double(max(savedTotal, 1) + 3600)) {
            let wallEnd = UserDefaults.standard.double(forKey: "lockin_wall_end")
            left = Int(wallEnd - Date().timeIntervalSince1970)
            targetMonotonicTime = nowMono + Double(max(left, 0))
            UserDefaults.standard.set(targetMonotonicTime, forKey: "lockin_target_mono")
        } else {
            targetMonotonicTime = savedMono
        }

        if left > 0 {
            remainingSeconds = left
            sessionStartSeconds = max(savedTotal, left)
            isLocked = true
            PersistenceManager.installSupervisor()
            BlockerEngine.shared.start(mode: listMode, apps: selectedApps, siteMode: websiteMode, sites: blockedDomains)
        } else {
            endSession()
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(red: 0.90, green: 0.90, blue: 0.91)
                .contentShape(Rectangle())
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }

            VStack(spacing: 12) {
                if isLocked {
                    Text("Blocking").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary).frame(width: 110, height: 24)
                        .background(Color.white.opacity(0.6)).cornerRadius(5).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.2), lineWidth: 1)).padding(.top, 2)
                } else {
                    Button("Start Blocking", action: start).buttonStyle(HoverBtn(disabled: errorMessage != nil, w: 110, h: 24, size: 12))
                        .disabled(errorMessage != nil).opacity(errorMessage != nil ? 0.6 : 1.0).padding(.top, 2)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if isLocked {
                        Text(countdownStr).font(.system(size: 13)).monospacedDigit().foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.25)).frame(height: 4)
                                RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.25, green: 0.25, blue: 0.25))
                                    .frame(width: max(0, g.size.width * progressFraction), height: 4)
                            }
                        }.frame(height: 20)
                    } else {
                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                TimeBox(text: $hoursText, hasError: errorMessage != nil, onChange: validate)
                                Text(hoursText == "1" ? "hour" : "hours").font(.system(size: 12)).foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                            }
                            HStack(spacing: 4) {
                                TimeBox(text: $minsText, hasError: errorMessage != nil, onChange: validate)
                                Text("minutes").font(.system(size: 12)).foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                            }
                            if let err = errorMessage { Text(err).font(.system(size: 11, weight: .medium)).foregroundColor(.red).padding(.leading, 4) }
                            Spacer()
                        }

                        Slider(value: $totalMinutes, in: 1...720)
                            .accentColor(Color(red: 0.25, green: 0.25, blue: 0.25))
                            .onChange(of: totalMinutes) { _, v in
                                let rounded = Int(v.rounded())
                                hoursText = "\(rounded / 60)"
                                minsText = "\(rounded % 60)"
                                errorMessage = nil
                            }
                    }
                }

                Spacer(minLength: 2)

                HStack(alignment: .center, spacing: 10) {
                    Text(statusSummary).font(.system(size: 10)).foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.35)).lineLimit(2).minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    HStack(spacing: 6) {
                        Button("Apps") { showApps = true }.buttonStyle(HoverBtn(disabled: isLocked)).disabled(isLocked)
                        Button("Sites") { showSites = true }.buttonStyle(HoverBtn(disabled: isLocked)).disabled(isLocked)
                    }
                }.frame(height: 42)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            if isLocked {
                Button("+ 15m", action: addTime)
                    .buttonStyle(HoverBtn(disabled: remainingSeconds >= 43200, size: 11, bold: true))
                    .padding([.top, .trailing], 10)
                    .disabled(remainingSeconds >= 43200)
            }
        }
        .frame(width: 500, height: 175)
        .background(WindowAccessor(isLocked: isLocked))
        .onAppear { checkActiveSession() }
        .sheet(isPresented: $showApps) {
            ListEditorSheet(title: "Manage Apps", placeholder: "", subtitle: { $0 == .blocklist ? "Blocklist: unapproved apps will be blocked." : "Allowlist: only chosen apps will be allowed." }, isPresented: $showApps, mode: $listMode, items: $selectedApps, onSave: save)
        }
        .sheet(isPresented: $showSites) {
            ListEditorSheet(title: "Manage Websites", placeholder: "e.g. youtube.com", subtitle: { $0 == .blocklist ? "Blocklist: Tabs with these domains will be closed." : "Allowlist: Only tabs with these domains will stay open." }, isPresented: $showSites, mode: $websiteMode, items: $blockedDomains, isWeb: true, onSave: save)
        }
        .onReceive(timer) { _ in
            guard isLocked else { return }
            let nowMono = getMonotonicTime()
            let diff = Int(targetMonotonicTime - nowMono)
            if diff > 0 {
                remainingSeconds = diff
            } else {
                endSession()
            }
        }
    }
}

// Entry Point
@main
struct LockinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Single-Instance Guard: Prevents duplicate windows
        let myPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "com.lockin.app"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }

        if let existing = others.first {
            if getppid() == 1 {
                // This instance was launched by launchd to supervise:
                // Kill the old un-supervised window so only this one remains!
                for other in others {
                    other.forceTerminate()
                }
            } else {
                // User accidentally opened a second copy: focus the existing one and exit
                existing.activate()
                exit(0)
            }
        }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Lockin") {
                    let text = NSMutableAttributedString(string: "By Lucas H\n\n")
                    let link = NSAttributedString(string: "GitHub Repository", attributes: [
                        .link: URL(string: "https://github.com/sigma-prog/lockin")!,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ])
                    text.append(link)
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .credits: text
                    ])
                }
            }
        }
    }
}