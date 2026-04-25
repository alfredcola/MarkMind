//
//  MCStudyView 2.swift
//  Markdown Opener
//
//  Created by alfred chen on 8/3/2026.
//
internal import AVFAudio
import Combine
import PDFKit
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit
import ZIPFoundation

struct MCStudyView: View {
    @ObservedObject var session: MCSession
    @EnvironmentObject var mcStore: MCStore
    @ObservedObject var rewardedAdManager = RewardedAdManager.shared
    
    let docURL: URL?
    let docText: String?
    
    var onGenerate: (() async -> Void)? = nil
    
    @State var selectedIndex: Int? = nil
    @State var showResult: Bool = false
    @State var isCorrect: Bool = false
    @State var gradingFeedback: String = ""
    @State var isBatchExplaining: Bool = false
    @State var isGrading: Bool = false
    
    // Generation UI state
    @State var isGenerating: Bool = false
    @State var countdownRemaining: Int = 30
    @State var showIndefiniteSpinner: Bool = false
    let generationTotalSeconds = 30
    
    @State var explainingCardIDs: Set<UUID> = []
    @State var selectedFiles: [(url: URL, content: String)] = []
    @State var showFilePicker = false
    @State var errorMessage: String?
    
    @StateObject var adManager = InterstitialAdManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    func isExplainingCard(_ id: UUID) -> Bool {
        explainingCardIDs.contains(id)
    }
    
    @State var customPrompt: String = ""
    @State var isGeneratingExplanation = false
    @EnvironmentObject var model: TestAppModel
    @ObservedObject var settingsVM = MultiSettingsViewModel.shared
    
    // TTS states (if not already present)
    @State var ttsIsPlaying = false
    
    @State var ttsCurrentChunkIndex = 0
    @State var ttsChunks: [String] = []
    @State var ttsSpokenSoFar = ""
    @State var ttsUseBuiltInTTS = false
    @State var ttsChineseSynthesizer = AVSpeechSynthesizer()
    @State var ttsChineseDelegate: ChineseTTSDelegate?
    @State var ttsChunkTimer: Timer? = nil
    @State var showRegenerateConfirmation = false
    @State var weakConcepts: [String] = []
    @State var masteredConcepts: [String] = []
    @State var showWeaknessSummary = false
    @Binding var ttsEnabled: Bool
    @State var ttsTask: Task<Void, Never>? = nil
    @AppStorage("usehistory") var useHistory: Bool = true
    @State var showuseHistoryHit = false
    @State var showHighScoreCoinBanner = false
    
    // Error Review Mode
    @State var isErrorReviewMode: Bool = false
    @State var errorCards: [MCcard] = []
    
    // Study Streaks
    @State var currentStreak: Int = 0
    @State var lastStudyDate: Date?
    @State var showStreakBanner: Bool = false
    
    // Quick Navigation
    @State var showCardNavigator: Bool = false
    
    // Search
    @State var searchText: String = ""
    @State var showSearch: Bool = false
    @State var searchResults: [MCcard] = []
    
    // Performance Analytics
    @State var showAnalytics: Bool = false
    @State var sessionStats: SessionStats = SessionStats()
    
    struct SessionStats {
        var totalTime: TimeInterval = 0
        var averageTimePerCard: TimeInterval = 0
        var fastestCard: TimeInterval = Double.infinity
        var slowestCard: TimeInterval = 0
        var correctStreak: Int = 0
        var longestCorrectStreak: Int = 0
    }
    
    func explainSingleCard(_ card: MCcard) async {
        guard let index = session.cards.firstIndex(where: { $0.id == card.id })
        else { return }
        guard session.cards[index].explanation?.isEmpty ?? true else { return }
        
        await MainActor.run { explainingCardIDs.insert(card.id) }
        
        let apiKey = ProcessInfo.processInfo.environment["MINIMAX_API_KEY"]
        ?? (Bundle.main.object(forInfoDictionaryKey: "MiniMaxAPIKey") as? String)
        ?? ""
        
        guard !apiKey.isEmpty else {
            await MainActor.run { explainingCardIDs.remove(card.id) }
            return
        }
        
        do {
            let explanation = try await withCoinProtected(actionDescription: "Card explanation") {
                let userIdx = card.lastUserIndex ?? card.correctIndex
                let userAnswer = card.options[userIdx]
                
                return try await GradingService.explain(
                    userAnswer: userAnswer,
                    card: card,
                    apiKey: apiKey
                )
            }
            
            await MainActor.run {
                session.cards[index].explanation = explanation
                explainingCardIDs.remove(card.id)
                saveCardsToStore()
            }
        } catch {
            await MainActor.run {
                explainingCardIDs.remove(card.id)
            }
        }
    }
    
    // MARK: - Spaced Repetition System
    func calculateSRScore(for card: MCcard) -> Double {
        let baseScore = 1.0
        
        let accuracyRate = card.timesSeen > 0
        ? Double(card.timesCorrect) / Double(card.timesSeen)
        : 0.5
        
        let recencyWeight = card.lastAttemptDate != nil
        ? max(0, 1.0 - Date().timeIntervalSince(card.lastAttemptDate!) / (7 * 24 * 60 * 60))
        : 0.0
        
        let difficultyWeight = 1.0 - accuracyRate
        
        return baseScore * (0.3 + recencyWeight * 0.3 + difficultyWeight * 0.4)
    }
    
    func getSortedByDifficulty() -> [MCcard] {
        session.cards.sorted { calculateSRScore(for: $0) > calculateSRScore(for: $1) }
    }
    
    func getWeakCards(threshold: Double = 0.6) -> [MCcard] {
        session.cards.filter { card in
            let accuracy = card.timesSeen > 0
            ? Double(card.timesCorrect) / Double(card.timesSeen)
            : 1.0
            return accuracy < threshold
        }
    }

    
    // MARK: - Error Review Mode
    func startErrorReviewMode() {
        errorCards = session.cards.filter { card in
            guard let userIdx = card.lastUserIndex else { return true }
            return userIdx != card.correctIndex
        }
        
        if errorCards.isEmpty {
            errorCards = session.cards.filter { card in
                card.timesSeen > 0 && Double(card.timesCorrect) / Double(card.timesSeen) < 1.0
            }
        }
        
        isErrorReviewMode = true
        session.cards = errorCards
        session.index = 0
        session.done = errorCards.isEmpty
        resetState()
    }
    
    func exitErrorReviewMode() {
        isErrorReviewMode = false
    }
    
    // MARK: - Study Streaks
    func checkAndUpdateStreak() {
        let today = Calendar.current.startOfDay(for: Date())
        
        if let lastDate = lastStudyDate {
            let lastDay = Calendar.current.startOfDay(for: lastDate)
            let daysDiff = Calendar.current.dateComponents([.day], from: lastDay, to: today).day ?? 0
            
            if daysDiff == 1 {
                currentStreak += 1
                showStreakBanner = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.showStreakBanner = false
                }
            } else if daysDiff > 1 {
                currentStreak = 1
            }
        } else {
            currentStreak = 1
        }
        
