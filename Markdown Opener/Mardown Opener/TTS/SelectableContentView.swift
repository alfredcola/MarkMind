//
//  SelectableContentView.swift
//  Markdown Opener
//
//  Created by alfred chen on 22/12/2025.
//


import SwiftUI
import PDFKit
import UIKit

struct SelectableContentView<Content: UIView>: UIViewRepresentable {
    let contentView: Content
    let onAskAIAboutSelection: (String) -> Void
    @Binding var isEditorFullScreen: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onAskAIAboutSelection: onAskAIAboutSelection)
    }
    
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        
        // Add content view (PDFView or UITextView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentView)
        
        // Floating Ask AI button
        let askButton = UIButton(configuration: .filled(), primaryAction: nil)
        var cfg = askButton.configuration!
        cfg.baseBackgroundColor = .systemOrange.withAlphaComponent(0.85)
        cfg.baseForegroundColor = .white
        cfg.title = "Ask AI"
        cfg.image = UIImage(systemName: "brain.head.profile")
        cfg.imagePlacement = .leading
        cfg.imagePadding = 8
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16)
        cfg.cornerStyle = .capsule
        askButton.configuration = cfg
        askButton.layer.shadowOpacity = 0.4
        askButton.layer.shadowRadius = 10
        askButton.layer.shadowOffset = CGSize(width: 0, height: 5)
        askButton.layer.shadowColor = UIColor.black.cgColor
        askButton.isHidden = true
        askButton.alpha = 0
        askButton.addTarget(context.coordinator, action: #selector(Coordinator.askAITapped), for: .touchUpInside)
        
        context.coordinator.askButton = askButton
        context.coordinator.contentView = contentView
        
        // Add subviews
        container.addSubview(askButton)
        
        askButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: container.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            askButton.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -70),
            askButton.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -15),
        ])
        
        context.coordinator.startMonitoringSelection()
        return container
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        let shouldShowButton = !isEditorFullScreen
        context.coordinator.askButton?.isHidden = !shouldShowButton
        context.coordinator.askButton?.alpha = shouldShowButton ? 1.0 : 0.0
    }
    
    class Coordinator: NSObject {
        let onAskAIAboutSelection: (String) -> Void
        var askButton: UIButton?
        var contentView: Content?
        var selectionTimer: Timer?
        private var cachedSelectedText: String = ""
        
        init(onAskAIAboutSelection: @escaping (String) -> Void) {
            self.onAskAIAboutSelection = onAskAIAboutSelection
        }
        
        @objc func askAITapped() {
            let rawText = cachedSelectedText
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmed.isEmpty else {
                hideAskButton()
                clearSelection()
                return
            }
            
            stopMonitoringSelection()
            onAskAIAboutSelection(rawText)
            clearSelection()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startMonitoringSelection()
            }
        }
        
        func startMonitoringSelection() {
            selectionTimer?.invalidate()
            selectionTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                self?.checkSelection()
            }
            checkSelection()
        }
        
        func stopMonitoringSelection() {
            selectionTimer?.invalidate()
            selectionTimer = nil
            hideAskButton()
        }
        
        private func checkSelection() {
            guard let view = contentView else { return }
            
            let selectedText: String
            if let pdfView = view as? PDFView {
                selectedText = pdfView.currentSelection?.string ?? ""
            } else if let textView = view as? UITextView {
                if let range = textView.selectedTextRange, !range.isEmpty {
                    selectedText = textView.text(in: range) ?? ""
                } else {
                    selectedText = ""
                }
            } else {
                selectedText = ""
            }
            
            let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasText = !trimmed.isEmpty
            
            cachedSelectedText = selectedText
            
            DispatchQueue.main.async {
                self.showAskButton(show: hasText)
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
            if let pdfView = contentView as? PDFView {
                pdfView.clearSelection()
            } else if let textView = contentView as? UITextView {
                textView.selectedTextRange = nil
            }
        }
        
        deinit {
            stopMonitoringSelection()
        }
    }
}