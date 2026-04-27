//
//  TTSSheet.swift
//  Markdown Opener
//
//  Created by alfred chen on 8/12/2025.
//
import AVFoundation
import MLX
import KokoroSwift
import Combine
import MLXUtilsLibrary
import SwiftUI
import WebKit


struct WebMarkdownView: UIViewRepresentable {
    let markdown: String
    let onAskAIAboutSelection: (String) -> Void
    
    @Binding var isEditorFullScreen: Bool
    @Binding var ttsEnabled: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true   // ← needed for selection JS
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsHorizontalScrollIndicator = false
        
        // Allow text selection (default on iOS, but we make sure)
        webView.configuration.selectionGranularity = .dynamic
        
        // Ask AI floating button
        let askButton = UIButton(configuration: .filled(), primaryAction: nil)
        if var askCfg = askButton.configuration {
            askCfg.baseBackgroundColor = .systemOrange.withAlphaComponent(0.85)
            askCfg.baseForegroundColor = .white
            askCfg.title = "Ask AI"
            askCfg.image = UIImage(systemName: "brain.head.profile")
            askCfg.imagePlacement = .leading
            askCfg.imagePadding = 8
            askCfg.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16)
            askCfg.cornerStyle = .capsule
            askButton.configuration = askCfg
        }
        
        askButton.layer.shadowOpacity = 0.4
        askButton.layer.shadowRadius = 10
        askButton.layer.shadowOffset = CGSize(width: 0, height: 5)
        askButton.layer.shadowColor = UIColor.black.cgColor
        
        askButton.isHidden = true
        askButton.alpha = 0
        askButton.addTarget(context.coordinator, action: #selector(Coordinator.askAITapped), for: .touchUpInside)
        
        // Store references
        context.coordinator.webView = webView
        context.coordinator.askButton = askButton
        
        container.addSubview(webView)
        container.addSubview(askButton)
        
        webView.translatesAutoresizingMaskIntoConstraints = false
        askButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            askButton.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            askButton.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -15),
        ])
        
        context.coordinator.startMonitoringSelection()
        return container
    }
    
    static func exportHTML(markdown: String) -> String {
        let escaped =
        markdown
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let htmlBody = SimpleMarkdown.gfmToHTML(from: escaped)
        let css = """
                <style>
                body { font: -apple-system-body; padding: 16px; color: #111; overflow-wrap: break-word; word-wrap: break-word; }
                h1,h2,h3 { margin-top: 1.0em; }
                code, pre { font-family: ui-monospace, Menlo, monospace; background: #f5f5f7; }
                pre { padding: 12px; border-radius: 8px; overflow-x: auto; white-space: pre-wrap; word-wrap: normal; }
                table { border-collapse: collapse; width: 100%; max-width: 100%; overflow-x: auto; display: block; }
                th, td { border: 1px solid #ddd; padding: 8px; }
                blockquote { border-left: 4px solid #ddd; padding-left: 12px; color: #555; }
                img { max-width: 100%; height: auto; display: block; }
                ::selection { background: #FFEB3B; color: black; }
                </style>
                """
        return """
                <html><head>\(css)</head><body>\(htmlBody)</body></html>
                """
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.debouncedUpdate(markdown: markdown, isEditorFullScreen: isEditorFullScreen) {
            uiView.layoutIfNeeded()
        }
    }
    
    class Coordinator: NSObject {
        var parent: WebMarkdownView
        var webView: WKWebView?
        var askButton: UIButton?
        
        // MARK: - Scroll Restoration
        private var lastSavedScrollY: CGFloat = 0
        private var scrollRestoreTimer: Timer?
        
        // MARK: - Cached Selection
        private var cachedSelectedText: String = ""
        
        private var selectionTimer: Timer?
        
        // MARK: - Debounced Preview Update
        private var previewUpdateTimer: Timer?
        private let previewDebounceInterval: TimeInterval = 0.3
        
        init(_ parent: WebMarkdownView) {
            self.parent = parent
            super.init()
        }
        
        func debouncedUpdate(markdown: String, isEditorFullScreen: Bool, completion: @escaping () -> Void) {
            previewUpdateTimer?.invalidate()
            previewUpdateTimer = Timer.scheduledTimer(withTimeInterval: previewDebounceInterval, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.performPreviewUpdate(markdown: markdown, isEditorFullScreen: isEditorFullScreen)
                completion()
            }
        }

        private func performPreviewUpdate(markdown: String, isEditorFullScreen: Bool) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let html = WebMarkdownView.exportHTML(markdown: markdown)
                let styledHTML = """
                <style>
                    @media (prefers-color-scheme: dark) {
                        body, p, div, span, h1, h2, h3, h4, h5, h6 { color: white !important; }
                        ::selection { background: #FFD60A; }
                    }
                    ::selection { background: #FFEB3B; color: black; }
                    body { -webkit-user-select: text; user-select: text; }
                </style>
                \(html)
                """
                DispatchQueue.main.async {
                    self?.webView?.loadHTMLString(styledHTML, baseURL: nil)

                    self?.webView?.evaluateJavaScript("document.readyState") { [weak self] result, _ in
                        if let readyState = result as? String, readyState == "complete" {
                            self?.restoreScrollPosition()
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                self?.restoreScrollPosition()
                            }
                        }
                    }

                    self?.startMonitoringSelection()

                    UIView.animate(withDuration: 0.35) {
                        self?.askButton?.alpha = isEditorFullScreen ? 0 : 1
                    }
                }
            }
        }
        
        @objc func askAITapped() {
            let rawSelectedText = cachedSelectedText
            let trimmedForCheck = rawSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmedForCheck.isEmpty else {
                Log.warning("[WebMarkdownView] Ask AI tapped but selection is effectively empty", category: .tts)
                hideAskButton()
                clearSelection()
                return
            }
            
            Log.debug("[WebMarkdownView] Ask AI tapped → captured text (\(rawSelectedText.count) raw chars)", category: .tts)
            
            stopMonitoringSelection()
            parent.onAskAIAboutSelection(rawSelectedText)
            clearSelection()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startMonitoringSelection()
            }
        }
        
        // MARK: - Scroll Position Management
        
        func startMonitoringScrollPosition() {
            scrollRestoreTimer?.invalidate()
            scrollRestoreTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.saveCurrentScrollPosition()
            }
            // Save immediately
            saveCurrentScrollPosition()
        }
        
        func stopMonitoringScrollPosition() {
            scrollRestoreTimer?.invalidate()
            scrollRestoreTimer = nil
        }
        
        private func saveCurrentScrollPosition() {
            let js = """
            (function() {
                return {
                    scrollY: window.scrollY,
                    scrollHeight: document.body.scrollHeight,
                    clientHeight: document.documentElement.clientHeight
                };
            })();
            """
            
            webView?.evaluateJavaScript(js) { [weak self] result, _ in
                if let dict = result as? [String: Any],
                   let scrollY = dict["scrollY"] as? CGFloat {
                    self?.lastSavedScrollY = scrollY
                }
            }
        }
        
        func restoreScrollPosition() {
            guard lastSavedScrollY > 0 else { return }
            
            let js = "window.scrollTo(0, \(lastSavedScrollY));"
            
            // Small delay to ensure content is laid out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.webView?.evaluateJavaScript(js, completionHandler: { _, error in
                    if let error = error {
                    } else {
                        Log.debug("Restored scroll position to \(self.lastSavedScrollY)", category: .tts)
                    }
                })
            }
        }
        
        // MARK: - Selection Monitoring (unchanged except starting scroll monitoring)
        
        func startMonitoringSelection() {
            selectionTimer?.invalidate()
            selectionTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                self?.updateCachedSelection()
            }
            updateCachedSelection()
            
            // Also start monitoring scroll while we're here
            startMonitoringScrollPosition()
        }
        
        func stopMonitoringSelection() {
            selectionTimer?.invalidate()
            selectionTimer = nil
            hideAskButton()
            stopMonitoringScrollPosition()
        }
        
        private func updateCachedSelection() {
            let js = """
            (function() {
                var sel = window.getSelection();
                if (sel.rangeCount > 0) {
                    return sel.toString();
                }
                return '';
            })();
            """
            
            webView?.evaluateJavaScript(js) { [weak self] result, _ in
                guard let rawText = result as? String else { return }
                
                let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasText = !trimmed.isEmpty
                
                DispatchQueue.main.async {
                    self?.cachedSelectedText = rawText
                    self?.showAskButton(show: hasText)
                }
            }
        }
        
        private func showAskButton(show: Bool) {
            guard let btn = askButton else { return }
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
                btn.isHidden = !show
                btn.alpha = show ? 1.0 : 0.0
                btn.transform = show ? .identity : CGAffineTransform(scaleX: 0.8, y: 0.8)
            }
        }
        
        private func hideAskButton() {
            showAskButton(show: false)
        }
        
        private func clearSelection() {
            webView?.evaluateJavaScript("window.getSelection().removeAllRanges();", completionHandler: nil)
        }
        
        deinit {
            stopMonitoringSelection()
            stopMonitoringScrollPosition()
            previewUpdateTimer?.invalidate()
        }
    }

}

struct WebMarkdownViewWithTTS: View {
    let markdown: String
    let onAskAIAboutSelection: (String) -> Void
    let filePath: String?

    @Binding var isEditorFullScreen: Bool

    var body: some View {
        WebMarkdownView(
            markdown: markdown,
            onAskAIAboutSelection: onAskAIAboutSelection,
            isEditorFullScreen: $isEditorFullScreen,
            ttsEnabled: .constant(MultiSettingsViewModel.shared.ttsEnabled)
        )
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: isEditorFullScreen)
    }
}
