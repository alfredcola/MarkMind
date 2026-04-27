//
//  TagsManager.swift
//  Markdown Opener
//
//  Created by alfred chen on 4/12/2025.
//  Enhanced: December 2025
//

import SwiftUI
import Combine
import FirebaseAuth

// MARK: - ColorCodable
struct ColorCodable: Codable, Hashable {
    let red, green, blue, alpha: Double

    init(color: Color) {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.alpha = Double(a)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}


extension String {
     var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}



// MARK: - Tag
class Tag: Identifiable, Codable, Hashable, ObservableObject {
    let id: UUID
    @Published var name: String {
        didSet {
            if name != name.trimmed {
                name = name.trimmed
            }
        }
    }
    @Published var color: ColorCodable

    init(name: String, color: Color) {
        self.id = UUID()
        self.name = name.trimmed
        self.color = ColorCodable(color: color)
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Tag, rhs: Tag) -> Bool {
        lhs.id == rhs.id
    }

    enum CodingKeys: String, CodingKey {
        case id, name, color
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decode(ColorCodable.self, forKey: .color)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
    }
}

// MARK: - TagsManager
final class TagsManager: ObservableObject {
    static let shared = TagsManager()

    @Published var allTags: [Tag] = [] {
        didSet {
            if !isReceivingRemoteChange {
                debounceSaveTags()
            }
        }
    }

    @Published private(set) var tagAssignments: [String: [String]] = [:] {
        didSet {
            if !isReceivingRemoteChange {
                saveTagAssignmentsDebounced()
            }
        }
    }

    @AppStorage("com.markmind.tags.expanded") private var expandedTagsData: Data = Data()

    private let allTagsKey = "com.markmind.tags.all.v1"
    private let tagAssignmentsKey = "com.markmind.tagAssignments.v1"
    private var tagsSaveWorkItem: DispatchWorkItem?
    private var assignmentsSaveWorkItem: DispatchWorkItem?
    private let firestore = FirestoreService.shared
    private var initialSyncComplete = false
    private let syncLock = NSLock()
    private var isReceivingRemoteChange = false

    private init() {
        loadAllTags()
        loadTagAssignments()

        if allTags.isEmpty {
            allTags = [
                Tag(name: "Study",      color: .red),
                Tag(name: "Work",       color: .blue),
                Tag(name: "Important",  color: .yellow),
                Tag(name: "Project",    color: .orange),
                Tag(name: "Personal",   color: .green),
                Tag(name: "Idea",       color: .purple),
                Tag(name: "To Do",      color: .cyan)
            ]
        }

        setupAuthObserver()
    }

    private func setupAuthObserver() {
        NotificationCenter.default.addObserver(
            forName: .AuthStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if Auth.auth().currentUser != nil {
                self.setupFirestoreListenersIfSignedIn()
                Task {
                    await self.syncWithFirestore()
                }
            }
        }
    }

    func setupFirestoreListenersIfSignedIn() {
        if Auth.auth().currentUser != nil && !isListening {
            setupFirestoreListeners()
        }
    }

    private var isListening = false

    private func setupFirestoreListeners() {
        isListening = true
        firestore.listenForTags { [weak self] tags in
            self?.handleRemoteTags(tags)
        }

        firestore.listenForTagAssignments { [weak self] assignments in
            self?.handleRemoteTagAssignments(assignments)
        }
    }

    private func handleRemoteTags(_ tags: [Tag]) {
        syncLock.lock()
        guard initialSyncComplete else {
            syncLock.unlock()
            return
        }
        syncLock.unlock()

        isReceivingRemoteChange = true
        allTags = tags
        isReceivingRemoteChange = false
    }

    private func handleRemoteTagAssignments(_ assignments: [String: [String]]) {
        syncLock.lock()
        guard initialSyncComplete else {
            syncLock.unlock()
            return
        }
        syncLock.unlock()

        isReceivingRemoteChange = true
        tagAssignments = assignments
        isReceivingRemoteChange = false
        saveTagAssignmentsToUserDefaultsNow()
    }

    func syncWithFirestore() async {
        guard Auth.auth().currentUser != nil else { return }

        syncLock.lock()
        let wasInitialSync = initialSyncComplete
        if !wasInitialSync {
            initialSyncComplete = true
        }
        syncLock.unlock()

        if let remoteTags = await firestore.loadTags() {
            await MainActor.run {
                syncLock.lock()
                let shouldApply = !wasInitialSync || allTags.isEmpty
                syncLock.unlock()

                if shouldApply && !remoteTags.isEmpty {
                    isReceivingRemoteChange = true
                    allTags = remoteTags
                    isReceivingRemoteChange = false
                }
                saveTagsToUserDefaultsNow()
            }
        }

        if let remoteAssignments = await firestore.loadTagAssignments() {
            await MainActor.run {
                syncLock.lock()
                let shouldApply = !wasInitialSync || tagAssignments.isEmpty
                syncLock.unlock()

                if shouldApply && !remoteAssignments.isEmpty {
                    isReceivingRemoteChange = true
                    tagAssignments = remoteAssignments
                    isReceivingRemoteChange = false
                    saveTagAssignmentsToUserDefaultsNow()
                }
            }
        }
    }

    // MARK: - Expanded Tags State

