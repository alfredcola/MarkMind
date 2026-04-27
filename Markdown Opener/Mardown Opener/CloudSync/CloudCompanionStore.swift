//
//  CloudCompanionStore.swift
//  MarkMind
//
//  Protocol and implementations for companion data storage in GCS
//

import Foundation
import FirebaseStorage
import FirebaseAuth

protocol CloudCompanionStore {
    func save(_ data: Data, for fileId: String) async throws
    func load(for fileId: String) async throws -> Data?
    func delete(for fileId: String) async throws
}

enum CloudCompanionError: LocalizedError {
    case notAuthenticated
    case saveFailed
    case loadFailed
    case deleteFailed
    case notFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "User not authenticated"
        case .saveFailed: return "Failed to save companion data"
        case .loadFailed: return "Failed to load companion data"
        case .deleteFailed: return "Failed to delete companion data"
        case .notFound: return "Companion data not found"
        }
    }
}

final class CloudChatStore: CloudCompanionStore {
    static let shared = CloudChatStore()

    private let gcs = GCSStorageService.shared

    private var userID: String? {
        Auth.auth().currentUser?.uid
    }

    private var basePath: String {
        guard let uid = userID else { return "" }
        return "users/\(uid)"
    }

    private init() {}

    func save(_ data: Data, for fileId: String) async throws {
        guard userID != nil else {
            throw CloudCompanionError.notAuthenticated
        }

        let remotePath = CloudPath.companionPath(fileId: fileId, type: .chat)
        try await gcs.uploadData(data, to: remotePath)

        Log.debug("Saved chat data for fileId: \(fileId), size: \(data.count)", category: .cloudSync)
    }

    func load(for fileId: String) async throws -> Data? {
        guard userID != nil else {
            throw CloudCompanionError.notAuthenticated
        }

        let remotePath = CloudPath.companionPath(fileId: fileId, type: .chat)

        do {
            let data = try await gcs.downloadData(from: remotePath)
            Log.debug("Loaded chat data for fileId: \(fileId), size: \(data.count)", category: .cloudSync)
            return data
        } catch let error as GCSStorageError {
            if case .downloadFailed = error {
                return nil
            }
            throw error
        } catch {
            return nil
        }
    }

    func delete(for fileId: String) async throws {
        guard userID != nil else {
            throw CloudCompanionError.notAuthenticated
        }

        let remotePath = CloudPath.companionPath(fileId: fileId, type: .chat)

        do {
            try await gcs.deleteFile(at: remotePath)
            Log.debug("Deleted chat data for fileId: \(fileId)", category: .cloudSync)
        } catch GCSStorageError.deleteFailed {
            // File didn't exist, that's ok
        }
    }
}

final class CloudFlashcardStore: CloudCompanionStore {
    static let shared = CloudFlashcardStore()

    private let gcs = GCSStorageService.shared

    private var userID: String? {
        Auth.auth().currentUser?.uid
    }

    private init() {}

    func save(_ data: Data, for fileId: String) async throws {
        guard userID != nil else {
            throw CloudCompanionError.notAuthenticated
        }

        let remotePath = CloudPath.companionPath(fileId: fileId, type: .flashcards)
        try await gcs.uploadData(data, to: remotePath)

        Log.debug("Saved flashcards for fileId: \(fileId), size: \(data.count)", category: .cloudSync)
    }

    func load(for fileId: String) async throws -> Data? {
        guard userID != nil else {
            throw CloudCompanionError.notAuthenticated
        }

        let remotePath = CloudPath.companionPath(fileId: fileId, type: .flashcards)

        do {
            let data = try await gcs.downloadData(from: remotePath)
            Log.debug("Loaded flashcards for fileId: \(fileId), size: \(data.count)", category: .cloudSync)
            return data
        } catch let error as GCSStorageError {
            if case .downloadFailed = error {
                return nil
            }
            throw error
        } catch {
            return nil
        }
    }

    func delete(for fileId: String) async throws {
        guard userID != nil else {
            throw CloudCompanionError.notAuthenticated
        }

        let remotePath = CloudPath.companionPath(fileId: fileId, type: .flashcards)

        do {
            try await gcs.deleteFile(at: remotePath)
            Log.debug("Deleted flashcards for fileId: \(fileId)", category: .cloudSync)
        } catch GCSStorageError.deleteFailed {
            // File didn't exist
        }
    }
}

final class CloudMCStore: CloudCompanionStore {
    static let shared = CloudMCStore()

    private let gcs = GCSStorageService.shared

    private var userID: String? {
        Auth.auth().currentUser?.uid
    }

    private init() {}

    func save(_ data: Data, for fileId: String) async throws {
        guard userID != nil else {
            throw CloudCompanionError.notAuthenticated
        }

        let remotePath = CloudPath.companionPath(fileId: fileId, type: .mccards)
        try await gcs.uploadData(data, to: remotePath)

        Log.debug("Saved MC cards for fileId: \(fileId), size: \(data.count)", category: .cloudSync)
    }

    func load(for fileId: String) async throws -> Data? {
        guard userID != nil else {
            throw CloudCompanionError.notAuthenticated
        }

        let remotePath = CloudPath.companionPath(fileId: fileId, type: .mccards)

        do {
            let data = try await gcs.downloadData(from: remotePath)
            Log.debug("Loaded MC cards for fileId: \(fileId), size: \(data.count)", category: .cloudSync)
            return data
        } catch let error as GCSStorageError {
            if case .downloadFailed = error {
                return nil
            }
            throw error
        } catch {
            return nil
        }
    }

    func delete(for fileId: String) async throws {
        guard userID != nil else {
            throw CloudCompanionError.notAuthenticated
        }

        let remotePath = CloudPath.companionPath(fileId: fileId, type: .mccards)

        do {
            try await gcs.deleteFile(at: remotePath)
            Log.debug("Deleted MC cards for fileId: \(fileId)", category: .cloudSync)
        } catch GCSStorageError.deleteFailed {
            // File didn't exist
        }
    }
}
