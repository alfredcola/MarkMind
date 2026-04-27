//
//  GCSDocumentStore.swift
//  MarkMind
//
//  GCS-only implementation of DocumentRepository protocol
//

import Foundation
import Combine
import FirebaseAuth

final class GCSDocumentStore: DocumentRepository, ObservableObject {
    static let shared = GCSDocumentStore()

    private let gcsFileManager = GCSFileManager.shared
    private let fileIdManager = CloudFileIDManager.shared

    @Published private(set) var cloudFiles: [CloudFileInfo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var error: Error?

    private var cachedCloudFiles: [CloudFileInfo]?
    private var cachedCloudFilesDate: Date?
    private let cloudFilesCacheTTL: TimeInterval = 5.0

    private var authStateObserver: NSObjectProtocol?

    init() {
        setupAuthObserver()
        checkAuthState()
    }

    private func setupAuthObserver() {
        authStateObserver = NotificationCenter.default.addObserver(
            forName: .AuthStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkAuthState()
        }
    }

    private func checkAuthState() {
        isAuthenticated = Auth.auth().currentUser != nil
    }

    deinit {
        if let observer = authStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - DocumentRepository Protocol

    func listDocuments() throws -> [URL] {
        if let cached = cachedCloudFiles,
           let cachedDate = cachedCloudFilesDate,
           Date().timeIntervalSince(cachedDate) < cloudFilesCacheTTL {
            return cached.compactMap { urlFromPath($0.path) }
        }

        Task {
            try? await refreshCloudFiles()
        }

        if let cached = cachedCloudFiles {
            return cached.compactMap { urlFromPath($0.path) }
        }

        return []
    }

    func load(_ url: URL) throws -> DocumentData {
        guard let path = pathFromURL(url) else {
            throw GCSFileManagerError.fileNotFound
        }

        var result: DocumentData?
        var resultError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let data = try await gcsFileManager.load(path)
                result = data
            } catch {
                resultError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = resultError {
            throw error
        }

        guard let data = result else {
            throw GCSFileManagerError.networkError
        }

        return data
    }

    func loadAsync(_ url: URL) async throws -> DocumentData {
        guard let path = pathFromURL(url) else {
            throw GCSFileManagerError.fileNotFound
        }

        return try await gcsFileManager.load(path)
    }

    @discardableResult
    func saveAsync(content: String, to url: URL) async throws -> URL {
        guard let path = pathFromURL(url) else {
            throw GCSFileManagerError.fileNotFound
        }

        try await gcsFileManager.save(content: content, to: path)
        invalidateCloudFilesCache()
        return url
    }

    @discardableResult
    func save(content: String, to url: URL) throws -> URL {
        guard let path = pathFromURL(url) else {
            throw GCSFileManagerError.fileNotFound
        }

        var result: URL?
        var thrownError: Error?
        let lock = NSLock()

        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                do {
                    try await self.gcsFileManager.save(content: content, to: path)
                    lock.lock()
                    result = url
                    lock.unlock()
                } catch {
                    lock.lock()
                    thrownError = error
                    lock.unlock()
                }
            }
        }

        while result == nil && thrownError == nil {
            Thread.sleep(forTimeInterval: 0.01)
        }

        if let error = thrownError {
            throw error
        }

        invalidateCloudFilesCache()
        return url
    }

    @discardableResult
    func saveAsAsync(content: String, suggestedName: String?) async throws -> URL {
        Log.info("saveAsAsync called: suggestedName=\(suggestedName ?? "nil")", category: .cloudSync)
        let fileInfo = try await gcsFileManager.saveAs(content: content, suggestedName: suggestedName)
        invalidateCloudFilesCache()
        Log.info("saveAsAsync complete: \(fileInfo.name)", category: .cloudSync)
        return urlFromPath(fileInfo.path) ?? URL(fileURLWithPath: fileInfo.path)
    }

