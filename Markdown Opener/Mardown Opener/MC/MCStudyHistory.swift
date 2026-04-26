//
//  MCStudyHistory.swift
//  Markdown Opener
//
//  Created by alfred chen on 22/12/2025.
//
import SwiftUI
import Combine

@MainActor
class MCStudyHistory: ObservableObject {
    static let shared = MCStudyHistory()
    
    @Published var results: [MCStudyResult] = [] {
        didSet {
            if results.count > Constants.Limits.maxMCStudyHistoryResults {
                results = Array(results.prefix(Constants.Limits.maxMCStudyHistoryResults))
            }
            save()
        }
    }
    
    private init() {
        load()
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "MCStudyHistory") else { return }
        
        // Try new format first
        if let decoded = try? JSONDecoder().decode([MCStudyResult].self, from: data) {
            results = decoded.sorted { $1.date > $0.date }
            return
        }
        
        // If failed, clear old corrupted data
        UserDefaults.standard.removeObject(forKey: "MCStudyHistory")
        results = []
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(results) {
            UserDefaults.standard.set(encoded, forKey: "MCStudyHistory")
        }
    }
    
    func delete(_ result: MCStudyResult) {
        results.removeAll { $0.id == result.id }
    }
    
    func deleteAll() {
        results.removeAll()
    }
}

struct MCReviewHistoryView: View {
    @ObservedObject private var history = MCStudyHistory.shared
    
    var currentDocURL: URL?  // nil means "show all documents"
    
    // MARK: - Filters & Sorting State
    @State private var sortOption: SortOption = .dateDescending
    @State private var minScoreFilter: Double = 0  // 0% to 100%
    @State private var showFilters = false
    
    enum SortOption: String, CaseIterable, Identifiable {
        case dateDescending = "Newest First"
        case dateAscending = "Oldest First"
        case scoreDescending = "Highest Score"
        case scoreAscending = "Lowest Score"
        case documentName = "Document Name"
        
        var id: Self { self }
    }
    
    // MARK: - Computed Properties
    
    private var filteredAndSortedResults: [MCStudyResult] {
        var results = history.results
        
        // Filter by document if needed
        if let url = currentDocURL {
            let currentName = url.lastPathComponent
            results = results.filter { $0.documentName == currentName }
        }
        
        // Apply score filter
        results = results.filter { $0.scorePercentage >= minScoreFilter }
        
        // Sort
        switch sortOption {
        case .dateDescending:
            results = results.sorted { $0.date > $1.date }
        case .dateAscending:
            results = results.sorted { $0.date < $1.date }
        case .scoreDescending:
            results = results.sorted { $0.scorePercentage > $1.scorePercentage }
        case .scoreAscending:
            results = results.sorted { $0.scorePercentage < $1.scorePercentage }
        case .documentName:
            results = results.sorted { $0.documentName < $1.documentName }
        }
        
        return results
    }
    
    private var displayTitle: String {
        currentDocURL == nil ? "All Study History" : "Study History"
    }
    
    private var emptyMessageDocumentName: String {
        currentDocURL?.lastPathComponent ?? "any document"
    }
    
