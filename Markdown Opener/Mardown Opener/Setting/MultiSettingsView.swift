//
//  MultiSettingsView.swift
//  Markdown Opener
//
//  Created by alfred chen on 8/3/2026.
//

import Combine
import SwiftUI
import WidgetKit

struct MultiSettingsView: View {
    @ObservedObject private var vm = MultiSettingsViewModel.shared
    @EnvironmentObject private var store: DocumentStore
    @State private var titleTapCount: Int = 0
    @State private var showingWhatsNew = false
    @State private var showingChipOrderSheet = false
    // At the top of MultiSettingsView, add these observed objects:
    @ObservedObject private var rewardedAdManager = RewardedAdManager.shared
    @ObservedObject private var authManager = AuthManager.shared
    
    @Binding var showingTagManager: Bool


    private let tapsToRevealAds = 10
    @State private var showWebAdmin = false
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private var adsRevealed: Bool {
        titleTapCount > tapsToRevealAds
    }

    var body: some View {
        if !vm.adsDisabled && !vm.manually_adsDisabled{
            BannerAdContainer(adUnitID: AdIds.bannerTop)
        }
        Form {
            Section("Daily Reward") {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    HStack {
                        Label("Daily Bonus", systemImage: "gift.fill")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                        
                        Spacer()
                        
                        if rewardedAdManager.hasClaimedDailyRewardToday() {
                            Label("Claimed", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Capsule())
                        } else {
                            Text("Available Now!")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    
                    let nextRewardDate = rewardedAdManager.nextDailyRewardDate()
                    let timeUntilNext = nextRewardDate.timeIntervalSince(Date())
                    let hoursUntil = Int(timeUntilNext / 3600)

                    
                    if rewardedAdManager.hasClaimedDailyRewardToday() {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                            Text("Come back the next day to collect more coins.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 8)
                    } else {
                        Button {
                            rewardedAdManager.checkAndAwardDailyLoginReward()
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        } label: {
                            Label("Claim Daily Reward", systemImage: "gift")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Account") {
                NavigationLink {
                    ProfileView()
                } label: {
                    HStack {
                        Label(
                            "\(Text(authManager.displayName))'s Profile",
                            systemImage: "person.crop.circle"
                        )
                        .foregroundStyle(.primary)
                        Spacer()
                        Text("\(rewardedAdManager.coins)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.yellow)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage your account and coins.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Documents will not be synced.")  // Corrected grammar for clarity
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .italic()
                }
            }
            
            if vm.manually_adsDisabled {
                Section("Web Version") {
                    Button {
                        showWebAdmin = true
                    } label: {
                        HStack {
                            Label("Open MarkMind Web", systemImage: "globe")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    
                    Text("Open the web dashboard in-app (markmind.web.app)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if adsRevealed {
                Section("Ads (Dev)") {
                    if vm.manually_adsDisabled {
                        HStack {
                            Label(
                                "Ads Disabled",
                                systemImage: "checkmark.shield.fill"
                            )
                            .foregroundStyle(.green)
                            Spacer()
                            Button("Re-enable Ads") { vm.relockAds() }
                                .buttonStyle(.bordered)
                        }
                        Text("No banners or interstitials will appear.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        SecureField(
                            "Admin password",
                            text: $vm.adsPasswordInput
                        )
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                        Button("Disable All Ads") { vm.unlockAdsRemoval() }
                            .buttonStyle(.borderedProminent)

                        Text(
                            "Enter the secret code to remove ads on this device."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            
            if vm.manually_adsDisabled {
                Section("File ID Management (Debug)") {
                    ForEach(Array(FileIDManager.shared.getAllFileIDs()), id: \.fileID) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.fileName)
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Text(item.fileID)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                    
                    Button("Refresh File IDs") {
                        // Force refresh by accessing each file
                        Task {
                            await FileIDManager.shared.migrateExistingFilesAsync()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Text("\(FileIDManager.shared.getAllFileIDs().count) files with IDs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("What's New?") {
                Button {
                    showingWhatsNew = true
                } label: {
                    HStack(spacing: 12) {
                        Text("What's New in MarkMind")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        ZStack {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.quaternary)
                            Image(systemName: "sparkles")
                                .foregroundStyle(.indigo.gradient)
                                .font(.system(size: 22))
                                .offset(x: -20)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Text("See latest features & improvements")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Library Chips Order") {
                Button {
                    showingChipOrderSheet = true
                } label: {
                    HStack {
                        Text("Reorder Group Chips")
                        Spacer()
                        ZStack {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.quaternary)
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .foregroundStyle(.indigo.gradient)
                                .font(.system(size: 22))
                                .offset(x: -20)
                        }
                    }
                }
                .foregroundStyle(.primary)

                Text(
                    "Drag to reorder Starred, Tags, and file type chips at the top of the library."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            
            Section("Tag Manager") {
                
                Button {
                    showingTagManager = true
                } label: {
                    HStack {
                        Text("Tag Manager")
                        Spacer()
                        ZStack {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.quaternary)
                            Image(systemName: "tag.fill")
                                .foregroundStyle(.indigo.gradient)
                                .font(.system(size: 22))
                                .offset(x: -20)
                        }
                    }
                }
                .foregroundStyle(.primary)
                
            }
            

            Section("File Display") {
                Picker("Sort Order", selection: $vm.fileSort) {
                    ForEach(FileSort.allCases) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .pickerStyle(.menu)
                Text("Changes how files appear in the library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Text-to-Speech") {
                Toggle("Enable TTS", isOn: $vm.ttsEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))

                if vm.ttsEnabled {
                    Picker("AI Voice", selection: $vm.selectedVoice) {
                        ForEach(AIVoice.allCases) { voice in
                            Text(voice.displayName).tag(voice)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(
                        "\(vm.selectedVoice.displayName) (\(vm.selectedVoice.filename))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TTS is currently disabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(
                            "⚠️ Restart the app after enabling TTS for changes to take effect."
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .bold()
                    }
                    .padding(.top, 4)
                }
            }

//            Section("Editor") {
//                Picker("Default View", selection: $vm.defaultEditorView) {
//                    ForEach(EditorViewType.allCases) { viewType in
//                        Text(viewType.rawValue).tag(viewType)
//                    }
//                }
//                .pickerStyle(.segmented)
//                
//                HStack {
//                    Text("Font Size")
//                    Spacer()
//                    Text("\(Int(vm.editorFontSize))pt")
//                        .foregroundStyle(.secondary)
//                }
//                Slider(value: $vm.editorFontSize, in: 12...24, step: 1)
//                    .tint(.indigo)
//                
//                Toggle("Show Line Numbers", isOn: $vm.showLineNumbers)
//                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
//                
//                Toggle("Spell Check", isOn: $vm.spellCheckEnabled)
//                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
//                
//                Text("Configure editor appearance and behavior")
//                    .font(.caption)
//                    .foregroundStyle(.secondary)
//            }

            Section("Auto-Save") {
                Toggle("Enable Auto-Save", isOn: $vm.autoSaveEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                
                if vm.autoSaveEnabled {
                    Picker("Save Interval", selection: $vm.autoSaveInterval) {
                        Text("15 seconds").tag(15)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                    }
                    .pickerStyle(.menu)
                    
                    Text("Your document will be saved automatically")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Appearance") {
                Picker("App Theme", selection: $vm.appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                
                Text("Choose your preferred visual experience")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI") {
                Picker("Reply Language", selection: $vm.aiReplyLanguage) {
                    ForEach(AIReplyLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                //
                //                Picker("AI Model", selection: $vm.selectedModel) {
                //                    ForEach(MiniMaxModel.allCases) { model in
                //                        Text(model.displayName).tag(model)
                //                    }
                //                }
                //                .pickerStyle(.segmented)
                //
                //                Text("Chat = fast • Reasoner = deeper thinking (up to 2 min)")
                //                    .font(.caption)
                //                    .foregroundStyle(.secondary)
            }

            Section("Widget Flashcards") {
                NavigationLink {
                    WidgetFlashcardsManagementView()
                } label: {
                    HStack {
                        Label(
                            "Manage Widget Flashcards",
                            systemImage: "rectangle.on.rectangle"
                        )
                        .foregroundStyle(.primary)
                        Spacer()
                    }
                }

                Text(
                    "Remove flashcards that are no longer needed from your Home Screen widgets."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Tools") {
                Button {
                    vm.showPDFtoMDConverter = true
                } label: {
                    HStack {
                        Label(
                            "Convert PDF to Markdown",
                            systemImage: "arrow.right.doc.on.clipboard"
                        )
                        .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.quaternary)
                            .padding(.trailing, 10)
                    }
                }
                Text(
                    "Extract text from a PDF and import it as an editable Markdown file."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

            }
            
            EmptyStateView()

            Section("How to Use MarkMind") {
                NavigationLink {
                    TutorialVideosView()
                } label: {
                    HStack {
                        Label(
                            "Tutorial Videos",
                            systemImage: "play.rectangle.on.rectangle"
                        )
                        .foregroundStyle(.primary)
                        Spacer()
                    }
                }

                Text("Watch short video guides to get the most out of the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Legal") {
                NavigationLink {
                    EULAView(onAccept: {})
                } label: {
                    Label("End User License Agreement", systemImage: "doc.text")
                }
                Text("View the full EULA.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                EmptyView()
            } footer: {
                VStack(spacing: 8) {
                    Text("MarkMind")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Alfred's Production • September 2025")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .padding(.top, 5)
                .multilineTextAlignment(.center)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(.headline)
                    .onTapGesture {
                        titleTapCount += 1
                        if titleTapCount == tapsToRevealAds + 1 {
                            UIImpactFeedbackGenerator(style: .heavy)
                                .impactOccurred()
                        }
                    }
            }
        }
        .sheet(isPresented: $showWebAdmin) {
            SafariView(url: URL(string: "https://markmind.web.app/")!)
                .ignoresSafeArea(edges: .bottom)     // nicer full-width look
                .presentationDetents([.large])       // almost fullscreen
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $vm.showPDFtoMDConverter) {
            PDFtoMD { convertedTempURL in
                handlePDFConversion(convertedTempURL)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingChipOrderSheet) {
            NavigationStack {
                ChipOrderEditView()
                    .navigationTitle("Chips Order")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingChipOrderSheet = false
                            }
                            .fontWeight(.semibold)
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewSheet(isPresented: $showingWhatsNew)
        }
    }

    // MARK: - PDF to MD Handling Function (moved from EditorView)
    private func handlePDFConversion(_ convertedTempURL: URL?) {
        guard let tempURL = convertedTempURL else { return }

        Task {
            do {
                let finalURL = try await store.importIntoLibrary(from: tempURL)

                await MainActor.run {
                    // Refresh file list and open the new file
                    NotificationCenter.default.post(
                        name: NSNotification.Name("DocumentSaved"),
                        object: nil
                    )
                    // You could also post a custom notification to open the file if needed
                }
            } catch {
                await MainActor.run {
                    // In a real app, show an alert here
                    print(
                        "Failed to import converted PDF: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
}
