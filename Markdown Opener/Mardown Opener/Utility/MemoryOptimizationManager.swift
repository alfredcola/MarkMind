import Foundation
import UIKit
import PDFKit
import Combine

final class MemoryOptimizationManager {
    static let shared = MemoryOptimizationManager()

    let messageContentThreshold: Int = 500
    private let maxStoredContentLength = 200
    private var isObservingMemoryWarnings = false

    private var pdfCache: [URL: PDFDocument] = [:]
    private var renderedHTMLCache: [String: String] = [:]
    private let maxPDFCacheSize = 3
    private let maxHTMLCacheSize = 5

    private init() {}

    func startObservingMemoryWarnings() {
        guard !isObservingMemoryWarnings else { return }
        isObservingMemoryWarnings = true

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }

    func stopObservingMemoryWarnings() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        isObservingMemoryWarnings = false
    }

    private func handleMemoryWarning() {
        Log.info("Memory warning received, clearing caches", category: .performance)

        clearTTSAudioCache()
        clearImageCache()
        clearPDFCache()
        clearHTMLCache()
    }

    func clearTTSAudioCache() {
        Log.debug("Clearing TTS audio cache", category: .performance)
        URLCache.shared.removeAllCachedResponses()
    }

    func clearImageCache() {
        Log.debug("Clearing image cache", category: .performance)
        URLCache.shared.removeAllCachedResponses()
    }

    func clearPDFCache() {
        Log.debug("Clearing PDF cache", category: .performance)
        pdfCache.removeAll()
    }

    func clearHTMLCache() {
        Log.debug("Clearing HTML cache", category: .performance)
        renderedHTMLCache.removeAll()
    }

    func cachePDF(_ document: PDFDocument, for url: URL) {
        if pdfCache.count >= maxPDFCacheSize {
            if let firstKey = pdfCache.keys.first {
                pdfCache.removeValue(forKey: firstKey)
            }
        }
        pdfCache[url] = document
    }

    func getCachedPDF(for url: URL) -> PDFDocument? {
        return pdfCache[url]
    }

    func cacheRenderedHTML(_ html: String, for markdown: String) {
        if renderedHTMLCache.count >= maxHTMLCacheSize {
            if let firstKey = renderedHTMLCache.keys.first {
                renderedHTMLCache.removeValue(forKey: firstKey)
            }
        }
        let key = String(markdown.prefix(1000))
        renderedHTMLCache[key] = html
    }

    func getCachedRenderedHTML(for markdown: String) -> String? {
        let key = String(markdown.prefix(1000))
        return renderedHTMLCache[key]
    }

    func truncateMessageContent(_ content: String, maxLength: Int = 200) -> String {
        guard content.count > maxLength else { return content }
        return String(content.prefix(maxLength)) + "..."
    }

    func shouldTruncateMessage(at index: Int, totalMessages: Int) -> Bool {
        let thresholdIndex = totalMessages - 100
        return index < thresholdIndex && totalMessages > 100
    }
}

@MainActor
final class MessageCacheManager: ObservableObject {
    static let shared = MessageCacheManager()
    let messageContentThreshold: Int = 500

    @Published private(set) var cachedMessageIds: Set<UUID> = []
    @Published private(set) var truncatedMessageIds: Set<UUID> = []

    private let maxCachedMessages = 200
    private var messageContentCache: [UUID: String] = [:]

    private init() {}

    func cacheMessage(_ message: ChatMessage) {
        if cachedMessageIds.count >= maxCachedMessages {
            if let oldestId = cachedMessageIds.first {
                evictMessage(oldestId)
            }
        }

        cachedMessageIds.insert(message.id)
        if message.content.count > messageContentThreshold {
            truncatedMessageIds.insert(message.id)
            messageContentCache[message.id] = message.content
        }
    }

    func getFullContent(for messageId: UUID) -> String? {
        return messageContentCache[messageId]
    }

    func evictMessage(_ messageId: UUID) {
        cachedMessageIds.remove(messageId)
        truncatedMessageIds.remove(messageId)
        messageContentCache.removeValue(forKey: messageId)
    }

    func clearCache() {
        cachedMessageIds.removeAll()
        truncatedMessageIds.removeAll()
        messageContentCache.removeAll()
    }

    func isTruncated(_ messageId: UUID) -> Bool {
        truncatedMessageIds.contains(messageId)
    }
}
