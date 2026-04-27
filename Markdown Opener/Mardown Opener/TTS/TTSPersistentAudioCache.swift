@preconcurrency import AVFoundation
import KokoroSwift
import Combine

final class TTSPersistentAudioCache: ObservableObject {
    static let shared = TTSPersistentAudioCache()

    @Published private(set) var isPreloadingAll = false
    @Published private(set) var preloadProgress: Double = 0
    @Published private(set) var currentPreloadIndex: Int = 0
    @Published private(set) var totalChunksToPreload: Int = 0
    @Published private(set) var cachedSizeOnDisk: Int64 = 0

    private let cacheDirectory: URL
    private var preloadTask: Task<Void, Never>?
    private let ttsQueue = DispatchQueue(label: "com.markmind.tts.persistentcache", qos: .userInitiated)
    private let writeQueue = DispatchQueue(label: "com.markmind.tts.write", qos: .userInitiated)

    private let maxConcurrentGenerations = 3
    private var diskCacheCheckCache: [String: Set<Int>] = [:]
    private let cacheLock = NSLock()

    private init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cacheDir.appendingPathComponent("TTSAudioCache", isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        updateCachedSize()
    }

    func directoryForFile(_ filePath: String) -> URL {
        let hash = abs(filePath.hashValue)
        return cacheDirectory.appendingPathComponent("\(hash)", isDirectory: true)
    }

    func audioFilePath(for filePath: String, chunkIndex: Int) -> URL {
        return directoryForFile(filePath).appendingPathComponent("chunk_\(chunkIndex).wav")
    }

