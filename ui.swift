import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ListMode: String, CaseIterable {
    case blocklist = "Blocklist"
    case allowlist = "Allowlist"
}

// Loads the real application icon from macOS
struct AppIconView: View {
    let appName: String

    var icon: NSImage {
        let paths = [
            "/Applications/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/Utilities/\(appName).app",
            NSHomeDirectory() + "/Applications/\(appName).app"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: 18, height: 18)
    }
}

// Reusable Time Box component
struct TimeBox: View {
    @Binding var text: String
    @State private var isEditing = false
    var hasError: Bool
    var onChange: () -> Void

    var body: some View {
        ZStack {
            if isEditing {
                TextField("0", text: $text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12, weight: .medium))
                    .onChange(of: text) { _, val in
                        text = String(val.filter(\.isNumber).prefix(3))
                        onChange()
                    }
                    .onSubmit {
                        isEditing = false
                        if text.isEmpty { text = "0" }
                        onChange()
                    }
            } else {
                Text(text.isEmpty ? "0" : text)
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { isEditing = true }
            }
        }
        .frame(width: 32, height: 20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(hasError ? Color.red : Color.gray.opacity(0.35), lineWidth: 1)
        )
    }
}

// Blocklist / Allowlist Modal Sheet
struct BlocklistSheet: View {
    @Binding var isPresented: Bool
    @Binding var mode: ListMode
    @Binding var apps: [String]

    func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Add to List"

