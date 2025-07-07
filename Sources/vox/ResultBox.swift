import Foundation

/// Thread-safe result container for async operations
final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: T?
    private var error: Error?

    func setValue(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        self.result = value
    }

    func setError(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        self.error = error
    }

    func getResult() throws -> T {
        lock.lock()
        defer { lock.unlock() }

        if let error = error {
            throw error
        }

        guard let result = result else {
            throw VoxError.processingFailed("Async operation did not complete")
        }

        return result
    }
}
