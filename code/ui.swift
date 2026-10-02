import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Darwin
import CryptoKit

// Shared constants
private let defaults = UserDefaults.standard
private enum Key {
    static let appMode = "lockin_mode", siteMode = "lockin_website_mode", apps = "lockin_apps", domains = "lockin_blocked_domains"
}
private enum Limits { static let maxSeconds = 43_200, extensionSeconds = 900 }
private enum Palette {
    static let background = Color(red: 0.90, green: 0.90, blue: 0.91), textDark = Color(red: 0.15, green: 0.15, blue: 0.15)
    static let textLabel = Color(red: 0.20, green: 0.20, blue: 0.20), bar = Color(red: 0.25, green: 0.25, blue: 0.25)
    static let summary = Color(red: 0.35, green: 0.35, blue: 0.35)
}
// Authoritative lock state lives in memory, so editing saved preferences can't unlock a running session
private var sessionIsLocked = false

// clock that keeps counting through sleep, so changing the system time can't cheat the timer
func getMonotonicTime() -> Double {
    var info = mach_timebase_info()
    mach_timebase_info(&info)
    return (Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom)) / 1_000_000_000.0
}

private struct SessionRecord: Codable {
    var targetMono: Double
    var wallEnd: Double
    var total: Int
    var config: BlockConfig
}

private enum SessionStore {
    private static let secret = SymmetricKey(data: Data(("lockin.session.v1." + NSUserName() + ".7f3a9c1e").utf8))
    private static let defaultsKey = "lockin_session_v1"
    private static let fm = FileManager.default
    private static let tagLength = 32

    private static var fileURLs: [URL] {
        let home = fm.homeDirectoryForCurrentUser
        return [home.appendingPathComponent("Library/Application Support/Lockin/.session"),
                home.appendingPathComponent("Library/Caches/com.lockin.cache/.state")]
    }

    private static func tag(for payload: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: payload, using: secret))
    }

    private static func decode(_ data: Data) -> SessionRecord? {
        guard data.count > tagLength else { return nil }
        let payload = Data(data.prefix(data.count - tagLength))
        guard Data(data.suffix(tagLength)) == tag(for: payload) else { return nil }
        return try? JSONDecoder().decode(SessionRecord.self, from: payload)
    }

    static func save(_ record: SessionRecord) {
        guard let payload = try? JSONEncoder().encode(record) else { return }
        let blob = payload + tag(for: payload)
        defaults.set(blob, forKey: defaultsKey)
        for url in fileURLs {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? blob.write(to: url, options: .atomic)
        }
    }

    static func load() -> SessionRecord? {
        var blobs: [Data] = []
        if let d = defaults.data(forKey: defaultsKey) { blobs.append(d) }
        blobs += fileURLs.compactMap { try? Data(contentsOf: $0) }
        return blobs.compactMap(decode).max { $0.wallEnd < $1.wallEnd }
    }

    static func clear() {
        defaults.removeObject(forKey: defaultsKey)
        fileURLs.forEach { try? fm.removeItem(at: $0) }
    }
}

