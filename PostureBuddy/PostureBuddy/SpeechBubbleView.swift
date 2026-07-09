import SwiftUI

/// A small speech bubble with a downward-pointing tail, overlaid above the pet
/// to show the "Sit straight!" message (the transparent GIF has no text of its own).
struct SpeechBubbleView: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
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
        .fixedSize()
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
    SpeechBubbleView(text: "Sit straight!")
        .padding(40)
}
