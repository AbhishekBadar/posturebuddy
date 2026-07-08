import SwiftUI

/// The posture pet: a speech bubble + placeholder SF Symbol character that
/// slides in from the right. `isPresented` drives the slide/fade transition.
struct PetView: View {
    let message: String
    @Binding var isPresented: Bool

    init(message: String, isPresented: Binding<Bool> = .constant(true)) {
        self.message = message
        self._isPresented = isPresented
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
        .offset(x: isPresented ? 0 : 260)
        .opacity(isPresented ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: isPresented)
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
