//
//  StorageQuotaManager.swift
//  MarkMind
//
//  Manages storage quotas for free and pro users
//

import Foundation
import FirebaseAuth
import Combine

final class StorageQuotaManager: ObservableObject {
    static let shared = StorageQuotaManager()

    static let freeUserLimit: Int64 = 100 * 1024 * 1024 // 100 MB
    static let proUserLimit: Int64 = 1024 * 1024 * 1024 // 1 GB

    @Published private(set) var currentUsage: Int64 = 0
    @Published private(set) var quotaLimit: Int64 = 0
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private var gcsFileManager: GCSFileManager { GCSFileManager.shared }
    private var gcsStorage: GCSStorageService { GCSStorageService.shared }

    private var userID: String? {
        Auth.auth().currentUser?.uid
    }

    var isProUser: Bool {
        SubscriptionManager.shared.isSubscribed
    }

    var remainingQuota: Int64 {
        max(0, quotaLimit - currentUsage)
    }

    var usagePercentage: Double {
        guard quotaLimit > 0 else { return 0 }
        return Double(currentUsage) / Double(quotaLimit)
    }

    var isOverQuota: Bool {
        currentUsage >= quotaLimit
    }

    var canUpload: Bool {
        !isLoading && !isOverQuota
    }

    private init() {}

    func refreshQuota() async {
        guard let _ = userID else {
            await MainActor.run {
                self.quotaLimit = 0
                self.currentUsage = 0
            }
            return
        }

        await MainActor.run { isLoading = true }

        let limit = isProUser ? Self.proUserLimit : Self.freeUserLimit

        do {
            let usage = try await calculateTotalUsage()
            await MainActor.run {
                self.quotaLimit = limit
                self.currentUsage = usage
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func checkQuota(for fileSize: Int64) -> QuotaCheckResult {
        if isProUser {
            return QuotaCheckResult(allowed: true, reason: nil)
        }

        if currentUsage + fileSize > quotaLimit {
            let remaining = remainingQuota
            let remainingMB = remaining / (1024 * 1024)
            return QuotaCheckResult(
                allowed: false,
                reason: "Free users can store up to \(Self.freeUserLimit / (1024 * 1024)) MB. You have \(remainingMB) MB remaining. Please upgrade to Pro for 1 GB storage."
            )
        }

        return QuotaCheckResult(allowed: true, reason: nil)
    }

    func canUpload(fileSize: Int64) -> Bool {
        checkQuota(for: fileSize).allowed
    }

    func updateUsageAfterUpload(fileSize: Int64) {
        Task { @MainActor in
            currentUsage += fileSize
        }
    }

    func updateUsageAfterDelete(fileSize: Int64) {
        Task { @MainActor in
            currentUsage = max(0, currentUsage - fileSize)
        }
    }

    private func calculateTotalUsage() async throws -> Int64 {
        let files = try await gcsFileManager.listDocuments()
        var total: Int64 = 0

        for file in files {
            total += file.size
        }

        return total
    }

    func getFormattedUsage() -> String {
        let usedMB = Double(currentUsage) / (1024 * 1024)
        let limitMB = Double(quotaLimit) / (1024 * 1024)
        let usedGB = usedMB / 1024
        let limitGB = limitMB / 1024

        if limitGB >= 1 {
            return String(format: "%.2f GB / %.1f GB", usedGB, limitGB)
        } else {
            return String(format: "%.0f MB / %.0f MB", usedMB, limitMB)
        }
    }

    func getFormattedRemaining() -> String {
        let remainingMB = Double(remainingQuota) / (1024 * 1024)
        let remainingGB = remainingMB / 1024

        if remainingGB >= 1 {
            return String(format: "%.1f GB remaining", remainingGB)
        } else {
            return String(format: "%.0f MB remaining", remainingMB)
        }
    }
}

struct QuotaCheckResult {
    let allowed: Bool
    let reason: String?
}

enum StorageQuotaError: LocalizedError {
    case overQuota(Int64, Int64)
    case uploadExceedsQuota(Int64, Int64)
    case networkError
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .overQuota(let used, let limit):
            let usedMB = used / (1024 * 1024)
            let limitMB = limit / (1024 * 1024)
            return "Storage quota exceeded. Used: \(usedMB) MB, Limit: \(limitMB) MB"
        case .uploadExceedsQuota(let fileSize, let remaining):
            let fileSizeMB = fileSize / (1024 * 1024)
            let remainingMB = remaining / (1024 * 1024)
            return "File size (\(fileSizeMB) MB) exceeds remaining quota (\(remainingMB) MB)"
        case .networkError:
            return "Network error occurred while checking storage quota"
        case .notAuthenticated:
            return "Please sign in to access storage"
        }
    }
}
