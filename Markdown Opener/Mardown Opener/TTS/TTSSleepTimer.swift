import Foundation
import Combine

final class TTSSleepTimerManager: ObservableObject {
    static let shared = TTSSleepTimerManager()

    @Published var remainingSeconds: Int = 0
    @Published var isActive: Bool = false
    @Published var selectedOption: TTSSleepTimerOption = .off

    private var timer: Timer?
    private var totalSeconds: Int = 0
    private var onTimerExpired: (() -> Void)?

    private init() {}

    var isEndOfDocumentMode: Bool {
        remainingSeconds < 0 && selectedOption == .endOfDocument
    }

    func start(option: TTSSleepTimerOption, onExpired: @escaping () -> Void) {
        stop()
        selectedOption = option
        onTimerExpired = onExpired

        guard option != .off else { return }

        if option == .endOfDocument {
            isActive = true
            remainingSeconds = -1
            return
        }

        totalSeconds = option.rawValue * 60
        remainingSeconds = totalSeconds
        isActive = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.remainingSeconds > 0 {
                self.remainingSeconds -= 1
            } else {
                self.stop()
                self.onTimerExpired?()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
        remainingSeconds = 0
        selectedOption = .off
        onTimerExpired = nil
    }

    func pause() {
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard isActive else { return }
        guard remainingSeconds > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.remainingSeconds > 0 {
                self.remainingSeconds -= 1
            } else {
                self.stop()
                self.onTimerExpired?()
            }
        }
    }

    func triggerEndOfDocument() {
        guard isEndOfDocumentMode else { return }
        stop()
        onTimerExpired?()
    }

    var formattedRemainingTime: String {
        if isEndOfDocumentMode {
            return "End of Doc"
        }
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
