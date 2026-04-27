//
//  CloudSyncOnboardingView.swift
//  MarkMind
//
//  Onboarding view for setting up cloud sync
//

import SwiftUI
import FirebaseAuth
import Combine

struct CloudSyncOnboardingView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var cloudSync = CloudSyncManager.shared
    @ObservedObject private var authManager = AuthManager.shared

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasCompletedOnboarding = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    headerSection

                    if authManager.isSignedIn {
                        signedInContent
                    } else {
                        signInContent
                    }

                    featuresSection

                    if let error = errorMessage {
                        errorBanner(error)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
            .navigationTitle("Cloud Sync")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        completeOnboarding(syncEnabled: false)
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Sync Your Documents")
                .font(.title2)
                .fontWeight(.bold)

            Text("Access your files across all your devices with cloud sync")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var signInContent: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue.opacity(0.8))

                Text("Sign in Required")
                    .font(.headline)

                Text("Sign in with Google to enable cloud sync and access your files on any device")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)

            Button {
                signIn()
            } label: {
                HStack {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                    Text("Sign in with Google")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .disabled(isLoading)
        }
    }

    private var signedInContent: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Signed in as \(authManager.displayName)")
                        .font(.headline)
                    Text(authManager.user?.email ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Sign out") {
                    signOut()
                }
                .font(.caption)
                .foregroundColor(.red)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            Button {
                enableSync()
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath.icloud")
                    Text("Enable Cloud Sync")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .disabled(isLoading)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's Included")
                .font(.headline)

            VStack(spacing: 12) {
                featureRow(
                    icon: "doc.on.doc",
                    title: "All Document Types",
                    description: "Markdown, PDF, Word, PowerPoint files"
                )

                featureRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Real-time Sync",
                    description: "Changes sync automatically across devices"
                )

                featureRow(
                    icon: "trash",
                    title: "30-Day Trash",
                    description: "Deleted files can be recovered for 30 days"
                )

                featureRow(
                    icon: "tag",
                    title: "Tags & Favorites",
                    description: "Your organization syncs too"
                )

                featureRow(
                    icon: "brain",
                    title: "Chat & Flashcards",
                    description: "AI study data syncs across devices"
                )
            }
        }
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private func signIn() {
        isLoading = true
        errorMessage = nil

        authManager.signInWithGoogle { [self] result in
            DispatchQueue.main.async {
                isLoading = false
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func signOut() {
        authManager.signOut()
        cloudSync.setEnabled(false)
    }

    private func enableSync() {
        isLoading = true
        errorMessage = nil

        Task {
            cloudSync.setEnabled(true)

            await MainActor.run {
                isLoading = false
                completeOnboarding(syncEnabled: true)
            }
        }
    }

    private func completeOnboarding(syncEnabled: Bool) {
        UserDefaults.standard.set(true, forKey: "cloudSync_onboardingCompleted")
        UserDefaults.standard.set(syncEnabled, forKey: "cloudSync_enabled")
        dismiss()
    }
}

struct CloudSyncSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var cloudSync = CloudSyncManager.shared
    @ObservedObject private var authManager = AuthManager.shared

    @State private var showTrash = false
    @State private var showEmptyTrashConfirmation = false
    @State private var showClearCloudConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Sync Status", systemImage: statusIcon)
                            .foregroundColor(statusColor)
                        Spacer()
                        Text(cloudSync.status.rawValue.capitalized)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Last Synced", systemImage: "clock")
                        Spacer()
                        Text(cloudSync.lastSyncTimeFormatted)
                            .foregroundColor(.secondary)
                    }

                    if cloudSync.status == .error, let error = cloudSync.syncError {
                        HStack {
                            Label("Error", systemImage: "exclamationmark.triangle")
                                .foregroundColor(.red)
                            Spacer()
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { cloudSync.isEnabled },
                        set: { cloudSync.setEnabled($0) }
                    )) {
                        Label("Enable Cloud Sync", systemImage: "icloud")
                    }
                }

                if authManager.isSignedIn {
                    Section("Account") {
                        HStack {
                            Label("Signed in as", systemImage: "person.circle")
                            Spacer()
                            Text(authManager.displayName)
                                .foregroundColor(.secondary)
                        }

                        Button(role: .destructive) {
                            authManager.signOut()
                            cloudSync.setEnabled(false)
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }

                Section("Trash") {
                    Button {
                        showTrash = true
                    } label: {
                        HStack {
                            Label("Trash", systemImage: "trash")
                            Spacer()
                            Text(cloudSync.trashSizeFormatted)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    Button(role: .destructive) {
                        showEmptyTrashConfirmation = true
                    } label: {
                        Label("Empty Trash", systemImage: "trash.slash")
                    }
                    .disabled(cloudSync.getTrashItems().isEmpty)
                }

                Section {
                    Button(role: .destructive) {
                        showClearCloudConfirmation = true
                    } label: {
                        Label("Clear All Cloud Data", systemImage: "xmark.circle")
                    }
                }
            }
            .navigationTitle("Cloud Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showTrash) {
                TrashManagementView()
            }
            .alert("Clear All Cloud Data?", isPresented: $showClearCloudConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    Task {
                        await cloudSync.clearAllCloudData()
                    }
                }
            } message: {
                Text("This will delete all your files from the cloud. Your local files will not be affected.")
            }
        }
    }

    private var statusIcon: String {
        switch cloudSync.status {
        case .idle: return "checkmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .error: return "exclamationmark.icloud"
        case .offline: return "icloud.slash"
        case .disabled: return "icloud.slash"
        }
    }

    private var statusColor: Color {
        switch cloudSync.status {
        case .idle: return .green
        case .syncing: return .blue
        case .error: return .red
        case .offline: return .orange
        case .disabled: return .gray
        }
    }
}

