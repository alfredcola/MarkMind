import SwiftUI

struct TypingIndicatorView: View {
    @State private var animating = false

    private let dotCount = 3
    private let dotSize: CGFloat = 6

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Spacer(minLength: 50)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)

                    Text("AI")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    ForEach(0..<dotCount, id: \.self) { index in
                        Circle()
                            .fill(Color.gray.opacity(0.6))
                            .frame(width: dotSize, height: dotSize)
                            .scaleEffect(animating ? 1.0 : 0.5)
                            .animation(
                                .easeInOut(duration: 0.4)
                                .repeatForever()
                                .delay(Double(index) * 0.15),
                                value: animating
                            )
                    }

                    Text(Localization.locWithUserPreference("thinking...", "思考中..."))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
            }

            Spacer(minLength: 50)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onAppear {
            animating = true
        }
    }
}

struct TypingIndicatorModifier: ViewModifier {
    let isTyping: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTyping {
                    VStack {
                        Spacer()
                        TypingIndicatorView()
                            .padding(.bottom, 8)
                    }
                }
            }
    }
}

extension View {
    func typingIndicator(isTyping: Bool) -> some View {
        modifier(TypingIndicatorModifier(isTyping: isTyping))
    }
}