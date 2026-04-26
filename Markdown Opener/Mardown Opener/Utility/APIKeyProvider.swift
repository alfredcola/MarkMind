import Foundation

enum APIKeyProvider {
    static func getMiniMaxAPIKey() -> String {
        if let envKey = ProcessInfo.processInfo.environment["MINIMAX_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        if let bundleKey = Bundle.main.object(forInfoDictionaryKey: "MiniMaxAPIKey") as? String, !bundleKey.isEmpty {
            return bundleKey
        }
        return ""
    }
}