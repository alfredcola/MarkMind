//
//  FlashcardWidget.swift - Enhanced & Polished UI (Fixed: Independent progress per widget instance)
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Shared UserDefaults for current index per document
private let sharedDefaults = UserDefaults(
    suiteName: "group.com.alfredchen.MarkdownOpener"
)

// MARK: - Provider
struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            cards: [.sample],
            currentIndex: 0,
            filename: "sample.json"
        )
    }

    func snapshot(for configuration: SelectDocumentIntent, in context: Context)
        async -> SimpleEntry
    {
        await loadEntry(from: configuration)
    }

    func timeline(for configuration: SelectDocumentIntent, in context: Context)
        async -> Timeline<SimpleEntry>
    {
        let entry = await loadEntry(from: configuration)
        return Timeline(entries: [entry], policy: .atEnd)
    }

    private func loadEntry(from configuration: SelectDocumentIntent) async -> SimpleEntry {
        guard let entity = configuration.document else {
            return SimpleEntry(
                date: Date(),
                cards: [],
                currentIndex: 0,
                filename: nil
            )
        }

        let filename = entity.id  // e.g., "MyNotes.md.json"
        let cards = loadFlashcards(for: filename)

        guard !cards.isEmpty else {
            return SimpleEntry(
                date: Date(),
                cards: [],
                currentIndex: 0,
                filename: filename
            )
        }

        let shuffled = cards.shuffled()

        // Load saved index for this specific document
        let indexKey = "widget_currentIndex_\(filename)"
        var savedIndex = sharedDefaults?.integer(forKey: indexKey) ?? 0
        savedIndex = max(0, min(savedIndex, shuffled.count - 1))  // Clamp

        return SimpleEntry(
            date: Date(),
            cards: shuffled,
            currentIndex: savedIndex,
            filename: filename
        )
    }

    private func loadFlashcards(for filename: String) -> [Flashcard] {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    "group.com.alfredchen.MarkdownOpener"
            )
        else { return [] }

        let fileURL = containerURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: fileURL),
              let cards = try? JSONDecoder().decode([Flashcard].self, from: data),
              !cards.isEmpty
        else {
            return []
        }
        return cards
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let cards: [Flashcard]
    let currentIndex: Int
    let filename: String?  // Used for display / debugging
}

// MARK: - Navigation Intent (Fixed: Independent per widget)
struct NextCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Card"
    static var description = IntentDescription("Show the next flashcard")

    @Parameter(title: "Selected Document")
    var document: DocumentEntity?

    static var openAppWhenRun: Bool = false  // Important: prevent app launch on tap

    func perform() async throws -> some IntentResult {
        guard let filename = document?.id else {
            return .result()
        }

        // Prevent double execution using timestamp debounce
        let lastExecutionKey = "widget_lastNextIntent_\(filename)"
        let now = Date().timeIntervalSince1970

        let lastTime = sharedDefaults?.double(forKey: lastExecutionKey) ?? 0
        let timeSinceLast = now - lastTime

        // If last tap was less than 1 second ago → ignore (debounce)
        if timeSinceLast < 1.0 {
            return .result()
        }

        // Record this execution time
        sharedDefaults?.set(now, forKey: lastExecutionKey)

        // Now safely advance
        updateCurrentIndex(for: filename, by: +1, shouldLoop: true)

        // Reload widget timeline
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }
}

private func updateCurrentIndex(for filename: String, by delta: Int, shouldLoop: Bool = false) {
    guard let cards = loadFlashcardsFromFilename(filename), !cards.isEmpty else {
        return
    }

    let key = "widget_currentIndex_\(filename)"
    var current = sharedDefaults?.integer(forKey: key) ?? 0

    var newIndex = current + delta

    if shouldLoop && delta > 0 && current == cards.count - 1 {
        newIndex = 0
    } else {
        newIndex = max(0, min(newIndex, cards.count - 1))
    }

    // Only write if changed (minor optimization)
    if newIndex != current {
        sharedDefaults?.set(newIndex, forKey: key)
    }
}

