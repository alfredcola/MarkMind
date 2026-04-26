// MarkMindApp.swift
// MarkMind
// Created by Alfred Chen on 9/11/2025.
// Updated: December 27, 2025

import Combine
import GoogleMobileAds
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import MLX
import FirebaseCore
import GoogleSignIn

@main
struct MarkMindApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Shared managers
    @StateObject private var favorites = FavoritesManager.shared
    @StateObject private var router = OpenURLRouter()
    @StateObject private var ttsModel = TestAppModel()
    
    // Authentication & Rewarded Ads (for coin sync)
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var rewardedAdManager = RewardedAdManager.shared
    
    // EULA handling
    @AppStorage("hasAcceptedEULAv1") private var hasAcceptedEULA: Bool = false
    @AppStorage("eulaVersionAccepted") private var eulaVersionAccepted: Double = 0
    private let currentEULAVersion: Double = 1.0
    
    @AppStorage("ads_disabled") var adsDisabled: Bool = false

    init() {
        MLX.GPU.set(cacheLimit: Constants.MLX.gpuCacheLimit)
        MLX.GPU.set(memoryLimit: Constants.MLX.gpuMemoryLimit)
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if shouldShowEULA {
                    EULAView(onAccept: acceptEULA)
                } else {
                    AdaptiveRoot()
                        .environmentObject(router)
                        .environmentObject(favorites)
                        .environmentObject(ConversationStore.shared)
                        .environmentObject(FlashcardStore.shared)
                        .environmentObject(DocumentStore.shared)
                        .environmentObject(TagsManager.shared)
                        .environmentObject(ttsModel)
                        .environmentObject(MCStore.shared)
                        .environmentObject(authManager)
                        .environmentObject(rewardedAdManager)
                        .onOpenURL { url in
                            if router.handle(url) {
                                return
                            }
                            
                            _ = GIDSignIn.sharedInstance.handle(url)
                        }
                        .onAppear {
                            SceneDelegate.router = router
                        }
                        .task {
                            await printSharedContainerContents()
                        }
                        .onAppear {
                            if authManager.isSignedIn {
                                authManager.loadOrMergeCoins()
                                
                                RewardedAdManager.shared.checkAndAwardDailyLoginReward()
                            }
                        }
                        // MARK: - NEW: Reload coins every time app enters foreground
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                            if authManager.isSignedIn {
                                print("App entered foreground – syncing latest coins from Firestore")
                                authManager.loadOrMergeCoins()
                            }
                        }
                }
            }
        }
    }
    
    private func printSharedContainerContents() async {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.alfredchen.MarkMind"
        ) else {
            print("App Group container not found!")
            return
        }
        
        print("Shared container path: \(container.path)")
        
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: container.path)
            print("Files in shared container:")
            for file in files {
                print("  - \(file)")
            }
        } catch {
            print("Error reading shared container: \(error)")
        }
    }

    private var shouldShowEULA: Bool {
        !hasAcceptedEULA || eulaVersionAccepted != currentEULAVersion
    }

    private func acceptEULA() {
        hasAcceptedEULA = true
        eulaVersionAccepted = currentEULAVersion
    }
}

// ... (Rest of the file remains unchanged: AppDelegate, SceneDelegate, AdIds, BannerAdContainer, etc.)
// No need to paste the rest — only the changes above matter.

// MARK: - App Delegate (Firebase + AdMob)

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialise Firebase (required before any Firebase services)
        FirebaseApp.configure()
        
        // Initialise Google Mobile Ads
        MobileAds.shared.start(completionHandler: nil)
        
        print("Firebase and AdMob initialised successfully")
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = SceneDelegate.self
        return config
    }
}

// MARK: - Scene Delegate (deep links)

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    static var router: OpenURLRouter?

    func scene(
        _ scene: UIScene,
        openURLContexts contexts: Set<UIOpenURLContext>
    ) {
        guard let url = contexts.first?.url else { return }
        SceneDelegate.router?.handle(url)
    }
}

