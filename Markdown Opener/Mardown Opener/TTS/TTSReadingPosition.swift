import Foundation

final class TTSReadingPositionManager {
    static let shared = TTSReadingPositionManager()

    private let settings = MultiSettingsViewModel.shared

    private init() {}

    func savePosition(for filePath: String, chunkIndex: Int) {
        var positions = settings.ttsReadingPositions
        positions[filePath] = chunkIndex
        settings.ttsReadingPositions = positions
        settings.ttsLastPlayedFile = filePath
    }

    func getPosition(for filePath: String) -> Int? {
        let positions = settings.ttsReadingPositions
        return positions[filePath]
    }

    func clearPosition(for filePath: String) {
        var positions = settings.ttsReadingPositions
        positions.removeValue(forKey: filePath)
        settings.ttsReadingPositions = positions
    }

    func clearAllPositions() {
        settings.ttsReadingPositions = [:]
    }
}