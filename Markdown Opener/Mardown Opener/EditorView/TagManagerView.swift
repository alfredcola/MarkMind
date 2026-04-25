//
//  TagManagerView.swift
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

struct TagManagerView: View {
    @EnvironmentObject var tagsManager: TagsManager
    @Environment(\.dismiss) private var dismiss
    @State private var newTagName = ""
    @State private var newTagColor: Color = .blue
    @State private var errorMessage: String?
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("New tag name", text: $newTagName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: newTagName) { newValue in
                            validateNewName(newValue)
                        }
                        .submitLabel(.done)
                        .onSubmit(addNewTag)

                    ColorPicker("Tag color", selection: $newTagColor)
                        .labelsHidden()
                        .scaleEffect(1.3)

                    Button(action: addNewTag) {
                        Label("Create Tag", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(
                        isCreating
                            || newTagName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty || errorMessage != nil
                    )
                } header: {
                    Text("Create New Tag")
                } footer: {
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    ForEach(tagsManager.allTags) { tag in
                        TagEditRow(tag: tag)
                    }
                    .onDelete { indexSet in
                        let tagsToDelete = indexSet.map {
                            tagsManager.allTags[$0]
                        }
                        for tag in tagsToDelete {
                            tagsManager.deleteTag(tag)
                        }
                    }
                } header: {
                    Text("Existing Tags (\(tagsManager.allTags.count))")
                }
            }
            .navigationTitle("Manage Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isCreating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func validateNewName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errorMessage = nil
            return
        }

        let lower = trimmed.lowercased()
        if tagsManager.allTags.contains(where: { $0.name.lowercased() == lower }
        ) {
            errorMessage = "A tag with this name already exists"
        } else {
            errorMessage = nil
        }
    }

    private func addNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if tagsManager.allTags.contains(where: {
            $0.name.lowercased() == trimmed.lowercased()
        }) {
            errorMessage = "Tag name already exists"
            return
        }

        isCreating = true
        tagsManager.createTag(name: trimmed, color: newTagColor)

        newTagName = ""
        newTagColor = .blue
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isCreating = false
        }
    }
}