        lastStudyDate = Date()
        saveStreakData()
    }
    
    func saveStreakData() {
        guard let url = docURL else { return }
        let base = "MCStreak_\(url.absoluteString)"
        UserDefaults.standard.set(currentStreak, forKey: "\(base)_count")
        UserDefaults.standard.set(lastStudyDate, forKey: "\(base)_date")
    }
    
    func loadStreakData() {
        guard let url = docURL else { return }
        let base = "MCStreak_\(url.absoluteString)"
        currentStreak = UserDefaults.standard.integer(forKey: "\(base)_count")
        lastStudyDate = UserDefaults.standard.object(forKey: "\(base)_date") as? Date
    }
    
    // MARK: - Search
    func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        let query = searchText.lowercased()
        searchResults = session.cards.filter { card in
            card.question.lowercased().contains(query) ||
            card.options.contains { $0.lowercased().contains(query) }
        }
    }
    
    // MARK: - Quick Navigation
    func goToCard(at index: Int) {
        guard index >= 0 && index < session.cards.count else { return }
        session.index = index
        session.done = false
        resetState()
        showCardNavigator = false
    }
    
    func goToPreviousCard() {
        if session.index > 0 {
            session.index -= 1
            resetState()
        }
    }
    
    func goToNextCard() {
        if session.index < session.cards.count - 1 {
            session.index += 1
            resetState()
        } else {
            session.done = true
            // Save study result when all questions are completed
            if session.totalAttempts != 0 && session.totalMarks != 0 {
                saveStudyResult()
            }
        }
    }
    
    // MARK: - Performance Analytics
    func updateSessionStats(correct: Bool, timeSpent: TimeInterval) {
        sessionStats.totalTime += timeSpent
        
        if timeSpent < sessionStats.fastestCard {
            sessionStats.fastestCard = timeSpent
        }
        if timeSpent > sessionStats.slowestCard {
            sessionStats.slowestCard = timeSpent
        }
        
        if correct {
            sessionStats.correctStreak += 1
            if sessionStats.correctStreak > sessionStats.longestCorrectStreak {
                sessionStats.longestCorrectStreak = sessionStats.correctStreak
            }
        } else {
            sessionStats.correctStreak = 0
        }
        
        let totalCards = sessionStats.totalTime > 0 ? Double(session.index + 1) : 1
        sessionStats.averageTimePerCard = sessionStats.totalTime / totalCards
    }
    
    func getPerformanceReport() -> String {
        let accuracy = session.totalAttempts > 0
        ? Double(session.totalMarks) / Double(session.totalAttempts * 10) * 100
        : 0
        
        var report = "📊 Performance Report\n\n"
        report += "Score: \(session.totalMarks)/\(session.totalAttempts * 10) (\(Int(accuracy))%)\n"
        report += "Total Time: \(Int(sessionStats.totalTime / 60)) min \(Int(sessionStats.totalTime.truncatingRemainder(dividingBy: 60))) sec\n"
        report += "Avg Time/Card: \(Int(sessionStats.averageTimePerCard)) sec\n"
        report += "Best Streak: \(sessionStats.longestCorrectStreak)\n"
        
        return report
    }
    
    // MARK: - Shuffle Options
    func shuffleCurrentOptions(for card: MCcard) -> [String] {
        var options = card.options
        guard card.correctIndex >= 0 && card.correctIndex < options.count else {
            options.shuffle()
            return options
        }
        let correctAnswer = options[card.correctIndex]
        
        options.shuffle()
        
        if let newCorrectIndex = options.firstIndex(of: correctAnswer) {
            if session.index < session.cards.count {
                session.cards[session.index].correctIndex = newCorrectIndex
            }
        }
        
        return options
    }
    
    var body: some View {
        NavigationStack {
            if UIDevice.current.userInterfaceIdiom == .pad
                || (UIDevice.current.userInterfaceIdiom == .phone
                    && Environment(\.horizontalSizeClass).wrappedValue
                    == .regular)
            {
                VStack(spacing: 0) {
                    HStack {
                        Group {
                            if session.cards.isEmpty {
                                Button {
                                    useHistory.toggle()
                                    showuseHistoryHit = true
                                } label: {
                                    Image(
                                        systemName: useHistory
                                        ? "clock"
                                        : "clock.badge.exclamationmark"
                                    )
                                    .font(.title2)
                                    .padding(8)
                                    .background(
                                        Circle().fill(
                                            Color.secondary.opacity(0.15)
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
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
                                    "Regenerate MCcard?",
                                    isPresented: $showRegenerateConfirmation,
                                    titleVisibility: .visible
                                ) {
                                    Button("Regenerate", role: .destructive) {
                                        NotificationCenter.default.post(
                                            name: .regenerateMCcards,
                                            object: nil
                                        )
                                        if session.totalAttempts != 0
                                            && session.totalMarks != 0
                                            && session.done
                                        {
                                            saveStudyResult()
                                        }
                                    }
                                    Button("Cancel", role: .cancel) {}
                                } message: {
                                    Text(
                                        "This will clear all current mc. This action cannot be undone."
                                    )
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Text("MC Study")
                            .font(.headline.bold())
                        
                        Spacer()
                        
                        Group {
                            if session.cards.isEmpty {
                                Menu {
                                    ForEach(MCLanguage.allCases) { lang in
                                        Button {
                                            selectedLanguage = lang
                                            UserDefaults.standard.set(
                                                lang.rawValue,
                                                forKey: "MCLanguage"
                                            )
                                        } label: {
                                            HStack {
                                                Text(lang.rawValue)
                                                if selectedLanguage == lang {
                                                    Image(
                                                        systemName: "checkmark"
                                                    )
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Label(
                                        selectedLanguage.rawValue,
                                        systemImage: "globe"
                                    )
                                    .font(.title3)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)  // Adjust radius here
                                            .fill(Color.secondary.opacity(0.15))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if session.current != nil {
                                Button {
                                    session.restart()
                                    resetState()
                                } label: {
                                    Image(systemName: "gobackward")
                                        .font(.title2)
                                        .padding(8)
                                        .background(
                                            Circle().fill(
                                                Color.secondary.opacity(0.15)
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            
                            NavigationLink {
                                MCReviewHistoryView(currentDocURL: docURL)
                            } label: {
                                Image(systemName: "tray.full.fill")
                                    .font(.title2)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.secondary.opacity(0.15))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 2)
                    .background(Color(UIColor.systemBackground))
                    .overlay(Divider(), alignment: .bottom)
                    
                    Spacer()
                    
                    VStack(spacing: 0) {
                        if session.cards.isEmpty {
                            generateEmptyState
                        } else if session.done {
                            resultsViewAll()
                        } else if let card = session.current {
                            mcCardView(card: card)
                        } else {
                            ProgressView().padding()
                        }
                    }
                    
                    Spacer()
                    
                }
                .navigationBarHidden(true)
            } else {
                VStack(spacing: 0) {
                    if session.cards.isEmpty {
                        generateEmptyState
                    } else if session.done {
                        resultsViewAll()
                    } else if let card = session.current {
                        mcCardView(card: card)
                    } else {
                        ProgressView().padding()
                    }
                }
                .navigationTitle("MC Study")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if session.cards.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                useHistory.toggle()
                                showuseHistoryHit = true
                            } label: {
                                Image(
                                    systemName: useHistory
                                    ? "clock"
                                    : "clock.badge.exclamationmark"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if !session.cards.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showRegenerateConfirmation = true
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .confirmationDialog(
                                "Regenerate MCcard?",
                                isPresented: $showRegenerateConfirmation,
                                titleVisibility: .visible
                            ) {
                                Button("Regenerate", role: .destructive) {
                                    NotificationCenter.default.post(
                                        name: .regenerateMCcards,
                                        object: nil
                                    )
                                    if session.totalAttempts != 0
                                        && session.totalMarks != 0
                                        && session.done
                                    {
                                        saveStudyResult()
                                    }
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text(
                                    "This will clear all current mc. This action cannot be undone."
                                )
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            MCReviewHistoryView(currentDocURL: docURL)
                        } label: {
                            Image(systemName: "tray.full.fill")
                        }
                    }
                    
                    if session.cards.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                ForEach(MCLanguage.allCases) { lang in
                                    Button {
                                        selectedLanguage = lang
                                        UserDefaults.standard.set(
                                            lang.rawValue,
                                            forKey: "MCLanguage"
                                        )
                                    } label: {
                                        HStack {
                                            Text(lang.rawValue)
                                            if selectedLanguage == lang {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Label(
                                    selectedLanguage.rawValue,
                                    systemImage: "globe"
                                )
                            }
                        }
                    }
                    
                    if session.current != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button {
                                    session.restart()
                                    resetState()
                                } label: {
                                    Label("Restart", systemImage: "gobackward")
                                }
                                
                                Divider()
                                
                                Button {
                                    showSearch = true
                                } label: {
                                    Label("Search Cards", systemImage: "magnifyingglass")
                                }
                                
                                Button {
                                    showCardNavigator = true
                                } label: {
                                    Label("Quick Navigation", systemImage: "list.number")
                                }
                                
                                Button {
                                    startErrorReviewMode()
                                } label: {
                                    Label("Review Errors", systemImage: "arrow.counterclockwise")
                                }
                                
                                Divider()
                                
                                Button {
                                    showAnalytics = true
                                } label: {
                                    Label("Statistics", systemImage: "chart.bar.fill")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
            
        }
        .onChange(of: isGenerating) {
            UIApplication.shared.isIdleTimerDisabled = isGenerating
        }
        .onAppear {
            adManager.loadAd()
            restoreSessionState()
            loadStreakData()
            checkAndUpdateStreak()
        }
        .onDisappear {
            ttsTask?.cancel()
            ttsTask = nil
            stopTTS()
            saveSessionState()
            saveStreakData()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .regenerateMCcards)
        ) { _ in
            Task { await handleRegenerate() }
        }
        .overlay(
            Group {
                if showHighScoreCoinBanner {
                    VStack {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text("Perfect! +1 coin earned for 90%+ score 🎉")
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                        }
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding()
                        .transition(
                            .move(edge: .bottom).combined(with: .opacity)
                        )
                    }
                    .animation(.spring(), value: showHighScoreCoinBanner)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation(.easeOut) {
                                showHighScoreCoinBanner = false
                            }
                        }
                    }
                }
                Group {
                    if showuseHistoryHit {
                        VStack {
                            Spacer()
                            Text(
                                useHistory
                                ? "History ON: New MC will reference past results"
                                : "History OFF: Standard MC generation"
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
                        .animation(.spring(), value: showuseHistoryHit)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(
                                deadline: .now() + 1.0
                            ) {
                                withAnimation(.easeOut) {
                                    showuseHistoryHit = false
                                }
                            }
                        }
                    }
                }
            }
        )
        .alert(isPresented: .constant(errorMessage != nil)) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage ?? ""),
                dismissButton: .default(Text("OK")) { errorMessage = nil }
            )
        }
        .sheet(isPresented: $showSearch) {
            NavigationStack {
                VStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("Search questions...", text: $searchText)
                            .textFieldStyle(.plain)
                            .onChange(of: searchText) { _, _ in
                                performSearch()
                            }
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                    .padding()
                    
                    if searchResults.isEmpty && !searchText.isEmpty {
                        Text("No results found")
                            .foregroundColor(.secondary)
                    } else if !searchResults.isEmpty {
                        List(searchResults, id: \.id) { card in
                            Button {
                                if let index = session.cards.firstIndex(where: { $0.id == card.id }) {
                                    goToCard(at: index)
                                    showSearch = false
                                }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(card.question)
                                        .font(.headline)
                                        .lineLimit(2)
                                    Text("Tap to go to this card")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Search Cards")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showSearch = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showCardNavigator) {
            NavigationStack {
                VStack {
                    Text("Go to Card")
                        .font(.headline)
                        .padding()
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 10) {
                            ForEach(Array(session.cards.enumerated()), id: \.element.id) { index, card in
                                let isCorrect = card.lastUserIndex == card.correctIndex
                                let isAttempted = card.lastUserIndex != nil
                                
                                Button {
                                    goToCard(at: index)
                                    showCardNavigator = false
                                } label: {
                                    VStack {
                                        Text("\(index + 1)")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                    }
                                    .frame(width: 50, height: 50)
                                    .background(
                                        Circle()
                                            .fill(
                                                isCorrect ? Color.green :
                                                    (isAttempted ? Color.red : Color.blue)
                                            )
                                    )
                                }
                            }
                        }
                        .padding()
                    }
                    
                    HStack {
                        Circle().fill(Color.green).frame(width: 10, height: 10)
                        Text("Correct").font(.caption)
                        Circle().fill(Color.red).frame(width: 10, height: 10)
                        Text("Incorrect").font(.caption)
                        Circle().fill(Color.blue).frame(width: 10, height: 10)
                        Text("Not attempted").font(.caption)
                    }
                    .padding()
                }
                .navigationTitle("Quick Navigation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showCardNavigator = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showAnalytics) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Score Overview")
                                .font(.headline)
                            HStack {
                                VStack {
                                    Text("\(session.totalMarks)")
                                        .font(.largeTitle.bold())
                                        .foregroundColor(.green)
                                    Text("Points")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack {
                                    Text("\(session.totalAttempts * 10)")
                                        .font(.largeTitle.bold())
                                    Text("Max Points")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack {
                                    let accuracy = session.totalAttempts > 0 ?
                                    Int(Double(session.totalMarks) / Double(session.totalAttempts * 10) * 100) : 0
                                    Text("\(accuracy)%")
                                        .font(.largeTitle.bold())
                                        .foregroundColor(accuracy >= 70 ? .green : .orange)
                                    Text("Accuracy")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Time Statistics")
                                .font(.headline)
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Total Time")
                                    Text("\(Int(sessionStats.totalTime / 60)) min")
                                        .font(.title3.bold())
                                }
                                Spacer()
                                VStack(alignment: .leading) {
                                    Text("Avg/Card")
                                    Text("\(Int(sessionStats.averageTimePerCard)) sec")
                                        .font(.title3.bold())
                                }
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Streaks")
                                .font(.headline)
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Current Streak")
                                    Text("\(sessionStats.correctStreak)")
                                        .font(.title3.bold())
                                        .foregroundColor(.orange)
                                }
                                Spacer()
                                VStack(alignment: .leading) {
                                    Text("Best Streak")
                                    Text("\(sessionStats.longestCorrectStreak)")
                                        .font(.title3.bold())
                                        .foregroundColor(.green)
                                }
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        
                        if !getWeakCards().isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Areas to Improve")
                                    .font(.headline)
                                ForEach(getWeakCards().prefix(5), id: \.id) { card in
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text(card.question)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                    }
                                }
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(12)
                            }
                        }
                        
                        Button {
                            let report = getPerformanceReport()
                            UIPasteboard.general.string = report
                        } label: {
                            Label("Copy Report", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
                .navigationTitle("Statistics")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showAnalytics = false }
                    }
                }
            }
        }

        .sheet(isPresented: $showStreakBanner) {
            VStack(spacing: 16) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)
                
                Text("\(currentStreak) Day Streak!")
                    .font(.title.bold())
                
                Text("Keep up the great work!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
    
    func startTTS(for text: String) {
        guard ttsEnabled, !text.isEmpty else { return }
        
        let cleanText = cleanMarkdownForTTS(text)
        let (isChinese, _) = detectContentLanguage(cleanText)
        ttsUseBuiltInTTS = isChinese || !TestAppModel.isSupportedDevice()
        
        let chunks = computeTTSChunks(from: cleanText, isChinese: isChinese)
        if chunks.isEmpty { return }
        
        ttsChunks = chunks
        ttsCurrentChunkIndex = 0
        ttsIsPlaying = true
        ttsSpokenSoFar = ""
        
        playCurrentTTSChunk()
    }
    
    func computeTTSChunks(from text: String, isChinese: Bool)
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
    
    func playCurrentTTSChunk() {
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
        
        let forceBuiltin = chunk.count > (ttsUseBuiltInTTS ? 100 : 100)
        
        if ttsUseBuiltInTTS || forceBuiltin {
            playChineseTTS(chunk)
        } else {
            safeKokoroSpeak(text: chunk) {
                self.handleTTSChunkComplete()
            }
        }
    }
    
    func safeKokoroSpeak(text: String, completion: @escaping () -> Void)
    {
        // Cancel any previous TTS task
        ttsTask?.cancel()
        
        // Reset audio state
        model.stringToFollowTheAudio = ""
        ttsSpokenSoFar = ""
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
    
    func handleTTSChunkComplete() {
        guard ttsIsPlaying else { return }
        
        if ttsCurrentChunkIndex < ttsChunks.count - 1 {
            ttsCurrentChunkIndex += 1
            ttsSpokenSoFar = ""
            playCurrentTTSChunk()
        } else {
            finishTTSPlayback()
        }
    }
    
    func finishTTSPlayback() {
        ttsIsPlaying = false
        ttsCurrentChunkIndex = 0
        ttsChunks = []
        ttsSpokenSoFar = ""
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
        
        // Safely deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
    
    func stopTTS() {
        finishTTSPlayback()
    }
    
    func toggleTTS(for text: String) {
        if ttsIsPlaying {
            stopTTS()
        } else {
            startTTS(for: text)
        }
    }
    
    func startTTSChunkMonitoring() {
        ttsChunkTimer?.invalidate()
        ttsChunkTimer = Timer.scheduledTimer(
            withTimeInterval: 0.2,
            repeats: true
        ) { _ in
            guard !model.stringToFollowTheAudio.isEmpty else { return }
            self.ttsSpokenSoFar = model.stringToFollowTheAudio
                .trimmingCharacters(in: .whitespaces)
        }
    }
    
    func playChineseTTS(_ text: String) {
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
        utterance.rate = isChinese ? 0.5 : 0.45
        
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AVAudioSession error: \(error)")
        }
        
        ttsChineseSynthesizer.speak(utterance)
    }
    
    func resetCardState() {
        selectedIndex = nil
        showResult = false
        isCorrect = false
        gradingFeedback = ""
    }
    
    @State var selectedLanguage: MCLanguage = {
        if let saved = UserDefaults.standard.string(forKey: "MCLanguage"),
           let lang = MCLanguage(rawValue: saved)
        {
            return lang
        }
        return .english  // Default
    }()
    
    func saveStudyResult() {
        guard let url = docURL else { return }
        
        let documentName = url.lastPathComponent
        
        let resultCards = session.cards.map { card -> MCcardResult in
            let userIdx = card.lastUserIndex
            let isCorrect = userIdx == card.correctIndex
            return MCcardResult(
                question: card.question,
                options: card.options,
                correctIndex: card.correctIndex,
                userIndex: userIdx,
                isCorrect: isCorrect,
                explanation: card.explanation
            )
        }
        
        let result = MCStudyResult(
            documentName: documentName,
            date: Date(),
            totalMarks: session.totalMarks,
            totalAttempts: session.totalAttempts,
            cards: resultCards
        )
        
        let scorePercentage: Double =
        session.totalAttempts > 0
        ? Double(session.totalMarks) / Double(session.totalAttempts * 10)
        * 100
        : 0
        
        if scorePercentage >= 90.0 {
            RewardedAdManager.shared.earnCoin()
            
            DispatchQueue.main.async {
                showHighScoreCoinBanner = true
            }
        }
        
        var allResults = MCStudyHistory.shared.results
        allResults.append(result)
        allResults.sort { $1.date > $0.date }
        
        if let data = try? JSONEncoder().encode(allResults) {
            UserDefaults.standard.set(data, forKey: "MCStudyHistory")
        }
        
        MCStudyHistory.shared.results = allResults
    }
    
    func submitAnswer(userChoiceIndex: Int, card: MCcard) async {
        let isCorrectAnswer = userChoiceIndex == card.correctIndex
        
        await MainActor.run {
            // Update performance tracking on the card
            if let idx = session.cards.firstIndex(where: { $0.id == card.id }) {
                session.cards[idx].timesSeen += 1
                if isCorrectAnswer {
                    session.cards[idx].timesCorrect += 1
                    session.cards[idx].consecutiveCorrect += 1
                } else {
                    session.cards[idx].consecutiveCorrect = 0
                }
                session.cards[idx].lastUserIndex = userChoiceIndex
                session.cards[idx].lastFeedback =
                isCorrectAnswer ? "Correct!" : "Incorrect"
                session.cards[idx].lastAttemptDate = Date()
            }
            
            // Update session scoring (10 marks for correct)
            session.applyMark(isCorrect: isCorrectAnswer, for: card.id)
            
            // UI feedback
            selectedIndex = userChoiceIndex
            showResult = true
            isCorrect = isCorrectAnswer
            gradingFeedback =
            isCorrectAnswer
            ? "Correct! 🎉"
            : "Incorrect — Correct answer: \(card.correctAnswer)"
            
            // Persist cards
            saveCardsToStore()
        }
    }
    
    func advanceToNextCard() {
        session.index += 1
        if session.index >= session.cards.count {
            session.done = true
            // Save study result when all questions are completed
            if session.totalAttempts != 0 && session.totalMarks != 0 {
                saveStudyResult()
            }
        }
        resetCardState()
    }
    
    func handleRegenerate() async {
        await MainActor.run {
            clearCurrentMCs()
            clearSavedIndex()
        }
        if let onGenerate { await onGenerate() }
    }
    
    // MARK: - Empty State + Generation
    var generateEmptyState: some View {
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
                        
                        Image(systemName: "rectangle.stack.badge.plus")
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
                    
                    Text("No MC Yet")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    
                    Text(
                        "Generate mc from the current document to start studying."
                    )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Custom Instructions", systemImage: "text.badge.plus")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        if !customPrompt.isEmpty {
                            Button("Clear") { 
                                customPrompt = ""
                                UserDefaults.standard.removeObject(forKey: "LastCustomMCPrompt")
                            }
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.8))
                        }
                    }
                    
                    TextField(
                        "e.g. Make questions very difficult, focus on formulas, add examples…",
                        text: $customPrompt,
                        axis: .vertical
                    )
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .lineLimit(3...6)
                    .onAppear {
                        if customPrompt.isEmpty {
                            customPrompt =
                            UserDefaults.standard.string(
                                forKey: "LastCustomMCPrompt"
                            ) ?? ""
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                if docURL != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Additional References", systemImage: "doc.badge.plus")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                showFilePicker = true
                            } label: {
                                Label("Add", systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.medium))
                            }
                            .disabled(selectedFiles.count >= 5)
                        }
                        
                        if !selectedFiles.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 8) {
                                    ForEach(selectedFiles, id: \.url) { file in
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.fill")
                                                .font(.caption2)
                                            Text(file.url.lastPathComponent)
                                                .font(.caption)
                                                .lineLimit(1)
                                            Button(action: {
                                                removeSelectedFile(file.url)
                                            }) {
                                                Image(
                                                    systemName: "xmark.circle.fill"
                                                )
                                                .font(.caption)
                                                .foregroundColor(.red.opacity(0.8))
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                        } else {
                            Text("Add up to 5 reference files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
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
                            Text("Generating your questions...")
                                .font(.headline)
                            
                            Text(
                                "Please keep this screen open"
                            )
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
                            Text("Generate MC cards")
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
            .onTapGesture {
                hideKeyboard()
            }
            .sheet(isPresented: $showFilePicker) {
                if let url = docURL {
                    InAppFilePicker(
                        documentStore: DocumentStore.shared,
                        selectedFiles: $selectedFiles,
                        docURL: url
                    )
                }
            }
        }
        
    }
        
        func removeSelectedFile(_ url: URL) {
            selectedFiles.removeAll { $0.url == url }
        }
        
        func startGeneration() async {
            guard !isGenerating else { return }
            isGenerating = true
            countdownRemaining = generationTotalSeconds
            showIndefiniteSpinner = false
            
            Task {
                while countdownRemaining > 0 && session.cards.isEmpty {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await MainActor.run { countdownRemaining -= 1 }
                }
                await MainActor.run {
                    showIndefiniteSpinner = session.cards.isEmpty
                }
            }
            
            await generateMCsLocal(regenerate: false)
        }
        
        var latestStudyResult: [MCStudyResult] {
            guard let url = docURL else { return [] }
            let documentName = url.lastPathComponent
            return MCStudyHistory.shared.results
                .filter { $0.documentName == documentName }
                .sorted { $1.date < $0.date }
                .prefix(2)
                .map { $0 }
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
        func deductCoinIfPossible() -> Bool {
            // First, check if user has enough coins
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
        func withCoinProtected<T>(
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
                // Perform the API / expensive operation
                let result = try await operation()
                // Success → coin remains deducted
                return result
            } catch {
                // Failure → refund the coin
                print("❌ \(actionDescription) failed → refunding 1 coin. Error: \(error)")
                RewardedAdManager.shared.earnCoin()
                
                throw error
            }
        }
        
        func generateMCsLocal(regenerate: Bool = false) async {
            // Early validation — no coin spent yet
            if let err = validateMCInputs() {
                await MainActor.run { errorMessage = err }
                return
            }
            
            do {
                try await withCoinProtected(actionDescription: "MC card generation") {
                    
                    var sourceTextBuffer =
                    "### SECTION 1: MANDATORY SOURCE DOCUMENTS ###\n"
                    
                    let primarySnapshot = (docText ?? "").trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    if !primarySnapshot.isEmpty {
                        sourceTextBuffer +=
                        "[PRIMARY_DOC]: \(String(primarySnapshot.prefix(100_000)))\n\n"
                    }
                    
                    for (index, file) in selectedFiles.enumerated() {
                        let trimmed = file.content.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        guard !trimmed.isEmpty else { continue }
                        sourceTextBuffer +=
                        "[FILE_\(index + 1)_\(file.url.lastPathComponent)]: \(trimmed.prefix(100_000))\n\n"
                    }
                    
                    // ── 2. ENHANCED HISTORY & WEAKNESS MAPPING ──
                    var historyBuffer = "### SECTION 2: EXCLUSION & FOCUS RULES ###\n"
                    let results = latestStudyResult
                    
                    if !results.isEmpty {
                        let previousQuestions = Set(
                            results.flatMap { $0.cards.map { $0.question } }
                        )
                        historyBuffer +=
                        "REPETITION_PENALTY: The following questions are in the user's brain already. DO NOT use these topics or logic.\n"
                        historyBuffer +=
                        Array(previousQuestions.prefix(30)).map { "- \($0)" }
                            .joined(separator: "\n") + "\n\n"
                        
                        if useHistory {
                            let weakAreas = results.flatMap {
                                $0.cards.filter { !$0.isCorrect }.prefix(5).map {
                                    $0.question
                                }
                            }
                            historyBuffer +=
                            "ADAPTIVE_FOCUS: The user failed the following concepts recently. Generate NEW, harder questions that test the same underlying principles from a different angle:\n"
                            historyBuffer +=
                            weakAreas.map { "- REINFORCE: \($0)" }.joined(
                                separator: "\n"
                            ) + "\n"
                        }
                    }
                    
                    let userPrompt = sourceTextBuffer + "\n" + historyBuffer
                    
                    // ── 3. REFINED SYSTEM CONTENT ──
                    let trimmedCustom = customPrompt.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    
                    let isChinese = selectedLanguage == .traditionalChinese
                    let langInstruction = isChinese
                        ? "\n所有題目和選項必須使用正體中文。"
                        : "\nAll questions and options must be in English."
                    
                    let outputFormat = isChinese
                        ? """
                        Q: [直接提問]
                        A) [選項]
                        B) [選項]
                        C) [選項]
                        D) [選項]
                        Correct: [字母]
                        """
                        : """
                        Q: [Direct Question]
                        A) [Option]
                        B) [Option]
                        C) [Option]
                        D) [Option]
                        Correct: [Letter]
                        """
                    
                    var systemContent = """
                    ### ROLE
                    You are a Lead Psychometrician and Subject Matter Expert. Your mission is to transform raw technical documentation into a rigorous, 20-item professional certification practice exam.
                    
                    \(langInstruction)
                    
                    ### 1. THE "ZERO-FLUFF" PHRASING PROTOCOL
                    - **No Lead-ins**: Completely ban phrases like "Based on the text," "In the document," "According to,"
                    - **Direct Start**: Every question must start with the core noun or action.
                    - **Constraint**: Question Stem must be 10–15 words. Options must be 1–6 words.
                    
                    ### 2. THE COMPETITIVE INTERFERENCE PRINCIPLE (DISTRACTORS)
                    - **Plausibility**: Every incorrect option (A-D) must be a real term or concept found within 'SECTION 1'.
                    - **Homogeneity**: All four options must belong to the same category
                    - **Non-Overlap**: Ensure no two options mean the same thing.
                    - **Prohibited Distractors**: Never use "All of the above," "None of the above,"
                    
                    ### 3. QUALITY CONTROL
                    - Each question must target different content from the document
                    - Questions must be independent and self-contained
                    
                    ### 4. OUTPUT SCHEMA (STRICT)
                    \(outputFormat)
                    
                    (One blank line between cards. No bolding, no asterisks, no numbering.)
                    
                    \(selectedLanguage.promptInstruction)
                    
                    ### USER SPECIFIC CONSTRAINTS
                    \(trimmedCustom.isEmpty ? "None." : "ADDITIONAL RULE: " + trimmedCustom)
                    """
                    
                    // ── 4. API EXECUTION ──
                    let apiKey =
                    (ProcessInfo.processInfo.environment["MINIMAX_API_KEY"]
                     ?? (Bundle.main.object(
                        forInfoDictionaryKey: "MiniMaxAPIKey"
                     ) as? String) ?? "")
                    
                    print("🔑 API Key present: \(!apiKey.isEmpty)")
                    
                    guard !apiKey.isEmpty else {
                        throw NSError(domain: "APIError", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: "MiniMax API key is empty. Please set it in Settings."
                        ])
                    }
                    
                    print("📤 Sending request to MiniMax...")
                    let (replyContent, _) = try await MiniMaxService.chat(
                        apiKey: apiKey,
                        messages: [
                            .init(role: .system, content: systemContent),
                            .init(role: .user, content: userPrompt),
                        ],
                        temperature: 0.1,
                        maxTokens: 8192
                    )
                    
                    // ── 5. UI & PERSISTENCE ──
                    let cards = parseMCMCs(from: replyContent)
                    print("✅ Parsed \(cards.count) cards")
                    
                    if let url = docURL { try mcStore.save(cards, for: url) }
                    
                    // Force UI update with delay
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    
                    await MainActor.run {
                        session.cards = cards
                        session.index = 0
                        session.done = false
                        print("🎯 Session updated: cards=\(cards.count)")
                    }
                    
                    // Another small delay to ensure UI refreshes
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    
                    await MainActor.run {
                        if !trimmedCustom.isEmpty {
                            UserDefaults.standard.set(
                                trimmedCustom,
                                forKey: "LastCustomMCPrompt"
                            )
                        }
                    }
                }
            } catch {
                print("❌ MC Generation Error: \(error)")
                await MainActor.run {
                    errorMessage = loc(
                        "Failed to generate MC cards: \(error.localizedDescription). Coin has been refunded.",
                        "生成題目失敗：\(error.localizedDescription)。已退還硬幣。"
                    )
                }
            }
            
            await MainActor.run {
                isGenerating = false
                showIndefiniteSpinner = false
            }
        }
        
        // MARK: - Progress Bar with Animation
        func progressBarView() -> some View {
            VStack(spacing: 8) {
                let current = session.index + 1
                let total = session.cards.count
                let progress = total > 0 ? Double(current) / Double(total) : 0.0
                let percentage = Int(progress * 100)
                
                HStack {
                    Text("Question \(current) of \(total)")
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
        }
        
        // MARK: - Validation
        func validateMCInputs() -> String? {
            guard docURL != nil else { return "Open a document first." }
            
            let primarySnapshot = (docText ?? "").trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let hasPrimaryText = !primarySnapshot.isEmpty
            let isPPTOrPPTX =
            docURL?.pathExtension.lowercased() == "ppt"
            || docURL?.pathExtension.lowercased() == "pptx"
            
            if isPPTOrPPTX {
                return
                "PPT and PPTX files are not supported for mc generation."
            }
            
            let hasAdditional = selectedFiles.contains { pair in
                !pair.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            }
            
            guard hasPrimaryText || hasAdditional else {
                return "This file has no extractable text for mcs."
            }
            
            return nil
        }
        
        // MARK: - Parsing
        func parseMCMCs(from response: String) -> [MCcard] {
            var cards: [MCcard] = []
            
            // First, extract just the MC question part (before any reasoning/analysis)
            var cleanResponse = response
            if let reasoningIndex = response.range(of: #"(?:Let me|I'LL|I'll|The user wants|I'll verify|This seems)"#, options: .regularExpression) {
                cleanResponse = String(response[..<reasoningIndex.lowerBound])
            }
            
            // Remove extra blank lines and normalize
            let normalized = cleanResponse
                .replacingOccurrences(of: "\n\n\n", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "\n\n", with: "\n", options: .regularExpression)
            
            // Split by "Q:" to find all questions
            let qParts = normalized.components(separatedBy: "Q:")
            
            for part in qParts {
                guard !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                
                var qText = part
                var options: [String] = []
                var correctLetter = ""
                
                // Split into lines
                let allLines = qText.components(separatedBy: "\n")
                
                // First line is the question (might have "Q:" prefix already removed)
                var question = ""
                for line in allLines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { continue }
                    
                    if trimmed.hasPrefix("A)") || trimmed.hasPrefix("A.") {
                        // Options start
                        let opt = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                        if !opt.isEmpty { options.append(opt) }
                    } else if trimmed.hasPrefix("B)") || trimmed.hasPrefix("B.") {
                        let opt = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                        if !opt.isEmpty { options.append(opt) }
                    } else if trimmed.hasPrefix("C)") || trimmed.hasPrefix("C.") {
                        let opt = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                        if !opt.isEmpty { options.append(opt) }
                    } else if trimmed.hasPrefix("D)") || trimmed.hasPrefix("D.") {
                        let opt = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                        if !opt.isEmpty { options.append(opt) }
                    } else if trimmed.uppercased().hasPrefix("CORRECT:") || trimmed.uppercased().hasPrefix("ANSWER:") {
                        let letter = trimmed.components(separatedBy: CharacterSet.alphanumerics.inverted).first(where: { ["A","B","C","D"].contains($0.uppercased()) })
                        if let l = letter {
                            correctLetter = l.uppercased()
                        }
                    } else if question.isEmpty && !trimmed.isEmpty && !trimmed.hasPrefix("Q") {
                        // This might be the question text (but no Q: prefix)
                        question = trimmed
                    } else if question.isEmpty && trimmed.hasPrefix("Q") {
                        // Skip lines starting with Q that aren't our question
                    }
                }
                
                // If we didn't find a question with the above, try harder
                if question.isEmpty {
                    // Take everything before first option as question
                    var qLines: [String] = []
                    for line in allLines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("A)") || trimmed.hasPrefix("A.") || 
                           trimmed.hasPrefix("B)") || trimmed.hasPrefix("B.") ||
                           trimmed.hasPrefix("C)") || trimmed.hasPrefix("C.") ||
                           trimmed.hasPrefix("D)") || trimmed.hasPrefix("D.") {
                            break
                        }
                        if !trimmed.isEmpty && !trimmed.uppercased().hasPrefix("CORRECT") {
                            qLines.append(trimmed)
                        }
                    }
                    question = qLines.joined(separator: " ")
                }
                
                guard !question.isEmpty, options.count >= 2 else { continue }
                
                // Ensure we have 4 options, pad if needed
                while options.count < 4 {
                    options.append("")
                }
                
                // Find correct index
                var correctIdx = 0
                if let letter = correctLetter.first, let idx = ["A","B","C","D"].firstIndex(of: String(letter).uppercased()) {
                    correctIdx = idx
                }
                
                cards.append(MCcard(
                    question: question,
                    options: Array(options.prefix(4)),
                    correctIndex: correctIdx
                ))
            }
            
            return cards
        }
        
        // MARK: - During Session
        @ViewBuilder
        func mcCardView(card: MCcard) -> some View {
            VStack(alignment: .leading, spacing: 16) {
                progressBarView()
                
                // MARK: - Question Card with improved styling
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        // Question Number Badge
                        Text("Q\(session.index + 1)")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.15))
                            )
                            .foregroundColor(.blue)
                        
                        // Adaptive Question Text
                        Text(card.question)
                            .font(.title3.weight(.semibold))
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .minimumScaleFactor(0.6)
                            .lineSpacing(4)
                        
                        if ttsEnabled {
                            Button(action: toggleTTS) {
                                ZStack {
                                    Circle()
                                        .fill(ttsIsPlaying ? Color.orange.opacity(0.15) : Color.blue.opacity(0.1))
                                        .frame(width: 40, height: 40)
                                    Image(
                                        systemName: ttsIsPlaying
                                        ? "pause.circle.fill" : "play.circle.fill"
                                    )
                                    .font(.title2)
                                    .foregroundStyle(ttsIsPlaying ? .orange : .blue)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor.secondarySystemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                )
                
                // MARK: - Options with improved styling
                ForEach(0..<min(4, card.options.count), id: \.self) { i in
                    let option = card.options[i]
                    let letter = ["A", "B", "C", "D"][i]
                    
                    Button {
                        guard !showResult else { return }
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        selectedIndex = i
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            // Letter Circle with improved styling
                            ZStack {
                                Circle()
                                    .fill(
                                        letterBackgroundColor(
                                            for: i,
                                            card: card
                                        )
                                    )
                                    .frame(width: 25, height: 25)
                                
                                if showResult && i == card.correctIndex {
                                    Circle()
                                        .stroke(Color.green, lineWidth: 2)
                                        .frame(width: 25, height: 25)
                                }
                            }
                            
                            // Option Text
                            Text(option)
                                .font(.callout.weight(.medium))
                                .minimumScaleFactor(0.55)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                                .allowsTightening(true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Spacer()
                            
                            // Check/X mark after answer
                            if showResult {
                                Image(
                                    systemName: i == card.correctIndex
                                    ? "checkmark.circle.fill" : "xmark.circle.fill"
                                )
                                .font(.title2)
                                .foregroundStyle(
                                    i == card.correctIndex ? .green : .red
                                )
                                .fontWeight(.bold)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(backgroundColor(for: i, card: card))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    borderColor(for: i, card: card),
                                    lineWidth: selectedIndex == i && !showResult ? 2 : (showResult && (i == card.correctIndex || i == selectedIndex) ? 2 : 0)
                                )
                        )
                        .shadow(color: selectedIndex == i && !showResult ? .blue.opacity(0.2) : .clear, radius: 4, x: 0, y: 2)
                    }
                    .disabled(showResult)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedIndex)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showResult)
                    
                }
                .animation(.easeInOut(duration: 0.4), value: showResult)
                .animation(.easeInOut(duration: 0.4), value: isCorrect)
                
                // MARK: - Submit Button
                if selectedIndex != nil && !showResult {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        Task {
                            await submitAnswer(
                                userChoiceIndex: selectedIndex!,
                                card: card
                            )
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Submit Answer")
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
                    .disabled(isGrading)
                }
                
                // MARK: - Result Section
                if showResult {
                    VStack(spacing: 12) {
//                        // Score Feedback
//                        HStack {
//                            Image(systemName: isCorrect ? "checkmark.seal.fill" : "xmark.seal.fill")
//                                .font(.title2)
//                                .foregroundColor(isCorrect ? .green : .red)
//                            
//                            Text(isCorrect ? "Correct!" : "Incorrect")
//                                .font(.headline)
//                                .foregroundColor(isCorrect ? .green : .red)
//                            
//                            Spacer()
//                            
//                            if card.timesSeen > 1 {
//                                Text("Attempt \(card.timesSeen)")
//                                    .font(.caption)
//                                    .padding(.horizontal, 8)
//                                    .padding(.vertical, 4)
//                                    .background(Color.secondary.opacity(0.15))
//                                    .cornerRadius(8)
//                            }
//                        }
//                        .padding()
//                        .background(
//                            RoundedRectangle(cornerRadius: 12)
//                                .fill(isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
//                        )
                        
                        Divider()
                            .padding(.vertical,1)
                        
                        HStack{
                            
                            HStack(alignment: .top) {
                                if let explanation = card.explanation, !explanation.isEmpty
                                {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Label("Explanation", systemImage: "lightbulb.fill")
                                            .font(.subheadline)
                                            .foregroundColor(.yellow)
                                        
                                        NativeMarkdownView2(
                                            markdown: explanation,
                                            ttsEnabled: .constant(
                                                MultiSettingsViewModel.shared.ttsEnabled
                                            )
                                        )
                                    }
                                } else if isExplainingCard(card.id) {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(1.1)
                                        Text("Generating explanation...")
                                            .font(.headline)
                                            .foregroundColor(.purple)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 12)
                                    .background(Color.purple.opacity(0.1))
                                    .cornerRadius(12)
                                } else {
                                    Button {
                                        let generator = UIImpactFeedbackGenerator(style: .light)
                                        generator.impactOccurred()
                                        Task { await explainSingleCard(card) }
                                    } label: {
                                        Label(
                                            "Explain Answer",
                                            systemImage: "brain.head.profile"
                                        )
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.purple.opacity(0.15))
                                        .foregroundColor(.purple)
                                        .cornerRadius(12)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Button {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                advanceToNextCard()
                            } label: {
                                VStack {
                                    Text(session.index < session.cards.count - 1 ? "Next" : "See Results")
                                    Image(systemName: session.index < session.cards.count - 1 ? "arrow.right.circle.fill" : "chart.bar.doc.horizontal.fill")
                                }
                                .font(.subheadline.weight(.semibold))
                                .padding(.vertical,6)
                                .padding(.horizontal,4)
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
                            .disabled(isGrading)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 50)
                            .onEnded { value in
                                let horizontalAmount = value.translation.width
                                if horizontalAmount < -50 && !showResult {
                                    advanceToNextCard()
                                } else if horizontalAmount > 50 && session.index > 0 && !showResult {
                                    goToPreviousCard()
                                }
                            }
                    )
                }
            }.padding()
        }
        
        // MARK: - Helper Color Functions (keep your original ones)
        func letterBackgroundColor(for index: Int, card: MCcard) -> Color {
            guard showResult else { return .gray }
            return index == card.correctIndex
            ? .green : (index == selectedIndex ? .red : .gray)
        }
        
        func backgroundColor(for index: Int, card: MCcard) -> Color {
            if showResult {
                if index == card.correctIndex {
                    return Color.green.opacity(0.15)
                }
                if index == selectedIndex && !isCorrect {
                    return Color.red.opacity(0.15)
                }
                return Color(UIColor.systemBackground)
            }
            
            if selectedIndex == nil {
                return .gray.opacity(0.08)
            } else {
                // User has selected an option
                return selectedIndex == index
                ? Color.blue.opacity(0.15) : Color(UIColor.systemBackground)
            }
        }
        
        func borderColor(for index: Int, card: MCcard) -> Color {
            if showResult {
                if index == card.correctIndex {
                    return .green
                }
                if index == selectedIndex && !isCorrect {
                    return .red
                }
                return .clear
            }
            
            if selectedIndex == nil {
                return .gray.opacity(0.5)
            } else {
                return selectedIndex == index ? .blue : .clear
            }
        }
        
        @ViewBuilder
        func resultsViewAll() -> some View {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with score
                    VStack(spacing: 16) {
                        let accuracy = session.totalAttempts > 0 ?
                        Double(session.totalMarks) / Double(session.totalAttempts * 10) * 100 : 0
                        
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: accuracy >= 70 ? [Color.green.opacity(0.2), Color.green.opacity(0.1)] : [Color.orange.opacity(0.2), Color.orange.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 120, height: 120)
                            
                            VStack(spacing: 4) {
                                Text("\(Int(accuracy))%")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(accuracy >= 70 ? .green : .orange)
                                Text("Accuracy")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("Study Complete!")
                            .font(.title2.bold())
                        
                        HStack(spacing: 20) {
                            VStack {
                                Text("\(session.totalMarks)")
                                    .font(.headline.bold())
                                    .foregroundColor(.green)
                                Text("Score")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 1, height: 40)
                            
                            VStack {
                                Text("\(session.totalAttempts)")
                                    .font(.headline.bold())
                                Text("Questions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 1, height: 40)
                            
                            VStack {
                                Text("\(session.cards.filter { $0.lastUserIndex == $0.correctIndex }.count)")
                                    .font(.headline.bold())
                                    .foregroundColor(.blue)
                                Text("Correct")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                    }
                    .padding(.top, 20)
                    
                    // Cards breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Question Review")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(session.cards) { card in
                            let isCorrect = card.lastUserIndex == card.correctIndex
                            
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(isCorrect ? .green : .red)
                                    
                                    Text(card.question)
                                        .font(.headline)
                                        .lineLimit(2)
                                    
                                    Spacer()
                                }
                                
                                HStack {
                                    Label("Correct: \(["A","B","C","D"][card.correctIndex])", systemImage: "checkmark")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    
                                    Spacer()
                                    
                                    if let chosen = card.lastUserIndex {
                                        let letter = ["A", "B", "C", "D"][chosen]
                                        Label("Your: \(letter)", systemImage: isCorrect ? "checkmark" : "xmark")
                                            .font(.caption)
                                            .foregroundColor(isCorrect ? .green : .red)
                                    }
                                }
                                
                                if let exp = card.explanation, !exp.isEmpty {
                                    Divider().padding(.vertical, 4)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label("Explanation", systemImage: "lightbulb.fill")
                                            .font(.caption.bold())
                                            .foregroundColor(.yellow)
                                        
                                        NativeMarkdownView2(
                                            markdown: exp,
                                            ttsEnabled: .constant(
                                                MultiSettingsViewModel.shared.ttsEnabled
                                            )
                                        )
                                        .font(.caption)
                                    }
                                } else if !isExplainingCard(card.id) && !session.explanationsReady {
                                    Button {
                                        Task { await explainSingleCard(card) }
                                    } label: {
                                        Label("Explain", systemImage: "brain.head.profile")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(UIColor.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isCorrect ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                HStack(spacing: 12) {
                    Button {
                        let csv = mcCardsToCSV(session.cards)
                        let url = FileExporter.tempFile(
                            named: "mcmcs.csv",
                            content: csv
                        )
                        ShareSheet.present(items: [url])
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    if !session.explanationsReady {
                        Button {
                            batchExplainAll()
                        } label: {
                            Label(
                                "All Explanations",
                                systemImage: "brain.head.profile"
                            )
                            .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(isBatchExplaining)
                    }
                    
                }.padding(.bottom, 6)
            }.padding(.horizontal)
            
        }
        
        func splitIntoOptimalChunks(text: String) -> [String] {
            let clean = cleanMarkdownForTTS(text)
            let sentences = linguisticSentenceSplit(clean)
            let maxLen = 220
            var finalChunks: [String] = []
            
            for s in sentences {
                if s.count <= maxLen {
                    finalChunks.append(s)
                } else {
                    finalChunks.append(
                        contentsOf: safeSplitLongSentence(
                            sentence: s,
                            maxLength: maxLen
                        )
                    )
                }
            }
            
            return
            finalChunks
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        
        // MARK: - Logic
        func gradeOnly(userChoiceIndex: Int, card: MCcard) async {
            let isCorrectAnswer = userChoiceIndex == card.correctIndex
            let mark = isCorrectAnswer ? 10 : 0
            
            await MainActor.run {
                // Critical: Update session-level stats
                session.totalAttempts += 1
                session.totalMarks += mark
                
                // Also update per-card mark (if you use it)
                session.perCardMarks[card.id] = mark
                
                // Update feedback
                gradingFeedback =
                isCorrectAnswer
                ? "Correct answer!"
                : "Incorrect. The correct answer is \(card.correctAnswer)."
            }
        }
        
        func batchExplainAll() {
            guard !session.explanationsReady, !isBatchExplaining else { return }
            isBatchExplaining = true
            
            Task {
                defer {
                    Task { @MainActor in
                        isBatchExplaining = false
                    }
                }
                
                let apiKey = ProcessInfo.processInfo.environment["MINIMAX_API_KEY"]
                ?? (Bundle.main.object(forInfoDictionaryKey: "MiniMaxAPIKey") as? String)
                ?? ""
                
                guard !apiKey.isEmpty else {
                    await MainActor.run {
                        session.explanationsReady = true
                    }
                    return
                }
                
                do {
                    try await withCoinProtected(actionDescription: "Batch explanations") {
                        var updated = session.cards
                        
                        for i in updated.indices {
                            if !(updated[i].explanation?.isEmpty ?? true) { continue }
                            
                            let userIdx = updated[i].lastUserIndex ?? updated[i].correctIndex
                            let userAnswer = updated[i].options[userIdx]
                            
                            do {
                                let exp = try await GradingService.explain(
                                    userAnswer: userAnswer,
                                    card: updated[i],
                                    apiKey: apiKey
                                )
                                updated[i].explanation = exp
                            } catch let explainError {
                                print("Failed to explain card \(i): \(explainError)")
                                // Continue — don't fail whole batch for one card
                            }
                        }
                        
                        await MainActor.run {
                            session.cards = updated
                            session.explanationsReady = true
                            saveCardsToStore()
                        }
                        
                        return ()
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = loc(
                            "Batch explanation failed. Coin refunded.",
                            "批量生成解釋失敗，已退還硬幣。"
                        )
                    }
                }
            }
        }
        
        func rate(_ r: MCSession.Rating) {
            withAnimation(.easeInOut(duration: 0.5)) {
                session.rate(r)
            }
            resetState()
            saveSessionState()
            saveCardsToStore()
        }
        
        func resetState() {
            selectedIndex = nil
            showResult = false
            isCorrect = false
            gradingFeedback = ""
            isGrading = false
        }
        func mcCardsToCSV(_ cards: [MCcard]) -> String {
            var out = "Question,A,B,C,D,Correct\n"
            for c in cards {
                let q = c.question.replacingOccurrences(of: ",", with: " ")
                let opts = c.options.map {
                    $0.replacingOccurrences(of: ",", with: " ")
                }
                let correctLetter = ["A", "B", "C", "D"][c.correctIndex]
                out +=
                "\(q),\(opts[0]),\(opts[1]),\(opts[2]),\(opts[3]),\(correctLetter)\n"
            }
            return out
        }
        
        func saveSessionState() {
            guard let url = docURL else { return }
            let base = "MCSession_\(url.absoluteString)"
            
            UserDefaults.standard.set(session.index, forKey: "\(base)_index")
            UserDefaults.standard.set(session.done, forKey: "\(base)_done")
            UserDefaults.standard.set(
                session.totalAttempts,
                forKey: "\(base)_attempts"
            )
            UserDefaults.standard.set(session.totalMarks, forKey: "\(base)_marks")
        }
        
        func restoreSessionState() {
            guard let url = docURL else { return }
            let base = "MCSession_\(url.absoluteString)"
            
            let savedIndex = UserDefaults.standard.integer(forKey: "\(base)_index")
            let savedDone = UserDefaults.standard.bool(forKey: "\(base)_done")
            let savedAttempts = UserDefaults.standard.integer(
                forKey: "\(base)_attempts"
            )
            let savedMarks = UserDefaults.standard.integer(forKey: "\(base)_marks")
            
            if savedIndex >= 0 && savedIndex < session.cards.count {
                session.index = savedIndex
            }
            session.done = savedDone
            session.totalAttempts = savedAttempts
            session.totalMarks = savedMarks
        }
        
        func clearAllSavedState() {
            guard let url = docURL else { return }
            let base = "MCSession_\(url.absoluteString)"
            
            let keys = ["_index", "_done", "_attempts", "_marks"]
            for suffix in keys {
                UserDefaults.standard.removeObject(forKey: base + suffix)
            }
        }
        
        @MainActor
        func clearCurrentMCs() {
            if let url = docURL {
                try? mcStore.delete(for: url)
                clearAllSavedState()
            }
            
            session.cards = []
            session.index = 0
            session.done = false
            session.totalAttempts = 0
            session.totalMarks = 0
            session.perCardMarks.removeAll()
            
            selectedIndex = nil
            showResult = false
            isCorrect = false
            gradingFeedback = ""
            
            explainingCardIDs.removeAll()
        }
        
        func clearSavedIndex() {
            guard let url = docURL else { return }
            let keyIndex = "MCIndex_\(url.absoluteString)"
            let keyDone = "MCSessionDone_\(url.absoluteString)"
            UserDefaults.standard.removeObject(forKey: keyIndex)
            UserDefaults.standard.removeObject(forKey: keyDone)
        }
        
        func saveCardsToStore() {
            guard let url = docURL else { return }
            try? mcStore.save(session.cards, for: url)
        }
        
        func toggleTTS() {
            if ttsIsPlaying {
                stopTTS()
            } else {
                guard let card = session.current else { return }
                
                // Always read the QUESTION when the play button (next to question) is tapped
                // Only read explanation if user explicitly wants it (future enhancement)
                let textToRead = card.question
                
                prepareTTSChunks(for: textToRead)
                
                if !ttsChunks.isEmpty {
                    ttsIsPlaying = true
                    ttsCurrentChunkIndex = 0
                    playCurrentTTSChunk()
                }
            }
        }
        
        func prepareTTSChunks(for text: String) {
            // First: detect if we should force built-in TTS (device or language)
            detectTTSMode(for: text)
            
            let cleanText = cleanMarkdownForTTS(text)
            
            var chunks: [String] = []
            
            if ttsUseBuiltInTTS {
                // Chinese-friendly splitting: by punctuation
                let punctuation = CharacterSet(charactersIn: "。！？；：，…")
                let parts = cleanText.components(separatedBy: punctuation)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count > 3 }
                
                for part in parts {
                    if part.count <= 220 {
                        chunks.append(part)
                    } else {
                        chunks.append(
                            contentsOf: safeSplitLongSentence(
                                sentence: part,
                                maxLength: 220
                            )
                        )
                    }
                }
            } else {
                // English: linguistic sentence splitting
                let sentences = linguisticSentenceSplit(cleanText)
                for sentence in sentences {
                    if sentence.count <= 220 {
                        chunks.append(sentence)
                    } else {
                        chunks.append(
                            contentsOf: safeSplitLongSentence(
                                sentence: sentence,
                                maxLength: 220
                            )
                        )
                    }
                }
            }
            
            // Fallback
            if chunks.isEmpty {
                chunks = [cleanText]
            }
            
            ttsChunks = chunks.filter { !$0.isEmpty }
            print(
                "📚 TTS prepared \(ttsChunks.count) chunks for: \"\(text.prefix(50))...\""
            )
        }
        
        func detectTTSMode(for text: String) {
            // Force built-in on unsupported devices
            if !TestAppModel.isSupportedDevice() {
                ttsUseBuiltInTTS = true
                print("🔧 TTS: Using built-in (unsupported device)")
                return
            }
            
            let clean = cleanMarkdownForTTS(text)
            
            if hasSignificantChineseContent(clean) {
                ttsUseBuiltInTTS = true
                print("🇨🇳 TTS: Using built-in (Chinese content)")
            } else if isPrimarilyEnglish(clean) {
                ttsUseBuiltInTTS = false
                print("🇺🇸 TTS: Using Kokoro (English content)")
            } else {
                ttsUseBuiltInTTS = true
                print("🔤 TTS: Using built-in (fallback)")
            }
        }
        
        func speakWithBuiltInTTS(_ text: String) {
            let (isChinese, _) = detectContentLanguage(text)
            let locale = isChinese ? "zh-HK" : "en-US"
            
            print("🗣️ Built-in TTS (\(locale)): \"\(text.prefix(40))...\"")
            
            ttsChineseDelegate = ChineseTTSDelegate { [self] in
                DispatchQueue.main.async {
                    guard ttsIsPlaying else { return }
                    if ttsCurrentChunkIndex < ttsChunks.count - 1 {
                        ttsCurrentChunkIndex += 1
                        playCurrentTTSChunk()
                    } else {
                        stopTTS()
                    }
                }
            }
            ttsChineseSynthesizer.delegate = ttsChineseDelegate
            
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: locale)
            utterance.rate = isChinese ? 0.50 : 0.45
            utterance.pitchMultiplier = 1.0
            
            // Ensure audio session is active
            do {
                try AVAudioSession.sharedInstance().setCategory(
                    .playback,
                    mode: .default,
                    options: []
                )
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("❌ AVAudioSession error: $error)")
            }
            
            ttsChineseSynthesizer.speak(utterance)
        }
        func startTTSMonitoring() {
            ttsChunkTimer?.invalidate()
            ttsChunkTimer = Timer.scheduledTimer(
                withTimeInterval: 0.2,
                repeats: true
            ) { _ in
                // Optional: track spoken text if needed for highlighting
            }
        }
        
        func playTTSCurrentChunk() {
            guard ttsIsPlaying, ttsCurrentChunkIndex < ttsChunks.count else {
                stopTTS()
                return
            }
            
            let text = ttsChunks[ttsCurrentChunkIndex]
            
            if ttsUseBuiltInTTS {
                playChineseTTS(text)
            } else {
                model.playerNode?.stop()
                model.playerNode?.reset()
                model.timer?.invalidate()
                model.say(text: text) {
                    DispatchQueue.main.async {
                        if self.ttsIsPlaying {
                            if self.ttsCurrentChunkIndex < self.ttsChunks.count - 1
                            {
                                self.ttsCurrentChunkIndex += 1
                                self.playTTSCurrentChunk()
                            } else {
                                self.stopTTS()
                            }
                        }
                    }
                    self.startTTSChunkMonitoring()
                }
            }
        }
        
        func detectContentLanguage(_ text: String) -> (
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
        
        func detectTTSLanguagefor(_ text: String) {
            // CRITICAL: Force built-in TTS on unsupported devices
            if !TestAppModel.isSupportedDevice() {
                ttsUseBuiltInTTS = true
                print("🔧 MCcard TTS: Using Built-in TTS (Unsupported device)")
                return
            }
            
            let cleanText = cleanMarkdownForTTS(text)
            
            if hasSignificantChineseContent(cleanText) {
                ttsUseBuiltInTTS = true
                print("🇨🇳 MCcard TTS: Built-in TTS (Chinese detected)")
            } else if isPrimarilyEnglish(cleanText) {
                ttsUseBuiltInTTS = false
                print("🇺🇸 MCcard TTS: Kokoro TTS (English detected)")
            } else {
                ttsUseBuiltInTTS = true
                print("🔤 MCcard TTS: Built-in TTS (Mixed fallback)")
            }
        }
        
        // MARK: - TTS Helper Functions (copy from NativeMarkdownView2)
        func hasSignificantChineseContent(_ text: String) -> Bool {
            let chineseCount = text.unicodeScalars.filter { scalar in
                (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
            }.count
            let chineseRatio = Double(chineseCount) / Double(text.count)
            return chineseRatio > 0.3
        }
        
        func isPrimarilyEnglish(_ text: String) -> Bool {
            let englishChars = CharacterSet.letters
            let englishCount = text.unicodeScalars.filter {
                englishChars.contains($0)
            }.count
            let totalCount = text.unicodeScalars.count
            return totalCount > 0
            ? Double(englishCount) / Double(totalCount) > 0.6 : true
        }
        
        func cleanMarkdownForTTS(_ text: String) -> String {
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
        
        func linguisticSentenceSplit(_ text: String) -> [String] {
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
        
        func safeSplitLongSentence(sentence: String, maxLength: Int)
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
    
    class ChineseTTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
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
}
