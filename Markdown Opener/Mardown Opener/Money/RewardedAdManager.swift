//
//  RewardedAdManager.swift
//  MarkMind
//
//  Fixed: Infinite sync loop resolved with sync guard
//  Added: Coin transaction history (last 20 records) saved to Firestore
//

import GoogleMobileAds
import UIKit
import Combine
import FirebaseFirestore
import FirebaseAuth    // if not already imported via AuthManager

final class RewardedAdManager: NSObject, ObservableObject {
    static let shared = RewardedAdManager()
    
    private let localCoinsKey = "user_coins_local"
    
    // MARK: - Sync Guard to Prevent Loops
    private var isUpdatingFromCloud = false
    
    @Published var coins: Int = 0 {
        didSet {
            // Always save locally
            UserDefaults.standard.set(coins, forKey: localCoinsKey)
            
            // Only sync to cloud if:
            // 1. User is signed in
            // 2. This change did NOT come from cloud sync
            if AuthManager.shared.isSignedIn && !isUpdatingFromCloud {
                AuthManager.shared.saveCoins(coins)
            }
        }
    }
    
    private override init() {
        super.init()
        
        // Migrate old key
        if UserDefaults.standard.object(forKey: "user_coins") != nil &&
           UserDefaults.standard.object(forKey: localCoinsKey) == nil {
            let oldCoins = UserDefaults.standard.integer(forKey: "user_coins")
            UserDefaults.standard.set(oldCoins, forKey: localCoinsKey)
            UserDefaults.standard.removeObject(forKey: "user_coins")
        }
        
        coins = UserDefaults.standard.integer(forKey: localCoinsKey)
        loadAd()
    }
    
    func reloadLocalCoins() {
        let local = UserDefaults.standard.integer(forKey: localCoinsKey)
        if coins != local {
            coins = local
        }
    }
    
    func setCoinsDirectly(_ amount: Int) {
        isUpdatingFromCloud = true  // Prevent any sync attempts
        coins = amount
        UserDefaults.standard.set(amount, forKey: localCoinsKey)
        DispatchQueue.main.async {
            self.isUpdatingFromCloud = false
        }
        print("Coins forcibly reset to \(amount) on sign-out")
    }
    
    // MARK: - Safe Coin Updates (Used by Cloud & Subscriptions)
    
    /// Use this when adding coins from ads, subscription, etc.
    func addCoins(_ amount: Int, reason: String = "earn", note: String? = nil) {
        guard amount > 0 else {
            print("Warning: Attempted to add non-positive coins: \(amount)")
            return
        }
        
        coins += amount
        print("Added \(amount) coins. Total: \(coins)")
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        
        recordTransaction(amount: amount, reason: reason, note: note)
    }
    
    /// Called only by AuthManager when syncing from cloud
    func setCoinsFromCloud(_ amount: Int) {
        guard coins != amount else { return }  // No change → avoid unnecessary didSet
        
        let difference = amount - coins
        
        isUpdatingFromCloud = true
        coins = amount
        
        DispatchQueue.main.async {
            self.isUpdatingFromCloud = false
        }
        
        print("Synced coins from cloud: \(amount)")
        
        if difference != 0 {
            recordTransaction(
                amount: difference,
                reason: "cloud_sync_correction",
                note: "Balance adjusted from cloud"
            )
        }
    }
    
    // MARK: - Transaction History
    
    private func recordTransaction(amount: Int, reason: String, adType: String? = nil, note: String? = nil) {
        guard let uid = AuthManager.shared.currentUserId, AuthManager.shared.isSignedIn else {
            print("Cannot save transaction — no authenticated user")
            return
        }
        
        let transaction = CoinTransaction(
            id: UUID().uuidString,
            amount: amount,
            balanceAfter: coins,
            reason: reason,
            timestamp: Date(),
            adType: adType,
            note: note
        )
        
        let db = Firestore.firestore()
        let collection = db.collection("users").document(uid).collection("coin_transactions")
        
        // Save the transaction
        collection.document().setData(transaction.firestoreData) { error in
            if let error {
                print("Failed to save coin transaction: \(error.localizedDescription)")
                return
            }
            
            // Trim to keep only the latest 20
            self.trimOldTransactions(toKeep: 20, in: collection)
        }
    }
    
