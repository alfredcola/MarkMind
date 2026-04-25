//
//  EULAView.swift
//  MarkMind
//
//  Created by Alfred Chen on 9/11/2025.
//  Updated: November 9, 2025
//

import SwiftUI

struct EULAView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var agreed = false
    @State private var hasScrolledToBottom = false
    var onAccept: () -> Void = {}

    private let privacyPolicyURL = URL(string: "https://markmind.web.app/privacypolicy.html")!
    private let appleEulaURL      = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private let currentEULAVersion = "1.2"
    private let eulaText = """
        END USER LICENSE AGREEMENT

        Last updated: March 21, 2026

        IMPORTANT: PLEASE READ THIS END USER LICENSE AGREEMENT ("EULA") CAREFULLY BEFORE USING THIS SOFTWARE.

        1. ACCEPTANCE OF TERMS
        By tapping "I Accept" below, you agree to be bound by the terms of this EULA. If you do not agree, tap "Decline" and you will not be able to use the app.

        2. LICENSE GRANT
        "MarkMind" (the "App") is licensed, not sold, to you for use only under the terms of this license. Alfred Chen (the "Developer") reserves all rights not expressly granted to you.

        You are granted a non-transferable, non-exclusive, limited license to install and use the App on any iPhone, iPad, or iPod touch that you own or control, as permitted by Apple’s App Store Terms of Service.

        3. PERMITTED USES
        You may:
        • Use the App for personal, non-commercial purposes.
        • Import, view, edit, and save files.
        • Use AI features (summarization, flashcards, grading) via MiniMax API.

        4. RESTRICTIONS
        You may NOT:
        • Modify, reverse engineer, decompile, or disassemble the App.
        • Distribute, sell, or sublicense the App.
        • Use the App for any unlawful purpose.
        • Remove or alter any copyright, trademark, or other proprietary notices.

        5. THIRD-PARTY SERVICES
        • The App uses the MiniMax API for AI features. You must provide your own valid API key.
        • Use of MiniMax is subject to their terms: https://platform.minimaxi.com/
        • You are responsible for any costs or usage limits from MiniMax.
        • The Developer is not responsible for third-party service availability or performance.

        6. DATA & PRIVACY
        • The App stores files locally in your device’s Documents directory.
        • Chat history, flashcards, and conversation threads are stored locally.
        • No data is sent to the Developer’s servers.
        • WhatsApp chat exports are processed entirely on-device.
        • You are solely responsible for the content you import and process.

        7. NO WARRANTY
        THE APP IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND. THE DEVELOPER DISCLAIMS ALL WARRANTIES, INCLUDING MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.

        8. LIMITATION OF LIABILITY
        IN NO EVENT SHALL THE DEVELOPER BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, OR CONSEQUENTIAL DAMAGES ARISING FROM USE OF THE APP.

        9. TERMINATION
        This license is effective until terminated. Your rights will terminate automatically if you fail to comply with any term. Upon termination, you must delete the App and all copies.

        10. GOVERNING LAW
        This EULA is governed by the laws of Hong Kong SAR.

        11. CONTACT
        For support or questions: alfredwork668@gmail.com

        ---

        By tapping "I Accept", you acknowledge that you have read, understood, and agree to be bound by this EULA.

        © 2026 Chen Ching Lok. All rights reserved.
        """

    var body: some View {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(eulaText)
                            .font(.system(.body, design: .default))
                            .foregroundColor(.primary)
                            .lineSpacing(4)

                        // ── Improved links section ──
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Legal Documents")
                                .font(.headline)
                                .padding(.top, 8)

                            Link("Privacy Policy (our full policy)", destination: privacyPolicyURL)
                                .font(.subheadline)
                                .foregroundColor(.accentColor)

                            Link("Apple Standard EULA (base license terms)", destination: appleEulaURL)
                                .font(.subheadline)
                                .foregroundColor(.accentColor)
                        }
                        .padding(.vertical, 8)

                        if let subscriptionNote = subscriptionNoteText {
                            Text(subscriptionNote)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.top, 12)
                        }

                        Color.clear
                            .frame(height: 1)
                            .onAppear { hasScrolledToBottom = true }
                    }
                    .padding()
                }
                .navigationTitle("License Agreement & Privacy")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    bottomSection
                }
                .onAppear {
                    hasScrolledToBottom = false
                }
            }
            .interactiveDismissDisabled()
        }

        // Update this note to be more accurate and helpful
        private var subscriptionNoteText: String? {
            """
            MarkMind offers auto-renewable subscriptions (e.g. Pro Member – Monthly). 
            Full details including title, price, duration, and renewal terms are displayed before purchase. 
            Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period via your App Store account settings.
            """
        }

        private var bottomSection: some View {
            VStack(spacing: 20) {
                checkbox

                HStack(spacing: 12) {
                    Button("Decline") {
                        exit(0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .cornerRadius(12)
                    .font(.headline)

                    Button("I Accept") {
                        onAccept()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canAccept ? Color.accentColor : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .font(.headline)
                    .disabled(!canAccept)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }

        private var checkbox: some View {
            Button(action: { agreed.toggle() }) {
                HStack {
                    Image(systemName: agreed ? "checkmark.square.fill" : "square")
                        .foregroundColor(agreed ? .accentColor : .secondary)
                        .font(.title2)

                    Text("I have read and agree to the EULA and Privacy Policy")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer()
                }
            }
            .opacity(hasScrolledToBottom ? 1.0 : 0.5)
        }

        private var canAccept: Bool {
            agreed
        }
    }