// MARK: - Ad IDs
enum AdIds {
    static let bannerTop = Constants.Ads.bannerTopID
    static let bannerBottom = Constants.Ads.bannerBottomID
}

// MARK: - Banner Ad Container (Top)

struct BannerAdContainer: View {
    let adUnitID: String
    @State private var adHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                BannerAdView(
                    adUnitID: adUnitID,
                    containerWidth: safeContentWidth(from: geo),
                    onHeightChange: { newHeight in
                        adHeight = newHeight
                    }
                )
                .frame(height: 60)
                .clipped()

                Divider()
                    .accessibilityHidden(adHeight == 0)
                    .padding(.bottom, 2)
            }
        }
        .frame(height: 60)
    }

    private func safeContentWidth(from geo: GeometryProxy) -> CGFloat {
        let insets = geo.safeAreaInsets
        let width = geo.size.width - (insets.leading + insets.trailing)
        return max(0, floor(width))
    }
}

// MARK: - UIKit Banner Wrapper

struct BannerAdView: UIViewRepresentable {
    let adUnitID: String
    let containerWidth: CGFloat
    var onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange)
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitID
        banner.rootViewController = Self.topViewController()
        banner.delegate = context.coordinator
        banner.translatesAutoresizingMaskIntoConstraints = false

        loadAdaptiveBanner(banner, containerWidth: containerWidth)
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        let width = containerWidth
        let currentSize = uiView.adSize.size
        if abs(currentSize.width - width) > 1 || currentSize.height == 0 {
            loadAdaptiveBanner(uiView, containerWidth: width)
        }
    }

    private func loadAdaptiveBanner(
        _ banner: BannerView,
        containerWidth: CGFloat
    ) {
        let viewWidth = max(0, floor(containerWidth))
        guard viewWidth > 0 else { return }

        let adSize = currentOrientationAnchoredAdaptiveBanner(width: viewWidth)
        banner.adSize = adSize
        banner.load(Request())
    }

    // Helper to find the top view controller
    private static func topViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        var onHeightChange: (CGFloat) -> Void

        init(onHeightChange: @escaping (CGFloat) -> Void) {
            self.onHeightChange = onHeightChange
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            onHeightChange(bannerView.adSize.size.height)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            onHeightChange(0)
        }
    }
}

// MARK: - Adaptive Root View

struct AdaptiveRoot: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    @AppStorage("ads_disabled") var adsDisabled: Bool = false
    @EnvironmentObject var router: OpenURLRouter
    
    @State private var showWhatsNew = false
    @AppStorage("lastShownWhatsNewVersion") private var lastShownVersion: String = ""
    
    // Change this string whenever you want to show the What's New sheet
    private let currentAppVersion = "1.1.4"
    
    var body: some View {
        VStack(spacing: 0) {
            EditorView()
        }
        .accentColor(.indigo)
        .preferredColorScheme(appColorScheme)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // Force UI refresh when UserDefaults changes
            NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
        }
        .onAppear {
            if lastShownVersion != currentAppVersion {
                showWhatsNew = true
                lastShownVersion = currentAppVersion
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet(isPresented: $showWhatsNew)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                guard error == nil,
                      let data = item as? Data,
                      let urlString = String(data: data, encoding: .utf8),
                      let url = URL(string: urlString) else {
                    return
                }
                
                DispatchQueue.main.async {
                    _ = self.router.handle(url)
                }
            }
        }
    }
    
    @AppStorage("app_theme") private var appThemeRaw: String = AppTheme.system.rawValue
    
    private var appTheme: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .system
    }
    
    private var appColorScheme: ColorScheme? {
        switch appTheme {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

// MARK: - View Flip Extension

extension View {
    func flippedUpsideDown() -> some View {
        self.rotationEffect(.degrees(180))
            .scaleEffect(x: -1, y: 1, anchor: .center)
    }
}