        if panel.runModal() == .OK {
            for url in panel.urls {
                let name = url.deletingPathExtension().lastPathComponent
                if !apps.contains(name) {
                    apps.append(name)
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Configure App List")
                .font(.system(size: 14, weight: .semibold))

            // Blocklist / Allowlist Selector
            Picker("Mode", selection: $mode) {
                ForEach(ListMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Text(mode == .blocklist ? "Blocklist: unapproved apps will be blocked." : "Allowlist: only chosen apps will be allowed.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            // App List with Real macOS Icons
            List {
                if apps.isEmpty {
                    Text("No applications added yet.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(apps, id: \.self) { app in
                        HStack(spacing: 8) {
                            AppIconView(appName: app)
                            Text(app)
                                .font(.system(size: 12))
                            Spacer()
                            Button(action: {
                                apps.removeAll { $0 == app }
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(height: 140)
            .cornerRadius(6)

            // Bottom Buttons
            HStack {
                Button("+ Add App...") {
                    pickApp()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 360, height: 270)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ContentView: View {
    @State private var totalMinutes: Double = 90
    @State private var hoursText: String = "1"
    @State private var minsText: String = "30"
    @State private var errorMessage: String? = nil

    // Countdown state
    @State private var isLocked: Bool = false
    @State private var remainingSeconds: Int = 0
    @State private var sessionStartSeconds: Int = 0

    // Blocklist state loaded from UserDefaults
    @State private var showBlocklist: Bool = false
    @State private var listMode: ListMode = {
        if let raw = UserDefaults.standard.string(forKey: "lockin_mode"), let m = ListMode(rawValue: raw) {
            return m
        }
        return .blocklist
    }()
    @State private var selectedApps: [String] = {
        if let saved = UserDefaults.standard.stringArray(forKey: "lockin_apps") {
            return saved
        }
        return ["Discord", "Google Chrome", "Spotify"]
    }()

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var statusSummary: String {
        let prefix = listMode == .blocklist ? "Blocking" : "Only allowing"

        if selectedApps.isEmpty {
            return listMode == .blocklist ? "No apps blocked" : "Only allowing Safari"
        }

        if selectedApps.count <= 2 {
            return "\(prefix) " + selectedApps.joined(separator: ", ")
        } else {
            let displayed = selectedApps.prefix(2).joined(separator: ", ")
            let others = selectedApps.count - 2
            return "\(prefix) \(displayed), and \(others) \(others == 1 ? "other" : "others")"
        }
    }

    var formattedCountdown: String {
        let h = remainingSeconds / 3600
        let m = (remainingSeconds % 3600) / 60
        let s = remainingSeconds % 60
        if h > 0 {
            return String(format: "%d hr %02d min %02d sec remaining", h, m, s)
        } else {
            return String(format: "%02d min %02d sec remaining", m, s)
        }
    }

    func startBlocking() {
        validateAndUpdate()
        guard errorMessage == nil else { return }
        remainingSeconds = Int(totalMinutes * 60)
        sessionStartSeconds = remainingSeconds
        isLocked = true
    }

    func addTime() {
        let maxSec = 12 * 3600
        remainingSeconds = min(remainingSeconds + 900, maxSec)
        sessionStartSeconds = max(sessionStartSeconds, remainingSeconds)
    }

    func validateAndUpdate() {
        let h = Int(hoursText) ?? 0
        let m = Int(minsText) ?? 0
        let total = (h * 60) + m

        if total < 5 {
            errorMessage = "Invalid (min 5m)"
        } else if total > 720 {
            errorMessage = "Invalid (max 12h)"
        } else {
            errorMessage = nil
            totalMinutes = Double(total)
        }
    }

    func syncFromSlider(val: Double) {
        let roundedVal = (val / 5).rounded() * 5
        hoursText = "\(Int(roundedVal) / 60)"
        minsText = "\(Int(roundedVal) % 60)"
        errorMessage = nil
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                // Top Action Button
                if isLocked {
                    Text("Blocking")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 110, height: 24)
                        .background(Color.white.opacity(0.6))
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        .padding(.top, 2)
                } else {
                    Button(action: startBlocking) {
                        Text("Start Blocking")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(errorMessage != nil ? .secondary : .primary)
                            .frame(width: 110, height: 24)
                            .background(Color.white.opacity(0.95))
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.35), lineWidth: 1))
                            .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(errorMessage != nil)
                    .opacity(errorMessage != nil ? 0.6 : 1.0)
                    .padding(.top, 2)
                }

                // Middle: Setup Mode vs Refined Countdown Mode
                VStack(alignment: .leading, spacing: 6) {
                    if isLocked {
                        Text(formattedCountdown)
                            .font(.system(size: 13, weight: .regular))
                            .monospacedDigit()
                            .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))

                        // Clean, thin progress track (matching slider track)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.25))
                                    .frame(height: 4)

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(red: 0.25, green: 0.25, blue: 0.25))
                                    .frame(width: geo.size.width * CGFloat(Double(remainingSeconds) / Double(max(sessionStartSeconds, 1))), height: 4)
                            }
                        }
                        .frame(height: 20)
                    } else {
                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                TimeBox(text: $hoursText, hasError: errorMessage != nil, onChange: validateAndUpdate)
                                Text(hoursText == "1" ? "hour" : "hours")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                            }

                            HStack(spacing: 4) {
                                TimeBox(text: $minsText, hasError: errorMessage != nil, onChange: validateAndUpdate)
                                Text("minutes")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                            }

                            if let err = errorMessage {
                                Text(err).font(.system(size: 11, weight: .medium)).foregroundColor(.red).padding(.leading, 4)
                            }
                            Spacer()
                        }

                        Slider(value: $totalMinutes, in: 5...720)
                            .accentColor(Color(red: 0.25, green: 0.25, blue: 0.25))
                            .onChange(of: totalMinutes) { _, val in syncFromSlider(val: val) }
                    }
                }

                Spacer(minLength: 2)

                // Bottom Footer with Dynamic App Summary
                HStack {
                    Text(statusSummary)
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.35))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    Button("Edit Blocklist/Allowlist") {
                        showBlocklist = true
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isLocked ? .secondary : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(isLocked ? 0.5 : 0.95))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
                    .buttonStyle(.plain)
                    .disabled(isLocked)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(width: 480, height: 155)
            .background(Color(red: 0.90, green: 0.90, blue: 0.91))

            // Corner "+ Add Time" button
            if isLocked {
                Button(action: addTime) {
                    Text("+ 15m")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.95))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding([.top, .trailing], 10)
                .disabled(remainingSeconds >= 12 * 3600)
            }
        }
        .sheet(isPresented: $showBlocklist) {
            BlocklistSheet(isPresented: $showBlocklist, mode: $listMode, apps: $selectedApps)
        }
        // Save to UserDefaults automatically whenever apps or mode change
        .onChange(of: selectedApps) { _, newApps in
            UserDefaults.standard.set(newApps, forKey: "lockin_apps")
        }
        .onChange(of: listMode) { _, newMode in
            UserDefaults.standard.set(newMode.rawValue, forKey: "lockin_mode")
        }
        .onReceive(timer) { _ in
            if isLocked && remainingSeconds > 0 {
                remainingSeconds -= 1
                if remainingSeconds == 0 {
                    isLocked = false
                }
            }
        }
    }
}

@main
struct LockinApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