    private func trimOldTransactions(toKeep: Int = 20, in collection: CollectionReference) {
        collection
            .order(by: "timestamp", descending: true)
            .limit(to: toKeep + 5)  // small buffer
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents, error == nil else {
                    print("Trim failed: \(error?.localizedDescription ?? "unknown error")")
                    return
                }
                
                if documents.count <= toKeep { return }
                
                let documentsToDelete = documents.dropFirst(toKeep)
                
                let batch = collection.firestore.batch()
                for doc in documentsToDelete {
                    batch.deleteDocument(doc.reference)
                }
                
                batch.commit { error in
                    if let error {
                        print("Failed to trim old transactions: \(error.localizedDescription)")
                    } else {
                        print("Trimmed \(documentsToDelete.count) old coin transactions")
                    }
                }
            }
    }
    
    // MARK: - Other Methods
    
    func earnCoin() {
        addCoins(1, reason: "manual_earn")
    }
    
    @discardableResult
    func spendCoins(_ amount: Int = 10, note: String? = "feature_usage") -> Bool {
        guard coins >= amount else {
            print("Not enough coins: have \(coins), need \(amount)")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
        
        coins -= amount
        print("Spent \(amount) coins. Remaining: \(coins)")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        recordTransaction(amount: -amount, reason: "spend", note: note)
        
        return true
    }
    
    // MARK: - Ad Handling
    
    func loadAd() {
        let request = Request()
        RewardedAd.load(with: adUnitID, request: request) { [weak self] ad, error in
            guard let self else { return }
            
            if let error {
                print("Rewarded ad failed to load: \(error.localizedDescription)")
                self.rewardedAd = nil
                return
            }
            
            print("Rewarded ad loaded successfully")
            self.rewardedAd = ad
            self.rewardedAd?.fullScreenContentDelegate = self
        }
    }
    
    func showAd(from rootViewController: UIViewController, onReward: @escaping () -> Void) {
        guard let ad = rewardedAd else {
            print("Ad not ready")
            loadAd()
            return
        }
        
        ad.present(from: rootViewController) { [weak self] in
            onReward()
            self?.recordTransaction(
                amount: 5,  // ← change this to your actual rewarded ad coin amount
                reason: "ad_reward",
                adType: "rewarded_video"
            )
        }
        
        self.rewardedAd = nil
        self.loadAd()  // Preload next
    }
    
    private var rewardedAd: RewardedAd?
    private let adUnitID = "ca-app-pub-2445337445676652/1626687605"
    
    // MARK: - Daily Login Reward
    
    private let lastDailyRewardDateKey = "last_daily_reward_date"
    
    func checkAndAwardDailyLoginReward() {
        let calendar = Calendar.current
        
        var rewardDateComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        rewardDateComponents.hour = 8
        rewardDateComponents.minute = 0
        rewardDateComponents.second = 0
        
        guard let rewardStartToday = calendar.date(from: rewardDateComponents) else { return }
        
        let lastRewardDate: Date = UserDefaults.standard.object(forKey: lastDailyRewardDateKey) as? Date ?? .distantPast
        
        if lastRewardDate < rewardStartToday {
            let rewardAmount = Int.random(in: 2...5)
            
            addCoins(rewardAmount, reason: "daily_login")
            
            UserDefaults.standard.set(rewardStartToday, forKey: lastDailyRewardDateKey)
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .dailyRewardGranted,
                    object: nil,
                    userInfo: ["amount": rewardAmount]
                )
            }
            
            print("🎉 Daily login reward granted: +\(rewardAmount) coins")
        } else {
            print("Daily reward already claimed today (after 8 AM)")
        }
    }
    
    func resetDailyRewardClaim() {
        UserDefaults.standard.removeObject(forKey: lastDailyRewardDateKey)
        print("Daily reward claim reset")
    }
    
    func hasClaimedDailyRewardToday() -> Bool {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 8
        components.minute = 0
        components.second = 0
        
        guard let today8AM = calendar.date(from: components) else { return false }
        
        if let lastDate = UserDefaults.standard.object(forKey: lastDailyRewardDateKey) as? Date {
            return lastDate >= today8AM
        }
        return false
    }
    
    func nextDailyRewardDate() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 8
        components.minute = 0
        components.second = 0
        
        guard let today8AM = calendar.date(from: components) else {
            return Date().addingTimeInterval(86400)
        }
        
        if Date() >= today8AM {
            return calendar.date(byAdding: .day, value: 1, to: today8AM)!
        } else {
            return today8AM
        }
    }
}

// MARK: - Transaction Model

struct CoinTransaction: Identifiable {
    let id: String
    let amount: Int
    let balanceAfter: Int
    let reason: String
    let timestamp: Date
    let adType: String?
    let note: String?
    
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "amount": amount,
            "balance_after": balanceAfter,
            "reason": reason,
            "timestamp": Timestamp(date: timestamp)
        ]
        if let adType { data["ad_type"] = adType }
        if let note   { data["note"] = note }
        return data
    }
}

// MARK: - GADFullScreenContentDelegate

extension RewardedAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("Rewarded ad dismissed")
        loadAd()
    }
    
    func ad(_ ad: FullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        print("Rewarded ad failed to present: \(error.localizedDescription)")
        loadAd()
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let dailyRewardGranted = Notification.Name("dailyRewardGranted")
}
