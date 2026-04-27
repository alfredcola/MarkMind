import Foundation

actor BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    private var activeTasks: [UUID: Task<Void, Error>] = [:]
    private let maxConcurrentTasks = 3

    private init() {}

    func enqueue<T: Sendable>(
        name: String,
        priority: TaskPriority = .medium,
        operation: @escaping () async throws -> T
    ) async -> Task<T, Error> {
        let id = UUID()

        let task = Task(priority: priority) {
            while activeTasks.count >= maxConcurrentTasks {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            let trackingTask = Task<Void, Error> {
                defer {
                    Task { self.taskCompleted(id: id) }
                }
                _ = try await operation()
            }
            activeTasks[id] = trackingTask

            return try await trackingTask.value
        }

        return task as! Task<T, any Error>
    }

    private func taskCompleted(id: UUID) {
        activeTasks.removeValue(forKey: id)
    }

    func enqueueSaving(
        data: Data,
        to url: URL,
        name: String = "save"
    ) async throws {
        try await Task(priority: .utility) {
            try data.write(to: url, options: .atomic)
        }.value
    }

    func cancelAll() {
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
    }

    var activeTaskCount: Int {
        activeTasks.count
    }
}

final class FileCoordinator {
    static func coordinatedWrite(to url: URL, data: Data) throws {
        var coordinatorError: NSError?
        var writeError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinatorError
        ) { newURL in
            do {
                try data.write(to: newURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let error = coordinatorError {
            throw error
        }
        if let error = writeError {
            throw error
        }
    }

    static func coordinatedRead(from url: URL) throws -> Data {
        var coordinatorError: NSError?
        var readError: Error?
        var result: Data?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinatorError
        ) { newURL in
            do {
                result = try Data(contentsOf: newURL)
            } catch {
                readError = error
            }
        }

        if let error = coordinatorError {
            throw error
        }
        if let error = readError {
            throw error
        }
        guard let data = result else {
            throw NSError(domain: "FileCoordinator", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to read data"
            ])
        }
        return data
    }
}