// Persistence
enum PersistenceManager {
    static let label = "com.lockin.app"
    private static let fm = FileManager.default
    private static var serviceTarget: String { "gui/\(getuid())/\(label)" }
    private static var plistURL: URL { fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    static func installSupervisor() {
        guard let execPath = Bundle.main.executablePath ?? CommandLine.arguments.first else { return }
        let fullPath = execPath.hasPrefix("/") ? execPath
            : URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(execPath).standardized.path
        try? fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>ProgramArguments</key><array><string>\(fullPath)</string></array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
            <key>ThrottleInterval</key><integer>1</integer>
        </dict>
        </plist>
        """
        try? plist.write(to: plistURL, atomically: true, encoding: .utf8)

        if launchctl(["print", serviceTarget]) != 0 {
            launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])   // first time: load and start
        } else {
            launchctl(["kickstart", serviceTarget])                       // already loaded: start it if it isn't running
        }
    }

    static func removeSupervisor() {
        try? fm.removeItem(at: plistURL)
    }
}

// App delegate (blocks Cmd+Q and quitting while locked)
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isCmdQ = event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "q"
            if isCmdQ && sessionIsLocked { NSSound.beep(); return nil }
            return event
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.forEach { $0.makeKeyAndOrderFront(self) } }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if sessionIsLocked { NSSound.beep(); return .terminateCancel }
        return .terminateNow
    }
}
/// Disables the close/minimize buttons while a session is locked
struct WindowAccessor: NSViewRepresentable {
    var isLocked: Bool
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { update(view.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { update(nsView.window) }
    private func update(_ window: NSWindow?) {
        window?.standardWindowButton(.closeButton)?.isEnabled = !isLocked
        window?.standardWindowButton(.miniaturizeButton)?.isEnabled = !isLocked
    }
}

struct HoverBtn: ButtonStyle {
    var disabled = false
    var w: CGFloat? = nil
    var h: CGFloat? = nil
    var size: CGFloat = 10
    var bold = false
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let active = hovered && !disabled
        return configuration.label
            .font(.system(size: size, weight: bold ? .semibold : .medium))
            .foregroundColor(disabled ? .secondary : (hovered ? .black : .primary))
            .frame(width: w, height: h)
            .padding(.horizontal, w == nil ? 8 : 0).padding(.vertical, h == nil ? 3 : 0)
            .background(Color.white.opacity(disabled ? 0.45 : (hovered ? 1.0 : 0.92)))
            .cornerRadius(5)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(active ? 0.6 : 0.3), lineWidth: 1))
            .shadow(color: .black.opacity(active ? 0.08 : 0.03), radius: hovered ? 2 : 1, y: 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .onHover { if !disabled { hovered = $0 } }
    }
}

// Blocker engine
struct BlockConfig: Codable {
    var appMode: ListMode
    var apps: [String]
    var siteMode: ListMode
    var sites: [String]
}

class BlockerEngine {
    static let shared = BlockerEngine()
    private var timers: [Timer] = []
    private var launchObserver: NSObjectProtocol?
    private(set) var isRunning = false

    func start(_ config: BlockConfig) {
        stop()
        isRunning = true
        AppBlocker.shared.configure(mode: config.appMode, apps: config.apps, blockUnfilterableBrowsers: !config.sites.isEmpty)
        WebsiteBlocker.shared.configure(mode: config.siteMode, domains: config.sites)
        AppBlocker.shared.enforce()
        WebsiteBlocker.shared.enforce()

        schedule(every: 2) { AppBlocker.shared.enforce() }     
        schedule(every: 1) { WebsiteBlocker.shared.enforce() }


        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard self?.isRunning == true,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            AppBlocker.shared.check(app)
        }
    }

    func stop() {
        isRunning = false
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        if let observer = launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        launchObserver = nil
    }

    private func schedule(every interval: TimeInterval, _ work: @escaping () -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard self?.isRunning == true else { return }
            work()
        }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }
}

struct AppIconView: View {
    let appName: String
    private static let searchDirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
    private static var cache: [String: NSImage] = [:]

    private static func icon(for name: String) -> NSImage {
        if let cached = cache[name] { return cached }
        let path = searchDirs.map { "\($0)/\(name).app" }.first { FileManager.default.fileExists(atPath: $0) }
        let image = path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .application)
        cache[name] = image
        return image
    }

    var body: some View { Image(nsImage: Self.icon(for: appName)).resizable().frame(width: 18, height: 18) }
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
    var isWeb = false
    var onSave: () -> Void
    @State private var input = ""

    private func addItem(_ value: String) {
        let clean = isWeb
            ? value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "www.", with: "").lowercased()
            : value
        guard !clean.isEmpty, !items.contains(clean) else { return }
        items.append(clean); input = ""; onSave()
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { panel.urls.forEach { addItem($0.deletingPathExtension().lastPathComponent) } }
    }

    private func row(for item: String) -> some View {
        HStack(spacing: 8) {
            if isWeb { Image(systemName: "globe").font(.system(size: 12)).foregroundColor(.secondary) } else { AppIconView(appName: item) }
            Text(item).font(.system(size: 12))
            Spacer()
            Button { items.removeAll { $0 == item }; onSave() } label: {
                Image(systemName: "trash").font(.system(size: 10)).foregroundColor(.red.opacity(0.8))
            }.buttonStyle(.plain)
        }
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
                    Button("Add") { addItem(input) }.buttonStyle(.bordered).controlSize(.small)
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            List {
                if items.isEmpty { Text("No items added yet.").font(.system(size: 11)).foregroundColor(.secondary).padding(.vertical, 8) }
                ForEach(items, id: \.self) { row(for: $0) }
            }.listStyle(.inset).frame(height: 140).cornerRadius(6)

            HStack {
                if !isWeb { Button("+ Add App...", action: pickApp).buttonStyle(.bordered).controlSize(.small) }
                Spacer()
                Button("Done") { isPresented = false }.buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(16).frame(width: 360, height: isWeb ? 315 : 270).background(Color(NSColor.windowBackgroundColor))
    }
}

// Main view
struct ContentView: View {
    @State private var totalMinutes: Double = 90
    @State private var hoursText = "1"
    @State private var minsText = "30"
    @State private var errorMessage: String? = nil
    @State private var isLocked = false
    @State private var remainingSeconds = 0
    @State private var sessionStartSeconds = 1
    @State private var targetMonotonicTime: Double = 0
    @State private var wallEndTime: Double = 0
    @State private var lockedConfig = BlockConfig(appMode: .blocklist, apps: [], siteMode: .blocklist, sites: [])
    @State private var ticks = 0
    @State private var showApps = false
    @State private var showSites = false
    @State private var listMode = ListMode(rawValue: defaults.string(forKey: Key.appMode) ?? "") ?? .blocklist
    @State private var websiteMode = ListMode(rawValue: defaults.string(forKey: Key.siteMode) ?? "") ?? .blocklist
    @State private var selectedApps = defaults.stringArray(forKey: Key.apps) ?? []
    @State private var blockedDomains = defaults.stringArray(forKey: Key.domains) ?? []
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var config: BlockConfig { BlockConfig(appMode: listMode, apps: selectedApps, siteMode: websiteMode, sites: blockedDomains) }

    private func summarize(_ list: [String], _ mode: ListMode, _ emptyAllow: String) -> String {
        if list.isEmpty { return mode == .blocklist ? "none" : emptyAllow }
        return list.count <= 2 ? list.joined(separator: ", ") : "\(list.prefix(2).joined(separator: ", ")), +\(list.count - 2)"
    }

    private var statusSummary: String {
        let verb = { (m: ListMode) in m == .blocklist ? "Blocking" : "Allowing" }
        return "\(verb(listMode)) apps: \(summarize(selectedApps, listMode, "no restrictions"))  •  \(verb(websiteMode)) sites: \(summarize(blockedDomains, websiteMode, "no restrictions"))"
    }

    private var countdownStr: String {
        let h = remainingSeconds / 3600, m = (remainingSeconds % 3600) / 60, s = remainingSeconds % 60
        return h > 0 ? String(format: "%d hr %02d min %02d sec remaining", h, m, s) : String(format: "%02d min %02d sec remaining", m, s)
    }

    private var progressFraction: CGFloat {
        guard sessionStartSeconds > 0 else { return 0 }
        return min(max(CGFloat(Double(remainingSeconds) / Double(sessionStartSeconds)), 0), 1)
    }

    // Actions
    private func save() {
        defaults.set(selectedApps, forKey: Key.apps); defaults.set(listMode.rawValue, forKey: Key.appMode)
        defaults.set(blockedDomains, forKey: Key.domains); defaults.set(websiteMode.rawValue, forKey: Key.siteMode)
    }

    private func validate() {
        let total = ((Int(hoursText) ?? 0) * 60) + (Int(minsText) ?? 0)
        errorMessage = total < 1 ? "Invalid (min 1m)" : (total > 720 ? "Invalid (max 12h)" : nil)
        if errorMessage == nil { totalMinutes = Double(total) }
    }

    private func persist() {
        SessionStore.save(SessionRecord(targetMono: targetMonotonicTime, wallEnd: wallEndTime,
                                        total: sessionStartSeconds, config: lockedConfig))
    }

    private func beginBlocking() {
        sessionIsLocked = true
        PersistenceManager.installSupervisor()
        BlockerEngine.shared.start(lockedConfig)
    }

    private func start() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        validate()
        guard errorMessage == nil else { return }
        let secs = Int(totalMinutes * 60)
        targetMonotonicTime = getMonotonicTime() + Double(secs)
        wallEndTime = Date().timeIntervalSince1970 + Double(secs)
        lockedConfig = config
        remainingSeconds = secs; sessionStartSeconds = secs; isLocked = true
        persist()
        beginBlocking()
    }

    private func addTime() {
        let extra = Limits.extensionSeconds
        targetMonotonicTime += Double(extra)
        wallEndTime += Double(extra)
        remainingSeconds = min(remainingSeconds + extra, Limits.maxSeconds)
        sessionStartSeconds = max(sessionStartSeconds, remainingSeconds)
        persist()
    }

    private func endSession() {
        isLocked = false; remainingSeconds = 0
        sessionIsLocked = false
        SessionStore.clear()
        PersistenceManager.removeSupervisor()
        BlockerEngine.shared.stop()
    }

    /// Resumes a saved session on launch 
    private func checkActiveSession() {
        guard let saved = SessionStore.load() else { return endSession() }
        let nowMono = getMonotonicTime()
        var left = Int(saved.targetMono - nowMono)

        // Clock reset (e.g. after reboot)
        if left < 0 || nowMono < (saved.targetMono - Double(max(saved.total, 1) + 3600)) {
            left = Int(saved.wallEnd - Date().timeIntervalSince1970)
            targetMonotonicTime = nowMono + Double(max(left, 0))
        } else {
            targetMonotonicTime = saved.targetMono
        }
        guard left > 0 else { return endSession() }

        wallEndTime = saved.wallEnd
        lockedConfig = saved.config
        listMode = saved.config.appMode; selectedApps = saved.config.apps
        websiteMode = saved.config.siteMode; blockedDomains = saved.config.sites
        remainingSeconds = left; sessionStartSeconds = max(saved.total, left); isLocked = true
        persist()
        beginBlocking()
    }

    private func tickCountdown() {
        guard isLocked else { return }
        let diff = Int(targetMonotonicTime - getMonotonicTime())
        guard diff > 0 else { return endSession() }
        remainingSeconds = diff
        ticks += 1
        if ticks % 3 == 0 { persist() }   
    }

    // Subviews
    @ViewBuilder private var statusPill: some View {
        if isLocked {
            Text("Blocking").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary).frame(width: 110, height: 24)
                .background(Color.white.opacity(0.6)).cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.2), lineWidth: 1)).padding(.top, 2)
        } else {
            Button("Start Blocking", action: start).buttonStyle(HoverBtn(disabled: errorMessage != nil, w: 110, h: 24, size: 12))
                .disabled(errorMessage != nil).opacity(errorMessage != nil ? 0.6 : 1.0).padding(.top, 2)
        }
    }

    private var lockedProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(countdownStr).font(.system(size: 13)).monospacedDigit().foregroundColor(Palette.textDark)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.25)).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(Palette.bar).frame(width: max(0, g.size.width * progressFraction), height: 4)
                }
            }.frame(height: 20)
        }
    }

    private var timeInputs: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    TimeBox(text: $hoursText, hasError: errorMessage != nil, onChange: validate)
                    Text(hoursText == "1" ? "hour" : "hours").font(.system(size: 12)).foregroundColor(Palette.textLabel)
                }
                HStack(spacing: 4) {
                    TimeBox(text: $minsText, hasError: errorMessage != nil, onChange: validate)
                    Text("minutes").font(.system(size: 12)).foregroundColor(Palette.textLabel)
                }
                if let err = errorMessage { Text(err).font(.system(size: 11, weight: .medium)).foregroundColor(.red).padding(.leading, 4) }
                Spacer()
            }
            Slider(value: $totalMinutes, in: 1...720).accentColor(Palette.bar)
                .onChange(of: totalMinutes) { _, v in
                    let rounded = Int(v.rounded())
                    hoursText = "\(rounded / 60)"; minsText = "\(rounded % 60)"; errorMessage = nil
                }
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(statusSummary).font(.system(size: 10)).foregroundColor(Palette.summary).lineLimit(2).minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                Button("Apps") { showApps = true }.buttonStyle(HoverBtn(disabled: isLocked)).disabled(isLocked)
                Button("Sites") { showSites = true }.buttonStyle(HoverBtn(disabled: isLocked)).disabled(isLocked)
            }
        }.frame(height: 42)
    }

    private var extendButton: some View {
        let atMax = remainingSeconds >= Limits.maxSeconds
        return Button("+ 15m", action: addTime).buttonStyle(HoverBtn(disabled: atMax, size: 11, bold: true))
            .padding([.top, .trailing], 10).disabled(atMax)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Palette.background.contentShape(Rectangle()).onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
            VStack(spacing: 12) {
                statusPill
                if isLocked { lockedProgress } else { timeInputs }
                Spacer(minLength: 2)
                footer
            }.padding(.horizontal, 22).padding(.vertical, 14)
            if isLocked { extendButton }
        }
        .frame(width: 500, height: 175)
        .background(WindowAccessor(isLocked: isLocked))
        .onAppear { checkActiveSession() }
        .onReceive(timer) { _ in tickCountdown() }
        .sheet(isPresented: $showApps) {
            ListEditorSheet(title: "Manage Apps", placeholder: "",
                subtitle: { $0 == .blocklist ? "Blocklist: unapproved apps will be blocked." : "Allowlist: only chosen apps will be allowed." },
                isPresented: $showApps, mode: $listMode, items: $selectedApps, onSave: save)
        }
        .sheet(isPresented: $showSites) {
            ListEditorSheet(title: "Manage Websites", placeholder: "e.g. youtube.com",
                subtitle: { $0 == .blocklist ? "Blocklist: Tabs with these domains will be closed." : "Allowlist: Only tabs with these domains will stay open." },
                isPresented: $showSites, mode: $websiteMode, items: $blockedDomains, isWeb: true, onSave: save)
        }
    }
}

private func enforceSingleInstance() {
    let myPID = ProcessInfo.processInfo.processIdentifier
    guard let myExecutable = Bundle.main.executableURL?.standardizedFileURL else { return }
    let others = NSWorkspace.shared.runningApplications.filter {
        $0.processIdentifier != myPID && $0.executableURL?.standardizedFileURL == myExecutable
    }
    guard let existing = others.first else { return }
    if getppid() == 1 { others.forEach { $0.forceTerminate() } } else { existing.activate(); exit(0) }
}

private func showAboutPanel() {
    let text = NSMutableAttributedString(string: "By Lucas H\n\n")
    text.append(NSAttributedString(string: "GitHub Repository", attributes: [
        .link: URL(string: "https://github.com/sigma-prog/lockin")!, .underlineStyle: NSUnderlineStyle.single.rawValue]))
    NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: text])
}

@main
struct LockinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        enforceSingleInstance()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup { ContentView() }
            .windowResizability(.contentSize)
            .commands { CommandGroup(replacing: .appInfo) { Button("About Lockin", action: showAboutPanel) } }
    }
}