    func hasCachedAudio(for filePath: String, chunkIndex: Int) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let cached = diskCacheCheckCache[filePath] else {
            let path = audioFilePath(for: filePath, chunkIndex: chunkIndex)
            return FileManager.default.fileExists(atPath: path.path)
        }
        if cached.contains(chunkIndex) {
            return true
        }
        let path = audioFilePath(for: filePath, chunkIndex: chunkIndex)
        return FileManager.default.fileExists(atPath: path.path)
    }

    func buildCacheCheckCache(for filePath: String, chunkIndices: [Int]) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        var cached = Set<Int>()
        let fileDir = directoryForFile(filePath)
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: fileDir.path) else {
            diskCacheCheckCache[filePath] = cached
            return
        }
        for name in contents where name.hasPrefix("chunk_") && name.hasSuffix(".wav") {
            if let index = Int(name.dropFirst(6).dropLast(4)) {
                cached.insert(index)
            }
        }
        diskCacheCheckCache[filePath] = cached
    }

    func preloadAllChunks(
        chunks: [TTSSheet.TTSChunk],
        filePath: String,
        model: TestAppModel,
        voiceLocale: KokoroSwift.Language,
        completion: @escaping () -> Void
    ) {
        guard !isPreloadingAll else {
            completion()
            return
        }

        let kokoroChunks = chunks.enumerated().compactMap { index, chunk -> (index: Int, text: String)? in
            guard chunk.shouldUseKokoro else { return nil }
            return (index, chunk.text)
        }

        guard !kokoroChunks.isEmpty else {
            completion()
            return
        }

        isPreloadingAll = true
        preloadProgress = 0
        currentPreloadIndex = 0
        totalChunksToPreload = kokoroChunks.count

        let fileDir = directoryForFile(filePath)
        try? FileManager.default.createDirectory(at: fileDir, withIntermediateDirectories: true)
        buildCacheCheckCache(for: filePath, chunkIndices: kokoroChunks.map { $0.index })

        let pendingChunks = kokoroChunks.filter { !hasCachedAudio(for: filePath, chunkIndex: $0.index) }

        guard !pendingChunks.isEmpty else {
            isPreloadingAll = false
            preloadProgress = 1.0
            completion()
            return
        }

        preloadTask = Task { [weak self] in
            guard let self = self else { return }

            await self.processChunksInBatches(
                chunks: pendingChunks,
                filePath: filePath,
                model: model,
                language: voiceLocale
            )

            await MainActor.run {
                self.isPreloadingAll = false
                self.preloadProgress = 1.0
                self.updateCachedSize()
                completion()
            }
        }
    }

    private func processChunksInBatches(
        chunks: [(index: Int, text: String)],
        filePath: String,
        model: TestAppModel,
        language: KokoroSwift.Language
    ) async {
        let totalCount = chunks.count
        var completed = 0

        for batch in chunks.chunked(into: maxConcurrentGenerations) {
            guard !Task.isCancelled, isPreloadingAll else { break }

            let tasks = batch.map { item -> Task<Bool, Never> in
                Task {
                    guard !Task.isCancelled, self.isPreloadingAll else { return false }
                    if let buffer = await self.generateBuffer(for: item.text, model: model, language: language) {
                        await self.saveBufferToDiskAsync(buffer: buffer, filePath: filePath, chunkIndex: item.index)
                        return true
                    }
                    return false
                }
            }

            var results = [Bool]()
            for task in tasks {
                results.append(await task.value)
            }
            completed += results.filter { $0 }.count

            await MainActor.run {
                self.currentPreloadIndex = completed
                self.preloadProgress = Double(completed) / Double(totalCount)
            }
        }
    }

    private func generateBuffer(for text: String, model: TestAppModel, language: KokoroSwift.Language) async -> AVAudioPCMBuffer? {
        guard let tts = model.kokoroTTSEngine,
              let voices = model.voices,
              let voiceData = voices[model.selectedVoice + ".npy"] else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            ttsQueue.async {
                do {
                    let generated = try tts.generateAudio(
                        voice: voiceData,
                        language: language,
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
                    Log.error("TTSPersistentAudioCache: generateAudio failed", category: .tts, error: error)
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func saveBufferToDiskAsync(buffer: AVAudioPCMBuffer, filePath: String, chunkIndex: Int) async {
        let fileURL = audioFilePath(for: filePath, chunkIndex: chunkIndex)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writeQueue.async {
                do {
                    let audioFile = try AVAudioFile(
                        forWriting: fileURL,
                        settings: [
                            AVFormatIDKey: kAudioFormatLinearPCM,
                            AVSampleRateKey: buffer.format.sampleRate,
                            AVNumberOfChannelsKey: buffer.format.channelCount,
                            AVLinearPCMBitDepthKey: 32,
                            AVLinearPCMIsFloatKey: true,
                            AVLinearPCMIsBigEndianKey: false,
                            AVLinearPCMIsNonInterleaved: false
                        ]
                    )
                    try audioFile.write(from: buffer)
                    self.cacheLock.lock()
                    if var cached = self.diskCacheCheckCache[filePath] {
                        cached.insert(chunkIndex)
                        self.diskCacheCheckCache[filePath] = cached
                    }
                    self.cacheLock.unlock()
                } catch {
                    Log.error("TTSPersistentAudioCache: Failed to write audio buffer to disk", category: .tts, error: error)
                }
                continuation.resume()
            }
        }
    }

    private var diskReadTask: Task<Void, Never>?

    func prefetchFromDisk(filePath: String, chunkIndex: Int) {
        guard chunkIndex >= 0 else { return }
        diskReadTask?.cancel()
        diskReadTask = Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            _ = self.loadFromDiskSync(filePath: filePath, chunkIndex: chunkIndex)
        }
    }

    func loadFromDisk(filePath: String, chunkIndex: Int) -> AVAudioPCMBuffer? {
        return loadFromDiskSync(filePath: filePath, chunkIndex: chunkIndex)
    }

    private func loadFromDiskSync(filePath: String, chunkIndex: Int) -> AVAudioPCMBuffer? {
        let fileURL = audioFilePath(for: filePath, chunkIndex: chunkIndex)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let format = audioFile.processingFormat
            let frameCount = AVAudioFrameCount(audioFile.length)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return nil
            }

            try audioFile.read(into: buffer)
            return buffer
        } catch {
            Log.error("TTSPersistentAudioCache: Failed to read audio file from disk", category: .tts, error: error)
            return nil
        }
    }

    func cancelPreload() {
        preloadTask?.cancel()
        preloadTask = nil
        isPreloadingAll = false
        preloadProgress = 0
        currentPreloadIndex = 0
    }

    func clearCachedAudio(for filePath: String) {
        cacheLock.lock()
        diskCacheCheckCache.removeValue(forKey: filePath)
        cacheLock.unlock()
        let fileDir = directoryForFile(filePath)
        try? FileManager.default.removeItem(at: fileDir)
        updateCachedSize()
    }

    func clearAllCachedAudio() {
        cacheLock.lock()
        diskCacheCheckCache.removeAll()
        cacheLock.unlock()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        updateCachedSize()
    }

    func cachedAudioSize(for filePath: String) -> Int64 {
        let fileDir = directoryForFile(filePath)
        return directorySize(at: fileDir)
    }

    private func updateCachedSize() {
        cachedSizeOnDisk = directorySize(at: cacheDirectory)
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }
        return totalSize
    }

    var formattedCachedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: cachedSizeOnDisk)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
