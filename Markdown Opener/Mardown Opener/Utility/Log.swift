import Foundation
import os.log

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.alfredchen.MarkMind"

    private static func logger(for category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    enum Category: String {
        case tts = "TTS"
        case audio = "Audio"
        case fileIO = "FileIO"
        case data = "Data"
        case network = "Network"
        case general = "General"
        case widget = "Widget"
        case subscription = "Subscription"
    }

    static func error(_ message: String, category: Category = .general, error: Error? = nil) {
        if let error = error {
            logger(for: category.rawValue).error("\(message): \(error.localizedDescription)")
        } else {
            logger(for: category.rawValue).error("\(message)")
        }
    }

    static func warning(_ message: String, category: Category = .general) {
        logger(for: category.rawValue).warning("\(message)")
    }

    static func info(_ message: String, category: Category = .general) {
        logger(for: category.rawValue).info("\(message)")
    }

    #if DEBUG
    static func debug(_ message: String, category: Category = .general) {
        logger(for: category.rawValue).debug("\(message)")
    }
    #else
    static func debug(_ message: String, category: Category = .general) {}
    #endif
}