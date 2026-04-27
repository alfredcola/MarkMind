import SwiftUI

struct TTSSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var model: TestAppModel
    @ObservedObject private var settingsVM = MultiSettingsViewModel.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Voice") {
                    Picker("Voice", selection: $settingsVM.selectedVoice) {
                        ForEach(AIVoice.allCases, id: \.self) { voice in
                            Text(voice.rawValue.capitalized).tag(voice)
                        }
                    }
                    .onChange(of: settingsVM.selectedVoice) { _, newVoice in
                        model.selectedVoice = newVoice.rawValue
                    }
                }

                Section("Display") {
                    Picker("Font Size", selection: $settingsVM.ttsFontSize) {
                        ForEach(TTSFontSize.allCases) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }

                    Picker("Highlighting", selection: $settingsVM.ttsHighlightingStyle) {
                        ForEach(TTSHighlightingStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }

                    Picker("Theme", selection: $settingsVM.ttsTheme) {
                        ForEach(TTSTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                }

                Section("Playback") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Speed")
                            Spacer()
                            Text(String(format: "%.1fx", settingsVM.ttsPlaybackSpeed))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settingsVM.ttsPlaybackSpeed, in: 0.5...2.0, step: 0.25)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Pitch")
                            Spacer()
                            Text(String(format: "%.1fx", settingsVM.ttsPitch))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settingsVM.ttsPitch, in: 0.5...2.0, step: 0.1)
                    }
                }

                Section("Resume") {
                    Toggle("Auto Resume", isOn: $settingsVM.ttsAutoResume)
                }

                Section {
                    Button("Clear All Reading Positions") {
                        TTSReadingPositionManager.shared.clearAllPositions()
                    }
                    .foregroundColor(.red)
                }

                Section("Cache") {
                    HStack {
                        Text("Preloaded Audio")
                        Spacer()
                        Text(TTSPersistentAudioCache.shared.formattedCachedSize)
                            .foregroundColor(.secondary)
                    }

                    Button("Clear All Preloaded Audio") {
                        TTSPersistentAudioCache.shared.clearAllCachedAudio()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("TTS Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
