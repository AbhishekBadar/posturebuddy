import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.statusText,
                  systemImage: model.connectionState == .connected ? "checkmark.circle.fill" : "airpods")
                .font(.headline)

            Divider()

            Toggle("Monitor my posture", isOn: Binding(
                get: { model.isMonitoring },
                set: { model.setMonitoring($0) }
            ))

            VStack(alignment: .leading, spacing: 4) {
                Text("Sensitivity")
                    .font(.subheadline)
                Slider(
                    value: Binding(get: { model.threshold },
                                   set: { model.applyThreshold($0) }),
                    in: model.thresholdRange
                ) {
                    Text("Sensitivity")
                } minimumValueLabel: {
                    Text("Strict")
                } maximumValueLabel: {
                    Text("Relaxed")
                }
                Text("Threshold: \(Int(model.threshold))° head tilt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Recalibrate…") {
                model.startCalibration()
                openWindow(id: "calibration")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Quit PostureBuddy") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}
