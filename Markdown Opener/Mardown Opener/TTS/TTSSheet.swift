//
//  TTSSheet.swift
//  Markdown Opener
//
//  Enhanced Text-to-Speech Reader with Background Playback
//

import AVFoundation
import MLX
import KokoroSwift
import Combine
import MLXUtilsLibrary
import SwiftUI
import WebKit
import MediaPlayer

struct TTSSheet: View {
    let markdown: String
    let filePath: String?

    @EnvironmentObject var model: TestAppModel
    @State private var chunks: [TTSChunk] = []
    @State private var currentChunkIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var spokenSoFarInCurrentChunk: String = ""
    @State private var showSettingsSheet: Bool = false
    @ObservedObject private var settingsVM = MultiSettingsViewModel.shared
    @State private var chunkTimer: Timer? = nil
    @State private var isPausedMidChunk: Bool = false
    @State private var pausedChunkText: String = ""
    @State private var wasManuallySelected: Bool = false
    @State private var chineseSynthesizer = AVSpeechSynthesizer()
    @State private var chineseDelegate: TTSUtils.ChineseTTSDelegate?
    @State private var sleepTimerManager = TTSSleepTimerManager.shared
    @State private var abRepeatManager = TTSABRepeatManager.shared
    @State private var showResumePrompt: Bool = false
    @State private var savedChunkIndex: Int = 0
    @State private var currentTTSEngine: TTSEngine = .kokoro
    @State private var isLoading: Bool = true
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @State private var wasPlayingBeforeBackground: Bool = false
    @State private var displaySpokenText: String = ""

    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase

    enum TTSEngine {
        case kokoro
        case avSpeech
    }

