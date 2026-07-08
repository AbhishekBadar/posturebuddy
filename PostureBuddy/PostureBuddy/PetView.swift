import SwiftUI

/// The posture pet: a speech bubble + placeholder SF Symbol character.
/// Rendered statically; slide/fade is driven by PetOverlayWindowController.
struct PetView: View {
    let message: String

    init(message: String) {
        self.message = message
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            SpeechBubble(text: message)
            Image(systemName: "figure.seated.side")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .padding(16)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.orange.opacity(0.4), lineWidth: 2))
        }
        .padding(16)
    }
}

private struct SpeechBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.orange.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }
}

#Preview {
    PetView(message: "Sit up straight!")
        .frame(width: 220, height: 200)
        .padding()
}
