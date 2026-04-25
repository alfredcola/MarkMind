//
//  TagEditRow.swift
//  Markdown Opener
//
//  Created by alfred chen on 8/3/2026.
//

import PDFKit
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

struct TagEditRow: View {
    let tag: Tag
    @EnvironmentObject var tagsManager: TagsManager

    @State private var editName: String = ""
    @State private var editColor: Color = .blue
    @State private var isDuplicate: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            TextField("Tag name", text: $editName)
                .textFieldStyle(.roundedBorder)
                .onAppear {
                    editName = tag.name
                }
                .onChange(of: editName) {
                    let trimmed = editName.trimmed
                    if trimmed != editName {
                        editName = trimmed
                    }

                    isDuplicate = tagsManager.allTags.contains {
                        $0.id != tag.id
                            && $0.name.lowercased() == trimmed.lowercased()
                    }
                }
                .onSubmit {
                    commitNameChange()
                }

            if isDuplicate {
                Image(systemName: "exclamation.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }

            ColorPicker("", selection: $editColor)
                .labelsHidden()
                .scaleEffect(1.3)
                .onChange(of: editColor) {
                    tagsManager.updateTag(tag, color: editColor)
                }
                .onAppear {
                    editColor = tag.color.color
                }

            Button(role: .destructive) {
                tagsManager.deleteTag(tag)
            } label: {
                Image(systemName: "trash.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func commitNameChange() {
        let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            editName = tag.name
            return
        }

        if tagsManager.allTags.contains(where: {
            $0.id != tag.id && $0.name.lowercased() == trimmed.lowercased()
        }) {
            editName = tag.name
            return
        }

        tagsManager.renameTag(tag, to: trimmed)
    }
}
