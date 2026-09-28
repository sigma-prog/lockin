import SwiftUI
import AppKit

// Reusable clean input box for both Hours and Minutes
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

struct ContentView: View {
    @State private var totalMinutes: Double = 90
    @State private var hoursText: String = "1"
    @State private var minsText: String = "30"
    @State private var isLocked: Bool = false
    @State private var errorMessage: String? = nil

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
        VStack(spacing: 12) {
            // Action Button
            Button(action: { if errorMessage == nil { isLocked.toggle() } }) {
                Text(isLocked ? "Stop Blocking" : "Start Blocking")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(errorMessage != nil ? .secondary : (isLocked ? .red : .primary))
                    .frame(width: 110, height: 24)
                    .background(Color.white.opacity(0.95))
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isLocked ? Color.red.opacity(0.4) : Color.gray.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            }
            .buttonStyle(.plain)
            .disabled(errorMessage != nil)
            .opacity(errorMessage != nil ? 0.6 : 1.0)
            .padding(.top, 2)

            // Middle: Time Inputs + Slider
            VStack(alignment: .leading, spacing: 6) {
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

            Spacer(minLength: 2)

            // Bottom Footer
            HStack {
                Text("Blocking unapproved apps & distraction tabs")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.35))

                Spacer()

                Button("Edit Blocklist") {}
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.95))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(width: 480, height: 155)
        .background(Color(red: 0.90, green: 0.90, blue: 0.91))
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
