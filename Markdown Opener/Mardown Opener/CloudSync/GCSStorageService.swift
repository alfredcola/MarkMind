//
//  GCSStorageService.swift
//  MarkMind
//
//  Firebase Storage service for cloud sync
//

import Foundation
import FirebaseStorage
import FirebaseAuth
import Combine

enum GCSStorageError: LocalizedError {
    case notAuthenticated
    case uploadFailed
    case downloadFailed
    case deleteFailed
    case fileTooLarge
    case networkError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "User not authenticated"
        case .uploadFailed: return "Failed to upload file"
        case .downloadFailed: return "Failed to download file"
        case .deleteFailed: return "Failed to delete file"
        case .fileTooLarge: return "File exceeds 10MB limit"
        case .networkError: return "Network error occurred"
        }
    }
}

final class GCSStorageService: ObservableObject {
    static let shared = GCSStorageService()

    private let storage = Storage.storage()
    private let maxFileSize: Int64 = 10 * 1024 * 1024 // 10MB

    @Published private(set) var isUploading = false
    @Published private(set) var isDownloading = false
    @Published private(set) var uploadProgress: Double = 0
    @Published private(set) var downloadProgress: Double = 0

    private var userID: String? {
        Auth.auth().currentUser?.uid
    }

    private var basePath: String {
        guard let uid = userID else { return "" }
        return "users/\(uid)"
    }

    private init() {}

    func uploadFile(localURL: URL, to remotePath: String) async throws {
        guard let uid = userID else {
            throw GCSStorageError.notAuthenticated
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64 ?? 0
        if fileSize > maxFileSize {
            throw GCSStorageError.fileTooLarge
        }

        await MainActor.run {
            isUploading = true
            uploadProgress = 0
        }

        defer {
            Task { @MainActor in
                isUploading = false
                uploadProgress = 0
            }
        }

        let fullPath = "\(basePath)/\(remotePath)"
        Log.info("uploadFile called: fullPath=\(fullPath), fileSize=\(fileSize)", category: .cloudSync)
        let storageRef = storage.reference(withPath: fullPath)

        let metadata = StorageMetadata()
        metadata.contentType = mimeType(for: localURL)
        metadata.customMetadata = [
            "userID": uid,
            "originalFileName": localURL.lastPathComponent,
            "uploadedAt": ISO8601DateFormatter().string(from: Date())
        ]

        Log.debug("Uploading to: \(fullPath), size: \(fileSize)", category: .cloudSync)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let uploadTask = storageRef.putFile(from: localURL, metadata: metadata) { metadata, error in
                if let error = error {
                    Log.error("Upload failed: \(fullPath)", category: .cloudSync, error: error)
                    continuation.resume(throwing: error)
                } else if metadata != nil {
                    Log.debug("Upload succeeded: \(fullPath)", category: .cloudSync)
                    continuation.resume()
                } else {
                    Log.warning("Upload returned no metadata and no error: \(fullPath)", category: .cloudSync)
                    continuation.resume(throwing: GCSStorageError.uploadFailed)
                }
            }

            uploadTask.observe(.progress) { snapshot in
                guard let count = snapshot.progress?.completedUnitCount,
                      let total = snapshot.progress?.totalUnitCount,
                      total > 0 else { return }
                Task { @MainActor in
                    self.uploadProgress = Double(count) / Double(total)
                }
            }
        }
    }

