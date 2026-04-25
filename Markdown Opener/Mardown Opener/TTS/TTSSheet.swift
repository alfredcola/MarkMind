//
//  TTSSheet.swift
//  Markdown Opener
//
//  Created by alfred chen on 23/12/2025.
//


import AVFoundation
import MLX
import KokoroSwift
import Combine
import MLXUtilsLibrary
import SwiftUI
import WebKit

struct TTSSheet: View {
    let markdown: String
    @EnvironmentObject var model: TestAppModel
    @State private var chunks: [String] = []
    @State private var currentChunkIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var spokenSoFarInCurrentChunk: String = ""
    @State private var showVoicePickerSheet: Bool = false
    @ObservedObject private var settingsVM = MultiSettingsViewModel.shared
    @State private var useBuiltInTTS = false
    @State private var chunkTimer: Timer? = nil
    @State private var isWaitingForCompletion = false
    @State private var isPausedMidChunk: Bool = false
    @State private var pausedChunkText: String = ""
    @State private var wasManuallySelected: Bool = false
    @State private var chineseSynthesizer = AVSpeechSynthesizer()
    @State private var chineseDelegate: ChineseTTSDelegate?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Text-to-Speech Reader")
                    .font(.title2.bold())
                    .padding(.top)
                
                if !chunks.isEmpty {
                    HStack {
                        Text("\(currentChunkIndex + 1) / \(chunks.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                        ProgressView(value: Double(currentChunkIndex + 1), total: Double(chunks.count))
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                            .padding(.horizontal)
                    }
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(chunks.indices, id: \.self) { i in
                                    let text = chunks[i]
                                    let isCurrent = i == currentChunkIndex
                                    let highlightedText = isCurrent ? highlightCurrentChunk(full: text, spoken: spokenSoFarInCurrentChunk) : Text(text)
                                    
                                    highlightedText
                                        .font(.body)
                                        .lineSpacing(8)
                                        .foregroundColor(isCurrent ? .white : .primary)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(isCurrent ? Color.accentColor : Color(UIColor.secondarySystemBackground))
                                        )
                                        .shadow(color: isCurrent ? .accentColor.opacity(0.3) : .clear, radius: 6, y: 4)
                                        .scaleEffect(isCurrent ? 1.03 : 1.0)
                                        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: currentChunkIndex)
                                        .id(i)
                                        .padding(.horizontal, 8)
                                        .onTapGesture {
                                            playChunk(at: i)
                                        }
                                }
                                .padding(5)
                            }
                            .frame(maxHeight: .infinity)
                            .background(Color(UIColor.systemGroupedBackground))
                            .cornerRadius(20)
                        }
                        .onChange(of: currentChunkIndex) { _, newValue in
                            withAnimation(.easeInOut(duration: 0.7)) {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                }
                
                // Enhanced playback controls - hide voice picker for built-in TTS
                HStack(spacing: 10) {
                    // Only show voice picker for Kokoro TTS (English)
                    if !useBuiltInTTS {
                        Button {
                            showVoicePickerSheet = true
                        } label: {
                            Label(model.selectedVoice.capitalized, systemImage: "waveform")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Capsule().fill(Color.secondary.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .onChange(of: settingsVM.selectedVoice) {
                            model.selectedVoice = settingsVM.selectedVoice.rawValue
                        }
                    } else {
                        // Show TTS indicator for Chinese
                        Text("Build-in TTS")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Capsule().fill(Color.green.opacity(0.2)))
                            .foregroundColor(.green)
                    }
                    
                    Button(action: togglePlayPause) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(isPlaying ? .orange : .accentColor)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact, trigger: isPlaying)
                    
                    Button(action: stopPlayback) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
            .padding(.horizontal)
            .onAppear {
                splitIntoOptimalChunks()
                if !useBuiltInTTS {
                    startPlayback()
                    togglePlayPause()
                }
            }
            .onChange(of: isPlaying) {
                UIApplication.shared.isIdleTimerDisabled = isPlaying
            }
            .onDisappear {
                stopPlayback()
            }
            .onChange(of: model.stringToFollowTheAudio) { _, newValue in
                spokenSoFarInCurrentChunk = newValue.trimmingCharacters(in: .whitespaces)
            }
            .sheet(isPresented: $showVoicePickerSheet) {
                VoicePickerSheet()
                    .environmentObject(model)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Playback Controls
    private func playCurrentChunk() {
        guard isPlaying, currentChunkIndex < chunks.count else {
            finishPlayback()
            return
        }
        playCurrentChunkWithText(chunks[currentChunkIndex])
    }

    private func finishPlayback() {
        isPlaying = false
        isPausedMidChunk = false
        pausedChunkText = ""
        wasManuallySelected = false
        model.playerNode?.stop()
        model.playerNode?.reset()
        model.timer?.invalidate()
        chunkTimer?.invalidate()
        spokenSoFarInCurrentChunk = ""
    }

    private func playChunk(at index: Int) {
        guard index < chunks.count else { return }
        finishPlayback()  // Clean stop first
        currentChunkIndex = index
        isPlaying = true
        wasManuallySelected = true
        spokenSoFarInCurrentChunk = ""
        playCurrentChunk()
    }

    private func startPlayback() {
        guard !chunks.isEmpty else { return }
        
        finishPlayback()
        currentChunkIndex = 0
        spokenSoFarInCurrentChunk = ""
        isPlaying = true
        playCurrentChunk()
    }

    // MARK: - Word Highlighting & Text Processing
    private func highlightCurrentChunk(full: String, spoken: String) -> Text {
        let words = full.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var result = Text("")
        let spokenLower = spoken.lowercased()
        var consumed = spokenLower
        
        for word in words {
            let clean = word.replacingOccurrences(of: "[^a-zA-Z0-9']", with: "", options: .regularExpression).lowercased()
            if !clean.isEmpty && consumed.contains(clean) {
                result = result + Text(word + " ").bold().foregroundColor(.white)
                if let range = consumed.range(of: clean) {
                    consumed.removeSubrange(range)
                }
            } else {
                result = result + Text(word + " ").foregroundColor(.white.opacity(0.7))
            }
        }
        return result
    }

    private func hasSignificantChineseContent(_ text: String) -> Bool {
        let chineseCount = text.unicodeScalars.filter { scalar in
            // CJK 中文範圍檢查
            (0x4E00...0x9FFF).contains(scalar.value) ||  // 主要中文
            (0x3400...0x4DBF).contains(scalar.value) ||  // Extension A
            (0xF900...0xFAFF).contains(scalar.value)      // Compatibility
        }.count
        
        let chineseRatio = Double(chineseCount) / Double(text.count)
        print("中文比例: \(String(format: "%.1f", chineseRatio * 100))%")
        return chineseRatio > 0.3
    }

    private func isPrimarilyEnglish(_ text: String) -> Bool {
        let englishChars = CharacterSet.letters
        let englishCount = text.unicodeScalars.filter { englishChars.contains($0) }.count
        let totalCount = text.unicodeScalars.count
        return totalCount > 0 ? Double(englishCount) / Double(totalCount) > 0.6 : true
    }

    private func splitIntoOptimalChunks() {
        detectFileLanguage()
        let clean = cleanMarkdownForTTS(markdown)
        let sentences = linguisticSentenceSplit(clean)
        let maxLen = 220
        var finalChunks: [String] = []
        
        for s in sentences {
            if s.count <= maxLen {
                finalChunks.append(s)
            } else {
                finalChunks.append(contentsOf: safeSplitLongSentence(s, maxLength: maxLen))
            }
        }
        
        chunks = finalChunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.allSatisfy { $0.isWholeNumber } }
        
        if chunks.isEmpty {
            chunks = ["No readable text found"]
        }
    }

    private func playCurrentChunkWithText(_ text: String) {
        let shouldFallbackToBuiltIn = !canKokoroHandleText(text)
        
        if useBuiltInTTS || shouldFallbackToBuiltIn {
            print("Using Built-in TTS (chunk has non-English content or file preference)")
            playChineseTTS(text)
        } else {
            print("Attempting Kokoro TTS (A16+ only)")
            model.playerNode?.stop()
            model.playerNode?.reset()
            model.timer?.invalidate()
            
            model.say(text: text) { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.handlePlaybackComplete()
                }
            }
            startChunkMonitoring()
        }
    }
    
    private func detectContentLanguage(_ text: String) -> (isChinese: Bool, voiceLocale: String) {
        let cleanText = cleanMarkdownForTTS(text)
        
        // Chinese detection (CJK characters)
        let chineseCount = cleanText.unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0xF900...0xFAFF).contains(scalar.value)
        }.count
        
        let chineseRatio = Double(chineseCount) / Double(cleanText.count)
        print("🇨🇳 Chinese ratio: \(String(format: "%.1f", chineseRatio * 100))%")
        
        // English detection
        let englishChars = CharacterSet.letters
        let englishCount = cleanText.unicodeScalars.filter { englishChars.contains($0) }.count
        let englishRatio = Double(englishCount) / Double(cleanText.count)
        print("🇺🇸 English ratio: \(String(format: "%.1f", englishRatio * 100))%")
        
        if chineseRatio > 0.3 {
            return (true, "zh-HK")  // Chinese → zh-HK
        } else if englishRatio > 0.4 {
            return (false, "en-US")  // English → en-US
        } else {
            // Mixed or other → fallback to English
            return (false, "en-US")
        }
    }

    private func detectFileLanguage() {  // WebMarkdownView
        if !TestAppModel.isSupportedDevice() {
            useBuiltInTTS = true
            print("🔧 Using Built-in TTS: Unsupported device")
            return
        }
        
        let (isChinese, _) = detectContentLanguage(markdown)
        useBuiltInTTS = isChinese  // Chinese → Built-in, English → Try Kokoro
        print("📍 Final decision: useBuiltInTTS = \(useBuiltInTTS)")
    }

    private func canKokoroHandleText(_ text: String) -> Bool {
        let cleanText = cleanMarkdownForTTS(text)
        guard !cleanText.isEmpty else { return false }
        
        let nonEnglishCount = cleanText.unicodeScalars.filter { scalar in
            let value = scalar.value
            let isCJK = (0x4E00...0x9FFF).contains(value) ||
                        (0x3400...0x4DBF).contains(value) ||
                        (0xF900...0xFAFF).contains(value)
            let isJapanese = (0x3040...0x309F).contains(value) ||
                             (0x30A0...0x30FF).contains(value)
            let isKorean = (0xAC00...0xD7AF).contains(value) ||
                           (0x1100...0x11FF).contains(value)
            let isCyrillic = (0x0400...0x04FF).contains(value)
            let isArabic = (0x0600...0x06FF).contains(value) ||
                           (0x0750...0x077F).contains(value)
            let isThai = (0x0E00...0x0E7F).contains(value)
            let isDevanagari = (0x0900...0x097F).contains(value)
            let isLatinExtended = (0x0080...0x024F).contains(value)
            
            return isCJK || isJapanese || isKorean || isCyrillic || isArabic || isThai || isDevanagari || isLatinExtended
        }.count
        
        let ratio = Double(nonEnglishCount) / Double(cleanText.count)
        let canHandle = ratio < 0.1
        print("🔍 Kokoro handle check: non-English ratio = \(String(format: "%.1f", ratio * 100))% → \(canHandle ? "YES" : "NO (fallback to built-in)"))
        return canHandle
    }

    private func playChineseTTS(_ text: String) {
        let (isChinese, voiceLocale) = detectContentLanguage(text)
        let locale = isChinese ? "zh-HK" : "en-US"
        
        print("🗣️ Built-in TTS: \(locale) - '\(text.prefix(30))...'")
        
        chineseDelegate = ChineseTTSDelegate { [self] in
            DispatchQueue.main.async {
                self.handlePlaybackComplete()
            }
        }
        chineseSynthesizer.delegate = chineseDelegate
        
        // Dynamic voice selection
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: locale)
        utterance.rate = isChinese ? 0.5 : 0.45  // Slightly faster for English
        utterance.pitchMultiplier = 1.0
        
        // AVAudioSession setup
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            print("✅ AVAudioSession activated (\(locale))")
        } catch {
            print("❌ AVAudioSession failed: \(error)")
        }
        
        chineseSynthesizer.speak(utterance)
    }


    private class ChineseTTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
        let completion: () -> Void
        
        init(completion: @escaping () -> Void) {
            self.completion = completion
        }
        
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            print("✅ Built-in TTS finished")
            completion()
        }
        
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            print("⏹️ Built-in TTS cancelled")
            completion()
        }
    }

    private func handlePlaybackComplete() {
        if isPlaying && !wasManuallySelected {
            if currentChunkIndex < chunks.count - 1 {
                currentChunkIndex += 1
                spokenSoFarInCurrentChunk = ""
                playCurrentChunk()
            } else {
                finishPlayback()
            }
        }
        wasManuallySelected = false
        isPausedMidChunk = false
        
        // 只對英文啟用監控
        if !useBuiltInTTS {
            startChunkMonitoring()
        }
    }

    private func togglePlayPause() {
        if isPlaying {
            if useBuiltInTTS {
                chineseSynthesizer.pauseSpeaking(at: .immediate)
            } else {
                model.playerNode?.pause()
            }
            isPlaying = false
            isPausedMidChunk = true
            pausedChunkText = chunks[currentChunkIndex]
            chunkTimer?.invalidate()
            model.timer?.invalidate()
        } else {
            isPlaying = true
            if isPausedMidChunk, !pausedChunkText.isEmpty {
                wasManuallySelected = true
                playCurrentChunkWithText(pausedChunkText)
            } else {
                playCurrentChunk()
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        if useBuiltInTTS {
            chineseSynthesizer.stopSpeaking(at: .immediate)
            chineseDelegate = nil
        } else {
            model.playerNode?.stop()
            model.playerNode?.reset()
            model.timer?.invalidate()
        }
        currentChunkIndex = 0
        spokenSoFarInCurrentChunk = ""
        chunkTimer?.invalidate()
    }

    private func startChunkMonitoring() {
        guard !useBuiltInTTS else { return } // 中文不監控
        chunkTimer?.invalidate()
        chunkTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            if model.stringToFollowTheAudio.isEmpty {
                chunkTimer?.invalidate()
                return
            }
            spokenSoFarInCurrentChunk = model.stringToFollowTheAudio.trimmingCharacters(in: .whitespaces)
        }
    }


    private func cleanMarkdownForTTS(_ text: String) -> String {
        var s = text
        
        let replacements: [(pattern: String, template: String, options: NSRegularExpression.Options)] = [
            ("``````", "", []),
            ("`[^`]+`", "", []),
            ("!\\[[^\\]]*\\]\\([^)]*\\)", "", []),
            ("^#{1,6}\\s+", "", [.anchorsMatchLines]),
            ("^[-*_]{3,}$", "", [.anchorsMatchLines]),
            ("\\*\\*(.*?)\\*\\*", "$1", []),
            ("__(.*?)__", "$1", []),
            ("\\*(.*?)\\*", "$1", []),
            ("_(.*?)_", "$1", []),
            ("^\\s*[-*+•]\\s+", "", [.anchorsMatchLines]),
            ("^\\s*\\d+\\.\\s+", "", [.anchorsMatchLines]),
            ("^\\|.*\\|$", "", [.anchorsMatchLines]),
            ("^[-| :]+$", "", [.anchorsMatchLines]),
            ("\\n{3,}", "\n\n", []),
            ("[ \\t]{2,}", " ", [])
        ]
        
        for (pattern, template, options) in replacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: template)
            }
        }
        
        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^)]*\\)", options: []) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
        }
        
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func linguisticSentenceSplit(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tagger = NSLinguisticTagger(tagSchemes: [.tokenType], options: 0)
        tagger.string = text
        var sentences: [String] = []
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        
        tagger.enumerateTags(in: range, unit: .sentence, scheme: .tokenType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { _, sentenceRange, _ in
            let sentence = (text as NSString).substring(with: sentenceRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty && ![".", "…", "•"].contains(sentence) {
                sentences.append(sentence)
            }
        }
        return sentences.isEmpty ? [text] : sentences
    }

    private func safeSplitLongSentence(_ sentence: String, maxLength: Int) -> [String] {
        var parts: [String] = []
        var remaining = sentence
        while remaining.count > maxLength {
            let limitIndex = remaining.index(remaining.startIndex, offsetBy: maxLength)
            let splitIndex = remaining[..<limitIndex].rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards)?.upperBound ?? limitIndex
            let part = String(remaining[..<splitIndex]).trimmingCharacters(in: .whitespaces)
            if !part.isEmpty { parts.append(part) }
            remaining = String(remaining[splitIndex...]).trimmingCharacters(in: .whitespaces)
        }
        if !remaining.isEmpty { parts.append(remaining) }
        return parts
    }
}


// MARK: - Voice Picker Sheet
struct VoicePickerSheet: View {
    @EnvironmentObject var model: TestAppModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var settingsVM = MultiSettingsViewModel.shared
    
    var body: some View {
        NavigationStack {
            List(model.voiceNames, id: \.self) { voice in
                HStack {
                    Image(systemName: settingsVM.selectedVoice.rawValue == voice ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                    Text(voice.capitalized)
                        .font(.title3)
                    Spacer()
                    if settingsVM.selectedVoice.rawValue == voice {
                        Image(systemName: "speaker.wave.3")
                            .foregroundColor(.secondary)
                    }
                }
                .onTapGesture {
                    // Sync both ways
                    model.selectedVoice = voice
                    if let aiVoice = AIVoice.allCases.first(where: { $0.rawValue == voice }) {
                        settingsVM.selectedVoice = aiVoice
                    }
                    dismiss()
                }
            }
            .navigationTitle("Choose Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                model.selectedVoice = settingsVM.selectedVoice.rawValue
            }
        }
    }
}
