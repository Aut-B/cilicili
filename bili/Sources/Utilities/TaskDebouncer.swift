import Foundation

@MainActor
final class TaskDebouncer {
    private var task: Task<Void, Never>?

    func schedule(delay: Duration = .milliseconds(350), action: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay.timeInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

