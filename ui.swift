import SwiftUI
import AppKit

enum TimeField: Hashable {
    case hours
    case mins
}

struct ContentView: View {
    @State private var totalMinutes: Double = 90
    @State private var hoursText: String = "1"
    @State private var minsText: String = "30"
    @State private var isLocked: Bool = false
    @State private var errorMessage: String? = nil

    @State private var isEditingHours: Bool = false
    @State private var isEditingMins: Bool = false
    @FocusState private var focusedField: TimeField?

    // Filter to numbers only (strips letters)
    func cleanNumbers(_ input: String) -> String {
        return String(input.filter { "0123456789".contains($0) }.prefix(3))
    }

    // Validate inputs (Max 12 hours = 720 minutes)
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
        if !isEditingHours && !isEditingMins {
            let roundedVal = (val / 5).rounded() * 5
            let h = Int(roundedVal) / 60
            let m = Int(roundedVal) % 60
            hoursText = "\(h)"
            minsText = "\(m)"
            errorMessage = nil
        }
    }

    func stopEditing() {
        // Fall back to 0 if left empty
        if hoursText.trimmingCharacters(in: .whitespaces).isEmpty {
            hoursText = "0"
        }
        if minsText.trimmingCharacters(in: .whitespaces).isEmpty {
            minsText = "0"
        }

        isEditingHours = false
        isEditingMins = false
        focusedField = nil
        validateAndUpdate()
    }

    var body: some View {
        VStack(spacing: 12) {
            // Top: Action Button
            Button(action: {
                if errorMessage == nil {
                    isLocked.toggle()
                }
            }) {
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
                    .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .disabled(errorMessage != nil)
            .opacity(errorMessage != nil ? 0.6 : 1.0)
            .padding(.top, 2)

            // Middle: Clean Inset Inputs + Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    // Hours Box
                    HStack(spacing: 4) {
                        ZStack {
                            if isEditingHours {
                                TextField("0", text: $hoursText)
                                    .focused($focusedField, equals: .hours)
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 12, weight: .medium))
                                    .onChange(of: hoursText) { newVal in
                                        hoursText = cleanNumbers(newVal)
                                        validateAndUpdate()
                                    }
                                    .onSubmit { stopEditing() }
                            } else {
                                Text(hoursText.isEmpty ? "0" : hoursText)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        isEditingHours = true
                                        DispatchQueue.main.async {
                                            focusedField = .hours
                                        }
                                    }
                            }
                        }
                        .frame(width: 32, height: 20)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(errorMessage != nil ? Color.red : Color.gray.opacity(0.35), lineWidth: 1)
                        )

                        Text(hoursText == "1" ? "hour" : "hours")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                    }

                    // Minutes Box
                    HStack(spacing: 4) {
                        ZStack {
                            if isEditingMins {
                                TextField("0", text: $minsText)
                                    .focused($focusedField, equals: .mins)
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 12, weight: .medium))
                                    .onChange(of: minsText) { newVal in
                                        minsText = cleanNumbers(newVal)
                                        validateAndUpdate()
                                    }
                                    .onSubmit { stopEditing() }
                            } else {
                                Text(minsText.isEmpty ? "0" : minsText)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        isEditingMins = true
                                        DispatchQueue.main.async {
                                            focusedField = .mins
                                        }
                                    }
                            }
                        }
                        .frame(width: 32, height: 20)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(errorMessage != nil ? Color.red : Color.gray.opacity(0.35), lineWidth: 1)
                        )

                        Text("minutes")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                    }

                    // Error text
                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.leading, 4)
                    }

                    Spacer()
                }

                // Smooth full-width slider
                Slider(value: $totalMinutes, in: 5...720)
                    .accentColor(Color(red: 0.25, green: 0.25, blue: 0.25))
                    .onChange(of: totalMinutes) { val in
                        syncFromSlider(val: val)
                    }
            }

            Spacer(minLength: 2)

            // Bottom: Info on left + "Edit Blocklist" on right
            HStack(alignment: .center) {
                Text("Blocking unapproved apps & distraction tabs")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.35))
                    .lineLimit(1)

                Spacer()

                Button(action: {
                    // Blocklist trigger
                }) {
                    Text("Edit Blocklist")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.95))
                        .cornerRadius(5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(width: 480, height: 155)
        .background(Color(red: 0.90, green: 0.90, blue: 0.91))
        // Click outside the box to finish typing
        .contentShape(Rectangle())
        .onTapGesture {
            stopEditing()
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
