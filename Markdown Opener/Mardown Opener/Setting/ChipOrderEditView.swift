//
//  ChipOrderEditView.swift
//  Markdown Opener
//
//  Created by alfred chen on 8/3/2026.
//

import Combine
import SwiftUI
import WidgetKit

// MARK: - Chip Order Edit View
struct ChipOrderEditView: View {
    @ObservedObject private var vm = MultiSettingsViewModel.shared

    var body: some View {
        Form {
            Section("Drag to reorder") {
                ForEach(vm.chipGroupsOrder) { group in
                    HStack {
                        Image(systemName: group.systemImage)
                            .foregroundColor(group.color)
                            .frame(width: 30)

                        Text(group.rawValue)

                        Spacer()

                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .onMove(perform: move)
            }

            Section {
                Button("Reset to Default") {
                    vm.chipGroupsOrder = [
                        .starred, .tags, .markdown, .text, .pdf, .docx, .pptx,
                    ]
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    func move(from source: IndexSet, destination: Int) {
        vm.chipGroupsOrder.move(fromOffsets: source, toOffset: destination)
    }
}


