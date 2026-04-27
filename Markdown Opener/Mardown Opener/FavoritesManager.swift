//
//  FavoritesManager.swift
//  Markdown Opener
//
//  Created: alfred chen on 25/11/2025.
//  Enhanced: December 2025 - Firestore sync with optimized workflow
//

import Foundation
import Combine
import FirebaseAuth

final class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()

    @Published private(set) var starredURLs: Set<URL> = []

    private let key = "FavoritesManager.StarredURLs"
    private let firestore = FirestoreService.shared
    private var saveWorkItem: DispatchWorkItem?
    private var initialSyncComplete = false
    private let syncLock = NSLock()
    private var isListening = false
    private var isReceivingRemoteChange = false

    private init() {
        loadFromUserDefaults()
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

    private func setupFirestoreListeners() {
        isListening = true
        firestore.listenForFavorites { [weak self] urls in
            self?.handleRemoteFavorites(urls)
        }
    }

    private func handleRemoteFavorites(_ urls: Set<URL>) {
        syncLock.lock()
        guard initialSyncComplete else {
            syncLock.unlock()
            return
        }
        syncLock.unlock()

        isReceivingRemoteChange = true
        starredURLs = urls
        saveToUserDefaultsNow()
        isReceivingRemoteChange = false
    }

    func syncWithFirestore() async {
        guard Auth.auth().currentUser != nil else { return }

        syncLock.lock()
        let wasInitialSync = initialSyncComplete
        if !wasInitialSync {
            initialSyncComplete = true
        }
        syncLock.unlock()

        if let remoteURLs = await firestore.loadFavorites() {
            await MainActor.run {
                syncLock.lock()
                let shouldApply = !wasInitialSync || starredURLs.isEmpty
                syncLock.unlock()

                if shouldApply && !remoteURLs.isEmpty {
                    isReceivingRemoteChange = true
                    starredURLs = remoteURLs
                    saveToUserDefaultsNow()
                    isReceivingRemoteChange = false
                }
            }
        }
    }

    func toggleStar(for url: URL) {
        if starredURLs.contains(url) {
            starredURLs.remove(url)
        } else {
            starredURLs.insert(url)
        }
    }

    func isStarred(_ url: URL) -> Bool {
        starredURLs.contains(url)
    }

    private func saveDebounced() {
        guard !isReceivingRemoteChange else { return }

        saveWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }

        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func saveNow() {
        saveToUserDefaultsNow()
        saveToFirestore()
    }

    private func saveToUserDefaultsNow() {
        if let data = try? JSONEncoder().encode(starredURLs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func saveToFirestore() {
        Task {
            await firestore.saveFavorites(starredURLs)
        }
    }

    private func loadFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Set<URL>.self, from: data) {
            starredURLs = decoded
        }
    }
}
