import SwiftUI

struct ErrorBannerView: View {
    let error: String
    let isRetryable: Bool
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void

    @State private var isAppearing = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isRetryable ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(isRetryable ? .orange : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(isRetryable ? "Error" : "Failed")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isRetryable, let onRetry = onRetry {
                Button(action: onRetry) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                        Text("Retry")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
                }
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isRetryable ? Color.orange.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : -20)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isAppearing = true
            }
        }
    }
}

struct InlineErrorView: View {
    let message: ChatMessage
    @ObservedObject var errorManager = ChatErrorManager.shared

    var body: some View {
        if let chatError = errorManager.error(for: message.id) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)

                Text(chatError.error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                if chatError.isRetryable {
                    Button(action: {
                        errorManager.clearError(for: message.id)
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}