import SwiftUI

@main
struct PostureBuddyApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("PostureBuddy", systemImage: model.menuBarSymbol) {
            MenuBarContentView(model: model)
                .task {
                    if !model.settings.hasCalibrated {
                        openWindow(id: "calibration")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("Calibrate PostureBuddy", id: "calibration") {
            CalibrationView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
