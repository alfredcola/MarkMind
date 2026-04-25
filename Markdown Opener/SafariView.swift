//
//  SafariView.swift
//  Markdown Opener
//
//  Created by alfred chen on 28/12/2025.
//


import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.barCollapsingEnabled = false          // ← prevents weird resizing in sheet
        let safari = SFSafariViewController(url: url, configuration: config)
        return safari
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // no update needed
    }
}