    @discardableResult
    func saveAs(content: String, suggestedName: String?) throws -> URL {
        Log.info("saveAs called (sync): suggestedName=\(suggestedName ?? "nil")", category: .cloudSync)

        var result: URL?
        var thrownError: Error?
        let group = DispatchGroup()
        group.enter()

        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                do {
                    let url = try await self.saveAsAsync(content: content, suggestedName: suggestedName)
                    result = url
                } catch {
                    thrownError = error
                }
                group.leave()
            }
        }

        let timeout = DispatchTime.now() + 30.0
        while group.wait(timeout: timeout) == .timedOut && result == nil && thrownError == nil {
            Thread.sleep(forTimeInterval: 0.1)
        }

        if let error = thrownError {
            Log.error("saveAs sync throwing: \(error.localizedDescription)", category: .cloudSync)
            throw error
        }

        guard let url = result else {
            Log.error("saveAs sync: no result", category: .cloudSync)
            throw GCSFileManagerError.networkError
        }

        return url
    }

    func uniqueFileURL(baseName: String) throws -> URL {
        let sanitized = CloudPath.sanitizeFilename(baseName)
        return URL(fileURLWithPath: sanitized)
    }

    @discardableResult
    func importIntoLibrary(from externalURL: URL) throws -> URL {
        let filename = externalURL.lastPathComponent
        Log.info("importIntoLibrary called: filename=\(filename)", category: .cloudSync)

        let data = try Data(contentsOf: externalURL)
        Log.info("importIntoLibrary: loaded \(data.count) bytes from \(filename)", category: .cloudSync)

        let ext = (filename as NSString).pathExtension.lowercased()

        let textExtensions = ["md", "txt", "docx", "pptx"]

        if textExtensions.contains(ext), let content = String(data: data, encoding: .utf8) {
            Log.info("importIntoLibrary: text file, using saveAs", category: .cloudSync)
            return try saveAs(content: content, suggestedName: filename)
        }

        Log.info("importIntoLibrary: binary file, using saveDataAs", category: .cloudSync)

        var result: CloudFileInfo?
        var thrownError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let fileInfo = try await gcsFileManager.saveDataAs(data, suggestedName: filename)
                result = fileInfo
                Log.info("importIntoLibrary: saveDataAs succeeded", category: .cloudSync)
            } catch {
                Log.error("importIntoLibrary: saveDataAs failed: \(error.localizedDescription)", category: .cloudSync, error: error)
                thrownError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = thrownError {
            throw error
        }

        guard let fileInfo = result else {
            throw GCSFileManagerError.networkError
        }

        invalidateCloudFilesCache()
        return urlFromPath(fileInfo.path) ?? URL(fileURLWithPath: fileInfo.path)
    }

    func importIntoLibraryAsync(from externalURL: URL) async throws -> URL {
        let filename = externalURL.lastPathComponent
        Log.info("importIntoLibraryAsync called: filename=\(filename)", category: .cloudSync)

        let data = try Data(contentsOf: externalURL)
        Log.info("importIntoLibraryAsync: loaded \(data.count) bytes", category: .cloudSync)

        let ext = (filename as NSString).pathExtension.lowercased()
        let textExtensions = ["md", "txt", "docx", "pptx"]

        if textExtensions.contains(ext), let content = String(data: data, encoding: .utf8) {
            Log.info("importIntoLibraryAsync: text file, using saveAs", category: .cloudSync)
            let fileInfo = try await gcsFileManager.saveAs(content: content, suggestedName: filename)
            invalidateCloudFilesCache()
            return urlFromPath(fileInfo.path) ?? URL(fileURLWithPath: fileInfo.path)
        }

        Log.info("importIntoLibraryAsync: binary file, using saveDataAs", category: .cloudSync)
        let fileInfo = try await gcsFileManager.saveDataAs(data, suggestedName: filename)
        invalidateCloudFilesCache()
        return urlFromPath(fileInfo.path) ?? URL(fileURLWithPath: fileInfo.path)
    }

    func delete(_ url: URL) throws {
        guard let path = pathFromURL(url) else {
            throw GCSFileManagerError.fileNotFound
        }

        Task {
            try? await gcsFileManager.delete(path)
        }
    }

    func deleteAsync(_ url: URL) async throws {
        guard let path = pathFromURL(url) else {
            throw GCSFileManagerError.fileNotFound
        }

        try await gcsFileManager.delete(path)
        invalidateCloudFilesCache()
    }

    func rename(_ url: URL, to newName: String) throws -> URL {
        guard let path = pathFromURL(url) else {
            throw GCSFileManagerError.fileNotFound
        }

        var result: CloudFileInfo?
        var resultError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let fileInfo = try await gcsFileManager.rename(path, to: newName)
                result = fileInfo
            } catch {
                resultError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = resultError {
            throw error
        }

        guard let fileInfo = result else {
            throw GCSFileManagerError.networkError
        }

        invalidateCloudFilesCache()
        return urlFromPath(fileInfo.path) ?? URL(fileURLWithPath: fileInfo.path)
    }

    // MARK: - Cloud File Operations

    func refreshCloudFiles() async throws -> [CloudFileInfo] {
        await MainActor.run { isLoading = true }
        error = nil

        defer {
            Task { @MainActor in isLoading = false }
        }

        let files = try await gcsFileManager.listDocuments()
        await MainActor.run {
            self.cloudFiles = files
            self.cachedCloudFiles = files
            self.cachedCloudFilesDate = Date()
        }
        return files
    }

    func loadCloudFile(path: String) async throws -> DocumentData {
        return try await gcsFileManager.load(path)
    }

    func deleteCloudFile(path: String) async throws {
        try await gcsFileManager.delete(path)
        invalidateCloudFilesCache()
    }

    func renameCloudFile(path: String, to newName: String) async throws -> CloudFileInfo {
        let result = try await gcsFileManager.rename(path, to: newName)
        invalidateCloudFilesCache()
        return result
    }

    func getCloudFileInfo(path: String) async throws -> CloudFileInfo? {
        let allFiles = try await gcsFileManager.listDocuments()
        return allFiles.first { $0.path == path }
    }

    func getCloudFileInfo(for url: URL) -> CloudFileInfo? {
        guard let path = pathFromURL(url) else { return nil }
        return cloudFiles.first { $0.path == path }
    }

    // MARK: - Cache Management

    func invalidateCloudFilesCache() {
        cachedCloudFiles = nil
        cachedCloudFilesDate = nil
    }

    // MARK: - URL/Path Mapping

    func pathFromURL(_ url: URL) -> String? {
        var path = url.path
        if path.hasPrefix("/") {
            path = String(path.dropFirst())
        }
        return path
    }

    func urlFromPath(_ path: String) -> URL? {
        URL(fileURLWithPath: "/" + path)
    }

    // MARK: - File ID Operations

    func getFileId(for path: String) async -> String? {
        return await gcsFileManager.getFileId(for: path)
    }

    func getFileId(for url: URL) async -> String? {
        return await getFileId(for: url.path)
    }
}

// MARK: - For compatibility with existing code

extension GCSDocumentStore {
    var documentsURL: URL {
        URL(fileURLWithPath: "/")
    }

    func listAllItems(in directoryURL: URL? = nil) throws -> [FileSystemItem] {
        return cloudFiles.map { FileSystemItem(url: URL(fileURLWithPath: $0.path), isDirectory: false) }
    }

    func createFolder(named name: String, in parentURL: URL? = nil) throws -> URL {
        throw GCSFileManagerError.unsupportedFileType
    }

    func moveItem(at sourceURL: URL, to destinationFolderURL: URL) throws {
    }
}
