import FirebaseFirestore
//
//  ProfileView.swift
//  Markdown Opener
//
//  Updated by Grok on 28/12/2025
//
import StoreKit
import SwiftUI

struct ProfileView: View {
    @ObservedObject private var rewardedAdManager = RewardedAdManager.shared
    @ObservedObject private var authManager = AuthManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var userSettingsManager = UserSettingsManager.shared

    // MARK: - Transaction History
    @State private var showingCoinHistory = false
    @State private var transactions: [CoinTransaction] = []
    @State private var isLoadingTransactions = false
    @State private var transactionLoadError: String? = nil
    @State private var isShowingCoinHistorySheet = false

    // MARK: - Sign Out Confirmation
    @State private var showSignOutAlert = false

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        Form {

            // MARK: - Account & Sync
            Section("Account & Sync") {
                if authManager.isSignedIn {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 32))

                        Text("Signed in")
                            .fontWeight(.semibold)

                        Spacer()

                        Text(authManager.displayName)
                            .fontWeight(.bold)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    Text("Your coins are synced across all your devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        authManager.signInWithGoogle()
                    } label: {
                        Label("Sign in with Google", systemImage: "globe")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue.opacity(0.8))

                    Text("Sign in to sync your coins across devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if userSettingsManager.isSubscriptionEnabled {
                Section("Premium") {
                    if authManager.isSignedIn {
                        if subscriptionManager.isSubscribed {
                            VStack(alignment: .leading, spacing: 14) {
                                // Active Status Header
                                HStack {
                                    Label(
                                        "Premium Active",
                                        systemImage: "crown.fill"
                                    )
                                    .fontWeight(.bold)
                                    .foregroundStyle(.yellow)

                                    Spacer()

                                    if let expiry = subscriptionManager
                                        .subscriptionExpiryDate
                                    {
                                        Text(
                                            "Active until :\n\(dateFormatter.string(from: expiry))"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Color.secondary.opacity(0.15)
                                        )
                                        .clipShape(Capsule())
                                    }
                                }

                                // Benefits
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(
                                            systemName: "dollarsign.circle.fill"
                                        )
                                        .foregroundStyle(.green)
                                        Text("100 coins per month")
                                            .font(.headline)
                                    }

                                    HStack {
                                        Image(systemName: "nosign")
                                            .foregroundStyle(.green)
                                        Text("Ad-free experience")
                                            .font(.headline)
                                    }
                                }
                                .padding(.leading, 4)

                                // Manage
                                Button("Manage Subscription") {
                                    if let url = URL(
                                        string:
                                            "https://apps.apple.com/account/subscriptions"
                                    ) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.vertical, 4)
                        } else {
                            // Not subscribed – offer to subscribe
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Image(systemName: "crown.fill")
                                        .font(.largeTitle)
                                        .foregroundStyle(.yellow)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Premium Subscription")
                                            .font(.title3)
                                            .fontWeight(.bold)
                                        Text("100 coins per month • Ad-free")
                                            .font(.headline)
                                            .foregroundStyle(.green)
                                    }
                                }

                                Text(
                                    "Automatically receive 100 coins every month and enjoy the app without interruptions. Cancel anytime."
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                                if subscriptionManager.isLoading {
                                    ProgressView("Loading products...")
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Button("Subscribe Now") {
                                        Task {
                                            await subscriptionManager
                                                .purchaseMonthlySubscription()
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.purple)
                                }

                                Button("Restore Purchases") {
                                    Task {
                                        await subscriptionManager
                                            .restorePurchases()
                                    }
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text(
                            "Sign in to access Premium features and purchase options."
                        )
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            // MARK: - Coins Balance
            Section("Coins Balance") {
                HStack {
                    Label("Coins", systemImage: "dollarsign.circle.fill")
                        .fontWeight(.bold)
                        .foregroundStyle(.yellow)
                    Spacer()
                    Text("\(rewardedAdManager.coins)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                }
                .contentShape(Rectangle())  // better tap area
                .onTapGesture {
                    if authManager.isSignedIn {
                        loadRecentTransactionsAndPresent()
                    }
                }

                Text("Use coins to unlock future AI features.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .sheet(isPresented: $isShowingCoinHistorySheet) {
                CoinHistorySheet(
                    transactions: transactions,
                    isLoading: isLoadingTransactions,
                    errorMessage: transactionLoadError
                )
                .presentationDetents([.medium])
            }

            // MARK: - Get More Coins
            Section("Get More Coins") {
                if userSettingsManager.isSubscriptionEnabled {
                    if authManager.isSignedIn {
                        // 50 Coins Pack
                        if let product = subscriptionManager.coinPackProduct {
                            if subscriptionManager.isLoading {
                                ProgressView("Loading products...")
                                    .frame(maxWidth: .infinity)
                            } else {
                                Button {
                                    Task {
                                        await subscriptionManager
                                            .purchaseCoinPack50()
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text("50 Coins Pack")
                                                .font(.headline)
                                            Text("Get 50 coins instantly")
                                                .font(.subheadline)
                                        }
                                        Spacer()
                                        Text(product.displayPrice)
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.primary)
                                    }
                                    .padding()
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange.opacity(0.8))
                            }
                        } else {
                            ProgressView("Loading products...")
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        Text("Sign in to purchase coin packs.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                    }
                }

                Button {
                    guard
                        let rootVC = UIApplication.shared.connectedScenes
                            .compactMap({ $0 as? UIWindowScene })
                            .first?.windows.first?.rootViewController
                    else { return }

                    rewardedAdManager.showAd(from: rootVC) {
                        RewardedAdManager.shared.earnCoin()
                        UIImpactFeedbackGenerator(style: .medium)
                            .impactOccurred()
                    }
                } label: {
                    Label(
                        "Watch Ad to Earn 1 Coin",
                        systemImage: "play.rectangle.fill"
                    )
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green.opacity(0.85))
            }

            if authManager.isSignedIn {
                Section("Sign Out") {
                    HStack {
                        Text("Your coins are synced across all your devices.")
                            .font(.caption)
                        Spacer()
                        Button("Sign Out", role: .destructive) {
                            showSignOutAlert = true
                        }
                    }

                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle(
            authManager.isSignedIn
                ? "\(authManager.displayName)'s Profile" : "Profile"
        )
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign Out?", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) {
                // Do nothing, just dismiss
            }
            Button("Sign Out", role: .destructive) {
                authManager.signOut()
            }
        } message: {
            Text(
                "You will be signed out of your account. Your coins will remain synced to this account and can be accessed again when you sign back in."
            )
        }
        .alert(
            "Purchase Failed",
            isPresented: $subscriptionManager.showPurchaseError
        ) {
            Button("OK") {}
        } message: {
            Text(subscriptionManager.purchaseErrorMessage ?? "Unknown error")
        }
    }
    private func loadRecentTransactionsAndPresent() {
        guard let uid = AuthManager.shared.currentUserId else { return }

        // Reset states
        isLoadingTransactions = true
        transactions = []
        transactionLoadError = nil  // ← clear any previous error

        let db = Firestore.firestore()
        db.collection("users")
            .document(uid)
            .collection("coin_transactions")
            .order(by: "timestamp", descending: true)
            .limit(to: 20)
            .getDocuments { [self] snapshot, error in
                DispatchQueue.main.async {
                    self.isLoadingTransactions = false

                    if let error {
                        Log.error(
                            "Failed to load transactions: \(error.localizedDescription)", category: .general)

                        // ── Important changes ────────────────────────────────
                        self.transactionLoadError = error.localizedDescription
                        self.transactions = []  // make sure it's empty
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            self.isShowingCoinHistorySheet = true
                        }
                        // ──────────────────────────────────────────────────────

                        return
                    }

                    guard let documents = snapshot?.documents else {
                        self.transactionLoadError =
                            "No data received from server"
                        self.isShowingCoinHistorySheet = true
                        return
                    }

                    let loaded = documents.compactMap {
                        doc -> CoinTransaction? in
                        guard
                            let data = try? doc.data(),
                            let amount = data["amount"] as? Int,
                            let balance = data["balance_after"] as? Int,
                            let reason = data["reason"] as? String,
                            let timestamp = (data["timestamp"] as? Timestamp)?
                                .dateValue()
                        else { return nil }

                        return CoinTransaction(
                            id: doc.documentID,
                            amount: amount,
                            balanceAfter: balance,
                            reason: reason,
                            timestamp: timestamp,
                            adType: data["ad_type"] as? String,
                            note: data["note"] as? String
                        )
                    }

                    self.transactions = loaded
                    self.transactionLoadError = nil  // success → clear error

                    self.isShowingCoinHistorySheet = true
                }
            }
    }
}

struct CoinHistorySheet: View {
    let transactions: [CoinTransaction]
    let isLoading: Bool
    var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView(
                    "Loading Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if isLoading {
                ProgressView("Loading history...")
            } else if transactions.isEmpty {
                ContentUnavailableView(
                    "No transactions yet",
                    systemImage: "dollarsign.circle",
                    description: Text("Your coin activity will appear here.")
                )
            } else {
                Text("Lastest 20 transactions")
                    .font(Font.subheadline.bold())
                    .padding(.top)
                    .foregroundStyle(.secondary)

                List(transactions) { tx in
                    HStack(spacing: 12) {
                        Image(systemName: iconForReason(tx.reason))
                            .foregroundStyle(colorForReason(tx.reason))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(
                                        colorForReason(tx.reason).opacity(
                                            0.15
                                        )
                                    )
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(reasonDisplay(tx.reason, note: tx.note))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(dateFormatter.string(from: tx.timestamp))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(amountText(tx.amount))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(tx.amount >= 0 ? .green : .red)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func iconForReason(_ reason: String) -> String {
        switch reason {
        case "ad_reward": return "play.rectangle.fill"
        case "daily_login": return "sun.max.fill"
        case "spend": return "arrow.down.circle.fill"
        case "purchase", "coin_pack": return "bag.fill"
        case "cloud_sync_correction": return "arrow.triangle.2.circlepath"
        default: return "dollarsign.circle.fill"
        }
    }

    private func colorForReason(_ reason: String) -> Color {
        switch reason {
        case "ad_reward", "daily_login", "purchase", "coin_pack": return .green
        case "spend": return .red
        default: return .blue
        }
    }

    private func reasonDisplay(_ reason: String, note: String?) -> String {
        let base =
            reason
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        if let note, !note.isEmpty {
            return "\(base) – \(note)"
        }
        return base
    }

    private func amountText(_ amount: Int) -> String {
        if amount >= 0 {
            return "+\(amount)"
        } else {
            return "\(amount)"
        }
    }

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }
}
