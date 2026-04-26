import UIKit

enum CoinProtection {
    @MainActor
    static func deductCoinIfPossible(errorMessageHandler: (String) -> Void) -> Bool {
        let success = RewardedAdManager.shared.spendCoins(1)

        if success {
            return true
        }

        let isSubscribed = SubscriptionManager.shared.isSubscribed

        if isSubscribed {
            errorMessageHandler(
                Localization.loc("Not enough coins. Buy coins, or watch an ad to earn more!",
                                 "硬幣不足。購買硬幣，或觀看廣告賺取更多！")
            )
        } else {
            errorMessageHandler(
                Localization.loc("Not enough coins. Subscribe to Premium for 100 coins/month (ad-free!), buy coins, or watch an ad to earn more!",
                                 "硬幣不足。訂閱 Premium 每月獲得 100 硬幣（無廣告！）、購買硬幣，或觀看廣告賺取更多！")
            )
        }

        UINotificationFeedbackGenerator().notificationOccurred(.error)

        return false
    }

    @MainActor
    static func withCoinProtected<T>(
        actionDescription: String = "API operation",
        errorMessageHandler: (String) -> Void,
        operation: () async throws -> T
    ) async throws -> T {
        let deducted = deductCoinIfPossible(errorMessageHandler: errorMessageHandler)
        guard deducted else {
            throw NSError(domain: "CoinError", code: -1, userInfo: [
                NSLocalizedDescriptionKey: Localization.loc("Not enough coins to perform this action.",
                                                            "硬幣不足，無法執行此操作。")
            ])
        }

        do {
            let result = try await operation()
            return result
        } catch {
            Log.error("\(actionDescription) failed → refunding 1 coin", category: .subscription, error: error)
            RewardedAdManager.shared.earnCoin()
            throw error
        }
    }

    @MainActor
    static func withCoinProtected<T>(
        actionDescription: String = "API operation",
        operation: () async throws -> T
    ) async throws -> T {
        let success = RewardedAdManager.shared.spendCoins(1)
        guard success else {
            throw NSError(domain: "CoinError", code: -1, userInfo: [
                NSLocalizedDescriptionKey: Localization.loc("Not enough coins to perform this action.",
                                                            "硬幣不足，無法執行此操作。")
            ])
        }

        do {
            let result = try await operation()
            return result
        } catch {
            Log.error("\(actionDescription) failed → refunding 1 coin", category: .subscription, error: error)
            RewardedAdManager.shared.earnCoin()
            throw error
        }
    }
}