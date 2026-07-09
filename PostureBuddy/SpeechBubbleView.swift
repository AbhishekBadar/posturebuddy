import SwiftUI

/// A speech bubble with a downward-pointing tail, overlaid above the character
/// to show its nag line (the transparent GIF has no text of its own).
///
/// Lines vary in length, so the text wraps at `maxTextWidth` rather than forcing
/// an arbitrarily wide bubble.
struct SpeechBubbleView: View {
    let text: String
    var maxTextWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: maxTextWidth)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.black.opacity(0.12), lineWidth: 1)
                )

            BubbleTail()
                .fill(.white)
                .frame(width: 22, height: 12)
                .offset(y: -1)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }
}

/// Downward triangle for the speech-bubble tail.
private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        SpeechBubbleView(text: "Gravity: 1. You: 0.")
        SpeechBubbleView(text: "You're folding like a cheap lawn chair.")
    }
    .padding(40)
}
