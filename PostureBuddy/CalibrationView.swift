import SwiftUI

/// Guided calibration: records good posture, then bad posture, then lets the
/// user save the computed threshold. State comes from AppModel.calibrationState,
/// which mirrors the tracker's CalibrationPhase.
struct CalibrationView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Posture Calibration")
                .font(.title2.bold())

            instruction
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            progressView

            controls
        }
        .padding(28)
        .frame(width: 380)
    }

    @ViewBuilder
    private var instruction: some View {
        switch model.calibrationState {
        case .idle:
            Text("We'll measure your good and slouched posture to personalize your threshold. Keep your AirPods in.")
        case .samplingUpright:
            Text("Sit up straight and hold still…")
                .font(.headline)
        case .pause:
            Text("Great! Now get ready to slouch…")
                .font(.headline)
        case .samplingSlouch:
            Text("Now slouch the way you normally do…")
                .font(.headline)
        case .done(let threshold):
            Text("Done! Your personalized threshold is \(Int(threshold))°.")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var progressView: some View {
        switch model.calibrationState {
        case .samplingUpright(let p), .pause(let p), .samplingSlouch(let p):
            ProgressView(value: p)
                .progressViewStyle(.linear)
                .frame(width: 260)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.calibrationState {
        case .idle:
            HStack {
                Button("Cancel") { dismiss() }
                Button("Start") { model.startCalibration() }
                    .keyboardShortcut(.defaultAction)
            }
        case .samplingUpright, .pause, .samplingSlouch:
            Button("Cancel") {
                model.cancelCalibration()
                dismiss()
            }
        case .done:
            HStack {
                Button("Discard") {
                    model.cancelCalibration()
                    dismiss()
                }
                Button("Save") {
                    model.saveCalibration()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