    func uploadData(_ data: Data, to remotePath: String) async throws {
        guard let uid = userID else {
            throw GCSStorageError.notAuthenticated
        }

        if data.count > Int(maxFileSize) {
            throw GCSStorageError.fileTooLarge
        }

        await MainActor.run {
            isUploading = true
            uploadProgress = 0
        }

        defer {
            Task { @MainActor in
                isUploading = false
                uploadProgress = 0
            }
        }

        let fullPath = "\(basePath)/\(remotePath)"
        let storageRef = storage.reference(withPath: fullPath)

        let metadata = StorageMetadata()
        metadata.contentType = "application/octet-stream"
        metadata.customMetadata = [
            "userID": uid,
            "uploadedAt": ISO8601DateFormatter().string(from: Date()),
            "isCRDTState": "true"
        ]

        Log.debug("Uploading CRDT state to: \(fullPath), size: \(data.count)", category: .cloudSync)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let uploadTask = storageRef.putData(data, metadata: metadata) { metadata, error in
                if let error = error {
                    Log.error("Upload failed: \(fullPath)", category: .cloudSync, error: error)
                    continuation.resume(throwing: error)
                } else if metadata != nil {
                    Log.debug("Upload succeeded: \(fullPath)", category: .cloudSync)
                    continuation.resume()
                } else {
                    continuation.resume(throwing: GCSStorageError.uploadFailed)
                }
            }

            uploadTask.observe(.progress) { snapshot in
                guard let count = snapshot.progress?.completedUnitCount,
                      let total = snapshot.progress?.totalUnitCount,
                      total > 0 else { return }
                Task { @MainActor in
                    self.uploadProgress = Double(count) / Double(total)
                }
            }
        }
    }

    func downloadFile(from remotePath: String, to localURL: URL) async throws {
        guard let uid = userID else {
            throw GCSStorageError.notAuthenticated
        }

        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
        }

        defer {
            Task { @MainActor in
                isDownloading = false
                downloadProgress = 0
            }
        }

        let fullPath = "\(basePath)/\(remotePath)"
        let storageRef = storage.reference(withPath: fullPath)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let downloadTask = storageRef.write(toFile: localURL) { result in
                switch result {
                case .success:
                    Log.debug("Download succeeded: \(fullPath)", category: .cloudSync)
                    continuation.resume()
                case .failure(let error):
                    Log.error("Download failed: \(fullPath)", category: .cloudSync, error: error)
                    continuation.resume(throwing: error)
                }
            }

            downloadTask.observe(.progress) { snapshot in
                guard let count = snapshot.progress?.completedUnitCount,
                      let total = snapshot.progress?.totalUnitCount,
                      total > 0 else { return }
                Task { @MainActor in
                    self.downloadProgress = Double(count) / Double(total)
                }
            }
        }
    }

    func deleteFile(at remotePath: String) async throws {
        guard let uid = userID else {
            throw GCSStorageError.notAuthenticated
        }

        let fullPath = "\(basePath)/\(remotePath)"
        let storageRef = storage.reference(withPath: fullPath)

        do {
            try await storageRef.delete()
        } catch {
            throw GCSStorageError.deleteFailed
        }
    }

    func deleteFolder(at remotePath: String) async throws {
        guard let uid = userID else {
            throw GCSStorageError.notAuthenticated
        }

        let fullPath = "\(basePath)/\(remotePath)"
        let folderRef = storage.reference(withPath: fullPath)

        do {
            let result = try await folderRef.listAll()
            for item in result.items {
                try await item.delete()
            }
            for prefix in result.prefixes {
                try await deleteFolder(at: prefix.fullPath.replacingOccurrences(of: "\(basePath)/", with: ""))
            }
        } catch {
            throw GCSStorageError.deleteFailed
        }
    }

    func downloadData(from remotePath: String) async throws -> Data {
        guard let uid = userID else {
            throw GCSStorageError.notAuthenticated
        }

        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
        }

        defer {
            Task { @MainActor in
                isDownloading = false
                downloadProgress = 0
            }
        }

        let fullPath = "\(basePath)/\(remotePath)"
        let storageRef = storage.reference(withPath: fullPath)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            storageRef.getData(maxSize: maxFileSize) { data, error in
                if let error = error {
                    Log.error("Download data failed: \(fullPath)", category: .cloudSync, error: error)
                    continuation.resume(throwing: error)
                } else if let data = data {
                    Log.debug("Download data succeeded: \(fullPath), size: \(data.count)", category: .cloudSync)
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: GCSStorageError.downloadFailed)
                }
            }
        }
    }

    func listFiles(prefix: String? = nil) async throws -> [StorageReference] {
        guard let uid = userID else {
            throw GCSStorageError.notAuthenticated
        }

        let searchPath: String
        if let prefix = prefix {
            searchPath = "\(basePath)/\(prefix)"
        } else {
            searchPath = basePath
        }
        let storageRef = storage.reference(withPath: searchPath)

        Log.debug("listFiles: searching at path: \(searchPath)", category: .cloudSync)

        do {
            let result = try await storageRef.listAll()
            Log.debug("listFiles: found \(result.items.count) items, \(result.prefixes.count) prefixes", category: .cloudSync)
            for item in result.items {
                Log.debug("listFiles: item path = \(item.fullPath)", category: .cloudSync)
            }
            return result.items
        } catch {
            Log.error("listFiles failed: \(error.localizedDescription)", category: .cloudSync)
            throw GCSStorageError.networkError
        }
    }

    func getMetadata(for remotePath: String) async throws -> StorageMetadata {
        guard let uid = userID else {
            throw GCSStorageError.notAuthenticated
        }

        let fullPath = "\(basePath)/\(remotePath)"
        let storageRef = storage.reference(withPath: fullPath)

        do {
            return try await storageRef.getMetadata()
        } catch {
            throw GCSStorageError.networkError
        }
    }

    func fileExists(at remotePath: String) async -> Bool {
        guard let uid = userID else { return false }

        let fullPath = "\(basePath)/\(remotePath)"
        let storageRef = storage.reference(withPath: fullPath)

        do {
            _ = try await storageRef.getMetadata()
            return true
        } catch {
            return false
        }
    }

    private func mimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        switch pathExtension {
        case "md", "markdown":
            return "text/markdown"
        case "txt":
            return "text/plain"
        case "pdf":
            return "application/pdf"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "pptx":
            return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppt":
            return "application/vnd.ms-powerpoint"
        default:
            return "application/octet-stream"
        }
    }
}
