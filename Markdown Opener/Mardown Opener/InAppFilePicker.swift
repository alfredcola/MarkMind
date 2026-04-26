//
//  InAppFilePicker.swift
//  Markdown Opener
//
//  Created by alfred chen on 20/12/2025.
//

import Foundation
import PDFKit
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

struct InAppFilePicker: View {
    let documentStore: DocumentStore
    @Binding var selectedFiles: [(url: URL, content: String)]
    let docURL: URL
    var fileContentLoader: ((URL) throws -> String)? = nil
    @Environment(\.dismiss) var dismiss
    @State private var availableFiles: [URL] = []
    @State private var errorMessage: String?
    @State private var selectedTab = 0
    @State private var selectedFilter: FileFilter = .all
    @State private var fileSort: FileSort = .dateNew

    private enum FileGroup: String, CaseIterable {
        case markdown = "Markdown"
        case text = "Text Files"
        case pdf = "PDF"
        case docx = "Word"
        case pptx = "PowerPoint"
        case other = "Other"
    }

    // FileFilter enum for filtering files
    private enum FileFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case markdown = "MD"
        case text = "TXT"
        case pdf = "PDF"
        case docx = "DOCX"
        case pptx = "PPTX"

        var id: String { rawValue }

        var group: FileGroup? {
            switch self {
            case .all: return nil
            case .markdown: return .markdown
            case .text: return .text
            case .pdf: return .pdf
            case .docx: return .docx
            case .pptx: return .pptx
            }
        }
    }

    private enum FileSort: String, CaseIterable, Identifiable {
        case nameAsc = "Name (A to Z)"
        case nameDesc = "Name (Z to A)"
        case dateNew = "Date (Newest)"
        case dateOld = "Date (Oldest)"
        case sizeLarge = "Size (Largest)"
        case sizeSmall = "Size (Smallest)"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationView {
            VStack {
                // Tab Picker
                Picker("Source", selection: $selectedTab) {
                    Text(Localization.locWithUserPreference("In-App Files", "應用內檔案")).tag(0)
                    Text(Localization.locWithUserPreference("File Explorer", "檔案瀏覽器")).tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == 0 {
                    inAppFilesView
                } else {
                    fileExplorerView
                }
            }
            .navigationTitle(Localization.locWithUserPreference("Select Files (Max 10 files)", "選擇檔案 (最多10個檔案)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Localization.locWithUserPreference("Cancel", "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Localization.locWithUserPreference("Done", "完成")) { dismiss() }
                }
            }
            .alert(isPresented: .constant(errorMessage != nil)) {
                Alert(
                    title: Text(Localization.locWithUserPreference("Error", "錯誤")),
                    message: Text(errorMessage ?? ""),
                    dismissButton: .default(Text("OK")) { errorMessage = nil }
                )
            }
            .onAppear {
                if selectedTab == 0 {
                    loadAvailableFiles()
                }
            }
        }
    }
    @EnvironmentObject var favorites: FavoritesManager
    @EnvironmentObject var tagsManager: TagsManager

    @State private var expandedGroups: Set<ExpandableSection> = []

    private enum ExpandableSection: Hashable {
        case starred
        case tag(Tag)
        case fileGroup(FileGroup)

        func hash(into hasher: inout Hasher) {
            switch self {
            case .starred: hasher.combine("starred")
            case .tag(let tag): hasher.combine("tag"); hasher.combine(tag.id)
            case .fileGroup(let g): hasher.combine("fileGroup"); hasher.combine(g.rawValue)
            }
        }

        static func == (lhs: ExpandableSection, rhs: ExpandableSection) -> Bool {
            switch (lhs, rhs) {
            case (.starred, .starred): return true
            case (.tag(let l), .tag(let r)): return l.id == r.id
            case (.fileGroup(let l), .fileGroup(let r)): return l == r
            default: return false
            }
        }
    }

    private func toggleExpanded(_ section: ExpandableSection) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if expandedGroups.contains(section) {
                expandedGroups.remove(section)
            } else {
                expandedGroups.insert(section)
            }
        }
    }

    private func isExpanded(_ section: ExpandableSection) -> Bool {
        expandedGroups.contains(section)
    }

    private func initializeExpandedSections() {
        var allSections = Set<ExpandableSection>()
        allSections.insert(.starred)

        let usedTags = Set(availableFiles.flatMap { tagsManager.tags(for: $0) })
        for tag in tagsManager.allTags where usedTags.contains(tag) {
            allSections.insert(.tag(tag))
        }

        let presentGroups = Set(
            availableFiles
                .filter { !favorites.isStarred($0) && tagsManager.tags(for: $0).isEmpty }
                .map { group(for: $0.pathExtension.lowercased()) }
        )
        for g in FileGroup.allCases where presentGroups.contains(g) && g != .other {
            allSections.insert(.fileGroup(g))
        }

        withAnimation {
            expandedGroups = allSections
        }
    }
    
    private var groupChips: some View {
        let vm = MultiSettingsViewModel.shared

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Follow user-defined chip order
                ForEach(vm.chipGroupsOrder, id: \.self) { chip in
                    switch chip {
                    case .starred:
                        let count = availableFiles.filter { favorites.isStarred($0) }.count
                        if count > 0 {
                            groupChip(
                                title: "Starred (\(count))",
                                icon: "star.fill",
                                color: .yellow,
                                isActive: isExpanded(.starred)
                            ) { toggleExpanded(.starred) }
                        }

                    case .tags:
                        let usedTags = Set(availableFiles.flatMap { tagsManager.tags(for: $0) })
                        ForEach(tagsManager.allTags.filter { usedTags.contains($0) }, id: \.id) { tag in
                            let count = availableFiles.filter { tagsManager.tags(for: $0).contains(tag) }.count
                            groupChip(
                                title: "\(tag.name)(\(count))",
                                icon: "tag.fill",
                                color: tag.color.color,
                                isActive: isExpanded(.tag(tag))
                            ) { toggleExpanded(.tag(tag)) }
                        }

                    case .markdown, .text, .pdf, .docx, .pptx:
                        let group = fileGroupFromChip(chip)
                        let count = availableFiles
                            .filter { !favorites.isStarred($0) && tagsManager.tags(for: $0).isEmpty }
                            .filter { self.group(for: $0.pathExtension.lowercased()) == group }
                            .count
                        if count > 0 {
                            groupChip(
                                title: "\(group.rawValue)(\(count))",
                                icon: iconForGroup(group),
                                color: colorForGroup(group),
                                isActive: isExpanded(.fileGroup(group))
                            ) { toggleExpanded(.fileGroup(group)) }
                        }

                    default: EmptyView()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func fileGroupFromChip(_ chip: ChipGroup) -> FileGroup {
        switch chip {
        case .markdown: return .markdown
        case .text: return .text
        case .pdf: return .pdf
        case .docx: return .docx
        case .pptx: return .pptx
        default: return .other
        }
    }

    private func iconForGroup(_ group: FileGroup) -> String {
        switch group {
        case .markdown: return "doc.text"
        case .text: return "doc.plaintext"
        case .pdf: return "doc.richtext"
        case .docx: return "doc"
        case .pptx: return "play.rectangle"
        case .other: return "doc"
        }
    }

    private func colorForGroup(_ group: FileGroup) -> Color {
        switch group {
        case .markdown: return .orange
        case .text: return .blue
        case .pdf: return .red
        case .docx: return .green
        case .pptx: return .purple
        case .other: return .gray
        }
    }

    @ViewBuilder
    private func groupChip(title: String, icon: String, color: Color, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(
                title: { Text(title).font(.subheadline.bold()) },
                icon: { Image(systemName: icon) }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isActive ? color.opacity(0.22) : Color(UIColor.tertiarySystemFill))
            )
            .foregroundColor(isActive ? color : .primary)
            .overlay(
                Capsule().stroke(isActive ? color : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
    @ViewBuilder
    private func pickerFileRow(for url: URL, isStarred: Bool) -> some View {
        let info = self.info(for: url) ?? FileInfo(url: url, size: 0, modified: .distantPast, ext: url.pathExtension.lowercased())

        HStack(spacing: 12) {
            Image(systemName: iconName(for: url))
                .foregroundStyle(.secondary)

            Button {
                selectFile(url)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(url.lastPathComponent)
                        .font(.subheadline)
                        .lineLimit(2)

                    if !tagsManager.tags(for: url).isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(tagsManager.tags(for: url)) { tag in
                                    Text(tag.name)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(tag.color.color.opacity(0.18))
                                        .foregroundColor(tag.color.color)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(tag.color.color, lineWidth: 1))
                                }
                            }
                        }
                    }

                    Text("\(FormattingHelpers.byteCount(info.size)) • \(FormattingHelpers.friendlyDate(info.modified))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if selectedFiles.contains(where: { $0.url == url }) {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
            }
        }
        .padding(.vertical, 4)
        .opacity(
            selectedFiles.count >= 10 && !selectedFiles.contains(where: { $0.url == url })
            ? 0.5 : 1.0
        )
        .disabled(
            selectedFiles.count >= 10 && !selectedFiles.contains(where: { $0.url == url })
        )
    }

    private var inAppFilesView: some View {
        VStack(spacing: 0) {
            // Top: Horizontal Group Chips (exactly like recentList)
            groupChips
                .padding(.vertical, 8)

            // Main List with collapsible sections
            List {
                // 1. Starred files
                if isExpanded(.starred) {
                    let starred = availableFiles.filter { favorites.isStarred($0) }
                    if !starred.isEmpty {
                        Section {
                            ForEach(starred, id: \.self) { url in
                                pickerFileRow(for: url, isStarred: true)
                            }
                        } header: {
                            Label("Starred", systemImage: "star.fill")
                                .font(.headline)
                                .foregroundColor(.yellow)
                        }
                    }
                }

                // 2. Tags
                let usedTags = Set(availableFiles.flatMap { tagsManager.tags(for: $0) })
                ForEach(tagsManager.allTags.filter { usedTags.contains($0) }, id: \.id) { tag in
                    if isExpanded(.tag(tag)) {
                        let taggedFiles = availableFiles.filter {
                            tagsManager.tags(for: $0).contains(tag) && !favorites.isStarred($0)
                        }
                        if !taggedFiles.isEmpty {
                            Section {
                                ForEach(taggedFiles, id: \.self) { url in
                                    pickerFileRow(for: url, isStarred: false)
                                }
                            } header: {
                                Label(tag.name, systemImage: "tag.fill")
                                    .font(.headline)
                                    .foregroundColor(tag.color.color)
                            }
                        }
                    }
                }

                // 3. File Type Groups (only non-starred/non-tagged)
                let remainingFiles = availableFiles.filter {
                    !favorites.isStarred($0) && tagsManager.tags(for: $0).isEmpty
                }
                let visibleGroups = Set(remainingFiles.map { group(for: $0.pathExtension.lowercased()) })
                    .filter { $0 != .other }

                ForEach(visibleGroups.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { fileGroup in
                    if isExpanded(.fileGroup(fileGroup)) {
                        let groupFiles = remainingFiles.filter {
                            self.group(for: $0.pathExtension.lowercased()) == fileGroup
                        }

                        if !groupFiles.isEmpty {
                            Section {
                                ForEach(groupFiles, id: \.self) { url in
                                    pickerFileRow(for: url, isStarred: false)
                                }
                            } header: {
                                Text(fileGroup.rawValue)
                                    .font(.headline)
                            }
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
        }
        .onAppear {
            loadAvailableFiles()
            initializeExpandedSections()
        }
    }

    private var fileExplorerView: some View {
        FileExplorerView(
            selectedFiles: $selectedFiles,
            errorMessage: $errorMessage
        )
    }

    private func loadAvailableFiles() {
        do {
            availableFiles = try documentStore.listDocuments().filter {
                $0 != docURL
            }
        } catch {
            errorMessage = Localization.locWithUserPreference(
                "Failed to load files: \(error.localizedDescription)",
                "無法載入檔案：\(error.localizedDescription)"
            )
        }
    }

    private func selectFile(_ url: URL) {
        if selectedFiles.contains(where: { $0.url == url }) {
            selectedFiles.removeAll { $0.url == url }
        } else if selectedFiles.count < 10 {
            do {
                let data = try documentStore.load(url)
                let content =
                    data.text.isEmpty && url.pathExtension.lowercased() == "ppt"
                    ? Localization.locWithUserPreference(
                        "Legacy .ppt files are not supported for text extraction",
                        "舊版 .ppt 檔案不支援文字提取"
                    )
                    : data.text
                selectedFiles.append((url: url, content: content))
            } catch {
                let message =
                    url.pathExtension.lowercased() == "ppt"
                    ? Localization.locWithUserPreference(
                        "Legacy .ppt files are not supported: \(error.localizedDescription)",
                        "舊版 .ppt 檔案不支援：\(error.localizedDescription)"
                    )
                    : Localization.locWithUserPreference(
                        "Failed to load \(url.lastPathComponent): \(error.localizedDescription)",
                        "無法載入 \(url.lastPathComponent)：\(error.localizedDescription)"
                    )
                errorMessage = message
            }
        }
    }

    private func group(for ext: String) -> FileGroup {
        switch ext.lowercased() {
        case "md": return .markdown
        case "txt": return .text
        case "pdf": return .pdf
        case "docx": return .docx
        case "ppt", "pptx": return .pptx
        default: return .other
        }
    }

    private func iconName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md": return "doc.text"
        case "txt": return "doc.plaintext"
        case "pdf": return "doc.richtext"
        case "docx": return "doc"
        case "ppt", "pptx": return "doc.viewfinder"
        default: return "doc"
        }
    }

    private func info(for url: URL) -> FileInfo? {
        do {
            let attrs = try FileManager.default.attributesOfItem(
                atPath: url.path
            )
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let mod = (attrs[.modificationDate] as? Date) ?? .distantPast
            return FileInfo(
                url: url,
                size: size,
                modified: mod,
                ext: url.pathExtension.lowercased()
            )
        } catch {
            return nil
        }
    }

    private func groupedAndSorted(_ urls: [URL], by sort: FileSort) -> [(
        FileGroup, [FileInfo]
    )] {
        let infos = urls.compactMap { info(for: $0) }
        let sorted: [FileInfo] = {
            switch sort {
            case .nameAsc:
                return infos.sorted {
                    $0.url.lastPathComponent.localizedCaseInsensitiveCompare(
                        $1.url.lastPathComponent
                    ) == .orderedAscending
                }
            case .nameDesc:
                return infos.sorted {
                    $0.url.lastPathComponent.localizedCaseInsensitiveCompare(
                        $1.url.lastPathComponent
                    ) == .orderedDescending
                }
            case .dateNew:
                return infos.sorted { $0.modified > $1.modified }
            case .dateOld:
                return infos.sorted { $0.modified < $1.modified }
            case .sizeLarge:
                return infos.sorted { $0.size > $1.size }
            case .sizeSmall:
                return infos.sorted { $0.size < $1.size }
            }
        }()
        let grouped = Dictionary(grouping: sorted) { group(for: $0.ext) }
        let order: [FileGroup] = [.markdown, .text, .pdf, .docx, .pptx, .other]
        return order.compactMap { g in
            guard let arr = grouped[g], !arr.isEmpty else { return nil }
            return (g, arr)
        }
    }

    private func filterURLs(_ urls: [URL], by filter: FileFilter) -> [URL] {
        guard let g = filter.group else { return urls }
        return urls.filter { url in
            let ext = url.pathExtension.lowercased()
            return group(for: ext) == g
        }
    }

    private func metaLine(_ info: FileInfo) -> String {
        "\(FormattingHelpers.byteCount(info.size))  \(FormattingHelpers.friendlyDate(info.modified))"
    }

    private func share(url: URL) {
        ShareSheet.present(items: [url])
    }
}

struct FileExplorerView: UIViewControllerRepresentable {
    @Binding var selectedFiles: [(url: URL, content: String)]
    @Binding var errorMessage: String?

    func makeUIViewController(context: Context)
        -> UIDocumentPickerViewController
    {
        let supportedTypes: [UTType] = [
            .plainText,  // .txt
            .text,  // fallback
            .pdf,
            UTType(filenameExtension: "md") ?? .data,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "ppt") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
        ]
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: supportedTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FileExplorerView
        let documentStore = DocumentStore.shared

        init(parent: FileExplorerView) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            for url in urls {
                guard parent.selectedFiles.count < 10 else {
                    parent.errorMessage = Localization.locWithUserPreference(
                        "Maximum 10 files can be selected",
                        "最多只能選擇10個檔案"
                    )
                    return
                }

                do {
                    // Start accessing the security-scoped resource
                    guard url.startAccessingSecurityScopedResource() else {
                        throw NSError(
                            domain: "FileAccess",
                            code: -1,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "Cannot access file: \(url.lastPathComponent)"
                            ]
                        )
                    }

                    // Use DocumentStore to load file content
                    let data = try documentStore.load(url)
                    let content =
                        data.text.isEmpty
                            && (url.pathExtension.lowercased() == "ppt"
                                || url.pathExtension.lowercased() == "pptx"
                                    && data.text.isEmpty)
                        ? Localization.locWithUserPreference(
                            "This file type may have limited text extraction.",
                            "此檔案類型可能文字提取有限。"
                        )
                        : data.text
                    parent.selectedFiles.append((url: url, content: content))

                    url.stopAccessingSecurityScopedResource()
                } catch {
                    let message: String
                    if url.pathExtension.lowercased() == "ppt" {
                        message = Localization.locWithUserPreference(
                            "Legacy .ppt files are not supported: \(error.localizedDescription)",
                            "舊版 .ppt 檔案不支援：\(error.localizedDescription)"
                        )
                    } else {
                        message = Localization.locWithUserPreference(
                            "Failed to load \(url.lastPathComponent): \(error.localizedDescription)",
                            "無法載入 \(url.lastPathComponent)：\(error.localizedDescription)"
                        )
                    }
                    parent.errorMessage = message
                }
            }
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
        }
    }
}
