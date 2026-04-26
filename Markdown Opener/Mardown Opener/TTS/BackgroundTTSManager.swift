import AVFoundation
import MediaPlayer
import Combine

final class BackgroundTTSManager: ObservableObject {
    static let shared = BackgroundTTSManager()

    @Published var isPlaying: Bool = false
    @Published var currentTitle: String = "Text-to-Speech"
    @Published var currentChunkIndex: Int = 0
    @Published var totalChunks: Int = 1

    private var isSetup = false
    private var observersAdded = false

    private init() {}

    func setupAudioSession() {
        guard !isSetup else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
            try session.setActive(true, options: [])
            Log.debug("Audio session configured for background playback", category: .audio)
            isSetup = true

            if !observersAdded {
                setupInterruptionHandling()
                observersAdded = true
            }
        } catch {
            Log.error("Failed to setup audio session", category: .audio, error: error)
            isSetup = false
        }
    }

    func deactivateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            isSetup = false
        } catch {
            Log.error("Failed to deactivate audio session", category: .audio, error: error)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            Log.debug("Interruption began", category: .audio)
            DispatchQueue.main.async {
                self.isPlaying = false
            }

        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            if options.contains(.shouldResume) {
                Log.debug("Interruption ended - can resume", category: .audio)
                DispatchQueue.main.async {
                    self.isPlaying = true
                }
            }

        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            Log.debug("Audio output device disconnected", category: .audio)
            DispatchQueue.main.async {
                self.isPlaying = false
            }

        default:
            break
        }
    }

    // MARK: - Remote Command Center

    func setupRemoteCommandCenter(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onSkipForward: @escaping () -> Void,
        onSkipBackward: @escaping () -> Void
    ) {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            onPlay()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            onPause()
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            onNext()
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            onPrevious()
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [10]
        commandCenter.skipForwardCommand.addTarget { _ in
            onSkipForward()
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [10]
        commandCenter.skipBackwardCommand.addTarget { _ in
            onSkipBackward()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = false
    }

    func clearRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
    }

    // MARK: - Now Playing Info

    func updateNowPlayingInfo(
        title: String,
        chunkIndex: Int,
        totalChunks: Int,
        isPlaying: Bool,
        playbackRate: Double
    ) {
        var nowPlayingInfo = [String: Any]()

        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = "Chunk \(chunkIndex + 1) of \(totalChunks)"
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Text-to-Speech"
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Double(totalChunks)
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

        self.currentTitle = title
        self.currentChunkIndex = chunkIndex
        self.totalChunks = totalChunks
        self.isPlaying = isPlaying
    }

    func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