struct TrashManagementView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var cloudSync = CloudSyncManager.shared

    var body: some View {
        NavigationStack {
            List {
                let trashItems = cloudSync.getTrashItems()

                if trashItems.isEmpty {
                    ContentUnavailableView(
                        "Trash is Empty",
                        systemImage: "trash",
                        description: Text("Deleted files will appear here for 30 days")
                    )
                } else {
                    ForEach(trashItems, id: \.path) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.path)
                                .font(.subheadline)
                                .lineLimit(1)

                            HStack {
                                if let deletedAt = item.deletedAt {
                                    Text("Deleted \(deletedAt, style: .relative) ago")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                cloudSync.deleteFile(at: item.path)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                _ = cloudSync.restoreFile(at: item.path)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Trash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                if !cloudSync.getTrashItems().isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Empty") {
                            cloudSync.emptyTrash()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

struct CloudSyncStatusBadge: View {
    @ObservedObject private var cloudSync = CloudSyncManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption)
            Text(statusText)
                .font(.caption)
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var iconName: String {
        switch cloudSync.status {
        case .idle:
            return "checkmark.icloud.fill"
        case .syncing:
            return "arrow.triangle.2.circlepath.icloud"
        case .error:
            return "exclamationmark.icloud.fill"
        case .offline:
            return "icloud.slash"
        case .disabled:
            return "icloud.slash"
        }
    }

    private var statusText: String {
        switch cloudSync.status {
        case .idle:
            return cloudSync.isEnabled ? "Synced" : "Off"
        case .syncing:
            return "Syncing"
        case .error:
            return "Error"
        case .offline:
            return "Offline"
        case .disabled:
            return "Off"
        }
    }

    private var statusColor: Color {
        switch cloudSync.status {
        case .idle:
            return cloudSync.isEnabled ? .green : .gray
        case .syncing:
            return .blue
        case .error:
            return .red
        case .offline:
            return .orange
        case .disabled:
            return .gray
        }
    }
}