    var expandedTagIDs: Set<UUID> {
        get {
            guard let ids = try? JSONDecoder().decode([String].self, from: expandedTagsData) else {
                return []
            }
            return Set(ids.compactMap { UUID(uuidString: $0) })
        }
        set {
            let stringIDs = newValue.map { $0.uuidString }
            if let data = try? JSONEncoder().encode(stringIDs) {
                expandedTagsData = data
            }
        }
    }

    func isTagExpanded(_ tag: Tag) -> Bool {
        expandedTagIDs.contains(tag.id)
    }

    func toggleTagExpanded(_ tag: Tag) {
        var current = expandedTagIDs
        if current.contains(tag.id) {
            current.remove(tag.id)
        } else {
            current.insert(tag.id)
        }
        expandedTagsData = expandedTagsData
        expandedTagIDs = current
    }

    func expandAllTags() {
        expandedTagIDs = Set(allTags.map { $0.id })
    }

    func collapseAllTags() {
        expandedTagIDs = []
    }

    // MARK: - Tag Queries

    func tags(for url: URL) -> [Tag] {
        let fileID = getFileID(for: url)
        let tagIDs = tagAssignments[fileID] ?? []
        return allTags.filter { tagIDs.contains($0.id.uuidString) }
    }

    func contains(_ tag: Tag, for url: URL) -> Bool {
        let fileID = getFileID(for: url)
        let tagIDs = tagAssignments[fileID] ?? []
        return tagIDs.contains(tag.id.uuidString)
    }

    // MARK: - Tag Actions

    func toggleTag(_ tag: Tag, for url: URL) {
        let fileID = getFileID(for: url)
        var currentIDs = tagAssignments[fileID] ?? []
        let tagID = tag.id.uuidString

        if currentIDs.contains(tagID) {
            currentIDs.removeAll { $0 == tagID }
        } else {
            currentIDs.append(tagID)
        }

        if currentIDs.isEmpty {
            tagAssignments.removeValue(forKey: fileID)
        } else {
            tagAssignments[fileID] = currentIDs
        }
        objectWillChange.send()
    }

    private func getFileID(for url: URL) -> String {
        return FileIDManager.shared.getFileID(for: url)
    }

    func createTag(name: String, color: Color) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if allTags.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return
        }

        let newTag = Tag(name: trimmed, color: color)
        allTags.append(newTag)
    }

    func renameTag(_ tag: Tag, to newName: String) {
        let trimmed = newName.trimmed
        guard !trimmed.isEmpty else { return }

        guard let index = allTags.firstIndex(where: { $0.id == tag.id }) else { return }

        if allTags.contains(where: { $0.id != tag.id && $0.name.lowercased() == trimmed.lowercased() }) {
            return
        }

        allTags[index].name = trimmed
    }

    func updateTag(_ tag: Tag, color: Color? = nil) {
        guard let index = allTags.firstIndex(where: { $0.id == tag.id }) else { return }
        if let color {
            allTags[index].color = ColorCodable(color: color)
        }
    }

    func deleteTag(_ tag: Tag) {
        allTags.removeAll { $0.id == tag.id }

        var modified = false
        for (fileID, var ids) in tagAssignments {
            ids.removeAll { $0 == tag.id.uuidString }
            if ids.isEmpty {
                tagAssignments.removeValue(forKey: fileID)
            } else {
                tagAssignments[fileID] = ids
            }
            modified = true
        }

        if modified {
            saveTagAssignmentsToUserDefaultsNow()
        }
    }

    // MARK: - Tag Assignments Persistence

    private func saveTagAssignmentsDebounced() {
        assignmentsSaveWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.saveTagAssignmentsToUserDefaultsNow()
            self?.saveTagAssignmentsToFirestore()
        }

        assignmentsSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func saveTagAssignmentsToUserDefaultsNow() {
        if let data = try? JSONEncoder().encode(tagAssignments) {
            UserDefaults.standard.set(data, forKey: tagAssignmentsKey)
        }
    }

    private func saveTagAssignmentsToFirestore() {
        Task {
            await firestore.saveTagAssignments(tagAssignments)
        }
    }

    private func loadTagAssignments() {
        guard let data = UserDefaults.standard.data(forKey: tagAssignmentsKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            rebuildTagAssignmentsFromUserDefaults()
            return
        }
        tagAssignments = decoded
    }

    private func rebuildTagAssignmentsFromUserDefaults() {
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("tags_") }

        var assignments: [String: [String]] = [:]
        for key in allKeys {
            if let fileID = key.replacingOccurrences(of: "tags_", with: "") as String?,
               let tagIDs = UserDefaults.standard.array(forKey: key) as? [String] {
                assignments[fileID] = tagIDs
            }
        }
        tagAssignments = assignments
    }

    // MARK: - Tags Persistence

    private func debounceSaveTags() {
        tagsSaveWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.saveTagsToUserDefaultsNow()
            self?.saveTagsToFirestore()
        }

        tagsSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func saveTagsToUserDefaultsNow() {
        do {
            let data = try JSONEncoder().encode(allTags)
            UserDefaults.standard.set(data, forKey: allTagsKey)
        } catch {
        }
    }

    private func saveTagsToFirestore() {
        Task {
            await firestore.saveTags(allTags)
        }
    }

    private func loadAllTags() {
        guard let data = UserDefaults.standard.data(forKey: allTagsKey),
              let decoded = try? JSONDecoder().decode([Tag].self, from: data) else {
            return
        }
        allTags = decoded
    }
}
