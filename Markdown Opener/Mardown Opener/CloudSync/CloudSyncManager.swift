//
//  CloudSyncManager.swift
//  MarkMind
//
//  Simplified orchestrator for GCS-only cloud sync operations
//

import Foundation
import Combine
import FirebaseAuth

enum SyncStatus: String {
    case idle = "idle"
    case syncing = "syncing"
    case error = "error"
    case offline = "offline"
    case disabled = "disabled"
}

@MainActor
final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    @Published private(set) var status: SyncStatus = .idle
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var syncError: String?
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var pendingChangesCount: Int = 0
    @Published private(set) var syncProgress: Double = 0
    @Published private(set) var syncCurrentFile: String?

    private let gcsService = GCSStorageService.shared
    private let gcsFileManager = GCSFileManager.shared

    private let debounceInterval: TimeInterval = 2.0

    private var syncTask: Task<Void, Never>?
    private var debouncedSyncTask: Task<Void, Never>?

    private var isSyncing = false

    private var migrationCompleted: Bool {
        UserDefaults.standard.bool(forKey: "gcs_migration_completed")
    }

    private init() {
        loadEnabledState()
        setupAuthObserver()
    }

    private func loadEnabledState() {
        isEnabled = UserDefaults.standard.bool(forKey: "cloudSync_enabled")
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "cloudSync_enabled")

        if enabled {
            Task {
                await performSync()
            }
        } else {
            status = .disabled
        }
    }

    private func setupAuthObserver() {
        NotificationCenter.default.addObserver(
            forName: .AuthStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if Auth.auth().currentUser != nil && self.isEnabled {
                Task {
                    await self.performSync()
                }
            }
        }
    }

    func triggerSync() {
        guard isEnabled else { return }
        guard Auth.auth().currentUser != nil else {
            status = .offline
            return
        }

        debouncedSyncTask?.cancel()
        debouncedSyncTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await performSync()
        }
    }

    func cancelSync() {
        syncTask?.cancel()
        syncTask = nil
        isSyncing = false
        status = .idle
        syncProgress = 0
        syncCurrentFile = nil
    }

    func performSync() async {
        guard isEnabled else {
            status = .disabled
            return
        }

        guard Auth.auth().currentUser != nil else {
            status = .offline
            return
        }

        guard !isSyncing else { return }

        isSyncing = true
        status = .syncing
        syncError = nil
        syncProgress = 0
        syncCurrentFile = nil

        defer {
            isSyncing = false
            syncCurrentFile = nil
            if status == .syncing {
                status = .idle
            }
        }

        if !migrationCompleted {
            await performMigration()
        }

        await refreshCloudFiles()

        if status != .error {
            lastSyncTime = Date()
            syncProgress = 1.0
        }
    }

    private func refreshCloudFiles() async {
        syncCurrentFile = "Refreshing files..."

        do {
            _ = try await gcsFileManager.listDocuments()

            // Refresh storage quota
            await StorageQuotaManager.shared.refreshQuota()

            syncProgress = 1.0
        } catch {
            syncError = error.localizedDescription
            status = .error
        }
    }

    // MARK: - Migration

    private func performMigration() async {
        syncCurrentFile = "Migrating files to GCS..."
        syncProgress = 0

        Log.info("Starting GCS migration...", category: .cloudSync)

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let supportedExtensions = ["md", "txt", "pdf", "docx", "ppt", "pptx"]

        var files: [URL] = []

        if let enumerator = FileManager.default.enumerator(
            at: documentsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                if let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir == true {
                    continue
                }
                if url.path.contains(".markmind") { continue }
                if url.path.contains("Inbox/") { continue }

                let ext = url.pathExtension.lowercased()
                if supportedExtensions.contains(ext) {
                    files.append(url)
                }
            }
        }

        let totalFiles = files.count
        var migratedFiles = 0

        for url in files {
            guard !Task.isCancelled else { return }

            syncCurrentFile = "Migrating: \(url.lastPathComponent)"

            do {
                let data = try Data(contentsOf: url)
                guard let content = String(data: data, encoding: .utf8) else {
                    migratedFiles += 1
                    continue
                }

                let filename = url.lastPathComponent
                let cloudFileInfo = try await gcsFileManager.saveAs(content: content, suggestedName: filename)

                if let fileId = await gcsFileManager.getFileId(for: cloudFileInfo.path) {
                    await migrateCompanionFiles(from: url, fileId: fileId)
                }

                migratedFiles += 1
                syncProgress = Double(migratedFiles) / Double(totalFiles) * 0.5

            } catch {
                migratedFiles += 1
            }
        }

        UserDefaults.standard.set(true, forKey: "gcs_migration_completed")

        syncProgress = 1.0
        Log.info("GCS migration completed: \(migratedFiles) files", category: .cloudSync)
    }

    private func migrateCompanionFiles(from originalURL: URL, fileId: String) async {
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let directory = originalURL.deletingLastPathComponent()

        let chatURL = directory.appendingPathComponent("\(baseName).chat.json")
        if FileManager.default.fileExists(atPath: chatURL.path),
           let data = try? Data(contentsOf: chatURL) {
            try? await CloudChatStore.shared.save(data, for: fileId)
        }

        let flashcardURL = directory.appendingPathComponent("\(baseName).flashcards.json")
        if FileManager.default.fileExists(atPath: flashcardURL.path),
           let data = try? Data(contentsOf: flashcardURL) {
            try? await CloudFlashcardStore.shared.save(data, for: fileId)
        }

        let mcURL = directory.appendingPathComponent("\(baseName).mccards.json")
        if FileManager.default.fileExists(atPath: mcURL.path),
           let data = try? Data(contentsOf: mcURL) {
            try? await CloudMCStore.shared.save(data, for: fileId)
        }
    }

    // MARK: - Delete File (for compatibility)

    func deleteFile(at path: String) {
        Task {
            do {
                try await gcsFileManager.delete(path)
            } catch {
                Log.error("Failed to delete file from GCS: \(path)", category: .cloudSync, error: error)
            }
        }
    }

    // MARK: - Compatibility Properties/Methods

    var lastSyncTimeFormatted: String {
        guard let lastSyncTime = lastSyncTime else {
            return "Never"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSyncTime, relativeTo: Date())
    }

    func clearAllCloudData() async {
        do {
            try await gcsFileManager.deleteAllFiles()
            Log.info("Cleared all cloud data", category: .cloudSync)
        } catch {
            Log.error("Failed to clear cloud data", category: .cloudSync, error: error)
        }
    }

    struct TrashItem {
        let path: String
        let deletedAt: Date?
        let size: Int64
    }

    func getTrashItems() -> [TrashItem] {
        return []
    }

    var trashSizeFormatted: String {
        "0 KB"
    }

    func restoreFile(at path: String) {
    }

    func emptyTrash() {
    }
}
