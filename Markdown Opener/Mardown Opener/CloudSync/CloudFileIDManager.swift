//
//  CloudFileIDManager.swift
//  MarkMind
//
//  FileID management stored in Firestore for GCS-only architecture
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

final class CloudFileIDManager {
    static let shared = CloudFileIDManager()

    private let db = Firestore.firestore()
    private let collectionName = "fileIds"

    private var userID: String? {
        Auth.auth().currentUser?.uid
    }

    private var baseCollection: CollectionReference? {
        guard let uid = userID else { return nil }
        return db.collection("users").document(uid).collection(collectionName)
    }

    private init() {}

    func createFileID(for path: String, name: String) async throws -> String {
        guard let collection = baseCollection else {
            throw CloudFileIDError.notAuthenticated
        }

        let fileId = UUID().uuidString
        let now = Date()

        let data: [String: Any] = [
            "path": path,
            "name": name,
            "createdAt": Timestamp(date: now),
            "modifiedAt": Timestamp(date: now)
        ]

        try await collection.document(fileId).setData(data)

        Log.debug("Created FileID \(fileId) for path \(path)", category: .cloudSync)

        return fileId
    }

    func getFileInfo(for fileId: String) async throws -> FileIdInfo? {
        guard let collection = baseCollection else {
            throw CloudFileIDError.notAuthenticated
        }

        let doc = try await collection.document(fileId).getDocument()

        guard doc.exists, let data = doc.data() else {
            return nil
        }

        return parseFileIdInfo(fileId: fileId, data: data)
    }

    func getFileInfoByPath(_ path: String) async throws -> FileIdInfo? {
        guard let collection = baseCollection else {
            throw CloudFileIDError.notAuthenticated
        }

        let query = collection.whereField("path", isEqualTo: path).limit(to: 1)
        let snapshot = try await query.getDocuments()

        guard let doc = snapshot.documents.first else {
            return nil
        }

        return parseFileIdInfo(fileId: doc.documentID, data: doc.data())
    }

    func getPath(for fileId: String) async -> String? {
        guard let collection = baseCollection else { return nil }

        do {
            let doc = try await collection.document(fileId).getDocument()
            return doc.data()?["path"] as? String
        } catch {
            return nil
        }
    }

    func getFileId(for path: String) async -> String? {
        guard let collection = baseCollection else { return nil }

        do {
            let query = collection.whereField("path", isEqualTo: path).limit(to: 1)
            let snapshot = try await query.getDocuments()

            return snapshot.documents.first?.documentID
        } catch {
            return nil
        }
    }

    func updatePath(for fileId: String, to newPath: String) async throws {
        guard let collection = baseCollection else {
            throw CloudFileIDError.notAuthenticated
        }

        try await collection.document(fileId).updateData([
            "path": newPath,
            "modifiedAt": Timestamp(date: Date())
        ])

        Log.debug("Updated FileID \(fileId) path to \(newPath)", category: .cloudSync)
    }

    func updateName(for fileId: String, name: String) async throws {
        guard let collection = baseCollection else {
            throw CloudFileIDError.notAuthenticated
        }

        try await collection.document(fileId).updateData([
            "name": name,
            "modifiedAt": Timestamp(date: Date())
        ])
    }

    func deleteFileID(_ fileId: String) async throws {
        guard let collection = baseCollection else {
            throw CloudFileIDError.notAuthenticated
        }

        try await collection.document(fileId).delete()

        Log.debug("Deleted FileID \(fileId)", category: .cloudSync)
    }

    func listAllFileIDs() async throws -> [FileIdInfo] {
        guard let collection = baseCollection else {
            throw CloudFileIDError.notAuthenticated
        }

        let snapshot = try await collection.getDocuments()

        return snapshot.documents.compactMap { doc in
            parseFileIdInfo(fileId: doc.documentID, data: doc.data())
        }
    }

    func getAllPaths() async throws -> [String: String] {
        let fileIds = try await listAllFileIDs()
        var result: [String: String] = [:]
        for info in fileIds {
            result[info.path] = info.fileId
        }
        return result
    }

    private func parseFileIdInfo(fileId: String, data: [String: Any]) -> FileIdInfo? {
        guard let path = data["path"] as? String,
              let name = data["name"] as? String,
              let createdAtTimestamp = data["createdAt"] as? Timestamp,
              let modifiedAtTimestamp = data["modifiedAt"] as? Timestamp else {
            return nil
        }

        return FileIdInfo(
            fileId: fileId,
            path: path,
            name: name,
            createdAt: createdAtTimestamp.dateValue(),
            modifiedAt: modifiedAtTimestamp.dateValue()
        )
    }
}

enum CloudFileIDError: LocalizedError {
    case notAuthenticated
    case fileNotFound
    case invalidData

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "User not authenticated"
        case .fileNotFound: return "File not found"
        case .invalidData: return "Invalid file data"
        }
    }
}
