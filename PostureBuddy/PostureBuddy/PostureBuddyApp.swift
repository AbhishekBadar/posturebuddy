import SwiftUI

@main
struct PostureBuddyApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("PostureBuddy", systemImage: model.menuBarSymbol) {
            MenuBarContentView(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Calibrate PostureBuddy", id: "calibration") {
            CalibrationView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
