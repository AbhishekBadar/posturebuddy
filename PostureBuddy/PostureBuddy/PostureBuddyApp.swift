import SwiftUI

@main
struct PostureBuddyApp: App {
    var body: some Scene {
        MenuBarExtra("PostureBuddy", systemImage: "figure.seated.side") {
            Text("PostureBuddy")
            Divider()
            Button("Quit PostureBuddy") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.window)
    }
}
