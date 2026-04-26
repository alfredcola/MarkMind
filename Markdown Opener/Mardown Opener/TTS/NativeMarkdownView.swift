//
//  NativeMarkdownView.swift
//  Fully Fixed & Optimized for Performance
//

import AVFoundation
import SwiftUI
import Foundation
import Markdown

struct NativeMarkdownView: View {
    let markdown: String
    var horizontalAlignment: HorizontalAlignment = .leading

    @EnvironmentObject var model: TestAppModel
    @ObservedObject private var settingsVM = MultiSettingsViewModel.shared

    private typealias ChineseTTSDelegate = TTSUtils.ChineseTTSDelegate

    // Cached results — recompute only when markdown changes
    @State private var attributedContent: AttributedString = AttributedString("")
    @State private var chunks: [String] = []
    @State private var useBuiltInTTS: Bool = false

    // Playback state
    @State private var currentChunkIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var spokenSoFarInCurrentChunk: String = ""
    @State private var chunkTimer: Timer? = nil
    @State private var isPausedMidChunk: Bool = false
    @State private var pausedChunkText: String = ""
    @State private var wasManuallySelected: Bool = false
    @Binding var ttsEnabled: Bool

    // TTS
    @State private var chineseSynthesizer = AVSpeechSynthesizer()
    @State private var chineseDelegate: ChineseTTSDelegate?
    
    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 0) {
            ScrollView {
                VStack(alignment: horizontalAlignment) {
                    Text(attributedContent)
                        .textSelection(.enabled)
                        .frame(alignment: horizontalAlignment == .leading ? .leading : .trailing)
                        .padding(.horizontal,4)
                }
            }
            
            if !chunks.isEmpty && ttsEnabled {
                playbackControls
            }
        }
        .task(id: markdown) {
            await processMarkdownContent(markdown)
        }
        .onChange(of: model.stringToFollowTheAudio) { _, newValue in
            if ttsEnabled{
                spokenSoFarInCurrentChunk = newValue.trimmingCharacters(in: .whitespaces)
            }
        }
        .onChange(of: settingsVM.selectedVoice) { _, _ in
            model.selectedVoice = settingsVM.selectedVoice.rawValue
        }
        .onDisappear {
            stopPlayback()
        }
    }
    
    @ViewBuilder
    private var playbackControls: some View {
        HStack {
            Text("\(currentChunkIndex + 1)/\(chunks.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            
            // Progress within current chunk
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                    
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: playbackProgress * geometry.size.width, height: 4)
                }
            }
            .frame(height: 4)
            
            Button(action: {
                model.selectedVoice = settingsVM.selectedVoice.rawValue
            }) {
                if useBuiltInTTS {
                    Text("")
                } else {
                    Text(model.selectedVoice.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
             
            Spacer()
            
            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                    .font(.title3)
                    .foregroundStyle(isPlaying ? .orange : .blue)
            }
            .buttonStyle(.plain)
            
            if isPlaying {
                Button(action: stopPlayback) {
                    Image(systemName: "stop.circle")
                        .font(.title3)
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal,4)
        .padding(.top, 4)
    }
    
    // Calculate playback progress (0.0 to 1.0)
    private var playbackProgress: Double {
        guard !chunks.isEmpty else { return 0 }
        
        let completedChunks = Double(currentChunkIndex)
        let currentChunkText = currentChunkIndex < chunks.count ? chunks[currentChunkIndex] : ""
        let currentChunkLength = Double(max(currentChunkText.count, 1))
        let spokenLength = Double(max(spokenSoFarInCurrentChunk.count, 1))
        
        // Progress within current chunk (0.0 to 1.0)
        let inChunkProgress = min(spokenLength / currentChunkLength, 1.0)
        
        // Total progress
        let totalChunks = Double(chunks.count)
        let totalProgress = (completedChunks + inChunkProgress) / totalChunks
        
        return min(max(totalProgress, 0), 1.0)
    }
    
    // MARK: - Main Processing
    @MainActor
    private func processMarkdownContent(_ md: String) async {
        attributedContent = styled(md)
        
        if ttsEnabled{
            let (isChinese, _) = TTSUtils.detectContentLanguage(md)
            let shouldUseBuiltIn = isChinese || !TestAppModel.isSupportedDevice()
            useBuiltInTTS = shouldUseBuiltIn
            
            let clean = TTSUtils.cleanMarkdownForTTS(md)
            let newChunks = await computeOptimalChunks(cleanText: clean, isChinese: isChinese)
            
            if chunks != newChunks {
                chunks = newChunks
                currentChunkIndex = 0
                spokenSoFarInCurrentChunk = ""
            }
        }
    }
    
    private func computeOptimalChunks(cleanText: String, isChinese: Bool) async -> [String] {
        await Task.detached(priority: .utility) {
            TTSUtils.computeTTSChunks(from: cleanText, isChinese: isChinese)
        }.value
    }
    
    // MARK: - Playback Logic
    private func togglePlayPause() {
        if isPlaying {
            pausePlayback()
        } else {
            resumeOrStartPlayback()
        }
    }
    
    private func pausePlayback() {
        isPlaying = false
        isPausedMidChunk = true
        pausedChunkText = chunks[currentChunkIndex]
        
        if useBuiltInTTS {
            chineseSynthesizer.pauseSpeaking(at: .immediate)
        } else {
            model.playerNode?.pause()
        }
        chunkTimer?.invalidate()
        model.timer?.invalidate()
    }
    
    private func resumeOrStartPlayback() {
        isPlaying = true
        if isPausedMidChunk && !pausedChunkText.isEmpty {
            wasManuallySelected = true
            playCurrentChunkWithText(pausedChunkText)
        } else {
            playCurrentChunk()
        }
    }
    
    private func playCurrentChunk() {
        guard isPlaying, currentChunkIndex < chunks.count else {
            finishPlayback()
            return
        }
        playCurrentChunkWithText(chunks[currentChunkIndex])
    }
    
    private func playCurrentChunkWithText(_ text: String) {
        if useBuiltInTTS {
            playChineseTTS(text)
        } else {
            model.playerNode?.stop()
            model.playerNode?.reset()
            model.timer?.invalidate()
            model.say(text: text) {
                DispatchQueue.main.async {
                    self.handlePlaybackComplete()
                }
            }
            startChunkMonitoring()
        }
    }
    
    private func handlePlaybackComplete() {
        guard isPlaying else { return }
        
        if !wasManuallySelected && currentChunkIndex < chunks.count - 1 {
            currentChunkIndex += 1
            spokenSoFarInCurrentChunk = ""
            playCurrentChunk()
        } else {
            finishPlayback()
        }
        wasManuallySelected = false
        isPausedMidChunk = false
    }
    
    private func finishPlayback() {
        isPlaying = false
        isPausedMidChunk = false
        pausedChunkText = ""
        wasManuallySelected = false
        
        if useBuiltInTTS {
            chineseSynthesizer.delegate = nil
            chineseDelegate = nil
            
            chineseSynthesizer.stopSpeaking(at: .immediate)
        } else {
            model.playerNode?.stop()
            model.playerNode?.reset()
            model.timer?.invalidate()
        }
        chunkTimer?.invalidate()
        spokenSoFarInCurrentChunk = ""
    }
    
    private func startChunkMonitoring() {
        chunkTimer?.invalidate()
        chunkTimer = Timer.scheduledTimer(withTimeInterval: Constants.TTS.chunkMonitoringInterval, repeats: true) { _ in
            guard !self.model.stringToFollowTheAudio.isEmpty else {
                self.chunkTimer?.invalidate()
                return
            }
            self.spokenSoFarInCurrentChunk = self.model.stringToFollowTheAudio.trimmingCharacters(in: .whitespaces)
        }
    }

    private func stopPlayback() {
        finishPlayback()
        currentChunkIndex = 0
    }

    // MARK: - Helpers
    private func playChineseTTS(_ text: String) {
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
        utterance.rate = isChinese ? 0.5 : 0.45
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Log.error("AVAudioSession error", category: .tts, error: error)
        }
        
        chineseSynthesizer.speak(utterance)
    }
     
    private func styled(_ md: String) -> AttributedString {
        let html = SimpleMarkdown.gfmToHTML(from: md)
        let styledHTML = """
        <html>
        <head>
        <style>
        body { font: -apple-system-body; }
        h1,h2,h3 { margin-top: 1.0em; font-weight: bold; }
        h1 { font-size: 1.5em; }
        h2 { font-size: 1.3em; }
        h3 { font-size: 1.1em; }
        code, pre { font-family: ui-monospace, Menlo, monospace; background: #f5f5f7; }
        pre { padding: 12px; border-radius: 8px; overflow: auto; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; }
        blockquote { border-left: 4px solid #ddd; padding-left: 12px; color: #555; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """

        guard let data = styledHTML.data(using: .utf8),
              let nsAttributedString = try? NSAttributedString(
                  data: data,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue
                  ],
                  documentAttributes: nil
              ) else {
            return AttributedString(md)
        }

        do {
            var output = try AttributedString(nsAttributedString, including: \.uiKit)

            let key = AttributeScopes.FoundationAttributes
                .PresentationIntentAttribute.self

            func font(for level: Int) -> UIFont {
                let style: UIFont.TextStyle =
                    switch level {
                    case 1: .title2
                    case 2: .title2
                    case 3: .title3
                    case 4: .headline
                    default: .body
                    }
                let base = UIFont.preferredFont(forTextStyle: style)
                return UIFont.systemFont(ofSize: base.pointSize, weight: .bold)
            }

            for (intentBlock, range) in output.runs[key].reversed() {
                guard let block = intentBlock else { continue }
                for intent in block.components {
                    if case .header(let level) = intent.kind {
                        output[range].font = font(for: level)
                    }
                }
                if range.lowerBound != output.startIndex {
                    output.characters.insert(
                        contentsOf: "\n",
                        at: range.lowerBound
                    )
                }
            }
            return output
        } catch {
            Log.error("AttributedString conversion failed", category: .tts, error: error)
            return AttributedString(md)
        }
    }
    
    }
