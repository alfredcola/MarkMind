import AVFoundation
import MLX
import KokoroSwift
import Combine

final class TTSAudioCache: ObservableObject {
    static let shared = TTSAudioCache()

    private var bufferCache: [Int: AVAudioPCMBuffer] = [:]
    private let cacheQueue = DispatchQueue(label: "com.markmind.tts.cache", qos: .userInitiated)
    private let lockQueue = DispatchQueue(label: "com.markmind.tts.cachelock")

    let maxCacheSize = 7

    private var preloadTask: DispatchWorkItem?
    private var isPreloading = false

    private init() {}

    func preloadNext(from currentIndex: Int, text: String, model: TestAppModel) {
        let nextIndex = currentIndex + 1

        lockQueue.sync {
            if bufferCache[nextIndex] != nil { return }
        }

        generateBufferAsync(for: text, model: model) { [weak self] buffer in
            guard let self = self, let buffer = buffer else { return }
            self.lockQueue.async {
                self.bufferCache[nextIndex] = buffer
                self.evictOldBuffers(keepingFrom: currentIndex)
            }
        }
    }

    func preloadCurrent(currentIndex: Int, text: String, model: TestAppModel, completion: (() -> Void)? = nil) {
        lockQueue.sync {
            if bufferCache[currentIndex] != nil {
                completion?()
                return
            }
        }

        generateBufferAsync(for: text, model: model) { [weak self] buffer in
            guard let self = self, let buffer = buffer else {
                completion?()
                return
            }
            self.lockQueue.async {
                self.bufferCache[currentIndex] = buffer
                self.evictOldBuffers(keepingFrom: currentIndex)
            }
            completion?()
        }
    }

    func preloadMultiple(from startIndex: Int, texts: [(index: Int, text: String)], model: TestAppModel, completion: (() -> Void)? = nil) {
        guard !texts.isEmpty else {
            completion?()
            return
        }

        if isPreloading {
            completion?()
            return
        }

        isPreloading = true
        preloadTask?.cancel()

        let task = DispatchWorkItem { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion?() }
                return
            }

            var textsToCache = texts

            self.lockQueue.sync {
                textsToCache = texts.filter { self.bufferCache[$0.index] == nil }
            }

            guard !textsToCache.isEmpty else {
                self.isPreloading = false
                DispatchQueue.main.async { completion?() }
                return
            }

            let semaphore = DispatchSemaphore(value: 2)
            let group = DispatchGroup()

            for item in textsToCache {
                guard self.preloadTask?.isCancelled != true else { break }

                group.enter()
                semaphore.wait()

                self.generateBufferAsync(for: item.text, model: model) { [weak self] buffer in
                    defer { semaphore.signal(); group.leave() }
                    guard let self = self, let buffer = buffer else { return }
                    self.lockQueue.async {
                        self.bufferCache[item.index] = buffer
                        self.evictOldBuffers(keepingFrom: startIndex)
                    }
                }
            }

            group.wait()
            self.isPreloading = false
            DispatchQueue.main.async { completion?() }
        }

        preloadTask = task
        cacheQueue.async(execute: task)
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

    func clearAll() {
        preloadTask?.cancel()
        isPreloading = false
        lockQueue.async { [weak self] in
            self?.bufferCache.removeAll()
        }
    }

    private func generateBufferAsync(for text: String, model: TestAppModel, completion: @escaping (AVAudioPCMBuffer?) -> Void) {
        guard let tts = model.kokoroTTSEngine,
              let voices = model.voices,
              let voiceData = voices[model.selectedVoice + ".npy"] else {
            completion(nil)
            return
        }

        cacheQueue.async {
            var audioFloats: [Float] = []

            do {
                let generated = try tts.generateAudio(
                    voice: voiceData,
                    language: model.selectedVoice.first == "a" ? .enUS : .enGB,
                    text: text
                )
                audioFloats = generated.0
            } catch {
                print("TTSAudioCache: generateAudio failed: \(error)")
                completion(nil)
                return
            }

            guard !audioFloats.isEmpty else {
                completion(nil)
                return
            }

            let sampleRate = Double(KokoroTTS.Constants.samplingRate)

            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioFloats.count)) else {
                completion(nil)
                return
            }

            buffer.frameLength = buffer.frameCapacity

            if let channelData = buffer.floatChannelData?[0] {
                for i in 0..<audioFloats.count {
                    channelData[i] = audioFloats[i]
                }
            }

            completion(buffer)
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
                print("TTSAudioCache: AudioEngine start failed: \(error)")
                completion()
                return
            }
        }

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: completion)
        player.play()
        player.rate = model.playbackRate
    }
}