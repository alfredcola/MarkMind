//
//  WidgetFlashcardsManagementView.swift
//  Markdown Opener
//
//  Created by alfred chen on 8/3/2026.
//
import Combine
import SwiftUI
import WidgetKit

struct WidgetFlashcardsManagementView: View {
    @ObservedObject private var vm = MultiSettingsViewModel.shared
    @State private var items: [MultiSettingsViewModel.WidgetFlashcardItem] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading widget flashcards...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)

                    Text("No Widget Flashcards")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(
                        "When you add flashcards to a widget,\nthey will appear here for management."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List {
                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayName)
                                    .font(.body)
                                    .fontWeight(.medium)

                                Text(
                                    "\(item.cardCount) card\(item.cardCount == 1 ? "" : "s")"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                withAnimation {
                                    vm.deleteWidgetFlashcard(at: item.fileURL)
                                    items.removeAll {
                                        $0.fileURL == item.fileURL
                                    }
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Manage Widget Flashcards")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadItems()
        }
        .refreshable {
            await loadItems()
        }
    }

    private func loadItems() async {
        await MainActor.run {
            isLoading = true
        }

        let loaded = vm.loadWidgetFlashcardItems()

        await MainActor.run {
            items = loaded
            isLoading = false
        }
    }
}
