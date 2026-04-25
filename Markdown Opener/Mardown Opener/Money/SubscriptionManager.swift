//
//  SubscriptionManager.swift
//  MarkMind
//
//  FINAL FIX: Prevent duplicate 100-coin grants from double purchase handling
//  Date: December 28, 2025
//

import Foundation
import StoreKit
import FirebaseFirestore
import FirebaseAuth
import Combine

class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    // MARK: - Product IDs
    private let monthlyProductID = "MindMark_Subscription_ProMember"
    private let coinPack50ProductID = "MarkMInd_Coin"
    
    // MARK: - Published Properties
    @Published var isSubscribed = false
    @Published var subscriptionExpiryDate: Date?
    @Published var isLoading = false
    
    @Published var showPurchaseError = false
    @Published var purchaseErrorMessage: String?
    
    // Consumable product for UI
    @Published var coinPackProduct: Product?
    
    // MARK: - Private Properties
    private let db = Firestore.firestore()
    private var subscriptionListener: ListenerRegistration?
    private var processedTransactionIDs = Set<UInt64>() // Track ALL processed subscription transactions
    
    private var transactionListener: Task<Void, Never>? = nil
    
    private init() {
        // Load previously processed transaction IDs from UserDefaults (persist across app launches)
        if let savedIDs = UserDefaults.standard.array(forKey: "processedSubscriptionTransactionIDs") as? [UInt64] {
            processedTransactionIDs = Set(savedIDs)
            print("Loaded \(savedIDs.count) previously processed transaction IDs")
        }
        
        // Start listening to transaction updates
        transactionListener = Task.detached(priority: .background) { [weak self] in
            await self?.listenForTransactionUpdates()
        }
        
        // Listen to auth changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if user != nil {
                self?.startSubscriptionListener()
            } else {
                self?.stopSubscriptionListener()
                DispatchQueue.main.async {
                    self?.isSubscribed = false
                    self?.subscriptionExpiryDate = nil
                }
            }
        }
        
        // Initial load
        Task {
            await refreshSubscriptionStatus()
            await loadConsumableProducts()
        }
    }
    
    deinit {
        transactionListener?.cancel()
    }
    
    // MARK: - Public Methods
    
    func refreshSubscriptionStatus() async {
        await MainActor.run { self.isLoading = true }
        await loadSubscriptionFromFirestore()
        await MainActor.run { self.isLoading = false }
    }
    
    func purchaseMonthlySubscription() async {
        await MainActor.run { isLoading = true }
        
        guard let product = await fetchProduct() else {
            await showError("Unable to load subscription product.")
            return
        }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await handleSuccessfulPurchase(transaction: transaction, source: "directPurchase")
                } else {
                    await showError("Purchase could not be verified.")
                }
            case .userCancelled:
                print("User cancelled purchase")
            case .pending:
                await showError("Purchase pending approval.")
            @unknown default:
                break
            }
        } catch {
            await showError("Purchase failed: \(error.localizedDescription)")
        }
        
        await MainActor.run { isLoading = false }
    }
    
    // MARK: - Purchase 50 Coin Pack
    func purchaseCoinPack50() async {
        await MainActor.run { isLoading = true }
        
        guard let product = coinPackProduct else {
            await showError("Coin pack not available. Please try again.")
            await MainActor.run { isLoading = false }
            return
        }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verificationResult):
                if case .verified(let transaction) = verificationResult {
                    RewardedAdManager.shared.addCoins(50)
                    print("Successfully purchased 50 Coin Pack – granted 50 coins")
                    await transaction.finish()
                } else {
                    await showError("Purchase verification failed.")
                }
                
            case .userCancelled:
                print("User cancelled 50 coin pack purchase")
            case .pending:
                await showError("Purchase is pending approval.")
            @unknown default:
                break
            }
        } catch {
            await showError("Purchase failed: \(error.localizedDescription)")
        }
        
        await MainActor.run { isLoading = false }
    }
    
    func restorePurchases() async {
        await MainActor.run { isLoading = true }
        do {
            try await AppStore.sync()
            await loadSubscriptionFromFirestore()
            print("Restore purchases completed")
        } catch {
            await showError("Restore failed: \(error.localizedDescription)")
        }
        await MainActor.run { isLoading = false }
    }
    
    // MARK: - Consumable Product Loading
    func loadConsumableProducts() async {
        do {
            let productIDs = [coinPack50ProductID]
            let products = try await Product.products(for: productIDs)
            
            await MainActor.run {
                self.coinPackProduct = products.first { $0.id == coinPack50ProductID }
            }
            
            print("Loaded consumable products: \(products.map { $0.displayName })")
        } catch {
            print("Failed to load consumable products: \(error)")
        }
    }
    
    // MARK: - Transaction Listener
    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            do {
                let transaction = try result.payloadValue
                
                if transaction.productID == monthlyProductID,
                   case .verified = result {
                    
                    await handleSuccessfulPurchase(transaction: transaction, source: "backgroundListener")
                }
                
                if transaction.productID == coinPack50ProductID,
                   case .verified = result {
                    RewardedAdManager.shared.addCoins(50)
                    await transaction.finish()
                    print("Background: Granted 50 coins from verified coin pack transaction")
                }
                
            } catch {
                print("Transaction update failed verification: \(error)")
            }
        }
    }
    
    // MARK: - Core Purchase Handling (Centralized & Deduplicated)
    private func handleSuccessfulPurchase(transaction: StoreKit.Transaction, source: String) async {
        guard transaction.productID == monthlyProductID else { return }
        
        let transactionID = transaction.id
        print("Handling subscription transaction ID: \(transactionID) from \(source)")
        
        // CRITICAL: Check if already processed (prevents duplicates)
        if processedTransactionIDs.contains(transactionID) {
            print("Transaction \(transactionID) already processed – skipping to avoid duplicates")
            await transaction.finish()
            return
        }
        
        // Mark as processed immediately
        processedTransactionIDs.insert(transactionID)
        saveProcessedTransactionIDs()
        
        // Get expiry date
        let expiryDate = transaction.expirationDate ?? Date().addingTimeInterval(30 * 24 * 60 * 60)
        
        // Ignore expired periods
        guard expiryDate > Date() else {
            print("Ignoring expired subscription transaction (ID: \(transactionID))")
            await transaction.finish()
            return
        }
        
        let isFirstPurchase = await isFirstSubscription()
        
        await saveSubscriptionToFirestore(
            transaction: transaction,
            expiryDate: expiryDate,
            isFirstPurchase: isFirstPurchase
        )
        
        // Grant 100 coins for every new active subscription payment/renewal
        await grantMonthlyCoinsForActiveSubscription()
        
        await transaction.finish()
        print("Successfully processed subscription transaction \(transactionID)")
    }
    
    private func grantMonthlyCoinsForActiveSubscription() async {
        guard Auth.auth().currentUser != nil else { return }
        
        RewardedAdManager.shared.addCoins(100)
        print("Granted 100 coins for active subscription purchase/renewal")
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        
        // Optional analytics timestamp
        let userRef = db.collection("users").document(Auth.auth().currentUser!.uid)
        try? await userRef.setData(["lastCoinGrantDate": FieldValue.serverTimestamp()], merge: true)
    }
    
    private func saveProcessedTransactionIDs() {
        UserDefaults.standard.set(Array(processedTransactionIDs), forKey: "processedSubscriptionTransactionIDs")
    }
    
    private func isFirstSubscription() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return true }
        
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            return doc.data()?["subscription"] == nil
        } catch {
            print("Error checking first subscription: \(error)")
            return true
        }
    }
    
    private func saveSubscriptionToFirestore(
        transaction: StoreKit.Transaction,
        expiryDate: Date,
        isFirstPurchase: Bool
    ) async {
        guard let user = Auth.auth().currentUser else { return }
        
        let userRef = db.collection("users").document(user.uid)
        
        var subData: [String: Any] = [
            "isSubscribed": true,
            "subscriptionProductID": monthlyProductID,
            "expiryDate": Timestamp(date: expiryDate),
            "lastRenewalDate": Timestamp(date: Date()),
            "transactionID": transaction.id,
            "originalTransactionID": transaction.originalID ?? 0
        ]
        
        if isFirstPurchase {
            subData["firstSubscriptionDate"] = Timestamp(date: Date())
        }
        
        do {
            try await userRef.setData(["subscription": subData], merge: true)
            print("Subscription saved to Firestore")
        } catch {
            print("Failed to save subscription: \(error)")
        }
    }
    
    // MARK: - Subscription Listener & Status
    
    private func startSubscriptionListener() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        stopSubscriptionListener()
        
        subscriptionListener = db.collection("users")
            .document(uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Subscription listener error: \(error.localizedDescription)")
                    return
                }
                
                Task { @MainActor in
                    if let data = snapshot?.data(),
                       let subData = data["subscription"] as? [String: Any],
                       let isSubscribedRaw = subData["isSubscribed"] as? Bool,
                       isSubscribedRaw {
                        
                        let expiryTimestamp = subData["expiryDate"] as? Timestamp
                        let expiryDate = expiryTimestamp?.dateValue() ?? Date.distantPast
                        
                        if expiryDate > Date() {
                            self.isSubscribed = true
                            self.subscriptionExpiryDate = expiryDate
                        } else {
                            self.isSubscribed = false
                            self.subscriptionExpiryDate = nil
                        }
                    } else {
                        self.isSubscribed = false
                        self.subscriptionExpiryDate = nil
                    }
                }
            }
    }
    
    private func stopSubscriptionListener() {
        subscriptionListener?.remove()
        subscriptionListener = nil
    }
    
    private func loadSubscriptionFromFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            await MainActor.run {
                self.isSubscribed = false
                self.subscriptionExpiryDate = nil
            }
            return
        }
        
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            await updateSubscriptionStatus(from: doc.data())
        } catch {
            print("Failed to load subscription from Firestore: \(error)")
            await MainActor.run { self.isSubscribed = false }
        }
    }
    
    @MainActor
    private func updateSubscriptionStatus(from data: [String: Any]?) {
        guard let data = data,
              let subData = data["subscription"] as? [String: Any],
              let isSubscribedRaw = subData["isSubscribed"] as? Bool,
              isSubscribedRaw else {
            self.isSubscribed = false
            self.subscriptionExpiryDate = nil
            return
        }
        
        if let expiryTimestamp = subData["expiryDate"] as? Timestamp {
            let expiryDate = expiryTimestamp.dateValue()
            if expiryDate > Date() {
                self.isSubscribed = true
                self.subscriptionExpiryDate = expiryDate
            } else {
                self.isSubscribed = false
                self.subscriptionExpiryDate = nil
            }
        } else {
            self.isSubscribed = false
            self.subscriptionExpiryDate = nil
        }
    }
    
    private func fetchProduct() async -> Product? {
        do {
            let products = try await Product.products(for: [monthlyProductID])
            return products.first
        } catch {
            print("Fetch product failed: \(error)")
            return nil
        }
    }
    
    private func showError(_ message: String) async {
        await MainActor.run {
            self.purchaseErrorMessage = message
            self.showPurchaseError = true
        }
    }
}
