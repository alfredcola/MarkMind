import Foundation
import Combine
import Network

enum ChatError: LocalizedError {
    case networkUnavailable
    case timeout
    case serverError(statusCode: Int, message: String)
    case clientError(statusCode: Int, message: String)
    case maxRetriesExceeded
    case cancelled
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return Localization.locWithUserPreference("No internet connection. Your message will be sent when you're back online.", "無網絡連接。您的消息將在恢復連線後發送。")
        case .timeout:
            return Localization.locWithUserPreference("Request timed out. Please try again.", "請求超時。請重試。")
        case .serverError(let code, let msg):
            return Localization.locWithUserPreference("Server error (\(code)): \(msg)", "伺服器錯誤 (\(code)): \(msg)")
        case .clientError(let code, let msg):
            return Localization.locWithUserPreference("Request error (\(code)): \(msg)", "請求錯誤 (\(code)): \(msg)")
        case .maxRetriesExceeded:
            return Localization.locWithUserPreference("Unable to send message after multiple attempts. Please try again later.", "多次嘗試後無法發送訊息。請稍後再試。")
        case .cancelled:
            return Localization.locWithUserPreference("Request was cancelled.", "請求已被取消。")
        case .unknown(let error):
            return error.localizedDescription
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .timeout, .serverError:
            return true
        case .clientError(let code, _):
            return code >= 500
        case .maxRetriesExceeded, .cancelled, .unknown:
            return false
        }
    }
}

