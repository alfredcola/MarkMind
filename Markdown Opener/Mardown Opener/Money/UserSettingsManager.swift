//
//  UserSettingsManager.swift
//  MarkMind
//
//  Real-time global subscription control
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

/// Listens to a single global document in the top-level "setting" collection
/// to control whether Premium and coin purchase features are enabled app-wide.
final class UserSettingsManager: ObservableObject {
    static let shared = UserSettingsManager()
    
    @Published var isSubscriptionEnabled: Bool = true  // Default: show sections (safe)
    
    private var listener: ListenerRegistration?
    
    // MARK: - Fixed Document ID
    // Change this to match your actual document ID in the "setting" collection
    private let settingsDocumentID = "6So0Dng4AWWJD4UaGwFn"
    
    private init() {
        startGlobalSubscriptionListener()
    }
    
    private func startGlobalSubscriptionListener() {
        let db = Firestore.firestore()
        let settingsRef = db.collection("setting").document(settingsDocumentID)
        
        // Remove any old listener first
        listener?.remove()
        
        listener = settingsRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                Log.error("Global subscription listener error", category: .subscription, error: error)
                // On error, keep showing sections (safe default)
                self.isSubscriptionEnabled = true
                return
            }
            
            guard let data = snapshot?.data() else {
                // Document doesn't exist yet → treat as enabled
                Log.info("Settings document not found – defaulting to enabled", category: .subscription)
                self.isSubscriptionEnabled = true
                return
            }
            
            if let subscription = data["Subscription"] as? Bool {
                Log.debug("Global Subscription updated: \(subscription)", category: .subscription)
                self.isSubscriptionEnabled = subscription
            } else {
                // Field missing or wrong type → fallback
                self.isSubscriptionEnabled = true
            }
        }
        
        Log.debug("Started listening to global setting document: \(settingsDocumentID)", category: .subscription)
    }
    
    deinit {
        listener?.remove()
    }
}
