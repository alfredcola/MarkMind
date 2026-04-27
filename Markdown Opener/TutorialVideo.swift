//
//  TutorialVideosView.swift
//  MarkMind
//
//  Created by Alfred Chen on 22/12/2025.
//

import SwiftUI

// MARK: - Tutorial Video Model
struct TutorialVideo: Identifiable {
    let id = UUID()
    let title: String
    let youtubeID: String  // Only the video ID, e.g., "qLxm8JV1v44"
    
    var thumbnailURL: URL {
        // High-quality thumbnail
        URL(string: "https://img.youtube.com/vi/\(youtubeID)/hqdefault.jpg")!
    }
    
    var watchURL: URL {
        // Works for both regular videos and Shorts
        URL(string: "https://www.youtube.com/watch?v=\(youtubeID)")!
    }
}

// MARK: - Tutorial Videos View
struct TutorialVideosView: View {
    let videos: [TutorialVideo] = [
        TutorialVideo(
            title: "MarkMind | One Stop Self-Study App – Import Documents",
            youtubeID: "qLxm8JV1v44"  // Correct ID from https://youtube.com/shorts/qLxm8JV1v44
        ),
        TutorialVideo(
            title: "MarkMind | How to Add Flashcards to Home Screen Widget",
            youtubeID: "QUPzgkBpu7w"  // From https://youtube.com/shorts/QUPzgkBpu7w
        ),
        TutorialVideo(
            title: "MarkMind | How to Use Flashcards Effectively – Self-Study Tips",
            youtubeID: "tFKIrFH8Ees"  // From https://youtube.com/shorts/tFKIrFH8Ees
        ),
        TutorialVideo(
            title: "MarkMind | How to Create and Use MC Quizzes for Self-Study",
            youtubeID: "HZWnVMBjl4U"  // From https://youtube.com/shorts/HZWnVMBjl4U
        ),
        TutorialVideo(
            title: "MarkMind | How to Select Text & Query AI Instantly",
            youtubeID: "9Y8EN57RoAQ"  // From https://youtube.com/shorts/9Y8EN57RoAQ
        ),
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 20) {
                ForEach(videos) { video in
                    Button(action: {
                        UIApplication.shared.open(video.watchURL)
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            // Thumbnail with fallback
                            AsyncImage(url: video.thumbnailURL) { phase in
                                switch phase {
                                case .empty:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay(ProgressView())
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                case .failure:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay(
                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 60))
                                                .foregroundColor(.white.opacity(0.8))
                                        )
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(height: 180)
                            .clipped()
                            .cornerRadius(12)
                            
                            Text(video.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)  // Slightly more room for longer titles
                            
                            HStack {
                                Image(systemName: "play.circle")
                                Text("Watch on YouTube")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
        }
        .navigationTitle("How to Use MarkMind")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TutorialVideosView()
    }
}
