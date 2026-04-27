import Foundation
import Combine

struct ChatMessageError: Codable, Equatable {
    let messageId: UUID
    let error: String
    let timestamp: Date
    var isRetryable: Bool
    var retryCount: Int

    init(messageId: UUID, error: String, isRetryable: Bool = true, retryCount: Int = 0) {
        self.messageId = messageId
        self.error = error
        self.timestamp = Date()
        self.isRetryable = isRetryable
        self.retryCount = retryCount
    }
}

@MainActor
final class ChatErrorManager: ObservableObject {
    static let shared = ChatErrorManager()

    @Published private(set) var messageErrors: [UUID: ChatMessageError] = [:]
    @Published var globalError: String?
    @Published var showGlobalError: Bool = false

    private init() {}

    func setError(for messageId: UUID, error: String, isRetryable: Bool = true) {
        let existingRetryCount = messageErrors[messageId]?.retryCount ?? 0
        messageErrors[messageId] = ChatMessageError(
            messageId: messageId,
            error: error,
            isRetryable: isRetryable,
            retryCount: existingRetryCount
        )
    }

    func incrementRetryCount(for messageId: UUID) {
        if var existing = messageErrors[messageId] {
            existing.retryCount += 1
            messageErrors[messageId] = existing
        }
    }

    func clearError(for messageId: UUID) {
        messageErrors.removeValue(forKey: messageId)
    }

    func clearAllErrors() {
        messageErrors.removeAll()
        globalError = nil
        showGlobalError = false
    }

    func error(for messageId: UUID) -> ChatMessageError? {
        messageErrors[messageId]
    }

    func setGlobalError(_ error: String) {
        globalError = error
        showGlobalError = true
    }

    func dismissGlobalError() {
        showGlobalError = false
    }
}
