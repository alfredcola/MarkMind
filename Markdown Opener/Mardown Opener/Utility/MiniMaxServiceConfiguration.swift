import Foundation
import Combine

final class MiniMaxServiceConfiguration: ObservableObject {
    static let shared = MiniMaxServiceConfiguration()

    @Published var enableStreaming: Bool = true
    @Published var streamingChunkSize: Int = 20
    @Published var connectTimeout: TimeInterval = 30
    @Published var readTimeout: TimeInterval = 240

    private init() {}
}
