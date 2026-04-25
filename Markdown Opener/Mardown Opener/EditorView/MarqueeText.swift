//
//  MarqueeText.swift
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

struct MarqueeText: View {
    let text: String
    let style: Font.TextStyle
    let foregroundColor: Color?
    let speed: CGFloat = 30  // pixels per second

    @State private var offsetX: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(foregroundColor!)
                    .fixedSize()
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    textWidth = proxy.size.width
                                }
                        }
                    )
            }
            .frame(width: containerWidth)
            .offset(x: offsetX)
            .onAppear {
                containerWidth = geo.size.width
                startScroll()
            }
            .onDisappear {
                offsetX = 0
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIDevice.orientationDidChangeNotification
                )
            ) { _ in
                containerWidth = geo.size.width
                offsetX = 0
                startScroll()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startScroll() {
        guard textWidth > containerWidth else {
            offsetX = 0
            return
        }

        let totalDistance = textWidth + containerWidth
        let duration = totalDistance / speed

        withAnimation(
            .linear(duration: duration).repeatForever(autoreverses: false)
        ) {
            offsetX = -totalDistance
        }
    }
}
