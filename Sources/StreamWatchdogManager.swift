import Foundation

/// An inactivity watchdog that resets whenever a stream event arrives.
final class StreamWatchdogManager: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var timeout: TimeInterval = 0
    private var action: (() -> Void)?

    func arm(after timeout: TimeInterval, action: @escaping () -> Void) {
        lock.lock()
        self.timeout = timeout
        self.action = action
        generation += 1
        let currentGeneration = generation
        lock.unlock()
        schedule(generation: currentGeneration, after: timeout)
    }

    func recordActivity() {
        lock.lock()
        guard action != nil else {
            lock.unlock()
            return
        }
        generation += 1
        let currentGeneration = generation
        let currentTimeout = timeout
        lock.unlock()
        schedule(generation: currentGeneration, after: currentTimeout)
    }

    func cancel() {
        lock.lock()
        generation += 1
        action = nil
        lock.unlock()
    }

    private func schedule(generation scheduledGeneration: Int, after timeout: TimeInterval) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard self.generation == scheduledGeneration, let action = self.action else {
                self.lock.unlock()
                return
            }
            self.action = nil
            self.lock.unlock()
            DispatchQueue.main.async(execute: action)
        }
    }
}