private func loadFlashcardsFromFilename(_ filename: String) -> [Flashcard]? {
    guard
        let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier:
                "group.com.alfredchen.MarkdownOpener"
        )
    else { return nil }

    let fileURL = containerURL.appendingPathComponent(filename)
    guard let data = try? Data(contentsOf: fileURL),
          let cards = try? JSONDecoder().decode([Flashcard].self, from: data),
          !cards.isEmpty
    else {
        return nil
    }
    return cards
}

// MARK: - Main View
struct FlashcardWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    private var card: Flashcard? {
        entry.cards.isEmpty ? nil : entry.cards[entry.currentIndex]
    }
    private var progress: CGFloat {
        entry.cards.isEmpty
            ? 0 : CGFloat(entry.currentIndex + 1) / CGFloat(entry.cards.count)
    }

    var body: some View {
        Group {
            if let card = card {
                switch family {
                case .systemSmall:
                    SmallView(card: card)
                case .systemMedium:
                    MediumView(
                        card: card,
                        progress: progress,
                        current: entry.currentIndex + 1,
                        total: entry.cards.count
                    )
                case .systemLarge:
                    LargeView(
                        card: card,
                        progress: progress,
                        current: entry.currentIndex + 1,
                        total: entry.cards.count
                    )
                default:
                    SmallView(card: card)
                }
            } else {
                EmptyView()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Small Widget
struct SmallView: View {
    let card: Flashcard

    var body: some View {
        Button(intent: NextCardIntent()) {
            VStack(alignment: .leading, spacing: 5) {
                Text(card.question)
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .minimumScaleFactor(0.5)
                    .lineLimit(nil)

                Text(card.options[card.correctIndex])
                    .font(.title3)
                    .bold()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .minimumScaleFactor(0.5)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .padding(2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Medium Widget
struct MediumView: View {
    let card: Flashcard
    let progress: CGFloat
    let current: Int
    let total: Int

    var body: some View {
        Button(intent: NextCardIntent()) {
            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.question)
                        .font(.title2)
                        .bold()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .minimumScaleFactor(0.5)
                        .lineLimit(nil)

                    Text(card.options[card.correctIndex])
                        .font(.title3)
                        .bold()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .minimumScaleFactor(0.5)
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity,maxHeight: .infinity, alignment: .leading)
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(2)
        }
        .buttonStyle(.plain)
    }
}

struct LargeView: View {
    let card: Flashcard
    let progress: CGFloat
    let current: Int
    let total: Int

    var body: some View {
        VStack(spacing: 15) {
            // Question
            Text(card.question)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .minimumScaleFactor(0.5)
                .lineLimit(nil)


            HStack(spacing:0){
                Text(card.options[card.correctIndex])
                    .font(.title3)
                    .bold()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .minimumScaleFactor(0.5)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity,maxHeight: .infinity, alignment: .leading)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                
                Spacer()
                
                Button(intent: NextCardIntent()) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .padding(.vertical,50)
                        .foregroundColor(.primary)
                        .padding(2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

        }
        .padding(2)
    }
}

// MARK: - Empty State
struct EmptyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 35))
                .foregroundStyle(.secondary)

            Text("No Flashcards Yet")
                .font(.title3)
                .fontWeight(.semibold)
                .minimumScaleFactor(0.5)

            Text("Open the app, generate flashcards,\nand tap “Add to Widget”")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .minimumScaleFactor(0.5)

        }
    }
}

// MARK: - Widget Configuration
struct FlashcardWidget: Widget {
    static let kind: String = "FlashcardWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SelectDocumentIntent.self,
            provider: Provider()
        ) { entry in
            FlashcardWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Flashcard Study")
        .description("Review your flashcards with beautiful navigation")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Sample Flashcard
extension Flashcard {
    static var sample: Flashcard {
        Flashcard(
            question: "What is the powerhouse of the cell?",
            options: ["Mitochondria", "Nucleus", "Ribosome", "Golgi"],
            correctIndex: 0
        )
    }
}
