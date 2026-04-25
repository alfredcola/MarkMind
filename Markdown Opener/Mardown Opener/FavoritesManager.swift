//
//  FavoritesManager.swift
//  Markdown Opener
//
//  Created by alfred chen on 25/11/2025.
//


import Foundation
import Combine

final class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()
    
    @Published private(set) var starredURLs: Set<URL> = []
    
    private let key = "FavoritesManager.StarredURLs"
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Set<URL>.self, from: data) {
            starredURLs = decoded
        }
    }
    
    func toggleStar(for url: URL) {
        if starredURLs.contains(url) {
            starredURLs.remove(url)
        } else {
            starredURLs.insert(url)
        }
        save()
    }
    
    func isStarred(_ url: URL) -> Bool {
        starredURLs.contains(url)
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(starredURLs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
