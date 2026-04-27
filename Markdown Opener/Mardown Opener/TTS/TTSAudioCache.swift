import AVFoundation
import MLX
import KokoroSwift
import Combine

final class TTSAudioCache: ObservableObject {
    static let shared = TTSAudioCache()

    private var bufferCache: [Int: AVAudioPCMBuffer] = [:]
    private let lockQueue = DispatchQueue(label: "com.markmind.tts.cachelock")
    private let ttsQueue = DispatchQueue(label: "com.markmind.tts.generation", qos: .userInitiated)

    let maxCacheSize = 10
    private let maxTotalBuffers = 20

    private var preloadTask: Task<Void, Never>?
    private var isPreloading = false
    private var isCancelled = false

    private init() {}

    func cancelPreload() {
        isCancelled = true
        preloadTask?.cancel()
        preloadTask = nil
        isPreloading = false
    }

    func resetCancellation() {
        isCancelled = false
    }

    func preloadCurrent(currentIndex: Int, text: String, model: TestAppModel, completion: (() -> Void)? = nil) {
        guard !isCancelled else {
            completion?()
            return
        }

        lockQueue.sync {
            if bufferCache[currentIndex] != nil {
                completion?()
                return
            }
        }

        Task { [weak self] in
            guard let self = self, !self.isCancelled else {
                completion?()
                return
            }
            if let buffer = await self.generateBuffer(for: text, model: model) {
                self.lockQueue.async {
                    guard !self.isCancelled else { return }
                    self.bufferCache[currentIndex] = buffer
                    self.evictOldBuffers(keepingFrom: currentIndex)
                }
            }
            completion?()
        }
    }

    func preloadMultiple(from startIndex: Int, texts: [(index: Int, text: String)], model: TestAppModel, completion: (() -> Void)? = nil) {
        guard !texts.isEmpty, !isCancelled else {
            completion?()
            return
        }

        if isPreloading {
            completion?()
            return
        }

        resetCancellation()
        cancelPreload()
        isPreloading = true

        preloadTask = Task { [weak self] in
            guard let self = self else {
                completion?()
                return
            }

            var textsToCache: [(index: Int, text: String)] = []

            self.lockQueue.sync {
                textsToCache = texts.filter { self.bufferCache[$0.index] == nil }
            }

            guard !textsToCache.isEmpty else {
                self.isPreloading = false
                await MainActor.run { completion?() }
                return
            }

            for item in textsToCache {
                guard !Task.isCancelled, !self.isCancelled else { break }

                if let buffer = await self.generateBuffer(for: item.text, model: model) {
                    self.lockQueue.async {
                        guard !self.isCancelled else { return }
                        self.bufferCache[item.index] = buffer
                        self.evictOldBuffers(keepingFrom: startIndex)
                    }
                }
            }

            self.isPreloading = false
            if !Task.isCancelled {
                await MainActor.run { completion?() }
            }
        }
    }

    private func generateBuffer(for text: String, model: TestAppModel) async -> AVAudioPCMBuffer? {
        guard !isCancelled else { return nil }
        guard let tts = model.kokoroTTSEngine,
              let voices = model.voices,
              let voiceData = voices[model.selectedVoice + ".npy"] else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            ttsQueue.async { [weak self] in
                guard self == nil || !self!.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let generated = try tts.generateAudio(
                        voice: voiceData,
                        language: model.selectedVoice.first == "a" ? .enUS : .enGB,
                        text: text
                    )
                    let audioFloats = generated.0

                    guard !audioFloats.isEmpty else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let sampleRate = Double(KokoroTTS.Constants.samplingRate)

                    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
                          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioFloats.count)) else {
                        continuation.resume(returning: nil)
                        return
                    }

                    buffer.frameLength = buffer.frameCapacity

                    if let channelData = buffer.floatChannelData?[0] {
                        audioFloats.withUnsafeBufferPointer { src in
                            guard let srcBase = src.baseAddress else { return }
                            channelData.update(from: srcBase, count: audioFloats.count)
                        }
                    }

                    continuation.resume(returning: buffer)
                } catch {
                    Log.error("TTSAudioCache: generateAudio failed", category: .tts, error: error)
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func evictOldBuffers(keepingFrom currentIndex: Int) {
        let windowStart = max(0, currentIndex - 1)
        let windowEnd = currentIndex + maxCacheSize

        var keysToRemove: [Int] = []
        for key in bufferCache.keys {
            if key < windowStart || key > windowEnd {
                keysToRemove.append(key)
            }
        }

        if bufferCache.count > maxTotalBuffers {
            let excess = bufferCache.count - maxTotalBuffers
            let sortedKeys = bufferCache.keys.sorted()
            for key in sortedKeys.prefix(excess) where key < windowStart || key > windowEnd {
                keysToRemove.append(key)
            }
        }

        for key in keysToRemove {
            bufferCache.removeValue(forKey: key)
        }
    }

    func getBuffer(for index: Int) -> AVAudioPCMBuffer? {
        lockQueue.sync {
            bufferCache[index]
        }
    }

    func hasBuffer(for index: Int) -> Bool {
        lockQueue.sync {
            bufferCache[index] != nil
        }
    }

    func cacheBuffer(_ buffer: AVAudioPCMBuffer, for index: Int) {
        lockQueue.async { [weak self] in
            self?.bufferCache[index] = buffer
            self?.evictOldBuffers(keepingFrom: index)
        }
    }

    func clearAll() {
        cancelPreload()
        lockQueue.async { [weak self] in
            self?.bufferCache.removeAll()
        }
    }

    func playFromCache(_ buffer: AVAudioPCMBuffer, model: TestAppModel, completion: @escaping () -> Void) {
        guard let engine = model.audioEngine,
              let player = model.playerNode else {
            completion()
            return
        }

        player.stop()
        player.reset()

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                Log.error("TTSAudioCache: AudioEngine start failed", category: .tts, error: error)
                completion()
                return
            }
        }

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: completion)
        player.play()
        player.rate = model.playbackRate
    }
}