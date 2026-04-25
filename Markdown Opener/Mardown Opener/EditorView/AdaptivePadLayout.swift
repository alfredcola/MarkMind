//
//  AdaptivePadLayout.swift
//  Markdown Opener
//
//  Created by alfred chen on 8/3/2026.
//
import PDFKit
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

struct AdaptivePadLayout<Sidebar: View, Detail: View>: View {
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail
    @Binding var sidebarVisible: Bool

    private let sidebarWidth: CGFloat = 340

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                // Sidebar
                if sidebarVisible {
                    sidebar()
                        .frame(width: sidebarWidth)
                        .background(
                            Color(UIColor.secondarySystemGroupedBackground)
                        )
                        .transition(.move(edge: .leading))
                }

                // Detail — NOW has its own navigation bar!
                NavigationStack {
                    detail()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(
                .spring(response: 0.35, dampingFraction: 0.88),
                value: sidebarVisible
            )
        }
    }
}
