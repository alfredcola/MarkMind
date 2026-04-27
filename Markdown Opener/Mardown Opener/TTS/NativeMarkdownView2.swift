//
//  NativeMarkdownView.swift
//  Fully Fixed & Optimized for Performance
//

import AVFoundation
import SwiftUI
import Foundation

struct SelectableTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator as? any UITextViewDelegate
        
        textView.isEditable = false
        textView.isSelectable = true
        textView.dataDetectorTypes = .all
        textView.backgroundColor = .clear
        
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.maximumNumberOfLines = 0
        textView.textContainer.lineFragmentPadding = 0
        
        // Critical: Zero insets for accurate intrinsic size
        textView.textContainerInset = .zero
        
        textView.isScrollEnabled = false
        textView.panGestureRecognizer.isEnabled = false
        textView.textContainer.widthTracksTextView = true
        textView.adjustsFontForContentSizeCategory = false
        textView.allowsEditingTextAttributes = true
        
        // Content hugging and compression priorities
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        let mutableText = NSMutableAttributedString(attributedString: attributedText)
        mutableText.enumerateAttribute(.font, in: NSRange(location: 0, length: mutableText.length), options: []) { value, range, _ in
            if value == nil {
                mutableText.addAttribute(.font, value: UIFont.systemFont(ofSize: 17), range: range)
            }
        }
        uiView.attributedText = mutableText
        
        // Trigger layout update
        DispatchQueue.main.async {
            uiView.invalidateIntrinsicContentSize()
            context.coordinator.updateHeight(uiView)
        }
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        
        let targetSize = CGSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )
        
        let size = uiView.sizeThatFits(targetSize)
        return CGSize(width: width, height: size.height)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        func updateHeight(_ textView: UITextView) {
            let fixedWidth = textView.frame.size.width
            if fixedWidth > 0 {
                let newSize = textView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
                textView.invalidateIntrinsicContentSize()
            }
        }
    }
}



struct NativeMarkdownView2: View {
    let markdown: String

    @EnvironmentObject var model: TestAppModel
    @ObservedObject private var settingsVM = MultiSettingsViewModel.shared

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
    @State private var chineseDelegate: TTSUtils.ChineseTTSDelegate?

    // Debouncing
    @State private var previewUpdateTimer: Timer?
    @State private var lastProcessedMarkdown: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading) {
                    SelectableTextView(attributedText: NSAttributedString(attributedContent))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
                .padding(8)
                .background(Color(.systemBackground))
            }


            if !chunks.isEmpty && ttsEnabled {
                playbackControls
            }
        }
        .onChange(of: markdown) { _, newValue in
            guard newValue != lastProcessedMarkdown else { return }
            previewUpdateTimer?.invalidate()
            let currentMarkdown = newValue
            previewUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                Task { @MainActor in
                    self.lastProcessedMarkdown = currentMarkdown
                    await processMarkdownContent(currentMarkdown)
                }
            }
        }
        .onDisappear {
            previewUpdateTimer?.invalidate()
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
        .padding(.horizontal)
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
            
            let newChunks = await computeOptimalChunks(markdownText: md, isChinese: isChinese)
            
            if chunks != newChunks {
                chunks = newChunks
                currentChunkIndex = 0
                spokenSoFarInCurrentChunk = ""
            }
        }
    }
    
    private func computeOptimalChunks(markdownText: String, isChinese: Bool) async -> [String] {
        await Task.detached(priority: .utility) {
            TTSUtils.computeTTSChunks(from: markdownText, isChinese: isChinese)
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
    
    @MainActor
    private func styled(_ md: String) -> AttributedString {
        do {
            var output = try AttributedString(
                markdown: md,
                options: .init(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .full
                )
            )
            
            let key = AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self
            
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
            
            // Apply header fonts and add spacing
            for run in output.runs[key] {
                let (intentBlock, range) = run
                guard let block = intentBlock else { continue }
                
                for intent in block.components {
                    if case .header(let level) = intent.kind {
                        output[range].font = Font(font(for: level))
                    }
                }
                
                if range.lowerBound != output.startIndex {
                    output.characters.insert(
                        contentsOf: "\n",
                        at: range.lowerBound
                    )
                }
            }
            
            // Set explicit body font
            for run in output.runs[key] {
                let (intentBlock, range) = run
                if intentBlock?.components.isEmpty ?? true {
                    output[range].font = .system(size: 17, design: .default)
                }
            }
            
            // NEW: Set dynamic foreground color for proper Dark Mode support
            output.foregroundColor = .label
            
            // Optional: Make links use dynamic system link color (adapts better)
            // output.link = .some(Color(UIColor.link))
            
            return output
        } catch {
            Log.error("Markdown parsing failed", category: .tts, error: error)
            return AttributedString(md)
        }
    }}
