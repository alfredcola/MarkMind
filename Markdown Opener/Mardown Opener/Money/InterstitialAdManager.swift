//
//  InterstitialAdManager.swift
//  Markdown Opener
//
//  Created by alfred chen on 9/11/2025.
//

import GoogleMobileAds
import Combine
import UIKit
import SwiftUI

@MainActor
final class InterstitialAdManager: NSObject, ObservableObject {
    static let shared = InterstitialAdManager()
    @AppStorage("ads_disabled") var adsDisabled: Bool = false
    @AppStorage("manually_adsDisabled") var manually_adsDisabled: Bool = false

    
    @Published var isLoading = false
    private var interstitial: InterstitialAd?
    
    private let adUnitID = "ca-app-pub-2445337445676652/5437686206"
    
    private override init() {
        super.init()
        loadAd()
    }
    
    // MARK: - 載入廣告
    func loadAd() {
        guard !isLoading, interstitial == nil else { return }
        isLoading = true
        
        let request = Request()
        InterstitialAd.load(with: adUnitID, request: request) { [weak self] ad, error in
            guard let self else { return }
            self.isLoading = false
            if let error = error {
                print("Interstitial load failed: \(error.localizedDescription)")
                return
            }
            self.interstitial = ad
            self.interstitial?.fullScreenContentDelegate = self
        }
    }
    
    // MARK: - 顯示廣告
    func present(from root: UIViewController? = nil) {
        if !adsDisabled && !manually_adsDisabled{
            guard let ad = interstitial else {
                print("No interstitial ad ready.")
                loadAd()
                return
            }
            
            do {
                try ad.canPresent(from: root)  // root can be nil; SDK will use topmost VC.
                ad.present(from: root)
                interstitial = nil
                loadAd()
            } catch {
                print("Interstitial cannot present: \(error.localizedDescription)")
                interstitial = nil
                loadAd()
            }
        }
    }
}

// MARK: - GADFullScreenContentDelegate
extension InterstitialAdManager: FullScreenContentDelegate {
    
    // 廣告即將顯示（adDidPresentFullScreenContent 已被替換為 adWillPresentFullScreenContent）
    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("Interstitial will present.")
    }
    
    // 廣告被關閉
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("Interstitial dismissed.")
        interstitial = nil
        loadAd()
    }
    
    // 廣告顯示失敗
    func ad(_ ad: any FullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: any Error) {
        print("Interstitial failed to present: \(error.localizedDescription)")
        interstitial = nil
        loadAd()
    }
}
