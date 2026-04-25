//
//  FlashcardMode.swift
//  Markdown Opener
//
//  Created by alfred chen on 21/12/2025.
//

internal import AVFAudio
import SwiftUI
import Combine

// MARK: - Flashcard Study View
struct FlashcardStudyView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var session: FlashcardSession
    @EnvironmentObject var flashcardStore: FlashcardStore
    @ObservedObject private var rewardedAdManager = RewardedAdManager.shared


    let docURL: URL?
    let docText: String?
    var onGenerate: (() async -> Void)? = nil

    // UI state
    @State private var isFlipped = false
    @State private var showResult = false

    // Generation state
    @State private var isGenerating = false
    @State private var countdownRemaining = 30
    @State private var showIndefiniteSpinner = false
    private let generationTotalSeconds = 30

    @State private var customPrompt = ""
    @State private var selectedFiles: [(url: URL, content: String)] = []
    @State private var showFilePicker = false
    @State private var errorMessage: String?
    @State private var showRegenerateConfirmation = false
    @State private var selectedBilingualDirection: BilingualDirection =
        .englishToChinese  // New state

    @State private var selectedMode: FlashcardMode = .bilingual

    // MARK: - New Features State
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var showStatistics = false
    @State private var showFavoritesOnly = false
    @State private var cardDifficultyRatings: [UUID: CardDifficulty] = [:]
    @State private var favoriteCards: Set<UUID> = []
    @State private var showQuickNavigation = false
    @State private var quickNavCardNumber = ""
    @State private var currentCardStartTime: Date = Date()
    
    @EnvironmentObject var model: TestAppModel  // Same as in MCStudyView
    @ObservedObject private var settingsVM = MultiSettingsViewModel.shared

    private class ChineseTTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
        let completion: () -> Void
        init(completion: @escaping () -> Void) {
            self.completion = completion
        }
        func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer,
            didFinish utterance: AVSpeechUtterance
        ) {
            completion()
        }
    }

    @ObservedObject private var adManager = InterstitialAdManager.shared
    @State private var ttsIsPlaying = false
    @State private var ttsCurrentChunkIndex = 0
    @State private var ttsChunks: [String] = []
    @State private var ttsUseBuiltInTTS = false
    @State private var ttsChineseSynthesizer = AVSpeechSynthesizer()
    @State private var ttsChineseDelegate: ChineseTTSDelegate?
    @State private var ttsChunkTimer: Timer? = nil
    @State private var ttsTask: Task<Void, Never>? = nil
    @Binding var ttsEnabled: Bool  // Add this binding where you instantiate the view (or use settingsVM.ttsEnabled)

    // MARK: - Add these helper functions (copy-paste from MCStudyView, placed inside FlashcardStudyView)

    private func startTTS(for text: String) {
        guard settingsVM.ttsEnabled, !text.isEmpty else { return }

        let cleanText = cleanMarkdownForTTS(text)
        let (isChinese, _) = detectContentLanguage(cleanText)
        ttsUseBuiltInTTS = isChinese || !TestAppModel.isSupportedDevice()

        let chunks = computeTTSChunks(from: cleanText, isChinese: isChinese)
        guard !chunks.isEmpty else { return }

        ttsChunks = chunks
        ttsCurrentChunkIndex = 0
        ttsIsPlaying = true

        playCurrentTTSChunk()
    }

    private func computeTTSChunks(from text: String, isChinese: Bool)
        -> [String]
    {
        let maxLength = 220
        if isChinese {
            let punctuation = CharacterSet(charactersIn: "。？！，；：…")
            let sentences = text.components(separatedBy: punctuation)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 1 }
            return
                sentences
                .flatMap {
                    safeSplitLongSentence(sentence: $0, maxLength: maxLength)
                }
                .filter { $0.count > 3 }
        } else {
            let sentences = linguisticSentenceSplit(text)
            var final: [String] = []
            for s in sentences {
                if s.count <= maxLength {
                    final.append(s)
                } else {
                    final.append(
                        contentsOf: safeSplitLongSentence(
                            sentence: s,
                            maxLength: maxLength
                        )
                    )
                }
            }
            return final.filter { !$0.isEmpty }
        }
    }

    private func playCurrentTTSChunk() {
        guard ttsIsPlaying, ttsCurrentChunkIndex < ttsChunks.count else {
            finishTTSPlayback()
            return
        }

        let chunk = ttsChunks[ttsCurrentChunkIndex].trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !chunk.isEmpty else {
            handleTTSChunkComplete()
            return
        }

        if ttsUseBuiltInTTS {
            playChineseTTS(chunk)
        } else {
            safeKokoroSpeak(text: chunk) {
                self.handleTTSChunkComplete()
            }
        }
    }

    private func safeKokoroSpeak(text: String, completion: @escaping () -> Void)
    {
        ttsTask?.cancel()

        model.stringToFollowTheAudio = ""
        model.playerNode?.stop()
        model.playerNode?.reset()
        model.timer?.invalidate()

        let task = Task { [weak model] in
            guard !Task.isCancelled else { return }
            model?.say(text: text) {
                Task { @MainActor in
                    guard !Task.isCancelled else { return }
                    completion()
                }
            }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.startTTSChunkMonitoring()
            }
        }
        ttsTask = task
    }

    private func handleTTSChunkComplete() {
        guard ttsIsPlaying else { return }
        if ttsCurrentChunkIndex < ttsChunks.count - 1 {
            ttsCurrentChunkIndex += 1
            playCurrentTTSChunk()
        } else {
            finishTTSPlayback()
        }
    }

    private func finishTTSPlayback() {
        ttsIsPlaying = false
        ttsCurrentChunkIndex = 0
        ttsChunks = []
        model.stringToFollowTheAudio = ""

        if ttsUseBuiltInTTS {
            ttsChineseSynthesizer.delegate = nil
            ttsChineseDelegate = nil
            ttsChineseSynthesizer.stopSpeaking(at: .immediate)
        } else {
            model.playerNode?.stop()
            model.playerNode?.reset()
            model.timer?.invalidate()
        }

        ttsChunkTimer?.invalidate()
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func stopTTS() {
        finishTTSPlayback()
    }

    private func toggleTTS(for text: String) {
        if ttsIsPlaying {
            stopTTS()
        } else {
            startTTS(for: text)
        }
    }

    private func startTTSChunkMonitoring() {
        ttsChunkTimer?.invalidate()
        ttsChunkTimer = Timer.scheduledTimer(
            withTimeInterval: 0.2,
            repeats: true
        ) { _ in }
    }

    private func playChineseTTS(_ text: String) {
        let (isChinese, _) = detectContentLanguage(text)
        let locale = isChinese ? "zh-HK" : "en-US"

        ttsChineseDelegate = ChineseTTSDelegate {
            DispatchQueue.main.async {
                self.handleTTSChunkComplete()
            }
        }
        ttsChineseSynthesizer.delegate = ttsChineseDelegate

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: locale)
        utterance.rate = isChinese ? 0.48 : 0.45
        utterance.postUtteranceDelay = 0.15

        DispatchQueue.global(qos: .userInitiated).async {
            self.ttsChineseSynthesizer.speak(utterance)
        }
    }
    private func detectContentLanguage(_ text: String) -> (
        isChinese: Bool, voiceLocale: String
    ) {
        let cleanText = cleanMarkdownForTTS(text)

        let chineseCount = cleanText.unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }.count

        let chineseRatio = Double(chineseCount) / Double(cleanText.count)

        let englishChars = CharacterSet.letters
        let englishCount = cleanText.unicodeScalars.filter {
            englishChars.contains($0)
        }.count
        let englishRatio = Double(englishCount) / Double(cleanText.count)

        print(
            "📊 MCcard TTS: Chinese=\(String(format: "%.1f", chineseRatio*100))%, English=\(String(format: "%.1f", englishRatio*100))%"
        )

        if chineseRatio > 0.3 {
            return (true, "zh-HK")
        } else if englishRatio > 0.4 {
            return (false, "en-US")
        } else {
            return (false, "en-US")
        }
    }
    private func cleanMarkdownForTTS(_ text: String) -> String {
        var s = text
        let replacements = [
            (
                pattern: "[#*`]+", template: "",
                options: NSRegularExpression.Options([])
            ),
            (pattern: "[1-6]\\.", template: "", options: [.anchorsMatchLines]),
            (pattern: "-{3,}", template: "", options: [.anchorsMatchLines]),
            (
                pattern: "\\s{3,}", template: " ",
                options: NSRegularExpression.Options([])
            ),
        ]
        for replacement in replacements {
            if let regex = try? NSRegularExpression(
                pattern: replacement.pattern,
                options: replacement.options
            ) {
                s = regex.stringByReplacingMatches(
                    in: s,
                    options: [],
                    range: NSRange(s.startIndex..., in: s),
                    withTemplate: replacement.template
                )
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func linguisticSentenceSplit(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tagger = NSLinguisticTagger(tagSchemes: [.tokenType], options: 0)
        tagger.string = text
        var sentences: [String] = []
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        tagger.enumerateTags(
            in: range,
            unit: .sentence,
            scheme: .tokenType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { (tag, sentenceRange, _) in
            let sentence = (text as NSString).substring(with: sentenceRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        return sentences.isEmpty ? [text] : sentences
    }

    // MARK: - New Feature: Card Difficulty Rating
    enum CardDifficulty: String, Codable, CaseIterable {
        case easy = "Easy"
        case medium = "Medium"
        case hard = "Hard"
        
        var color: String {
            switch self {
            case .easy: return "green"
            case .medium: return "orange"
            case .hard: return "red"
            }
        }
        
        var systemImage: String {
            switch self {
            case .easy: return "checkmark.circle.fill"
            case .medium: return "minus.circle.fill"
            case .hard: return "xmark.circle.fill"
            }
        }
    }
    
    private func getDifficultyForCard(_ card: Flashcard) -> CardDifficulty {
        return cardDifficultyRatings[card.id] ?? .medium
    }
    
    private func setDifficultyForCard(_ card: Flashcard, difficulty: CardDifficulty) {
        cardDifficultyRatings[card.id] = difficulty
        saveCardProgress()
    }
    
    private func difficultyColor(_ difficulty: CardDifficulty) -> Color {
        switch difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
    
    private func toggleFavorite(_ card: Flashcard) {
        if favoriteCards.contains(card.id) {
            favoriteCards.remove(card.id)
        } else {
            favoriteCards.insert(card.id)
        }
        saveCardProgress()
    }
    
    private func isFavorite(_ card: Flashcard) -> Bool {
        return favoriteCards.contains(card.id)
    }
    // MARK: - New Feature: Search Cards
    private var filteredCards: [Flashcard] {
        guard !searchText.isEmpty else { return session.cards }
        return session.cards.filter { card in
            card.question.localizedCaseInsensitiveContains(searchText) ||
            card.options[0].localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // MARK: - New Feature: Quick Navigation
    private func jumpToCard(number: Int) {
        let targetIndex = number - 1
        if targetIndex >= 0 && targetIndex < session.cards.count {
            session.index = targetIndex
            resetCardState()
        }
    }
    
    // MARK: - New Feature: Statistics
    private var cardStatistics: (total: Int, easy: Int, medium: Int, hard: Int, favorites: Int) {
        let total = session.cards.count
        let easy = cardDifficultyRatings.values.filter { $0 == .easy }.count
        let medium = cardDifficultyRatings.values.filter { $0 == .medium }.count
        let hard = cardDifficultyRatings.values.filter { $0 == .hard }.count
        let favorites = favoriteCards.count
        return (total, easy, medium, hard, favorites)
    }
    
    // MARK: - Persistence for new features
    private func saveCardProgress() {
        guard let url = docURL else { return }
        let base = "FlashcardProgress_\(url.absoluteString)"
        
        if let encoded = try? JSONEncoder().encode(Array(arrayLiteral: cardDifficultyRatings)) {
            UserDefaults.standard.set(encoded, forKey: "\(base)_difficulty")
        }
        if let encoded = try? JSONEncoder().encode(Array(favoriteCards)) {
            UserDefaults.standard.set(encoded, forKey: "\(base)_favorites")
        }
    }
    
    private func loadCardProgress() {
        guard let url = docURL else { return }
        let base = "FlashcardProgress_\(url.absoluteString)"
        
        if let data = UserDefaults.standard.data(forKey: "\(base)_difficulty"),
           let decoded = try? JSONDecoder().decode([UUID: CardDifficulty].self, from: data) {
            cardDifficultyRatings = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "\(base)_favorites"),
           let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            favoriteCards = decoded
        }
    }
    
    // MARK: - Study Time Tracking
    private var studyTimeSeconds: Int {
        return Int(Date().timeIntervalSince(currentCardStartTime))
    }
    
    private func formatStudyTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
    
    private func safeSplitLongSentence(sentence: String, maxLength: Int)
        -> [String]
    {
        var parts: [String] = []
        var remaining = sentence
        while remaining.count > maxLength {
            let limitIndex = remaining.index(
                remaining.startIndex,
                offsetBy: maxLength
            )
            let splitIndex =
                remaining[remaining.startIndex..<limitIndex].rangeOfCharacter(
                    from: .whitespacesAndNewlines,
                    options: .backwards
                )?.upperBound ?? limitIndex
            let part = String(remaining[..<splitIndex]).trimmingCharacters(
                in: .whitespaces
            )
            if !part.isEmpty {
                parts.append(part)
            }
            remaining = String(remaining[splitIndex...]).trimmingCharacters(
                in: .whitespaces
            )
        }
        if !remaining.isEmpty {
            parts.append(remaining)
        }
        return parts
    }

    var body: some View {
        NavigationStack {
            if UIDevice.current.userInterfaceIdiom == .pad
                || (UIDevice.current.userInterfaceIdiom == .phone
                    && Environment(\.horizontalSizeClass).wrappedValue
                        == .regular)
            {
                // ==================== iPAD / iPhone in Split View (Regular width) ====================
                // New UI: Custom header with visible buttons
                VStack(spacing: 0) {
                    // Custom Header Bar
                    HStack {
                        // Leading side
                        Group {
                            if !session.cards.isEmpty {
                                Button {
                                    showRegenerateConfirmation = true
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.title2)
                                        .padding(8)
                                        .background(
                                            Circle().fill(
                                                Color.secondary.opacity(0.15)
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                                .confirmationDialog(
                                    "Regenerate Flashcards?",
                                    isPresented: $showRegenerateConfirmation,
                                    titleVisibility: .visible
                                ) {
                                    Button("Regenerate", role: .destructive) {
                                        NotificationCenter.default.post(
                                            name: .regenerateFlashcards,
                                            object: nil
                                        )
                                    }
                                    Button("Cancel", role: .cancel) {}
                                } message: {
                                    Text(
                                        "This will delete all current flashcards, progress and regenerate new ones. Cannot be undone."
                                    )
                                }
                            }
                        }

                        Spacer()

                        // Center Title
                        Text("Flashcard Study")
                            .font(.headline.bold())

                        Spacer()

                        // Trailing side
                        Group {
                            if !session.cards.isEmpty {
                                // Search button
                                Button {
                                    showSearch = true
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .font(.title2)
                                        .padding(8)
                                        .background(
                                            Circle().fill(Color.secondary.opacity(0.15))
                                        )
                                }
                                .buttonStyle(.plain)
                                .help("Search cards")

                                // Statistics button
                                Button {
                                    showStatistics = true
                                } label: {
                                    Image(systemName: "chart.bar.fill")
                                        .font(.title2)
                                        .padding(8)
                                        .background(
                                            Circle().fill(Color.secondary.opacity(0.15))
                                        )
                                }
                                .buttonStyle(.plain)
                                .help("View statistics")

                                // Favorites filter button
                                Button {
                                    withAnimation { showFavoritesOnly.toggle() }
                                } label: {
                                    Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                                        .font(.title2)
                                        .foregroundColor(showFavoritesOnly ? .yellow : .primary)
                                        .padding(8)
                                        .background(
                                            Circle().fill(Color.secondary.opacity(0.15))
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(showFavoritesOnly ? "Show all cards" : "Show favorites only")

                                // Quick navigation
                                Button {
                                    showQuickNavigation = true
                                } label: {
                                    Image(systemName: "number.circle")
                                        .font(.title2)
                                        .padding(8)
                                        .background(
                                            Circle().fill(Color.secondary.opacity(0.15))
                                        )
                                }
                                .buttonStyle(.plain)
                                .help("Jump to card number")

                                Button {
                                    saveToWidget()
                                } label: {
                                    Label(
                                        "Add to Widget",
                                        systemImage: "apps.iphone"
                                    )
                                    .font(.headline)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.secondary.opacity(0.15))
                                    )
                                }
                                .buttonStyle(.plain)
                                .help(
                                    "Make this document's flashcards appear in the home screen widget"
                                )
                            }

                            if session.cards.isEmpty {
                                Menu {
                                    ForEach(FlashcardMode.allCases) { mode in
                                        Button {
                                            selectedMode = mode
                                        } label: {
                                            HStack {
                                                Text(mode.rawValue)
                                                if selectedMode == mode {
                                                    Image(
                                                        systemName: "checkmark"
                                                    )
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Text(selectedMode.rawValue)
                                        .font(.title3)
                                        .padding(8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.secondary.opacity(0.15))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 2)
                    .padding(.bottom, 2)
                    .background(Color(UIColor.systemBackground))
                    .overlay(Divider(), alignment: .bottom)

                    Spacer()
                    
                    VStack(spacing: 0) {
                        if session.cards.isEmpty {
                            generateEmptyState
                        } else if session.done {
                            resultsView
                        } else if let card = session.current {
                            flashcardView(card: card)
                        } else {
                            ProgressView().padding()
                        }
                    }
                    
                    Spacer()

                }
                .navigationBarHidden(true)  // Hide default navigation bar on iPad
            } else {
                // ==================== iPHONE (Compact width) ====================
                // Old UI: Using standard toolbar
                VStack(spacing: 0) {
                    if session.cards.isEmpty {
                        generateEmptyState
                    } else if session.done {
                        resultsView
                    } else if let card = session.current {
                        flashcardView(card: card)
                    } else {
                        ProgressView().padding()
                    }
                }
                .navigationTitle("Flashcard Study")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !session.cards.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showRegenerateConfirmation = true
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .confirmationDialog(
                                "Regenerate Flashcards?",
                                isPresented: $showRegenerateConfirmation
                            ) {
                                Button("Regenerate", role: .destructive) {
                                    NotificationCenter.default.post(
                                        name: .regenerateFlashcards,
                                        object: nil
                                    )
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text(
                                    "This will delete all current flashcards, progress and regenerate new ones. Cannot be undone."
                                )
                            }
                        }
                    }

                    if !session.cards.isEmpty {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {

                                Button {
                                    showSearch = true
                                } label: {
                                    Label("Search", systemImage: "magnifyingglass")
                                }

                                Button {
                                    showStatistics = true
                                } label: {
                                    Label("Statistics", systemImage: "chart.bar.fill")
                                }

                                Button {
                                    withAnimation { showFavoritesOnly.toggle() }
                                } label: {
                                    Label(
                                        showFavoritesOnly ? "Show All" : "Show Favorites",
                                        systemImage: showFavoritesOnly ? "star.fill" : "star"
                                    )
                                }

                                Button {
                                    showQuickNavigation = true
                                } label: {
                                    Label("Go to Card #", systemImage: "number.circle")
                                }

                                Divider()

                                Button {
                                    saveToWidget()
                                } label: {
                                    Label("Add to Widget", systemImage: "apps.iphone")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }

                    if session.cards.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                ForEach(FlashcardMode.allCases) { mode in
                                    Button {
                                        selectedMode = mode
                                    } label: {
                                        HStack {
                                            Text(mode.rawValue)
                                            if selectedMode == mode {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Text(selectedMode.rawValue)
                            }
                        }
                    }
                }
            }
        }
        .overlay(
            Group {
                if showWidgetSaveConfirmation {
                    VStack {
                        Spacer()
                        Text(
                            "✅ Flashcards saved!\nThey are now showing in the widget."
                        )
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding()
                        .transition(
                            .move(edge: .bottom).combined(with: .opacity)
                        )
                    }
                    .animation(.spring(), value: showWidgetSaveConfirmation)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + 1.0
                        ) {
                            withAnimation(.easeOut) {
                                showWidgetSaveConfirmation = false
                            }
                        }
                    }
                }
            }
        )
        .sheet(isPresented: $showSearch) {
            searchSheet
        }
        .sheet(isPresented: $showStatistics) {
            statisticsSheet
        }
        .sheet(isPresented: $showQuickNavigation) {
            quickNavigationSheet
        }
        .onAppear {
            restoreSessionState()
            loadCardProgress()
            currentCardStartTime = Date()

            if ttsEnabled {
                do {
                    try AVAudioSession.sharedInstance().setCategory(
                        .playback,
                        mode: .spokenAudio,
                        options: [.duckOthers]
                    )
                    try AVAudioSession.sharedInstance().setActive(
                        true,
                        options: [.notifyOthersOnDeactivation]
                    )
                } catch {
                    print("Audio session setup failed: \(error)")
                }

                // Pre-warm synthesizer more effectively
                let warmUpUtterance = AVSpeechUtterance(string: " ")
                warmUpUtterance.voice = AVSpeechSynthesisVoice(
                    language: "zh-HK"
                )
                ttsChineseSynthesizer.speak(warmUpUtterance)  // This primes the engine better
            }
        }
        .onChange(of: isGenerating) {
            UIApplication.shared.isIdleTimerDisabled = isGenerating
        }
        .onChange(of: session.index) { _ in
            currentCardStartTime = Date()
        }
        .onDisappear {
            saveSessionState()
            if ttsEnabled {
                stopTTS()
                try? AVAudioSession.sharedInstance().setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )
            }
        }
        .task {
            await loadExistingFlashcardsIfAny()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .regenerateFlashcards)
        ) { _ in
            Task { await handleRegenerate() }
        }
        .alert(isPresented: .constant(errorMessage != nil)) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage ?? ""),
                dismissButton: .default(Text("OK")) { errorMessage = nil }
            )
        }

    }

    @State private var showWidgetSaveConfirmation = false

    func saveToWidget() {
        guard let docURL = docURL, !session.cards.isEmpty else { return }

        let originalFilename = docURL.lastPathComponent  // e.g., "Biology.md"
        let widgetFilename = originalFilename + ".json"  // "Biology.md.json"

        let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier:
                "group.com.alfredchen.MarkdownOpener"
        )!

        let jsonURL = containerURL.appendingPathComponent(widgetFilename)
        let data = try! JSONEncoder().encode(session.cards)
        try! data.write(to: jsonURL)

        // THIS IS THE KEY LINE:
        UserDefaults(suiteName: "group.com.alfredchen.MarkdownOpener")?.set(
            widgetFilename,
            forKey: "widget_activeDocument"
        )

        showWidgetSaveConfirmation = true
    }

    // MARK: - Search Sheet
    private var searchSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search flashcards...", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))

                if filteredCards.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No cards found")
                            .font(.headline)
                        Text("Try a different search term")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List(filteredCards, id: \.id) { card in
                        Button {
                            if let index = session.cards.firstIndex(where: { $0.id == card.id }) {
                                session.index = index
                                resetCardState()
                            }
                            showSearch = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.question)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(card.options[0])
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showSearch = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Statistics Sheet
    private var statisticsSheet: some View {
        NavigationStack {
            List {
                Section("Overview") {
                    HStack {
                        Label("Total Cards", systemImage: "square.stack.3d.up")
                        Spacer()
                        Text("\(cardStatistics.total)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Favorites", systemImage: "star.fill")
                        Spacer()
                        Text("\(cardStatistics.favorites)")
                            .font(.headline)
                            .foregroundColor(.yellow)
                    }
                }
                
                Section("Difficulty Distribution") {
                    HStack {
                        Label("Easy", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Spacer()
                        Text("\(cardStatistics.easy)")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    
                    HStack {
                        Label("Medium", systemImage: "minus.circle.fill")
                            .foregroundColor(.orange)
                        Spacer()
                        Text("\(cardStatistics.medium)")
                            .font(.headline)
                            .foregroundColor(.orange)
                    }
                    
                    HStack {
                        Label("Hard", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Spacer()
                        Text("\(cardStatistics.hard)")
                            .font(.headline)
                            .foregroundColor(.red)
                    }
                }
                
                Section("Progress") {
                    HStack {
                        Label("Current Position", systemImage: "location")
                        Spacer()
                        Text("\(session.index + 1) of \(session.cards.count)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: Double(session.index + 1), total: Double(session.cards.count))
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showStatistics = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Quick Navigation Sheet
    private var quickNavigationSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Enter card number (1-\(session.cards.count))")
                    .font(.headline)
                    .padding(.top, 20)
                
                TextField("Card #", text: $quickNavCardNumber)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .multilineTextAlignment(.center)
                    .font(.title)
                
                Button {
                    if let number = Int(quickNavCardNumber) {
                        jumpToCard(number: number)
                        showQuickNavigation = false
                        quickNavCardNumber = ""
                    }
                } label: {
                    Text("Go")
                        .font(.headline)
                        .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(Int(quickNavCardNumber) == nil || (Int(quickNavCardNumber) ?? 0) < 1 || (Int(quickNavCardNumber) ?? 0) > session.cards.count)
                
                Spacer()
            }
            .navigationTitle("Go to Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showQuickNavigation = false
                        quickNavCardNumber = ""
                    }
                }
            }
        }
        .presentationDetents([.height(250)])
    }

    private func loadExistingFlashcardsIfAny() async {
        guard let docURL = docURL else { return }
        let filename =
            docURL.deletingPathExtension().lastPathComponent + "."
            + docURL.pathExtension

        let savedCards = flashcardStore.loadFlashcards(for: filename)
        if !savedCards.isEmpty {
            session.cards = savedCards
            print(
                "Loaded \(savedCards.count) existing flashcards for \(filename)"
            )
        }
    }

    private func flashcardView(card: Flashcard) -> some View {
        let currentDifficulty = getDifficultyForCard(card)
        
        return VStack(spacing: 20) {
            // MARK: - Enhanced Progress Bar
            VStack(spacing: 8) {
                let progress = Double(session.index + 1) / Double(session.cards.count)
                let percentage = Int(progress * 100)
                
                HStack {
                    Text("Card \(session.index + 1) of \(session.cards.count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(percentage)%")
                        .font(.subheadline.bold())
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 4)
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progress, height: 8)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: progress)
                    }
                }
                .frame(height: 8)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal)
            .padding(.top, 10)

            // MARK: - Favorite & Difficulty Row
            HStack {
                // Favorite button with enhanced styling
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    toggleFavorite(card)
                } label: {
                    ZStack {
                        Circle()
                            .fill(isFavorite(card) ? Color.yellow.opacity(0.15) : Color.secondary.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: isFavorite(card) ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundColor(isFavorite(card) ? .yellow : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(isFavorite(card) ? "Remove from favorites" : "Add to favorites")

                Spacer()

                // Difficulty indicator with enhanced styling
                HStack(spacing: 12) {
                    Text("Difficulty:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(CardDifficulty.allCases, id: \.self) { difficulty in
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            setDifficultyForCard(card, difficulty: difficulty)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        currentDifficulty == difficulty
                                            ? difficultyColor(difficulty).opacity(0.2)
                                            : Color.clear
                                    )
                                    .frame(width: 36, height: 36)
                                Image(systemName: difficulty.systemImage)
                                    .font(.body)
                                    .foregroundColor(
                                        currentDifficulty == difficulty
                                            ? difficultyColor(difficulty)
                                            : .secondary
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)

            // MARK: - Flip Card with Swipe Gestures
            ZStack {
                // BACK SIDE (when flipped)
                if isFlipped {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [Color(UIColor.secondarySystemBackground), Color(UIColor.tertiarySystemBackground)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
                        .overlay(
                                VStack(spacing: 16) {
                                    Text("Answer")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.bottom, 4)

                                    Text(card.options[0])
                                        .font(.system(size: 26, weight: .bold))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                        .minimumScaleFactor(0.5)
                                        .lineLimit(nil)

                                    if ttsEnabled {
                                        HStack {
                                            Spacer()
                                            Button(action: {
                                                toggleTTS(for: card.options[0])
                                            }) {
                                                ZStack {
                                                    Circle()
                                                        .fill(ttsIsPlaying ? Color.orange.opacity(0.2) : Color.blue.opacity(0.1))
                                                        .frame(width: 35, height: 35)
                                                    Image(
                                                        systemName: ttsIsPlaying
                                                            ? "speaker.wave.3.fill"
                                                            : "speaker.wave.2"
                                                    )
                                                    .font(.title3)
                                                    .foregroundColor(ttsIsPlaying ? .orange : .blue)
                                                }
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                }
                                .padding()
                            
                        )
                        .rotation3DEffect(
                            .degrees(180),
                            axis: (x: 0, y: 1, z: 0)
                        )
                }

                // FRONT SIDE
                if !isFlipped {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.12), Color.purple.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
                        .overlay(
                                VStack(spacing: 16) {
                                    Text("Question")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.bottom, 4)

                                    Text(card.question)
                                        .font(.system(size: 26, weight: .bold))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                        .minimumScaleFactor(0.5)
                                        .lineLimit(nil)

                                    if ttsEnabled {
                                        HStack {
                                            Spacer()

                                            Button(action: {
                                                toggleTTS(for: card.question)
                                            }) {
                                                ZStack {
                                                    Circle()
                                                        .fill(ttsIsPlaying ? Color.orange.opacity(0.2) : Color.blue.opacity(0.1))
                                                        .frame(width: 35, height: 35)
                                                    Image(
                                                        systemName: ttsIsPlaying
                                                            ? "speaker.wave.3.fill"
                                                            : "speaker.wave.2"
                                                    )
                                                    .font(.title3)
                                                    .foregroundColor(ttsIsPlaying ? .orange : .blue)
                                                }
                                            }
                                            .buttonStyle(PlainButtonStyle())

                                        }
                                    }
                                }
                                .padding()
                            
                        )
                }
            }
            .frame(minHeight: 300, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            .rotation3DEffect(
                .degrees(isFlipped ? 180 : 0),
                axis: (x: 0, y: 1, z: 0)
            )
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isFlipped)
            .onTapGesture {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation { isFlipped.toggle() }
            }
            .gesture(
                DragGesture(minimumDistance: 50)
                    .onEnded { value in
                        let horizontalAmount = value.translation.width
                        let verticalAmount = value.translation.height
                        
                        // Only handle horizontal swipes when card is not flipped
                        if !isFlipped && abs(horizontalAmount) > abs(verticalAmount) {
                            if horizontalAmount < -30 {
                                // Swipe left - go to next
                                withAnimation { goToNext() }
                            } else if horizontalAmount > 30 {
                                // Swipe right - go to previous
                                withAnimation { goToPrevious() }
                            }
                        }
                    }
            )

            // MARK: - Action Buttons
            if isFlipped {
                HStack(spacing: 20) {
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        goToPrevious()
                    }) {
                        HStack {
                            Image(systemName: "chevron.left.circle.fill")
                            Text("Back")
                        }
                        .font(.headline.weight(.medium))
                    }
                    .disabled(session.index == 0)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(
                        session.index == 0 ? 
                        Color.gray.opacity(0.1) : Color.secondary.opacity(0.1)
                    )
                    .foregroundColor(session.index == 0 ? .gray : .primary)
                    .cornerRadius(12)

                    if !(session.index + 1 == session.cards.count) {
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            goToNext()
                        }) {
                            HStack {
                                Text(session.index + 2 == session.cards.count ? "Finish" : "Next")
                                Image(systemName: session.index + 2 == session.cards.count ? "checkmark.circle.fill" : "chevron.right.circle.fill")
                            }
                            .font(.headline.weight(.semibold))
                            .padding(.vertical, 14)
                            .padding(.horizontal, 24)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .shadow(color: .blue.opacity(0.3), radius: 6, x: 0, y: 3)
                        }
                    }
                }
            } else {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    withAnimation { isFlipped = true }
                } label: {
                    HStack {
                        Image(systemName: "eye.circle.fill")
                        Text("Show Answer")
                    }
                    .font(.headline.weight(.semibold))
                    .padding(.vertical, 14)
                    .padding(.horizontal, 32)
                    .background(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .shadow(color: .blue.opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .keyboardShortcut(.defaultAction)
            }

            // MARK: - Card Preview Navigation (Enhanced)
            let displayCards: [(index: Int, card: Flashcard)] = showFavoritesOnly
                ? session.cards.enumerated().filter { favoriteCards.contains($0.element.id) }.map { ($0.offset, $0.element) }
                : session.cards.enumerated().map { ($0.offset, $0.element) }
            
            if displayCards.isEmpty && showFavoritesOnly {
                VStack {
                    Image(systemName: "star.slash")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("No favorite cards yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 80)
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(displayCards, id: \.index) { index, previewCard in
                            let cardDifficulty = getDifficultyForCard(previewCard)
                            
                            Button(action: {
                                session.index = index
                                resetCardState()
                            }) {
                                VStack(spacing: 4) {
                                    HStack {
                                        if favoriteCards.contains(previewCard.id) {
                                            Image(systemName: "star.fill")
                                                .font(.caption2)
                                                .foregroundColor(.yellow)
                                        }
                                        Spacer()
                                        Image(systemName: cardDifficulty.systemImage)
                                            .font(.caption2)
                                            .foregroundColor(difficultyColor(cardDifficulty))
                                    }
                                    
                                    Text(previewCard.question)
                                        .font(.caption)
                                        .bold()
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .foregroundColor(.primary)

                                    Text("\(index + 1)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 80, height: 65)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            session.index == index
                                                ? Color.accentColor.opacity(0.3)
                                                : Color(UIColor.tertiarySystemBackground)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    session.index == index
                                                        ? Color.accentColor
                                                        : difficultyColor(cardDifficulty).opacity(0.5),
                                                    lineWidth: session.index == index ? 2 : 1
                                                )
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .frame(height: 80)
            }
        }
        .padding()
        .onAppear {
            resetCardState()
        }
    }

    // MARK: - Results
    private var resultsView: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.2), Color.blue.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)
                        
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .padding(.top, 30)
                    
                    Text("Study Complete!")
                        .font(.title.bold())
                    
                    Text("You reviewed \(session.cards.count) flashcards")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                // Stats Cards
                let easyCount = cardDifficultyRatings.values.filter { $0 == .easy }.count
                let hardCount = cardDifficultyRatings.values.filter { $0 == .hard }.count
                let mediumCount = cardDifficultyRatings.values.filter { $0 == .medium }.count
                
                HStack(spacing: 16) {
                    VStack(spacing: 8) {
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                            Text("\(easyCount)")
                                .font(.title2.bold())
                            Text("Easy")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                        
                        VStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                            Text("\(hardCount)")
                                .font(.title2.bold())
                            Text("Hard")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    VStack(spacing: 8) {
                        VStack(spacing: 4) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                            Text("\(mediumCount)")
                                .font(.title2.bold())
                            Text("Medium")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                        
                        VStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.title2)
                                .foregroundColor(.yellow)
                            Text("\(favoriteCards.count)")
                                .font(.title2.bold())
                            Text("Favorites")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.yellow.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        session.index = 0
                        session.done = false
                        resetCardState()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Review Again")
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(14)
                        .shadow(color: .blue.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: - Empty State + Generation
    private var generateEmptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .padding(.top, 20)

                    Text("No Flashcards Yet")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    Text("Generate flashcards from the current document.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                if selectedMode == .bilingual {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Flashcard Direction", systemImage: "arrow.left.arrow.right")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)

                        Picker("Direction", selection: $selectedBilingualDirection)
                        {
                            ForEach(BilingualDirection.allCases) { direction in
                                Text(direction.rawValue).tag(direction)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal, 20)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Custom Instructions", systemImage: "text.badge.plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)

                    TextField(
                        "e.g. Focus on vocabulary, include examples…",
                        text: $customPrompt,
                        axis: .vertical
                    )
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .lineLimit(3...6)
                }
                .padding(.horizontal, 20)

                if isGenerating {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .stroke(Color.blue.opacity(0.3), lineWidth: 4)
                                .frame(width: 60, height: 60)
                            
                            Circle()
                                .trim(from: 0, to: CGFloat(generationTotalSeconds - countdownRemaining) / CGFloat(generationTotalSeconds))
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 60, height: 60)
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 1), value: countdownRemaining)
                            
                            if showIndefiniteSpinner {
                                ProgressView()
                            } else {
                                Text("\(countdownRemaining)")
                                    .font(.headline.monospacedDigit())
                            }
                        }
                        
                        VStack(spacing: 4) {
                            Text("Generating your flashcards...")
                                .font(.headline)
                            
                            Text("Please keep this screen open")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 20)
                } else {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        adManager.present()
                        Task { await startGeneration() }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Generate Flashcards")
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "bitcoinsign.circle.fill")
                                Text("\(rewardedAdManager.coins)")
                            }
                        }
                        .font(.headline.weight(.semibold))
                        .padding(.vertical, 14)
                        .padding(.horizontal, 24)
                        .background(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(14)
                        .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
        }
        .onAppear {
            adManager.loadAd()
        }
    }

    private func startGeneration() async {
        guard !isGenerating else { return }
        isGenerating = true
        countdownRemaining = generationTotalSeconds

        Task {
            while countdownRemaining > 0 && session.cards.isEmpty {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { countdownRemaining -= 1 }
            }
            await MainActor.run {
                showIndefiniteSpinner = session.cards.isEmpty
            }
        }

        await generateFlashcards()

        await MainActor.run {
            isGenerating = false
            showIndefiniteSpinner = false
        }
    }
    
    func loc(_ en: String, _ zh: String) -> String {
        let aiReplyLanguageRaw =
            UserDefaults.standard.string(forKey: "ai_reply_language")
            ?? AIReplyLanguage.english.rawValue
        let aiReplyLanguage =
            AIReplyLanguage(rawValue: aiReplyLanguageRaw) ?? .english
        return aiReplyLanguage == .traditionalChinese ? zh : en
    }
    
    @MainActor
    private func deductCoinIfPossible() -> Bool {
        let success = RewardedAdManager.shared.spendCoins(1)
        
        if success {
            return true
        }
        
        let isSubscribed = SubscriptionManager.shared.isSubscribed
        
        if isSubscribed {
            errorMessage = loc(
                "Not enough coins. Buy coins, or watch an ad to earn more!",
                "硬幣不足。購買硬幣，或觀看廣告賺取更多！"
            )
        } else {
            errorMessage = loc(
                "Not enough coins. Subscribe to Premium for 100 coins/month (ad-free!), buy coins, or watch an ad to earn more!",
                "硬幣不足。訂閱 Premium 每月獲得 100 硬幣（無廣告！）、購買硬幣，或觀看廣告賺取更多！"
            )
        }
        
        // Haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        
        return false
    }

    @MainActor
    private func withCoinProtected<T>(
        actionDescription: String = "API operation",
        operation: () async throws -> T
    ) async throws -> T {
        // Attempt to deduct coin first
        let deducted = deductCoinIfPossible()
        guard deducted else {
            throw NSError(domain: "CoinError", code: -1, userInfo: [
                NSLocalizedDescriptionKey: loc(
                    "Not enough coins to perform this action.",
                    "硬幣不足，無法執行此操作。"
                )
            ])
        }

        do {
            let result = try await operation()
            // Success → coin stays spent
            return result
        } catch {
            print("❌ \(actionDescription) failed → refunding 1 coin. Error: \(error)")
            RewardedAdManager.shared.earnCoin()

            throw error
        }
    }
    
    private func generateFlashcards() async {
        // No early deduct here anymore — withCoinProtected handles it

        do {
            try await withCoinProtected(actionDescription: "Flashcard generation") {
                let aiReplyLanguageRaw = UserDefaults.standard.string(forKey: "ai_reply_language") ?? AIReplyLanguage.english.rawValue
                let aiReplyLanguage = AIReplyLanguage(rawValue: aiReplyLanguageRaw) ?? .english
                let isChinese = aiReplyLanguage == .traditionalChinese
                
                let langInstruction = isChinese
                    ? "\n強制語言要求：所有內容必須使用正體中文。"
                    : "\nMandatory language requirement: All content must be in English."
                
                let outputFormat = isChinese
                    ? "Q: [正面]\nA: [背面]\n\n(空行分隔)"
                    : "Q: [Front]\nA: [Back]\n\n(Blank line between cards)"
                
                var systemPrompt: String
                
                switch selectedMode {
                case .bilingual:
                    let front = selectedBilingualDirection.frontLanguageDescription
                    let back = selectedBilingualDirection.backLanguageDescription
                    let format = isChinese
                        ? "Q: [英文術語]\nA: [中文翻譯]\n\n(空行分隔)"
                        : "Q: [Term in \(front)]\nA: [Translation in \(back)]\n\n(Blank line between cards)"
                    systemPrompt = """
                    \(langInstruction)
                    
                    You are an expert in bilingual terminology translation.
                    Generate flashcards for term recognition.
                    
                    Direction: \(front) → \(back)
                    
                    \(format)
                    
                    Rules:
                    - Each term appears ONCE
                    - Use standard translation
                    - Keep concise: 1-6 words
                    - No explanations
                    
                    Document content:
                    """
                    
                case .explanation:
                    let format = isChinese
                        ? "Q: [問題]\nA: [解釋]\n\n(空行分隔)"
                        : "Q: [Question]\nA: [Explanation]\n\n(Blank line between cards)"
                    systemPrompt = """
                    \(langInstruction)
                    
                    You are an expert educator. Generate flashcards for active recall.
                    
                    \(format)
                    
                    Rules:
                    - One idea per card
                    - Q: short question
                    - A: brief explanation
                    
                    Document content:
                    """
                }

                var userPrompt = ""
                if let text = docText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    userPrompt = String(text.prefix(80_000))
                }

                let apiKey = ProcessInfo.processInfo.environment["MINIMAX_API_KEY"]
                    ?? (Bundle.main.object(forInfoDictionaryKey: "MiniMaxAPIKey") as? String) ?? ""

                guard !apiKey.isEmpty else {
                    throw NSError(domain: "APIError", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "No API key found"
                    ])
                }

                let response = try await MiniMaxService.chatWithAutoContinue(
                    apiKey: apiKey,
                    messages: [
                        ChatMessage(role: .system, content: systemPrompt),
                        ChatMessage(role: .user, content: userPrompt),
                    ],
                    temperature: 0.1
                )

                print("📄 Raw response (first 500): \(String(response.prefix(500)))")
                
                let parsed = parseClassicFlashcards(from: response)
                print("✅ Parsed \(parsed.count) flashcards")

                // Force UI update with delay
                try? await Task.sleep(nanoseconds: 100_000_000)
                
                await MainActor.run {
                    session.cards = parsed
                    print("🎯 Flashcard Session updated: cards=\(parsed.count)")
                }
                
                // Another small delay
                try? await Task.sleep(nanoseconds: 100_000_000)
                
                await MainActor.run {
                    saveCardsToStore()
                }
            }
        } catch {
            print("❌ Flashcard Generation Error: \(error)")
            await MainActor.run {
                errorMessage = loc(
                    "Failed to generate flashcards: \(error.localizedDescription). Coin has been refunded.",
                    "生成閃卡失敗：\(error.localizedDescription)。已退還硬幣。"
                )
            }
        }
    }

    // MARK: - Parser for Q:/A: format
    private func parseClassicFlashcards(from response: String) -> [Flashcard] {
        var cards: [Flashcard] = []
        
        // First, clean the response - remove reasoning text
        var cleanResponse = response
        if let reasoningIndex = response.range(of: #"(?:Let me|I'LL|I'll|The user wants|I'll|Here are|生成的卡片)"#, options: .regularExpression) {
            cleanResponse = String(response[..<reasoningIndex.lowerBound])
        }
        
        // Method 1: Try Q:/A: format first
        let normalized = cleanResponse
            .replacingOccurrences(of: "\n\n\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\n\n", with: "\n", options: .regularExpression)
        
        let qParts = normalized.components(separatedBy: "Q:")

        for part in qParts {
            guard !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            
            let lines = part.components(separatedBy: "\n")
            var front = ""
            var back = ""

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                
                if trimmed.uppercased().hasPrefix("A:") || trimmed.hasPrefix("A.") {
                    back = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                } else if front.isEmpty && !trimmed.uppercased().hasPrefix("A") && !trimmed.uppercased().hasPrefix("CORRECT") {
                    front = trimmed
                }
            }

            if !front.isEmpty && !back.isEmpty {
                cards.append(Flashcard(question: front, options: [back, "", "", ""], correctIndex: 0))
            }
        }
        
        // Method 2: If no cards found, try alternating format (English\nChinese\nEnglish\nChinese...)
        if cards.isEmpty {
            let allLines = cleanResponse
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            var i = 0
            while i < allLines.count - 1 {
                let front = allLines[i]
                let back = allLines[i + 1]
                
                // Check if this looks like a term pair (one English, one Chinese)
                let frontHasChinese = front.range(of: #"[\u4E00-\u9FFF]"#, options: .regularExpression) != nil
                let backHasChinese = back.range(of: #"[\u4E00-\u9FFF]"#, options: .regularExpression) != nil
                
                if frontHasChinese != backHasChinese {
                    // This is a valid pair
                    let question = frontHasChinese ? back : front
                    let answer = frontHasChinese ? front : back
                    
                    if !question.isEmpty && !answer.isEmpty {
                        cards.append(Flashcard(question: question, options: [answer, "", "", ""], correctIndex: 0))
                    }
                    i += 2
                } else {
                    i += 1
                }
            }
        }
        
        return cards
    }

    // MARK: - Persistence helpers (reuse your existing ones)
    private func saveCardsToStore() {
        guard let url = docURL else { return }
        try? flashcardStore.save(session.cards, for: url)
    }

    private func saveSessionState() {
        guard let url = docURL else { return }
        let base = "FlashcardSession_\(url.absoluteString)"
        UserDefaults.standard.set(session.index, forKey: "\(base)_index")
        UserDefaults.standard.set(session.done, forKey: "\(base)_done")
    }

    private func restoreSessionState() {
        guard let url = docURL else { return }
        let base = "FlashcardSession_\(url.absoluteString)"
        session.index = UserDefaults.standard.integer(forKey: "\(base)_index")
        session.done = UserDefaults.standard.bool(forKey: "\(base)_done")
    }

    private func handleRegenerate() async {
        await MainActor.run {
            session.cards = []
        }
        if let onGenerate { await onGenerate() }
    }

    private func goToPrevious() {
        guard session.index > 0 else { return }
        session.index -= 1
        resetCardState()
    }

    private func goToNext() {
        if session.index + 1 < session.cards.count {
            session.index += 1
            resetCardState()
        } else {
            session.done = true
        }
    }

    private func resetCardState() {
        isFlipped = false
        currentCardStartTime = Date()
    }
}
