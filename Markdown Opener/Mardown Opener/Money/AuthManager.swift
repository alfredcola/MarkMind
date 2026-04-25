//
//  AuthManager.swift
//  MarkMind
//

import Combine
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import GoogleSignInSwift  // Optional, for nicer Google Sign-In button

final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var isSignedIn: Bool = false
    @Published var user: User?
    @Published var displayName: String = "User"
    private var coinsListener: ListenerRegistration?

    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }

            self.user = user
            self.isSignedIn = user != nil
            self.displayName = user?.displayName ?? user?.email ?? "User"
            self.manuallyAdsDisabled = UserDefaults.standard.bool(
                forKey: "manually_adsDisabled"
            )

            if user != nil {
                self.loadOrMergeCoins()
                self.loadOrMergeManuallyAdsDisabled()  // Add this
                self.startUserSettingsListener()  // Replace startCoinsListener()
            } else {
                self.stopUserSettingsListener()
            }
        }
    }

    // MARK: - Google Sign In
    func signInWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            print("Missing Firebase clientID")
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        // Get the current root view controller properly
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let rootVC = windowScene.windows
                .first(where: { $0.isKeyWindow })?.rootViewController
        else {
            print("Unable to find root view controller")
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) {
            [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                print("Google Sign-In error: \(error.localizedDescription)")
                return
            }

            guard let user = result?.user,
                let idToken = user.idToken?.tokenString
            else {
                print("Google Sign-In: missing token")
                return
            }

            let accessToken = user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: accessToken
            )

            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    print(
                        "Firebase sign-in error: \(error.localizedDescription)"
                    )
                    return
                }
                print("Signed in with Google successfully")
                self.loadOrMergeCoins()
            }
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            print("Signed out successfully")

            stopUserSettingsListener()

            RewardedAdManager.shared.setCoinsDirectly(0)
            RewardedAdManager.shared.resetDailyRewardClaim()
        } catch {
            print("Sign out error: \(error.localizedDescription)")
        }
    }

    // MARK: - Coin Sync Logic
    func loadOrMergeCoins() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        let userRef = db.collection("users").document(uid)

        userRef.getDocument { [weak self] snapshot, error in
            guard let self = self else { return }

            if let error = error {
                print("Error loading coins: \(error.localizedDescription)")
                return
            }

            let localCoins = UserDefaults.standard.integer(
                forKey: "user_coins_local"
            )

            if let data = snapshot?.data(),
                let cloudCoins = data["coins"] as? Int
            {
                // Cloud exists → ALWAYS use cloud value
                if cloudCoins != RewardedAdManager.shared.coins {
                    RewardedAdManager.shared.setCoinsFromCloud(cloudCoins)
                }
            } else {
                // First time ever → upload local to cloud
                print(
                    "First time: Uploading local coins \(localCoins) to cloud"
                )
                RewardedAdManager.shared.coins = localCoins
                AuthManager.shared.saveCoins(localCoins)
            }
        }
    }

    func saveCoins(_ coins: Int) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        Firestore.firestore()
            .collection("users")
            .document(uid)
            .setData(
                [
                    "coins": coins,
                    "lastUpdated": FieldValue.serverTimestamp(),
                ],
                merge: true
            )
    }

    private func startCoinsListener() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        stopUserSettingsListener()  // Safety

        coinsListener = Firestore.firestore()
            .collection("users")
            .document(uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("Coins listener error: \(error.localizedDescription)")
                    return
                }

                guard let data = snapshot?.data(),
                    let cloudCoins = data["coins"] as? Int
                else {
                    // No coins in cloud yet — don't override local
                    return
                }

                let currentLocal = RewardedAdManager.shared.coins

                // WITH this:
                if cloudCoins != currentLocal {
                    RewardedAdManager.shared.setCoinsFromCloud(cloudCoins)
                }
            }
    }

    // MARK: - Ads Disabled Sync (Manual)

    @Published var manuallyAdsDisabled: Bool = false {
        didSet {
            if oldValue != manuallyAdsDisabled {
                saveManuallyAdsDisabled(manuallyAdsDisabled)
            }
        }
    }

    private func loadOrMergeManuallyAdsDisabled() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        let userRef = db.collection("users").document(uid)

        userRef.getDocument { [weak self] snapshot, error in
            guard let self = self else { return }

            if let error = error {
                print(
                    "Error loading manually_adsDisabled: \(error.localizedDescription)"
                )
                return
            }

            let localValue = UserDefaults.standard.bool(
                forKey: "manually_adsDisabled"
            )

            if let data = snapshot?.data(),
                let cloudValue = data["manually_adsDisabled"] as? Bool
            {
                // Cloud has value → use cloud value (authoritative)
                if cloudValue != localValue {
                    UserDefaults.standard.set(
                        cloudValue,
                        forKey: "manually_adsDisabled"
                    )
                    self.manuallyAdsDisabled = cloudValue
                    MultiSettingsViewModel.shared.manually_adsDisabled =
                        cloudValue
                }
            } else {
                // First time: upload local value to cloud
                print(
                    "First time sync: uploading manually_adsDisabled \(localValue) to cloud"
                )
                self.manuallyAdsDisabled = localValue
                MultiSettingsViewModel.shared.manually_adsDisabled = localValue
                self.saveManuallyAdsDisabled(localValue)
            }
        }
    }

    private func saveManuallyAdsDisabled(_ value: Bool) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        Firestore.firestore()
            .collection("users")
            .document(uid)
            .setData(
                [
                    "manually_adsDisabled": value,
                    "lastUpdated": FieldValue.serverTimestamp(),
                ],
                merge: true
            )
    }

    // Add to existing startCoinsListener() or create a combined listener
    private func startUserSettingsListener() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        stopUserSettingsListener()  // Safety

        coinsListener = Firestore.firestore()  // Reuse the same listener var or rename
            .collection("users")
            .document(uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print(
                        "User settings listener error: \(error.localizedDescription)"
                    )
                    return
                }

                guard let data = snapshot?.data() else { return }

                // Sync coins
                if let cloudCoins = data["coins"] as? Int,
                    cloudCoins != RewardedAdManager.shared.coins
                {
                    RewardedAdManager.shared.setCoinsFromCloud(cloudCoins)
                }

                // Sync manually_adsDisabled
                if let cloudValue = data["manually_adsDisabled"] as? Bool,
                    cloudValue
                        != UserDefaults.standard.bool(
                            forKey: "manually_adsDisabled"
                        )
                {
                    UserDefaults.standard.set(
                        cloudValue,
                        forKey: "manually_adsDisabled"
                    )
                    self.manuallyAdsDisabled = cloudValue
                    MultiSettingsViewModel.shared.manually_adsDisabled =
                        cloudValue
                }
            }
    }

    private func stopUserSettingsListener() {
        coinsListener?.remove()
        coinsListener = nil
    }
}
