import Foundation

enum Constants {
    enum TTS {
        static let chunkMonitoringInterval: TimeInterval = 0.2
        static let chunkProcessingInterval: TimeInterval = 0.5
        static let selectionTimerInterval: TimeInterval = 0.3
        static let defaultAutoSaveDelay: TimeInterval = 0.5
        static let maxSentenceLength: Int = 220
    }

    enum Animation {
        static let defaultDuration: TimeInterval = 0.3
    }

    enum API {
        static let miniMaxAPITimeout: TimeInterval = 60
        static let maxTokensStandard: Int = 8192
        static let maxTokensPDF: Int = 8000
        static let maxRetries: Int = 3
        static let retryBaseDelay: TimeInterval = 1.0
        static let retryMaxDelay: TimeInterval = 30.0
    }

    enum ChatRetry {
        static let maxQueueSize: Int = 100
        static let maxRetriesPerMessage: Int = 3
        static let queuePersistenceFileName = "pending_messages.json"
    }

    enum Pagination {
        static let defaultPageSize: Int = 30
        static let maxCachedMessages: Int = 100
        static let maxMemoryMessages: Int = 300
    }

    enum Performance {
        static let backgroundSaveDebounceInterval: TimeInterval = 0.5
        static let maxConcurrentBackgroundTasks: Int = 3
        static let memoryWarningThresholdMB: Int = 100
        static let messageFilterDebounce: TimeInterval = 0.1
    }

    enum MLX {
        static let gpuCacheLimit: Int = 50 * 1024 * 1024
        static let gpuMemoryLimit: Int = 900 * 1024 * 1024
    }

    enum Security {
        static let adminPassword: String = {
            if let password = ProcessInfo.processInfo.environment["ADMIN_PASSWORD"], !password.isEmpty {
                return password
            }
            return ""
        }()
    }

    enum Ads {
        static let bannerTopID: String = "ca-app-pub-2445337445676652/1837637959"
        static let bannerBottomID: String = "ca-app-pub-2445337445676652/7550433284"
        static let rewardedAdUnitID: String = "ca-app-pub-2445337445676652/1626687605"
        static let interstitialAdUnitID: String = "ca-app-pub-2445337445676652/5437686206"
    }

    enum Time {
        static let secondsPerDay: TimeInterval = 86400
        static let secondsPerHour: TimeInterval = 3600
    }

    enum Limits {
        static let maxChatMessagesPerConversation: Int = 1000
        static let maxSavedSelectionChats: Int = 100
        static let maxSavedDocumentChats: Int = 100
        static let maxMCStudyHistoryResults: Int = 500
        static let maxTTSAudioCacheMB: Int = 50
    }
}