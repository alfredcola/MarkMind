import Foundation
import Combine

final class TTSABRepeatManager: ObservableObject {
    static let shared = TTSABRepeatManager()

    @Published var pointA: Int?
    @Published var pointB: Int?
    @Published var isActive: Bool = false

    var hasValidRange: Bool {
        guard let a = pointA, let b = pointB else { return false }
        return a < b
    }

    func setPointA(at chunkIndex: Int) {
        pointA = chunkIndex
        updateActiveState()
    }

    func setPointB(at chunkIndex: Int) {
        pointB = chunkIndex
        updateActiveState()
    }

    func clear() {
        pointA = nil
        pointB = nil
        isActive = false
    }

    func isWithinRange(_ chunkIndex: Int) -> Bool {
        guard hasValidRange else { return true }
        guard let a = pointA, let b = pointB else { return true }
        return chunkIndex >= a && chunkIndex <= b
    }

    func shouldLoop(backToA currentIndex: Int) -> Bool {
        guard isActive, hasValidRange else { return false }
        guard let b = pointB else { return false }
        return currentIndex >= b
    }

    func getPointAIndex() -> Int {
        return pointA ?? 0
    }

    private func updateActiveState() {
        isActive = hasValidRange
    }
}
