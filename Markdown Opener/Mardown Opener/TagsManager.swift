//
//  TagsManager.swift
//  Markdown Opener
//
//  Created by alfred chen on 4/12/2025.
//  Enhanced: December 2025
//

import SwiftUI
import Combine

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
            // Auto-trim on every change
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
    
    // Computed trimmed version
    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Hashable & Equatable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Tag, rhs: Tag) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Codable
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
            debounceSave()
        }
    }
    
    @AppStorage("com.markmind.tags.expanded") private var expandedTagsData: Data = Data()
    
    private let allTagsKey = "com.markmind.tags.all.v1"
    private var saveWorkItem: DispatchWorkItem?
    
    private init() {
        loadAllTags()
        
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
        let fileID = FileIDManager.shared.getFileID(for: url)
        let key = "tags_\(fileID)"
        guard let tagIDs = UserDefaults.standard.array(forKey: key) as? [String] else {
            return []
        }
        return allTags.filter { tagIDs.contains($0.id.uuidString) }
    }
    
    func contains(_ tag: Tag, for url: URL) -> Bool {
        let fileID = FileIDManager.shared.getFileID(for: url)
        let key = "tags_\(fileID)"
        guard let tagIDs = UserDefaults.standard.array(forKey: key) as? [String] else {
            return false
        }
        return tagIDs.contains(tag.id.uuidString)
    }
    
    // MARK: - Tag Actions
    
    func toggleTag(_ tag: Tag, for url: URL) {
        let fileID = FileIDManager.shared.getFileID(for: url)
        let key = "tags_\(fileID)"
        var currentIDs = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        let tagID = tag.id.uuidString
        
        if currentIDs.contains(tagID) {
            currentIDs.removeAll { $0 == tagID }
        } else {
            currentIDs.append(tagID)
        }
        
        UserDefaults.standard.set(currentIDs.isEmpty ? nil : currentIDs, forKey: key)
        objectWillChange.send()
    }
    
    func createTag(name: String, color: Color) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Prevent duplicates (case-insensitive)
        if allTags.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            Log.debug("Tag named '\(trimmed)' already exists", category: .data)
            return
        }
        
        let newTag = Tag(name: trimmed, color: color)
        allTags.append(newTag)
    }
    
    func renameTag(_ tag: Tag, to newName: String) {
        let trimmed = newName.trimmed
        guard !trimmed.isEmpty else { return }
        
        guard let index = allTags.firstIndex(where: { $0.id == tag.id }) else { return }
        
        // Optional: duplicate check here too
        if allTags.contains(where: { $0.id != tag.id && $0.name.lowercased() == trimmed.lowercased() }) {
            return
        }
        
        allTags[index].name = trimmed
        // allTags change → triggers save via didSet
    }

    func updateTag(_ tag: Tag, color: Color? = nil) {
        guard let index = allTags.firstIndex(where: { $0.id == tag.id }) else { return }
        if let color {
            allTags[index].color = ColorCodable(color: color)
        }
    }
    
    func deleteTag(_ tag: Tag) {
        allTags.removeAll { $0.id == tag.id }
        
        // Clean up references in all files
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("tags_") }
        
        for key in allKeys {
            if var ids = UserDefaults.standard.array(forKey: key) as? [String] {
                ids.removeAll { $0 == tag.id.uuidString }
                UserDefaults.standard.set(ids.isEmpty ? nil : ids, forKey: key)
            }
        }
        
        objectWillChange.send()
    }
    
    // MARK: - Persistence
    
    private func debounceSave() {
        saveWorkItem?.cancel()
        
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveAllTagsNow()
        }
        
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
    
    private func saveAllTagsNow() {
        do {
            let data = try JSONEncoder().encode(allTags)
            UserDefaults.standard.set(data, forKey: allTagsKey)
        } catch {
            Log.error("Failed to encode tags", category: .data, error: error)
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
