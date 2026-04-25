import AVFoundation
import MLX
import KokoroSwift
import Combine
import MLXUtilsLibrary
import SwiftUI
import WebKit

final class TestAppModel: ObservableObject {

    // Make these optional - they'll be nil on unsupported devices
    @Published private(set) var kokoroTTSEngine: KokoroTTS?
    @Published private(set) var audioEngine: AVAudioEngine?
    @Published private(set) var playerNode: AVAudioPlayerNode?
    @Published private(set) var voices: [String: MLXArray]?
    @Published var voiceNames: [String] = []
    @Published var selectedVoice: String = ""
    @Published var stringToFollowTheAudio: String = ""
    @Published var playbackRate: Float = 1.0

    var timer: Timer?

    private let settings = MultiSettingsViewModel.shared

    // MARK: - Device Support

    static func isSupportedDevice() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        var systemInfo = utsname()
        uname(&systemInfo)

        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        // iPhone A16+ (Kokoro TTS capable)
        let supportedIphones = [
            // iPhone 14 Pro series (A16)
            "iPhone15,2", "iPhone15,3",
            // iPhone 15 series (A16/A17 Pro)
            "iPhone15,4", "iPhone15,5",
            "iPhone16,1", "iPhone16,2",
            // iPhone 16 series (A18+)
            "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4", "iPhone17,5"
        ]

        // iPad M1+ (MLX capable)
        let supportedIpads = [
            // iPad Pro M1 (5th Gen 11", 5th Gen 12.9")
            "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7",
            "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11",
            // iPad Pro M2 (4th Gen 11", 6th Gen 12.9")
            "iPad14,3", "iPad14,4", "iPad14,5", "iPad14,6",
            // iPad Pro M4 (5th Gen 11", 7th Gen 12.9")
            "iPad16,3", "iPad16,4", "iPad16,5", "iPad16,6"
        ]

        return supportedIphones.contains(identifier) || supportedIpads.contains(identifier)
        #endif
    }

    // MARK: - Init

    init() {
        // Check device support first
        guard TestAppModel.isSupportedDevice() else {
            print("Device not supported - requires A16 or newer.")
            return
        }

        // Now check user preference
        guard settings.ttsEnabled else {
            print("TTS disabled by user preference.")
            return
        }

        // Safe to initialize heavy resources
        setupTTS()
    }

    // MARK: - TTS Setup

    private func setupTTS() {
        // 1. 加載模型
        guard let modelPath = Bundle.main.url(forResource: "kokoro-v1_0", withExtension: "safetensors") else {
            print("Failed to find kokoro-v1_0.safetensors in bundle")
            return
        }

        kokoroTTSEngine = KokoroTTS(modelPath: modelPath)

        // 2. 設置 AVAudioEngine
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let sampleRate = Double(KokoroTTS.Constants.samplingRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)

        self.audioEngine = engine
        self.playerNode = player

        // 3. 加載聲音檔案
        guard let voiceFilePath = Bundle.main.url(forResource: "voices", withExtension: "npz") else {
            print("Failed to find voices.npz in bundle")
            return
        }

        guard let loadedVoices = NpyzReader.read(fileFromPath: voiceFilePath) else {
            print("Failed to load voices.npz")
            return
        }

        self.voices = loadedVoices

        // 提取並排序聲音名稱
        let names = loadedVoices.keys
            .compactMap { $0.split(separator: ".").first }
            .map(String.init)
            .sorted()

        self.voiceNames = names

        if !names.isEmpty {
            self.selectedVoice = names[0]
        }

        // 4. 設置 Audio Session（只做一次）
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("Failed to configure AVAudioSession: \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - Speech

    func say(text: String, completion: @escaping () -> Void) {
        guard settings.ttsEnabled else {
            print("TTS is disabled in settings – skipping speech.")
            completion()
            return
        }

        guard let engine = audioEngine,
              let player = playerNode,
              let tts = kokoroTTSEngine,
              let voices = voices,
              let voiceData = voices[selectedVoice + ".npy"] else {
            print("TTS components not ready or not initialized")
            completion()
            return
        }

        player.stop()
        player.reset()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion() }
                return
            }

            var audioFloats: [Float] = []
            var tokenArray: Any?

            do {
                let generated = try tts.generateAudio(
                    voice: voiceData,
                    language: self.selectedVoice.first == "a" ? .enUS : .enGB,
                    text: text
                )
                audioFloats = generated.0
                tokenArray = generated.1
            } catch {
                print("KokoroTTS generateAudio failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion() }
                return
            }

            if let tokens = tokenArray as? [Any] {
                for case let token as NSDictionary in tokens {
                    if let tokenText = token["text"] as? String {
                        print("Token: \(tokenText)")
                    }
                }
            }

            let sampleRate = Double(KokoroTTS.Constants.samplingRate)
            let audioLength = Double(audioFloats.count) / sampleRate
            print("Audio Length: \(String(format: "%.4f", audioLength))s")

            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioFloats.count)) else {
                print("Failed to create AVAudioPCMBuffer")
                DispatchQueue.main.async { completion() }
                return
            }

            buffer.frameLength = buffer.frameCapacity
            if let channelData = buffer.floatChannelData?[0] {
                audioFloats.withUnsafeBufferPointer { srcBuffer in
                    let src = srcBuffer.baseAddress!
                    channelData.initialize(repeating: 0, count: audioFloats.count)
                    channelData.update(from: src, count: audioFloats.count)
                }
            }

            DispatchQueue.main.async {
                guard self.audioEngine != nil, self.playerNode != nil else {
                    completion()
                    return
                }

                if !engine.isRunning {
                    do {
                        try engine.start()
                    } catch {
                        print("AudioEngine start failed: \(error.localizedDescription)")
                        completion()
                        return
                    }
                }

                player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: completion)
                player.play()
                player.rate = self.playbackRate
                self.stringToFollowTheAudio = text
            }
        }
    }

    func updatePlaybackRate(_ rate: Float) {
        playbackRate = rate
        playerNode?.rate = rate
    }

    // MARK: - Deinit Cleanup

    deinit {
        playerNode?.stop()
        audioEngine?.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
