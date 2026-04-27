//
//  FirestoreService.swift
//  Markdown Opener
//
//  Handles Firestore operations for tags and favorites
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

final class FirestoreService: ObservableObject {
    static let shared = FirestoreService()

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    private var currentUserUID: String? {
        Auth.auth().currentUser?.uid
    }

    private init() {}

    deinit {
        listeners.forEach { $0.remove() }
    }

    private func ensureSignedIn() -> String? {
        guard let uid = currentUserUID else {
            Log.debug("Firestore operation skipped: user not signed in", category: .cloudSync)
            return nil
        }
        return uid
    }

    // MARK: - Tags

    func saveTags(_ tags: [Tag]) async {
        guard let uid = ensureSignedIn() else { return }

        do {
            let data = try JSONEncoder().encode(tags)
            guard let tagsData = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            try await db.collection("users").document(uid).collection("metadata").document("tags").setData([
                "allTags": tagsData,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            Log.debug("Tags saved to Firestore", category: .cloudSync)
        } catch {
            Log.error("Failed to save tags to Firestore", category: .cloudSync, error: error)
        }
    }

    func loadTags() async -> [Tag]? {
        guard let uid = ensureSignedIn() else { return nil }

        do {
            let doc = try await db.collection("users").document(uid).collection("metadata").document("tags").getDocument(source: .server)
            guard doc.exists,
                  let data = doc.data(),
                  let allTagsData = data["allTags"] as? [String: Any] else {
                return nil
            }
            let jsonData = try JSONSerialization.data(withJSONObject: allTagsData)
            let tags = try JSONDecoder().decode([Tag].self, from: jsonData)
            Log.debug("Tags loaded from Firestore", category: .cloudSync)
            return tags
        } catch {
            Log.error("Failed to load tags from Firestore", category: .cloudSync, error: error)
            return nil
        }
    }

    func listenForTags(onChange: @escaping ([Tag]) -> Void) {
        guard let uid = ensureSignedIn() else { return }

        let listener = db.collection("users").document(uid).collection("metadata").document("tags")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let snapshot = snapshot, !snapshot.metadata.isFromCache else { return }

                Task { @MainActor in
                    if let data = snapshot.data(),
                       let allTagsData = data["allTags"] as? [String: Any],
                       let jsonData = try? JSONSerialization.data(withJSONObject: allTagsData),
                       let tags = try? JSONDecoder().decode([Tag].self, from: jsonData) {
                        onChange(tags)
                    }
                }
            }
        listeners.append(listener)
    }

    // MARK: - Tag Assignments

    func saveTagAssignments(_ assignments: [String: [String]]) async {
        guard let uid = ensureSignedIn() else { return }

        do {
            try await db.collection("users").document(uid).collection("metadata").document("tagAssignments").setData([
                "assignments": assignments,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            Log.debug("Tag assignments saved to Firestore", category: .cloudSync)
        } catch {
            Log.error("Failed to save tag assignments to Firestore", category: .cloudSync, error: error)
        }
    }

    func loadTagAssignments() async -> [String: [String]]? {
        guard let uid = ensureSignedIn() else { return nil }

        do {
            let doc = try await db.collection("users").document(uid).collection("metadata").document("tagAssignments").getDocument(source: .server)
            guard doc.exists,
                  let data = doc.data(),
                  let assignments = data["assignments"] as? [String: [String]] else {
                return nil
            }
            Log.debug("Tag assignments loaded from Firestore", category: .cloudSync)
            return assignments
        } catch {
            Log.error("Failed to load tag assignments from Firestore", category: .cloudSync, error: error)
            return nil
        }
    }

    func listenForTagAssignments(onChange: @escaping ([String: [String]]) -> Void) {
        guard let uid = ensureSignedIn() else { return }

        let listener = db.collection("users").document(uid).collection("metadata").document("tagAssignments")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let snapshot = snapshot, !snapshot.metadata.isFromCache else { return }

                Task { @MainActor in
                    if let data = snapshot.data(),
                       let assignments = data["assignments"] as? [String: [String]] {
                        onChange(assignments)
                    }
                }
            }
        listeners.append(listener)
    }

    // MARK: - Favorites

    func saveFavorites(_ urls: Set<URL>) async {
        guard let uid = ensureSignedIn() else { return }

        do {
            let urlStrings = urls.map { $0.absoluteString }
            try await db.collection("users").document(uid).collection("metadata").document("favorites").setData([
                "starredURLs": urlStrings,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            Log.debug("Favorites saved to Firestore", category: .cloudSync)
        } catch {
            Log.error("Failed to save favorites to Firestore", category: .cloudSync, error: error)
        }
    }

    func loadFavorites() async -> Set<URL>? {
        guard let uid = ensureSignedIn() else { return nil }

        do {
            let doc = try await db.collection("users").document(uid).collection("metadata").document("favorites").getDocument(source: .server)
            guard doc.exists,
                  let data = doc.data(),
                  let urlStrings = data["starredURLs"] as? [String] else {
                return nil
            }
            let urls = Set(urlStrings.compactMap { URL(string: $0) })
            Log.debug("Favorites loaded from Firestore", category: .cloudSync)
            return urls
        } catch {
            Log.error("Failed to load favorites from Firestore", category: .cloudSync, error: error)
            return nil
        }
    }

    func listenForFavorites(onChange: @escaping (Set<URL>) -> Void) {
        guard let uid = ensureSignedIn() else { return }

        let listener = db.collection("users").document(uid).collection("metadata").document("favorites")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let snapshot = snapshot, !snapshot.metadata.isFromCache else { return }

                Task { @MainActor in
                    if let data = snapshot.data(),
                       let urlStrings = data["starredURLs"] as? [String] {
                        let urls = Set(urlStrings.compactMap { URL(string: $0) })
                        onChange(urls)
                    }
                }
            }
        listeners.append(listener)
    }

    // MARK: - Remove All Listeners

    func removeAllListeners() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
}
