//import AVFoundation
//import MLX
//import KokoroSwift
//import Combine
//import MLXUtilsLibrary
//import SwiftUI
//import WebKit
//
//final class TestAppModel: ObservableObject {
//    // Make these optional - they'll be nil on unsupported devices
//    @Published private(set) var kokoroTTSEngine: KokoroTTS?
//    @Published private(set) var audioEngine: AVAudioEngine?
//    @Published private(set) var playerNode: AVAudioPlayerNode?
//    @Published private(set) var voices: [String: MLXArray]?
//    
//    @Published var voiceNames: [String] = []
//    @Published var selectedVoice: String = ""
//    @Published var stringToFollowTheAudio: String = ""
//    var timer: Timer?
//    private let settings = MultiSettingsViewModel.shared
//    
//    static func isSupportedDevice() -> Bool {
//        #if targetEnvironment(simulator)
//        return true
//        #else
//        var systemInfo = utsname()
//        uname(&systemInfo)
//        let machineMirror = Mirror(reflecting: systemInfo.machine)
//        let identifier = machineMirror.children.reduce("") { identifier, element in
//            guard let value = element.value as? Int8, value != 0 else { return identifier }
//            return identifier + String(UnicodeScalar(UInt8(value)))
//        }
//        
//        // iPhone A16+ (Kokoro TTS capable)
//        let supportedIphones = [
//            // iPhone 14 Pro series (A16)
//            "iPhone15,2", "iPhone15,3",
//            // iPhone 15 series (A16/A17 Pro)
//            "iPhone15,4", "iPhone15,5",
//            "iPhone16,1", "iPhone16,2",
//            // iPhone 16 series (A18+)
//            "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4", "iPhone17,5"
//        ]
//        
//        // iPad M1+ (MLX capable)
//        let supportedIpads = [
//            // iPad Pro M1 (5th Gen 11", 5th Gen 12.9")
//            "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7",
//            "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11",
//            // iPad Pro M2 (4th Gen 11", 6th Gen 12.9")
//            "iPad14,3", "iPad14,4", "iPad14,5", "iPad14,6",
//            // iPad Pro M4 (5th Gen 11", 7th Gen 12.9")
//            "iPad16,3", "iPad16,4", "iPad16,5", "iPad16,6"
//        ]
//        
//        return supportedIphones.contains(identifier) || supportedIpads.contains(identifier)
//        #endif
//    }
//
//    init() {
//        // Check device support first
//        guard TestAppModel.isSupportedDevice() else {
//            print("Device not supported - requires A16 or newer.")
//            return
//        }
//        
//        // Now check user preference
//        guard settings.ttsEnabled else {
//            print("TTS disabled by user preference.")
//            return
//        }
//        
//        // Safe to initialize heavy resources
//        setupTTS()
//    }
//    
//    private func setupTTS() {
//        let modelPath = Bundle.main.url(forResource: "kokoro-v1_0", withExtension: "safetensors")!
//        kokoroTTSEngine = KokoroTTS(modelPath: modelPath)
//        
//        audioEngine = AVAudioEngine()
//        playerNode = AVAudioPlayerNode()
//        guard let audioEngine = audioEngine, let playerNode = playerNode else { return }
//        
//        audioEngine.attach(playerNode)
//        let sampleRate = Double(KokoroTTS.Constants.samplingRate)
//        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
//        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
//        
//        let voiceFilePath = Bundle.main.url(forResource: "voices", withExtension: "npz")!
//        voices = NpyzReader.read(fileFromPath: voiceFilePath)
//        
//        // Break into distinct steps to fix type checker
//        guard let voicesDict = voices else {
//            print("Failed to load voices")
//            return
//        }
//        
//        let voiceKeys = voicesDict.keys
//        let nameStrings = voiceKeys.map { String($0) }
//        let splitNames = nameStrings.map { String($0.split(separator: ".").first ?? "") }
//        voiceNames = splitNames.sorted()
//        
//        if !voiceNames.isEmpty {
//            selectedVoice = voiceNames[0]
//        }
//        
//        #if os(iOS)
//        do {
//            let audioSession = AVAudioSession.sharedInstance()
//            try audioSession.setCategory(.playback, mode: .default)
//            try audioSession.setActive(true)
//        } catch {
//            print("Failed to set up AVAudioSession: \(error.localizedDescription)")
//        }
//        #endif
//    }
//    
//    func say(text: String, completion: @escaping () -> Void) {
//        // Respect user setting
//        guard settings.ttsEnabled else {
//            print("TTS is disabled in settings – skipping speech.")
//            completion()
//            return
//        }
//        
//        guard let playerNode = playerNode,
//              let kokoroTTSEngine = kokoroTTSEngine,
//              let voices = voices else {
//            print("Kokoro TTS not available on this device or not initialized")
//            completion()
//            return
//        }
//        
//        playerNode.stop()
//        playerNode.reset()
//        
//        let result = try! kokoroTTSEngine.generateAudio(
//            voice: voices[selectedVoice + ".npy"]!,
//            language: selectedVoice.first! == "a" ? .enUS : .enGB,
//            text: text
//        )
//        let audio = result.0
//        let tokenArray = result.1
//        
//        // Simplified token handling - no MToken properties needed
//        if let tokenArray = tokenArray {
//            for token in tokenArray {
//                print("Token: \(token.text)")
//            }
//        }
//        
//        let sampleRate = Double(KokoroTTS.Constants.samplingRate)
//        let audioLength = Double(audio.count) / sampleRate
//        print("Audio Length: \(String(format: "%.4f", audioLength))")
//        
//        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
//        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.count)) else {
//            print("Couldn't create buffer")
//            completion()
//            return
//        }
//        
//        buffer.frameLength = buffer.frameCapacity
//        let channels = buffer.floatChannelData!
//        let dst = UnsafeMutablePointer<Float>(channels[0])
//        audio.withUnsafeBufferPointer { buf in
//            precondition(buf.baseAddress != nil)
//            let byteCount = buf.count * MemoryLayout<Float>.stride
//            UnsafeMutableRawPointer(dst).copyMemory(from: UnsafeRawPointer(buf.baseAddress!), byteCount: byteCount)
//        }
//        
//        do {
//            try audioEngine!.start()
//        } catch {
//            print("Audio engine failed to start: \(error.localizedDescription)")
//            completion()
//            return
//        }
//        
//        playerNode.scheduleBuffer(buffer, at: nil, options: []) {
//            completion()
//        }
//        playerNode.play()
//        
//        // Simplified word following - just set full text
//        stringToFollowTheAudio = text
//    }
//}
