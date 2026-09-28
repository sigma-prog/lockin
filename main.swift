import SwiftUI
import AppKit

struct ContentView: View {
    @State private var minutes: Double = 25

    var body: some View {
        VStack(spacing: 20) {
            Text("lockin")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            VStack(spacing: 10) {
                Text("\(Int(minutes)) MIN")
                    .font(.system(size: 40, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)

                Slider(value: $minutes, in: 5...120, step: 5)
                    .accentColor(.white)
            }
            .padding(.horizontal, 20)

            Text("Drag to set focus duration")
                .font(.footnote)
                .foregroundColor(.gray)
        }
        .frame(width: 320, height: 220)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
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
