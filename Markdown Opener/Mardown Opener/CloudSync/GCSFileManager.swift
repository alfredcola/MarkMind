//
//  GCSFileManager.swift
//  MarkMind
//
//  Core file operations for GCS-only architecture with local cache
//

import Foundation
import FirebaseAuth
import PDFKit
import ZIPFoundation
import Combine
import FirebaseStorage

final class GCSFileManager: ObservableObject {
    static let shared = GCSFileManager()

    private let gcs = GCSStorageService.shared
    private let fileIdManager = CloudFileIDManager.shared
    private let fileManager = FileManager.default
    private let quotaManager = StorageQuotaManager.shared

    private let cacheDirectory: URL
    private let maxCacheSize: Int64 = 50 * 1024 * 1024 // 50MB

    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isListing = false

    private var userID: String? {
        Auth.auth().currentUser?.uid
    }

    private init() {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesURL.appendingPathComponent("GCSFileCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - List Documents

    func listDocuments() async throws -> [CloudFileInfo] {
        guard userID != nil else {
            throw GCSFileManagerError.notAuthenticated
        }

        await MainActor.run { isListing = true }
        defer {
            Task { @MainActor in isListing = false }
        }

        let pathToFileIdMap = try await fileIdManager.getAllPaths()

        let storageRefs = try await gcs.listFiles(prefix: CloudPath.documentsPrefix)

        var files: [CloudFileInfo] = []

        for ref in storageRefs {
            let fullPath = ref.fullPath
            let documentsPath = "/\(CloudPath.documentsPrefix)/"
            guard fullPath.contains(documentsPath) else { continue }

            let relativePath = fullPath.components(separatedBy: documentsPath).last ?? ""
            guard !relativePath.isEmpty else { continue }

            let fileId = pathToFileIdMap[relativePath] ?? UUID().uuidString

            let metadata = try? await ref.getMetadata()
            let size = metadata?.size ?? 0
            let modified = metadata?.updated ?? Date()

            let name = (relativePath as NSString).lastPathComponent

            files.append(CloudFileInfo(
                id: fileId,
                path: relativePath,
                name: name,
                size: size,
                modified: modified,
                isDirectory: false
            ))
        }

        let sorted = files.sorted { $0.modified > $1.modified }
        Log.debug("Listed \(sorted.count) documents from GCS", category: .cloudSync)

        return sorted
    }

    // MARK: - Load Document

    func load(_ path: String) async throws -> DocumentData {
        guard userID != nil else {
            throw GCSFileManagerError.notAuthenticated
        }

        await MainActor.run { isLoading = true }
        defer {
            Task { @MainActor in isLoading = false }
        }

        // Check local cache first
        if let cachedData = loadFromCache(path: path) {
            Log.debug("Loaded \(path) from local cache", category: .cloudSync)
            return cachedData
        }

        // Download from GCS
        let gcsPath = CloudPath.documentPath(path)
        let data = try await gcs.downloadData(from: gcsPath)

        // Save to cache
        saveToCache(data: data, path: path)

        // Parse and return
        let result = try parseDocumentData(data, path: path)

        Log.debug("Loaded \(path) from GCS, size: \(data.count)", category: .cloudSync)

        return result
    }

    func loadData(_ path: String) async throws -> Data {
        guard userID != nil else {
            throw GCSFileManagerError.notAuthenticated
        }

        if let cachedData = loadDataFromCache(path: path) {
            return cachedData
        }

        let gcsPath = CloudPath.documentPath(path)
        let data = try await gcs.downloadData(from: gcsPath)
        saveToCache(data: data, path: path)

        return data
    }

    // MARK: - Save Document

    func save(content: String, to path: String) async throws {
        guard userID != nil else {
            throw GCSFileManagerError.notAuthenticated
        }

        await MainActor.run { isSaving = true }
        defer {
            Task { @MainActor in isSaving = false }
        }

        guard let data = content.data(using: .utf8) else {
            throw GCSFileManagerError.encodingFailed
        }

        try await saveData(data, to: path)
    }

    func saveData(_ data: Data, to path: String) async throws {
        guard userID != nil else {
            throw GCSFileManagerError.notAuthenticated
        }

        await MainActor.run { isSaving = true }
        defer {
            Task { @MainActor in isSaving = false }
        }

        let fileSize = Int64(data.count)

        let quotaResult = quotaManager.checkQuota(for: fileSize)
        guard quotaResult.allowed else {
            throw GCSFileManagerError.quotaExceeded(quotaResult.reason ?? "Storage quota exceeded")
        }

        let tempURL = cacheDirectory.appendingPathComponent("temp-\(UUID().uuidString)")
        try data.write(to: tempURL)

        defer {
            try? fileManager.removeItem(at: tempURL)
        }

        let gcsPath = CloudPath.documentPath(path)
        try await gcs.uploadFile(localURL: tempURL, to: gcsPath)

        if let fileId = try await fileIdManager.getFileId(for: path) {
            try await fileIdManager.updateName(for: fileId, name: URL(fileURLWithPath: path).lastPathComponent)
        } else {
            _ = try await fileIdManager.createFileID(for: path, name: URL(fileURLWithPath: path).lastPathComponent)
        }

        quotaManager.updateUsageAfterUpload(fileSize: fileSize)
        saveToCache(data: data, path: path)

        Log.debug("Saved document to GCS: \(path)", category: .cloudSync)
    }

    // MARK: - Save As (New File)

    func saveAs(content: String, suggestedName: String?) async throws -> CloudFileInfo {
        Log.info("saveAs called: suggestedName=\(suggestedName ?? "nil"), content length=\(content.count)", category: .cloudSync)

        guard let uid = userID else {
            Log.error("saveAs: not authenticated", category: .cloudSync)
            throw GCSFileManagerError.notAuthenticated
        }
        Log.info("saveAs: userID=\(uid)", category: .cloudSync)

        await MainActor.run { isSaving = true }
        defer {
            Task { @MainActor in isSaving = false }
        }

        let baseName = suggestedName ?? "Untitled.md"
        let sanitized = CloudPath.sanitizeFilename(baseName)
        Log.info("saveAs: sanitized=\(sanitized)", category: .cloudSync)

        let filename = await ensureUniqueFilename(sanitized)
        Log.info("saveAs: filename=\(filename)", category: .cloudSync)

        let path = CloudPath.documentPath(filename)
        Log.info("saveAs: path=\(path)", category: .cloudSync)

        guard let data = content.data(using: .utf8) else {
            Log.error("saveAs: UTF-8 encoding failed", category: .cloudSync)
            throw GCSFileManagerError.encodingFailed
        }
        Log.info("saveAs: data size=\(data.count)", category: .cloudSync)

        let fileSize = Int64(data.count)

        let quotaResult = quotaManager.checkQuota(for: fileSize)
        Log.info("saveAs: quota allowed=\(quotaResult.allowed)", category: .cloudSync)
        guard quotaResult.allowed else {
            throw GCSFileManagerError.quotaExceeded(quotaResult.reason ?? "Storage quota exceeded")
        }

        let tempURL = cacheDirectory.appendingPathComponent("temp-\(UUID().uuidString)")
        Log.info("saveAs: writing to tempURL=\(tempURL)", category: .cloudSync)
        try data.write(to: tempURL)

        defer {
            try? fileManager.removeItem(at: tempURL)
        }

        Log.info("saveAs: calling gcs.uploadFile to path=\(path)", category: .cloudSync)
        try await gcs.uploadFile(localURL: tempURL, to: path)
        Log.info("saveAs: upload complete", category: .cloudSync)

        Log.info("saveAs: creating fileID in Firestore", category: .cloudSync)
        let fileId = try await fileIdManager.createFileID(for: filename, name: filename)
        Log.info("saveAs: fileId=\(fileId)", category: .cloudSync)

        quotaManager.updateUsageAfterUpload(fileSize: fileSize)

        let metadata = try? await gcs.getMetadata(for: path)

        let cloudFileInfo = CloudFileInfo(
            id: fileId,
            path: filename,
            name: filename,
            size: Int64(data.count),
            modified: metadata?.updated ?? Date(),
            isDirectory: false
        )

        saveToCache(data: data, path: filename)

        Log.info("saveAs complete: \(filename), fileId: \(fileId)", category: .cloudSync)

        return cloudFileInfo
    }

    func saveDataAs(_ data: Data, suggestedName: String?) async throws -> CloudFileInfo {
        Log.info("saveDataAs called: suggestedName=\(suggestedName ?? "nil")", category: .cloudSync)

        guard let uid = userID else {
            Log.error("saveDataAs: not authenticated", category: .cloudSync)
            throw GCSFileManagerError.notAuthenticated
        }
        Log.info("saveDataAs: userID=\(uid)", category: .cloudSync)

        await MainActor.run { isSaving = true }
        defer {
            Task { @MainActor in isSaving = false }
        }

        let baseName = suggestedName ?? "Untitled.dat"
        let sanitized = CloudPath.sanitizeFilename(baseName)
        Log.info("saveDataAs: sanitized=\(sanitized)", category: .cloudSync)

        let filename = await ensureUniqueFilename(sanitized)
        Log.info("saveDataAs: unique filename=\(filename)", category: .cloudSync)

        let path = CloudPath.documentPath(filename)
        Log.info("saveDataAs: GCS path=\(path)", category: .cloudSync)

        let fileSize = Int64(data.count)
        Log.info("saveDataAs: fileSize=\(fileSize)", category: .cloudSync)

        let quotaResult = quotaManager.checkQuota(for: fileSize)
        Log.info("saveDataAs: quota check allowed=\(quotaResult.allowed)", category: .cloudSync)
        guard quotaResult.allowed else {
            throw GCSFileManagerError.quotaExceeded(quotaResult.reason ?? "Storage quota exceeded")
        }

        let tempURL = cacheDirectory.appendingPathComponent("temp-\(UUID().uuidString)")
        Log.info("saveDataAs: tempURL=\(tempURL)", category: .cloudSync)
        try data.write(to: tempURL)

        defer {
            try? fileManager.removeItem(at: tempURL)
        }

        Log.info("saveDataAs: calling gcs.uploadFile", category: .cloudSync)
        try await gcs.uploadFile(localURL: tempURL, to: path)
        Log.info("saveDataAs: upload complete", category: .cloudSync)

        Log.info("saveDataAs: creating fileID in Firestore", category: .cloudSync)
        let fileId = try await fileIdManager.createFileID(for: filename, name: filename)
        Log.info("saveDataAs: fileId=\(fileId)", category: .cloudSync)

        quotaManager.updateUsageAfterUpload(fileSize: fileSize)

        let metadata = try? await gcs.getMetadata(for: path)

        let cloudFileInfo = CloudFileInfo(
            id: fileId,
            path: filename,
            name: filename,
            size: Int64(data.count),
            modified: metadata?.updated ?? Date(),
            isDirectory: false
        )

        saveToCache(data: data, path: filename)

        Log.info("saveDataAs complete: \(filename), fileId: \(fileId)", category: .cloudSync)

        return cloudFileInfo
    }

    // MARK: - Delete Document

    func delete(_ path: String) async throws {
        guard userID != nil else {
            throw GCSFileManagerError.notAuthenticated
        }

        // Get FileID first
        guard let fileId = try await fileIdManager.getFileId(for: path) else {
            throw GCSFileManagerError.fileNotFound
        }

        // Get file size before deletion for quota update
        var fileSize: Int64 = 0
        if let fileInfo = try? await fileIdManager.getFileInfo(for: fileId) {
            fileSize = try await getFileSize(path: path)
        }

        // Delete from GCS
        let gcsPath = CloudPath.documentPath(path)
        try await gcs.deleteFile(at: gcsPath)

        // Delete companion data
        try? await CloudChatStore.shared.delete(for: fileId)
        try? await CloudFlashcardStore.shared.delete(for: fileId)
        try? await CloudMCStore.shared.delete(for: fileId)

        // Delete metadata folder
        let metadataPath = CloudPath.metadataPath(for: fileId)
        try? await gcs.deleteFolder(at: metadataPath)

        // Delete FileID from Firestore
        try await fileIdManager.deleteFileID(fileId)

        // Update quota usage
        if fileSize > 0 {
            quotaManager.updateUsageAfterDelete(fileSize: fileSize)
        }

        // Remove from cache
        removeFromCache(path: path)

        Log.debug("Deleted document from GCS: \(path)", category: .cloudSync)
    }

    func deleteAllFiles() async throws {
        guard userID != nil else {
            throw GCSFileManagerError.notAuthenticated
        }

        let files = try await listDocuments()
        for file in files {
            try? await delete(file.path)
        }
        Log.debug("Deleted all documents from GCS", category: .cloudSync)
    }

    private func getFileSize(path: String) async throws -> Int64 {
        let gcsPath = CloudPath.documentPath(path)
        let metadata = try await gcs.getMetadata(for: gcsPath)
        return metadata.size
    }

    // MARK: - Rename Document

    func rename(_ path: String, to newName: String) async throws -> CloudFileInfo {
        guard userID != nil else {
            throw GCSFileManagerError.notAuthenticated
        }

        // Get current content
        let content = try await load(path)
        let newSanitized = CloudPath.sanitizeFilename(newName)
        let newFilename = await ensureUniqueFilename(newSanitized)

        // Save to new location
        let newPath = CloudPath.documentPath(newFilename)
        guard let data = content.text.data(using: .utf8) else {
            throw GCSFileManagerError.encodingFailed
        }

        let tempURL = cacheDirectory.appendingPathComponent("temp-\(UUID().uuidString)")
        try data.write(to: tempURL)

        defer {
            try? fileManager.removeItem(at: tempURL)
        }

        // Upload to new GCS path
        try await gcs.uploadFile(localURL: tempURL, to: newPath)

        // Update FileID
        guard let fileId = try await fileIdManager.getFileId(for: path) else {
            throw GCSFileManagerError.fileNotFound
        }

        try await fileIdManager.updatePath(for: fileId, to: newFilename)
        try await fileIdManager.updateName(for: fileId, name: newFilename)

        // Delete old file
        let oldGcsPath = CloudPath.documentPath(path)
        try? await gcs.deleteFile(at: oldGcsPath)

        // Update cache
        removeFromCache(path: path)
        saveToCache(data: data, path: newFilename)

        let metadata = try? await gcs.getMetadata(for: newPath)

        let cloudFileInfo = CloudFileInfo(
            id: fileId,
            path: newFilename,
            name: newFilename,
            size: Int64(data.count),
            modified: metadata?.updated ?? Date(),
            isDirectory: false
        )

        Log.debug("Renamed document: \(path) -> \(newFilename)", category: .cloudSync)

        return cloudFileInfo
    }

    // MARK: - File ID Lookup

    func getFileId(for path: String) async -> String? {
        return try? await fileIdManager.getFileId(for: path)
    }

    func getFileInfo(for path: String) async throws -> FileIdInfo? {
        return try await fileIdManager.getFileInfoByPath(path)
    }

    // MARK: - Cache Management

    private func loadFromCache(path: String) -> DocumentData? {
        guard let data = loadDataFromCache(path: path) else { return nil }
        return try? parseDocumentData(data, path: path)
    }

    private func loadDataFromCache(path: String) -> Data? {
        let cacheURL = cacheFileURL(for: path)
        guard fileManager.fileExists(atPath: cacheURL.path) else { return nil }

        // Check if cache is stale (older than 24 hours)
        let attrs = try? fileManager.attributesOfItem(atPath: cacheURL.path)
        if let modDate = attrs?[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) > 86400 {
            try? fileManager.removeItem(at: cacheURL)
            return nil
        }

        return try? Data(contentsOf: cacheURL)
    }

    private func saveToCache(data: Data, path: String) {
        let cacheURL = cacheFileURL(for: path)

        // Ensure cache directory exists
        let dir = cacheURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        try? data.write(to: cacheURL)

        // Evict if over limit
        evictCacheIfNeeded()
    }

    private func removeFromCache(path: String) {
        let cacheURL = cacheFileURL(for: path)
        try? fileManager.removeItem(at: cacheURL)
    }

    private func cacheFileURL(for path: String) -> URL {
        let filename = path.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory.appendingPathComponent(filename)
    }

    private func evictCacheIfNeeded() {
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }

        var totalSize: Int64 = 0
        var files: [(url: URL, size: Int64, date: Date)] = []

        for url in contents {
            let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(attrs?.fileSize ?? 0)
            let date = attrs?.contentModificationDate ?? .distantPast
            totalSize += size
            files.append((url, size, date))
        }

        guard totalSize > maxCacheSize else { return }

        // Sort by date (oldest first) and delete until under limit
        files.sort { $0.date < $1.date }

        for file in files {
            guard totalSize > maxCacheSize else { break }
            try? fileManager.removeItem(at: file.url)
            totalSize -= file.size
        }

        Log.debug("Evicted cache, freed \(totalSize) bytes", category: .cloudSync)
    }

    // MARK: - Helpers

    private func ensureUniqueFilename(_ baseName: String) async -> String {
        let ext = (baseName as NSString).pathExtension
        let nameWithoutExt = (baseName as NSString).deletingPathExtension

        var candidate = baseName
        var counter = 2

        var allPaths: [String: String] = [:]
        do {
            allPaths = try await fileIdManager.getAllPaths()
        } catch {
            allPaths = [:]
        }
        let existingNames = Set(allPaths.keys)

        while existingNames.contains(candidate) {
            if ext.isEmpty {
                candidate = "\(nameWithoutExt) \(counter)"
            } else {
                candidate = "\(nameWithoutExt) \(counter).\(ext)"
            }
            counter += 1
        }

        return candidate
    }

    private func parseDocumentData(_ data: Data, path: String) throws -> DocumentData {
        let ext = (path as NSString).pathExtension.lowercased()

        switch ext {
        case "md", "txt":
            guard let text = String(data: data, encoding: .utf8) else {
                throw GCSFileManagerError.encodingFailed
            }
            return DocumentData(text: text, attributed: nil, pdf: nil)

        case "docx":
            let tempURL = cacheDirectory.appendingPathComponent("docx-\(UUID().uuidString).docx")
            try data.write(to: tempURL)
            defer { try? fileManager.removeItem(at: tempURL) }
            let text = try DocxPlainTextExtractor.extract(from: tempURL)
            return DocumentData(text: text, attributed: nil, pdf: nil)

        case "pptx":
            let tempURL = cacheDirectory.appendingPathComponent("pptx-\(UUID().uuidString).pptx")
            try data.write(to: tempURL)
            defer { try? fileManager.removeItem(at: tempURL) }
            let text = try PPTXPlainTextExtractor.extract(from: tempURL)
            return DocumentData(text: text, attributed: nil, pdf: nil)

        case "pdf":
            let tempURL = cacheDirectory.appendingPathComponent("pdf-\(UUID().uuidString).pdf")
            try data.write(to: tempURL)
            defer { try? fileManager.removeItem(at: tempURL) }
            guard let doc = PDFDocument(url: tempURL) else {
                throw GCSFileManagerError.invalidPDF
            }
            let pageCount = doc.pageCount
            if pageCount > 100 {
                var text = ""
                for i in 0..<min(50, pageCount) {
                    if let page = doc.page(at: i), let t = page.string {
                        text.append(t + "\n")
                    }
                }
                return DocumentData(text: text, attributed: nil, pdf: doc, isPartial: true)
            }
            var text = ""
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i), let t = page.string {
                    text.append(t + "\n")
                }
            }
            return DocumentData(text: text, attributed: nil, pdf: doc)

        default:
            throw GCSFileManagerError.unsupportedFileType
        }
    }

    // MARK: - Clear Cache

    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        Log.debug("Cleared GCS file cache", category: .cloudSync)
    }

    func getCacheSize() -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for url in contents {
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            total += Int64(size ?? 0)
        }
        return total
    }
}

enum GCSFileManagerError: LocalizedError {
    case notAuthenticated
    case fileNotFound
    case encodingFailed
    case invalidPDF
    case unsupportedFileType
    case networkError
    case quotaExceeded(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "User not authenticated"
        case .fileNotFound: return "File not found"
        case .encodingFailed: return "Failed to encode/decode file content"
        case .invalidPDF: return "Invalid PDF document"
        case .unsupportedFileType: return "Unsupported file type"
        case .networkError: return "Network error occurred"
        case .quotaExceeded(let reason): return reason
        }
    }
}