struct QueuedMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let message: ChatMessage
    let docURL: URL
    let timestamp: Date
    var retryCount: Int
    var lastAttempt: Date?
    var errorMessage: String?

    init(message: ChatMessage, docURL: URL) {
        self.id = UUID()
        self.message = message
        self.docURL = docURL
        self.timestamp = Date()
        self.retryCount = 0
        self.lastAttempt = nil
        self.errorMessage = nil
    }

    static func == (lhs: QueuedMessage, rhs: QueuedMessage) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class ChatRetryManager: ObservableObject {
    static let shared = ChatRetryManager()

    @Published private(set) var queuedMessages: [QueuedMessage] = []
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var isNetworkAvailable: Bool = true

    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.markmind.chatnetmonitor")
    private var processingTask: Task<Void, Never>?
    private let maxRetries = Constants.ChatRetry.maxRetriesPerMessage

    private init() {
        loadFromDisk()
        startNetworkMonitoring()
    }

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let available = path.status == .satisfied
                self?.isNetworkAvailable = available

                if available {
                    self?.processQueue()
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    func enqueue(_ message: ChatMessage, to docURL: URL) {
        let queued = QueuedMessage(message: message, docURL: docURL)
        queuedMessages.append(queued)
        saveToDisk()

        if isNetworkAvailable {
            processQueue()
        }
    }

    func remove(_ id: UUID) {
        queuedMessages.removeAll { $0.id == id }
        saveToDisk()
    }

    func retry(_ id: UUID) {
        guard let index = queuedMessages.firstIndex(where: { $0.id == id }) else { return }
        queuedMessages[index].retryCount = 0
        queuedMessages[index].errorMessage = nil
        processQueue()
    }

    func clearAll() {
        queuedMessages.removeAll()
        saveToDisk()
    }

    func processQueue() {
        guard !isProcessing, !queuedMessages.isEmpty, isNetworkAvailable else { return }

        processingTask?.cancel()
        processingTask = Task {
            await processQueueAsync()
        }
    }

    private func processQueueAsync() async {
        isProcessing = true
        defer { isProcessing = false }

        var indicesToRemove: [Int] = []

        for i in 0..<queuedMessages.count {
            guard !Task.isCancelled else { break }

            var queued = queuedMessages[i]

            if queued.retryCount >= maxRetries {
                queued.errorMessage = ChatError.maxRetriesExceeded.localizedDescription
                queuedMessages[i] = queued
                continue
            }

            queued.lastAttempt = Date()
            queuedMessages[i] = queued

            do {
                try await processMessage(queued)
                indicesToRemove.append(i)
            } catch {
                let chatError = mapError(error)
                queued.errorMessage = chatError.localizedDescription
                queued.retryCount += 1
                queuedMessages[i] = queued

                if !chatError.isRetryable {
                    break
                }

                let delay = retryDelay(for: queued.retryCount)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        if !indicesToRemove.isEmpty {
            await MainActor.run {
                for index in indicesToRemove.sorted().reversed() {
                    if index < queuedMessages.count {
                        queuedMessages.remove(at: index)
                    }
                }
                saveToDisk()
            }
        }
    }

    private func processMessage(_ queued: QueuedMessage) async throws {
        let conversationStore = ConversationStore.shared

        guard conversationStore.threads[queued.docURL] != nil else {
            throw ChatError.cancelled
        }

        let fullConversation = buildConversationForAPI(for: queued.docURL, store: conversationStore)
        let apiKey = APIKeyProvider.getMiniMaxAPIKey()

        let reply: String
        if MiniMaxServiceConfiguration.shared.enableStreaming {
            reply = try await MiniMaxService.streamingChatWithAutoContinue(
                apiKey: apiKey,
                messages: fullConversation
            ) { _ in }
        } else {
            reply = try await MiniMaxService.chatWithAutoContinue(
                apiKey: apiKey,
                messages: fullConversation
            )
        }

        let assistantMessage = ChatMessage(role: .assistant, content: reply)
        conversationStore.append(assistantMessage, to: queued.docURL)
        conversationStore.saveToDisk(for: queued.docURL)
    }

    private func buildConversationForAPI(for docURL: URL, store: ConversationStore) -> [ChatMessage] {
        var conversation: [ChatMessage] = []

        let systemPrompt = PromptBuilder.buildChatSystemPrompt(
            docName: docURL.lastPathComponent,
            docContent: "",
            additionalFiles: []
        )
        conversation.append(.init(role: .system, content: systemPrompt))

        let allMessages = store.messages(for: docURL)
        guard !allMessages.isEmpty else { return conversation }

        let recentMessages = allMessages.suffix(24)
        let filteredMessages = recentMessages.filter { msg in
            !msg.content.isEmpty &&
            !msg.content.hasPrefix("Error:") &&
            !msg.content.hasPrefix("Loading")
        }

        var totalChars = filteredMessages.reduce(0) { $0 + $1.content.count }
        let maxChars = 100_000

        var finalMessages: [ChatMessage] = []
        for msg in filteredMessages.reversed() {
            if totalChars <= maxChars {
                finalMessages.insert(msg, at: 0)
                totalChars -= msg.content.count
            } else {
                break
            }
        }

        conversation.append(contentsOf: finalMessages)
        return conversation
    }

    private func mapError(_ error: Error) -> ChatError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkUnavailable
            case .timedOut:
                return .timeout
            default:
                return .unknown(urlError)
            }
        }

        if let nsError = error as NSError? {
            if nsError.domain == "MiniMax" {
                let code = nsError.code
                if code >= 500 {
                    return .serverError(statusCode: code, message: nsError.localizedDescription)
                } else if code >= 400 {
                    return .clientError(statusCode: code, message: nsError.localizedDescription)
                }
            }
        }

        if let chatError = error as? ChatError {
            return chatError
        }

        return .unknown(error)
    }

    func retryDelay(for retryCount: Int) -> TimeInterval {
        let baseDelay: TimeInterval = 1.0
        let maxDelay: TimeInterval = 30.0
        let delay = baseDelay * pow(2.0, Double(retryCount))
        return min(delay, maxDelay)
    }

    private var queueFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ChatQueues", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pending_messages.json")
    }

    private func saveToDisk() {
        Task {
            await saveToDiskAsync()
        }
    }

    private func saveToDiskAsync() async {
        do {
            let data = try JSONEncoder().encode(queuedMessages)
            try data.write(to: queueFileURL)
        } catch {
            Log.error("Failed to save queued messages: \(error)", category: .persistence)
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: queueFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: queueFileURL)
            let decoded = try JSONDecoder().decode([QueuedMessage].self, from: data)
            queuedMessages = decoded
        } catch {
            Log.error("Failed to load queued messages: \(error)", category: .persistence)
        }
    }
}