    private var hasActiveFilters: Bool {
        minScoreFilter > 0
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            List {
                if filteredAndSortedResults.isEmpty {
                    ContentUnavailableView(
                        "No Study History",
                        systemImage: "tray",
                        description: Text(buildEmptyMessage())
                    )
                } else {
                    ForEach(filteredAndSortedResults) { result in
                        NavigationLink(destination: MCResultDetailView(result: result)) {
                            HistoryRowView(result: result, showDocumentName: currentDocURL == nil)
                        }
                    }
                    .onDelete(perform: deleteResults)
                }
            }
            .navigationTitle(displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !filteredAndSortedResults.isEmpty {
                        EditButton()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Sort Section
                        Section("Sort By") {
                            Picker("Sort", selection: $sortOption) {
                                ForEach(SortOption.allCases) { option in
                                    Label(option.rawValue, systemImage: iconForSort(option))
                                        .tag(option)
                                }
                            }
                            .pickerStyle(.inline)
                        }
                        
                        // Filter Section
                        Section("Filter") {
                            Button(showFilters ? "Hide Filters" : "Show Filters") {
                                withAnimation {
                                    showFilters.toggle()
                                }
                            }
                            
                            if showFilters {
                                VStack(alignment: .leading) {
                                    Text("Minimum Score: \(Int(minScoreFilter))%")
                                    Slider(value: $minScoreFilter, in: 0...100, step: 10)
                                        .padding(.top, 4)
                                }
                                .padding(.vertical, 4)
                                
                                if hasActiveFilters {
                                    Button("Clear Filters") {
                                        minScoreFilter = 0
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Filter & Sort", systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter and sort options")
                }
            }
        }
    }
    
    // MARK: - Helper Views & Functions
    
    private func buildEmptyMessage() -> String {
        var message = "Complete some MC sessions for \n\(emptyMessageDocumentName)"
        if minScoreFilter > 0 {
            message += "\nwith at least \(Int(minScoreFilter))% score"
        }
        message += "\nto see results here."
        return message
    }
    
    private func iconForSort(_ option: SortOption) -> String {
        switch option {
        case .dateDescending, .dateAscending: return "calendar"
        case .scoreDescending, .scoreAscending: return "percent"
        case .documentName: return "doc.text"
        }
    }
    
    private func deleteResults(at offsets: IndexSet) {
        let resultsToDelete = offsets.map { filteredAndSortedResults[$0] }
        for result in resultsToDelete {
            history.delete(result)
        }
    }
}

// MARK: - Reusable Row View (cleaner UI)

struct HistoryRowView: View {
    let result: MCStudyResult
    let showDocumentName: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showDocumentName {
                Text(result.documentName)
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(Int(result.scorePercentage))%")
                        .font(.title3.bold())
                        .foregroundStyle(result.scorePercentage >= 80 ? .green : .orange)
                    
                    Text("• \(result.totalMarks)/\(result.totalAttempts * 10)")
                        .foregroundStyle(.secondary)
                }
                
                Text(result.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(result.date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MCResultDetailView: View {
    let result: MCStudyResult
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(result.documentName)
                        .font(.title2.bold())
                    
                    Text("Completed \(result.date, style: .relative)")
                        .foregroundStyle(.secondary)
                    
                    Text(result.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("Score: \(Int(result.scorePercentage))% (\(result.totalMarks)/\(result.totalAttempts * 10))")
                        .font(.title3)
                        .foregroundStyle(result.scorePercentage >= 80 ? .green : .orange)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
                
                ForEach(result.cards.indices, id: \.self) { i in
                    let card = result.cards[i]
                    VStack(alignment: .leading, spacing: 10) {
                        Text(card.question)
                            .font(.headline)
                        
                        ForEach(0..<4) { idx in
                            HStack {
                                Text(["A", "B", "C", "D"][idx])
                                    .font(.headline)
                                    .frame(width: 30)
                                    .foregroundColor(.white)
                                    .background(Circle().fill(backgroundColor(for: idx, card: card)))
                                
                                Text(card.options[idx])
                                    .foregroundColor(textColor(for: idx, card: card))
                                
                                Spacer()
                                
                                if idx == card.correctIndex {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                                if idx == card.userIndex && card.userIndex != card.correctIndex {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        if let exp = card.explanation, !exp.isEmpty {
                            Divider()
                            NativeMarkdownView2(markdown: exp,ttsEnabled: .constant(MultiSettingsViewModel.shared.ttsEnabled))
                                .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle("Session Review")
    }
    
    private func backgroundColor(for index: Int, card: MCcardResult) -> Color {
        if index == card.correctIndex { return .green }
        if index == card.userIndex && !card.isCorrect { return .red }
        return .gray
    }
    
    private func textColor(for index: Int, card: MCcardResult) -> Color? {
        if index == card.correctIndex { return .green }
        if index == card.userIndex && !card.isCorrect { return .red }
        return nil
    }
}