    struct TTSChunk: Identifiable {
        let id = UUID()
        let text: String
        let shouldUseKokoro: Bool
        let isEnglish: Bool
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if chunks.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }
            }
            .navigationTitle("Reading Aloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .onAppear {
                setupBackgroundPlayback()
                processContent()
            }
            .onDisappear {
                stopPlayback()
                sleepTimerManager.stop()
                endBackgroundTask()
                BackgroundTTSManager.shared.clearRemoteCommandCenter()
                BackgroundTTSManager.shared.clearNowPlayingInfo()
                BackgroundTTSManager.shared.deactivateAudioSession()
            }
            .onChange(of: isPlaying) { _, newValue in
                UIApplication.shared.isIdleTimerDisabled = newValue
                updateNowPlayingInfo()
            }
            .onChange(of: currentChunkIndex) { _, newIndex in
                updateNowPlayingInfo()
                displaySpokenText = ""
                spokenSoFarInCurrentChunk = ""
                if let path = filePath {
                    TTSReadingPositionManager.shared.savePosition(for: path, chunkIndex: newIndex)
                }
            }
            .onChange(of: model.stringToFollowTheAudio) { _, newValue in
                spokenSoFarInCurrentChunk = newValue.trimmingCharacters(in: .whitespaces)
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .background && isPlaying {
                    wasPlayingBeforeBackground = true
                    startBackgroundPreload()
                } else if newPhase == .active {
                    if wasPlayingBeforeBackground && isPlaying {
                        continuePlaybackIfReady()
                    }
                    wasPlayingBeforeBackground = false
                }
            }
            .sheet(isPresented: $showSettingsSheet) {
                TTSSettingsSheet()
                    .environmentObject(model)
            }
            .alert("Continue Reading?", isPresented: $showResumePrompt) {
                Button("Continue from Chunk \(savedChunkIndex + 1)") {
                    currentChunkIndex = savedChunkIndex
                    updateCurrentTTSEngine()
                }
                Button("Start from Beginning", role: .destructive) {
                    currentChunkIndex = 0
                    if let path = filePath {
                        TTSReadingPositionManager.shared.clearPosition(for: path)
                    }
                }
                Button("Cancel", role: .cancel) {
                    showResumePrompt = false
                }
            } message: {
                if let path = filePath {
                    let fileName = (path as NSString).lastPathComponent
                    Text("Resume \"\(fileName)\" at chunk \(savedChunkIndex + 1)?")
                } else {
                    Text("Resume at chunk \(savedChunkIndex + 1)?")
                }
            }
        }
    }

    private var backgroundColor: Color {
        settingsVM.ttsTheme.backgroundColor
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            progressSection

            chunkDisplay

            controlsSection
        }
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            Text("\(currentChunkIndex + 1) of \(chunks.count)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)

            ProgressView(value: Double(currentChunkIndex + 1), total: Double(chunks.count))
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    private var chunkDisplay: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(chunks.enumerated()), id: \.offset) { i, chunk in
                        chunkRow(chunk: chunk, index: i, isCurrent: i == currentChunkIndex)
                            .onTapGesture {
                                playChunk(at: i)
                            }
                    }
                }
                .padding()
            }
            .onChange(of: currentChunkIndex) { _, newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func chunkRow(chunk: TTSChunk, index: Int, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(index + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.secondary.opacity(0.2)))

                Spacer()

                Text(chunk.shouldUseKokoro ? "EN" : "CN")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(chunk.shouldUseKokoro ? Color.blue : Color.green))
            }

            chunkText(chunk: chunk, isCurrent: isCurrent)
                .font(.system(size: settingsVM.ttsFontSize.fontSize))
                .lineSpacing(6)
                .foregroundColor(isCurrent ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrent
                    ? Color.accentColor.opacity(0.15)
                    : Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .scaleEffect(isCurrent ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentChunkIndex)
        .id(index)
    }

    @ViewBuilder
    private func chunkText(chunk: TTSChunk, isCurrent: Bool) -> some View {
        if isCurrent {
            highlightCurrentChunk(full: chunk.text, spoken: displaySpokenText)
        } else {
            Text(chunk.text)
        }
    }

    private var controlsSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                Button {
                    previousChunk()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .disabled(currentChunkIndex == 0)

                Button {
                    togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(isPlaying ? .orange : .accentColor)
                }

                Button {
                    nextChunk()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .disabled(currentChunkIndex >= chunks.count - 1)

                Button {
                    stopPlayback()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground).opacity(0.95))
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.quote")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No readable text found")
                .font(.headline)
        }
    }

    // MARK: - Content Processing

    private func processContent() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let computedChunks = computeChunks()

            DispatchQueue.main.async {
                self.chunks = computedChunks
                self.isLoading = false
                self.updateCurrentTTSEngine()
                self.restoreReadingPosition()
                self.warmupCache()
            }
        }
    }

    private func restoreReadingPosition() {
        guard settingsVM.ttsAutoResume, let path = filePath else { return }

        if let savedIndex = TTSReadingPositionManager.shared.getPosition(for: path),
           savedIndex > 0 && savedIndex < chunks.count {
            savedChunkIndex = savedIndex
            showResumePrompt = true
        }
    }

    private func warmupCache() {
        guard chunks.count > 1 else { return }
        guard TestAppModel.isSupportedDevice() else { return }

        var textsToPreload: [(index: Int, text: String)] = []

        for i in 0..<min(2, chunks.count) {
            let chunk = chunks[i]
            if chunk.shouldUseKokoro {
                textsToPreload.append((index: i, text: chunk.text))
            }
        }

        guard !textsToPreload.isEmpty else { return }

        TTSAudioCache.shared.preloadMultiple(from: 0, texts: textsToPreload, model: model, completion: nil)
    }

    private func computeChunks() -> [TTSChunk] {
        let clean = TTSUtils.cleanMarkdownForTTS(markdown)
        let paragraphs = clean.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var finalChunks: [TTSChunk] = []

        for paragraph in paragraphs {
            guard isReadableChunk(paragraph) else { continue }

            let sentences = TTSUtils.linguisticSentenceSplit(paragraph)
            var currentChunk = ""

            for sentence in sentences {
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                if currentChunk.isEmpty {
                    currentChunk = trimmed
                } else if currentChunk.count + trimmed.count + 1 <= 500 {
                    currentChunk += " " + trimmed
                } else {
                    if currentChunk.count >= 20 {
                        let shouldUseKokoro = TTSUtils.canKokoroHandleText(currentChunk)
                        finalChunks.append(TTSChunk(text: currentChunk, shouldUseKokoro: shouldUseKokoro, isEnglish: shouldUseKokoro))
                    }
                    currentChunk = trimmed
                }
            }

            if currentChunk.count >= 20 {
                let shouldUseKokoro = TTSUtils.canKokoroHandleText(currentChunk)
                finalChunks.append(TTSChunk(text: currentChunk, shouldUseKokoro: shouldUseKokoro, isEnglish: shouldUseKokoro))
            }
        }

        return finalChunks
    }

    private func isReadableChunk(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let alphanumeric = CharacterSet.alphanumerics.union(.whitespacesAndNewlines)
        let readableCount = text.unicodeScalars.filter { alphanumeric.contains($0) }.count
        return Double(readableCount) / Double(text.count) >= 0.5
    }

    private var useBuiltInTTSForCurrentFile: Bool {
        guard !chunks.isEmpty else { return false }
        return !chunks[currentChunkIndex].shouldUseKokoro
    }

    // MARK: - Highlighting

    private func highlightCurrentChunk(full: String, spoken: String) -> Text {
        let words = full.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var result = Text("")
        let spokenLower = spoken.lowercased()
        var consumed = spokenLower

        for word in words {
            let clean = word.replacingOccurrences(of: "[^a-zA-Z0-9']", with: "", options: .regularExpression).lowercased()
            if !clean.isEmpty && consumed.contains(clean) {
                result = result + Text(word + " ").bold()
                if let range = consumed.range(of: clean) {
                    consumed.removeSubrange(range)
                }
            } else {
                result = result + Text(word + " ").foregroundColor(.secondary)
            }
        }
        return result
    }

    // MARK: - Background Playback

    private func setupBackgroundPlayback() {
        BackgroundTTSManager.shared.setupAudioSession()

        BackgroundTTSManager.shared.setupRemoteCommandCenter(
            onPlay: { [self] in
                DispatchQueue.main.async {
                    self.togglePlayPause()
                }
            },
            onPause: { [self] in
                DispatchQueue.main.async {
                    self.togglePlayPause()
                }
            },
            onNext: { [self] in
                DispatchQueue.main.async {
                    self.nextChunk()
                }
            },
            onPrevious: { [self] in
                DispatchQueue.main.async {
                    self.previousChunk()
                }
            },
            onSkipForward: { [self] in
                DispatchQueue.main.async {
                    self.nextChunk()
                }
            },
            onSkipBackward: { [self] in
                DispatchQueue.main.async {
                    self.previousChunk()
                }
            }
        )

        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        guard !chunks.isEmpty else { return }

        let fileName = (filePath as NSString?)?.lastPathComponent ?? "Text-to-Speech"
        let playbackRate = isPlaying ? Double(settingsVM.ttsPlaybackSpeed) : 0.0

        BackgroundTTSManager.shared.updateNowPlayingInfo(
            title: fileName,
            chunkIndex: currentChunkIndex,
            totalChunks: chunks.count,
            isPlaying: isPlaying,
            playbackRate: playbackRate
        )
    }

    private func startBackgroundPreload() {
        guard backgroundTaskID == .invalid else { return }
        guard isPlaying && currentChunkIndex < chunks.count else { return }

        let currentChunk = chunks[currentChunkIndex]
        guard currentChunk.shouldUseKokoro && TestAppModel.isSupportedDevice() else {
            return
        }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [self] in
            self.endBackgroundTask()
        }

        guard backgroundTaskID != .invalid else { return }

        TTSAudioCache.shared.preloadCurrent(
            currentIndex: currentChunkIndex,
            text: currentChunk.text,
            model: model
        ) { [self] in
            self.preloadFutureChunks()
        }
    }

    private func preloadFutureChunks() {
        let preloadCount = 3
        var textsToPreload: [(index: Int, text: String)] = []

        for i in 1...preloadCount {
            let nextIndex = currentChunkIndex + i
            guard nextIndex < chunks.count else { break }
            let chunk = chunks[nextIndex]
            if chunk.shouldUseKokoro && TestAppModel.isSupportedDevice() {
                textsToPreload.append((index: nextIndex, text: chunk.text))
            }
        }

        guard !textsToPreload.isEmpty else {
            endBackgroundTask()
            return
        }

        TTSAudioCache.shared.preloadMultiple(from: currentChunkIndex, texts: textsToPreload, model: model) { [self] in
            self.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    private func continuePlaybackIfReady() {
        let nextIndex = currentChunkIndex + 1
        guard nextIndex < chunks.count else { return }

        if TTSAudioCache.shared.hasBuffer(for: nextIndex) {
            currentChunkIndex = nextIndex
            spokenSoFarInCurrentChunk = ""
            updateCurrentTTSEngine()
            playCurrentChunk()
            preloadNextFewChunks()
        } else {
            preloadNextFewChunks()
        }
    }

    private func preloadNextFewChunks() {
        var textsToPreload: [(index: Int, text: String)] = []
        let startIndex = max(0, currentChunkIndex - 1)

        for i in 0..<3 {
            let idx = startIndex + i
            guard idx < chunks.count else { break }
            guard chunks[idx].shouldUseKokoro && TestAppModel.isSupportedDevice() else { continue }
            if !TTSAudioCache.shared.hasBuffer(for: idx) {
                textsToPreload.append((index: idx, text: chunks[idx].text))
            }
        }

        guard !textsToPreload.isEmpty else { return }
        TTSAudioCache.shared.preloadMultiple(from: currentChunkIndex, texts: textsToPreload, model: model, completion: nil)
    }

    // MARK: - Playback Controls

    private func playCurrentChunk() {
        guard isPlaying, currentChunkIndex < chunks.count else { return }

        if abRepeatManager.shouldLoop(backToA: currentChunkIndex) {
            currentChunkIndex = abRepeatManager.getPointAIndex()
            spokenSoFarInCurrentChunk = ""
        }

        let chunk = chunks[currentChunkIndex]
        currentTTSEngine = chunk.shouldUseKokoro ? .kokoro : .avSpeech

        if chunk.shouldUseKokoro && TestAppModel.isSupportedDevice() {
            playKokoroChunk()
        } else {
            playAVSpeech(chunk.text)
        }
    }

    private func playChunk(at index: Int) {
        guard index >= 0 && index < chunks.count else { return }
        wasManuallySelected = true
        stopPlayback()
        currentChunkIndex = index
        spokenSoFarInCurrentChunk = ""
        isPlaying = true
        playCurrentChunk()
    }

    private func playKokoroChunk() {
        let chunk = chunks[currentChunkIndex]

        if let cachedBuffer = TTSAudioCache.shared.getBuffer(for: currentChunkIndex) {
            TTSAudioCache.shared.playFromCache(cachedBuffer, model: model) { [self] in
                DispatchQueue.main.async {
                    handlePlaybackComplete()
                }
            }
        } else {
            model.playerNode?.stop()
            model.playerNode?.reset()
            model.updatePlaybackRate(Float(settingsVM.ttsPlaybackSpeed))

            model.say(text: chunk.text) { [self] in
                DispatchQueue.main.async {
                    handlePlaybackComplete()
                }
            }
        }

        model.stringToFollowTheAudio = chunk.text
        startChunkMonitoring()

        let nextIndex = currentChunkIndex + 1
        if nextIndex < chunks.count && chunks[nextIndex].shouldUseKokoro {
            var textsToPreload: [(index: Int, text: String)] = []
            for i in 0..<2 {
                let idx = nextIndex + i
                guard idx < chunks.count, chunks[idx].shouldUseKokoro else { break }
                if !TTSAudioCache.shared.hasBuffer(for: idx) {
                    textsToPreload.append((index: idx, text: chunks[idx].text))
                }
            }
            if !textsToPreload.isEmpty {
                TTSAudioCache.shared.preloadMultiple(from: currentChunkIndex, texts: textsToPreload, model: model, completion: nil)
            }
        }
    }

    private func playAVSpeech(_ text: String) {
        let (isChinese, _) = TTSUtils.detectContentLanguage(text)
        let locale = isChinese ? "zh-HK" : "en-US"

        chineseDelegate = TTSUtils.ChineseTTSDelegate { 
            DispatchQueue.main.async {
                self.handlePlaybackComplete()
            }
        }
        chineseSynthesizer.delegate = chineseDelegate

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: locale)
        utterance.rate = isChinese ? AVSpeechUtteranceDefaultSpeechRate * 0.9 : AVSpeechUtteranceDefaultSpeechRate * 0.85
        utterance.pitchMultiplier = Float(settingsVM.ttsPitch)

        chineseSynthesizer.speak(utterance)
    }

    private func handlePlaybackComplete() {
        if isPlaying && !wasManuallySelected {
            if currentChunkIndex < chunks.count - 1 {
                currentChunkIndex += 1
                spokenSoFarInCurrentChunk = ""
                updateCurrentTTSEngine()
                playCurrentChunk()
            } else {
                if sleepTimerManager.isEndOfDocumentMode {
                    sleepTimerManager.triggerEndOfDocument()
                }
                stopPlayback()
            }
        }
        wasManuallySelected = false
        isPausedMidChunk = false
    }

    private func startChunkMonitoring() {
        chunkTimer?.invalidate()
        chunkTimer = Timer.scheduledTimer(withTimeInterval: Constants.TTS.chunkProcessingInterval, repeats: true) { _ in
            if self.model.stringToFollowTheAudio.isEmpty {
                self.chunkTimer?.invalidate()
                return
            }
            let newText = self.model.stringToFollowTheAudio.trimmingCharacters(in: .whitespaces)
            if newText != self.displaySpokenText {
                self.displaySpokenText = newText
            }
        }
    }

    private func togglePlayPause() {
        if isPlaying {
            if currentTTSEngine == .avSpeech {
                chineseSynthesizer.pauseSpeaking(at: .immediate)
            } else {
                model.playerNode?.pause()
            }
            isPlaying = false
            isPausedMidChunk = true
            pausedChunkText = chunks[currentChunkIndex].text
            chunkTimer?.invalidate()
            model.timer?.invalidate()
        } else {
            isPlaying = true
            if isPausedMidChunk && !pausedChunkText.isEmpty {
                wasManuallySelected = true
                playCurrentChunkWithText(pausedChunkText)
            } else {
                playCurrentChunk()
            }
        }
    }

    private func playCurrentChunkWithText(_ text: String) {
        let chunk = chunks[currentChunkIndex]
        if chunk.shouldUseKokoro && TestAppModel.isSupportedDevice() {
            model.say(text: text) { [self] in
                DispatchQueue.main.async {
                    handlePlaybackComplete()
                }
            }
        } else {
            playAVSpeech(text)
        }
    }

    private func stopPlayback() {
        isPlaying = false
        if currentTTSEngine == .avSpeech {
            chineseSynthesizer.stopSpeaking(at: .immediate)
        } else {
            model.playerNode?.stop()
            model.playerNode?.reset()
            model.timer?.invalidate()
        }
        chunkTimer?.invalidate()
        TTSAudioCache.shared.clearAll()
        spokenSoFarInCurrentChunk = ""
        displaySpokenText = ""
    }

    private func previousChunk() {
        guard currentChunkIndex > 0 else { return }
        isPlaying = false
        currentChunkIndex -= 1
        isPlaying = true
        playCurrentChunk()
    }

    private func nextChunk() {
        guard currentChunkIndex < chunks.count - 1 else { return }
        isPlaying = false
        currentChunkIndex += 1
        isPlaying = true
        playCurrentChunk()
    }

    private func updateCurrentTTSEngine() {
        guard !chunks.isEmpty else { return }
        currentTTSEngine = chunks[currentChunkIndex].shouldUseKokoro ? .kokoro : .avSpeech
    }
}