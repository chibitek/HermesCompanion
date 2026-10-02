import Foundation

/// An inactivity watchdog that resets whenever a stream event arrives.
/// The initial timeout is longer (180s) to allow for server processing +
/// Tailscale latency before the first event. Once events start, recordActivity()
/// resets to the standard interval (90s).
final class StreamWatchdogManager: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var timeout: TimeInterval = 0
    private var deadline: TimeInterval = 0
    private var awaitingFirstActivity = true
    private var action: (() -> Void)?

    func arm(after timeout: TimeInterval, initialTimeout: TimeInterval? = nil, action: @escaping () -> Void) {
        lock.lock()
        self.timeout = timeout
        awaitingFirstActivity = true
        self.deadline = ProcessInfo.processInfo.systemUptime + (initialTimeout ?? timeout)
        self.action = action
        generation += 1
        let currentGeneration = generation
        let useTimeout = initialTimeout ?? timeout
        lock.unlock()
        schedule(generation: currentGeneration, after: useTimeout)
    }

    func recordActivity() {
        lock.lock()
        guard action != nil else {
            lock.unlock()
            return
        }
        // Move one deadline rather than allocating a delayed callback for
        // every token. The existing timer re-arms itself if activity continued.
        deadline = ProcessInfo.processInfo.systemUptime + timeout
        if awaitingFirstActivity {
            awaitingFirstActivity = false
            generation += 1
            let current = generation
            let interval = timeout
            lock.unlock()
            schedule(generation: current, after: interval)
        } else {
            lock.unlock()
        }
    }

    func cancel() {
        lock.lock()
        generation += 1
        action = nil
        lock.unlock()
    }

    private func schedule(generation scheduledGeneration: Int, after timeout: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard self.generation == scheduledGeneration, let action = self.action else {
                self.lock.unlock()
                return
            }
            let remaining = self.deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 {
                self.lock.unlock()
                self.schedule(generation: scheduledGeneration, after: remaining)
                return
            }
            self.action = nil
            self.lock.unlock()
            action()
            return
        }
    }
}
