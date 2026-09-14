import Foundation
import Combine
import CryptoKit

@MainActor
final class DurableRunController: ObservableObject {
    @Published private(set) var runID: String?
    @Published private(set) var status: DurableRunStatus?
    @Published private(set) var failure: String?
    @Published private(set) var operationFailure: String?
    @Published private(set) var streamNotice: String?
    @Published private(set) var liveText = ""
    @Published private(set) var liveOutputIncomplete = false
    @Published private(set) var activity = ""
    @Published private(set) var lastResponseAt: Date?
    @Published private(set) var isWorking = false
    @Published private(set) var submissionUncertain = false
    let supportsDurableAdmission: Bool
    private let retentionSeconds: TimeInterval
    private let supportsEventReplay: Bool
    private var lastEventSequence = 0
    private struct EventReplayGap: Error {}
    private let client: HermesAPIClient
    private let defaults: UserDefaults
    private let bookmarkKey: String
    private let pendingFile: URL
    private var generation = UUID()
    private var streamAvailableForNewRun = false
    private var pendingSubmission: PendingDurableRun?
    var pendingInput: String? { pendingSubmission?.payload.input }

    init(client: HermesAPIClient, connectionScope: String, supportsDurableAdmission: Bool = false, retentionSeconds: TimeInterval = 0, supportsEventReplay: Bool = false, defaults: UserDefaults = SharedDefaults.shared, pendingDirectory: URL? = nil) {
        self.client = client; self.defaults = defaults
        self.supportsDurableAdmission = supportsDurableAdmission && retentionSeconds > 0
        self.retentionSeconds = retentionSeconds
        self.supportsEventReplay = supportsEventReplay
        bookmarkKey = "hermes.durable-run." + Data(connectionScope.utf8).base64EncodedString()
        let directory = pendingDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HermesPendingRuns", isDirectory: true)
        let digest = SHA256.hash(data: Data(connectionScope.utf8)).map { String(format: "%02x", $0) }.joined()
        pendingFile = directory.appendingPathComponent(digest + ".json")
        runID = defaults.string(forKey: bookmarkKey)
        if FileManager.default.fileExists(atPath: pendingFile.path) {
            do {
                pendingSubmission = try JSONDecoder().decode(PendingDurableRun.self, from: Data(contentsOf: pendingFile))
                submissionUncertain = true
                operationFailure = "A previous run admission needs confirmation. Retry Admission uses its saved message and key; it will not submit the edited conversation as new work."
            } catch {
                submissionUncertain = true
                operationFailure = "Cannot recover the pending run request: \(error.localizedDescription) Unlock the device and reopen this screen. Do not resend this work until the original run has been checked."
            }
        }
    }

    var hasFreshStatus: Bool {
        lastResponseAt.map { Date().timeIntervalSince($0) < 10 } == true && failure == nil
    }

    func attach(_ id: String) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let value = try await client.runStatus(id: id)
            select(id)
            status = value
            activity = value.activityDescription
            lastResponseAt = Date()
        } catch { operationFailure = "Could not attach to run \(id): \(error.localizedDescription) The previously tracked run is retained." }
    }

    func submit(input: String, sessionID: String?, model: String?, provider: String?) async {
        guard supportsDurableAdmission else {
            operationFailure = "This gateway does not advertise durable run idempotency. Run admission is disabled so an uncertain response cannot be retried as duplicate work."
            return
        }
        guard !isWorking, runID == nil || status?.isTerminal == true else { return }
        isWorking = true
        operationFailure = nil
        defer { isWorking = false }
        if pendingSubmission == nil {
            guard !submissionUncertain else { return }
            pendingSubmission = PendingDurableRun(payload: DurableRunRequest(input: input, session_id: sessionID, model: model, provider: provider), key: UUID().uuidString, createdAt: Date())
        }
        guard let pendingSubmission else { return }
        guard Date().timeIntervalSince(pendingSubmission.createdAt) < retentionSeconds else {
            submissionUncertain = true
            operationFailure = "The saved run admission is older than this gateway's idempotency retention window. It was not retried because Hermes could start duplicate work. Check the original run on the server before submitting again."
            return
        }
        do {
            var directory = pendingFile.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try JSONEncoder().encode(pendingSubmission).write(to: pendingFile, options: [.atomic, .completeFileProtection])
        } catch {
            operationFailure = "Run admission was not sent because its recovery request could not be saved: \(error.localizedDescription) Check device storage and unlock the device before retrying."
            return
        }
        do {
            let result = try await client.submitRun(pendingSubmission.payload, idempotencyKey: pendingSubmission.key)
            select(result.run_id)
            streamAvailableForNewRun = result.replayed != true
            try FileManager.default.removeItem(at: pendingFile)
            self.pendingSubmission = nil
            submissionUncertain = false
        } catch {
            // Keep exactly the same body/key for a lost-admission retry. Never
            // silently launch another run just because a network response was lost.
            if let apiError = error as? APIError, case .http(let detail) = apiError,
               [400, 401, 403, 404, 422].contains(detail.status) {
                do { try FileManager.default.removeItem(at: pendingFile) }
                catch {
                    submissionUncertain = true
                    operationFailure = "Hermes rejected admission, but the saved recovery request could not be removed: \(error.localizedDescription) Reopen this screen before submitting different work."
                    return
                }
                self.pendingSubmission = nil
                submissionUncertain = false
                operationFailure = "Hermes rejected run admission: \(error.localizedDescription) Correct the request or connection settings before trying again."
                return
            }
            submissionUncertain = true
            operationFailure = "Could not confirm run admission: \(error.localizedDescription) Retry Admission sends the identical request and idempotency key. Do not submit the same work elsewhere until its status is known."
        }
    }

    func forgetBookmark() {
        guard !isWorking else { return }
        generation = UUID()
        runID = nil
        status = nil
        failure = nil
        operationFailure = nil
        streamNotice = nil
        liveText = ""
        liveOutputIncomplete = false
        activity = ""
        lastResponseAt = nil
        defaults.removeObject(forKey: bookmarkKey)
    }

    private func select(_ id: String) {
        generation = UUID()
        streamAvailableForNewRun = false
        lastEventSequence = 0
        runID = id
        status = nil
        liveText = ""
        liveOutputIncomplete = false
        activity = "Waiting for run status"
        failure = nil
        operationFailure = nil
        streamNotice = nil
        lastResponseAt = nil
        defaults.set(id, forKey: bookmarkKey)
    }

    func monitor() async {
        guard let id = runID else { return }
        let expected = generation
        // Older gateways have a single-consumer queue. Only use cursors and
        // reconnect streaming when the gateway explicitly advertises fanout.
        let shouldStream = supportsEventReplay || streamAvailableForNewRun
        streamAvailableForNewRun = false
        if !shouldStream { streamNotice = "Reconnected to saved run status. Earlier live events cannot be replayed by this gateway; final output and pending approvals remain available." }
        let streamTask = Task { if shouldStream { await receiveEvents(id: id, generation: expected) } }
        defer { streamTask.cancel() }
        repeat {
            await refresh(id: id, generation: expected)
            guard !Task.isCancelled, generation == expected, status?.isTerminal != true else { return }
            do { try await Task.sleep(for: .seconds(failure == nil ? 1 : 3)) }
            catch { return }
        } while !Task.isCancelled
    }

    private func refresh(id: String, generation expected: UUID) async {
        do {
            let value = try await client.runStatus(id: id)
            guard !Task.isCancelled, generation == expected else { return }
            status = value
            lastResponseAt = Date()
            failure = nil
            activity = value.activityDescription
        } catch {
            guard !Task.isCancelled, generation == expected else { return }
            failure = "Could not refresh run \(id): \(error.localizedDescription) Server work may still be active. Reconnection will query this same run."
        }
    }

    private func receiveEvents(id: String, generation expected: UUID) async {
        repeat {
            do {
                let stream = try await client.runEvents(id: id, after: supportsEventReplay ? lastEventSequence : nil)
                for try await event in stream {
                    guard !Task.isCancelled, generation == expected else { return }
                    guard event.runId == id else {
                        throw APIError.invalidEndpoint("The run event stream returned a different or missing run ID. Live events were stopped; status polling remains authoritative.")
                    }
                    if event.event == "error" {
                        if supportsEventReplay && event.code == "run_replay_gap" { throw EventReplayGap() }
                        throw APIError.invalidEndpoint(event.message ?? "The run event stream reported an error without a reason.")
                    }
                    if supportsEventReplay {
                        guard let sequence = event.sequence else { throw EventReplayGap() }
                        if sequence <= lastEventSequence { continue }
                        guard sequence == lastEventSequence + 1 else { throw EventReplayGap() }
                        lastEventSequence = sequence
                    }
                    if event.event == "message.delta", let delta = event.delta {
                        if liveText.utf8.count + delta.utf8.count <= 2_000_000 { liveText += delta }
                        else { liveOutputIncomplete = true }
                    }
                    if event.event == "run.progress", let message = event.message, !message.isEmpty {
                        activity = message
                    } else {
                        activity = [event.event, event.toolName, event.preview].compactMap { $0 }.joined(separator: ": ")
                    }
                    if ["run.completed", "run.failed", "run.cancelled", "run.interrupted"].contains(event.event) { return }
                }
                guard !Task.isCancelled, generation == expected else { return }
                streamNotice = "Live event delivery ended. Rechecking the same run; the final output comes from Hermes's saved status."
            } catch {
                guard !Task.isCancelled, generation == expected else { return }
                let isGap: Bool
                if let apiError = error as? APIError, case .http(let failure) = apiError {
                    isGap = failure.status == 409 && failure.detail?.contains("run_replay_gap") == true
                } else { isGap = error is EventReplayGap }
                if isGap && supportsEventReplay {
                    do {
                        let current = try await client.runStatus(id: id)
                        guard !Task.isCancelled, generation == expected else { return }
                        guard let cursor = current.event_cursor else {
                            streamNotice = "Earlier run events are unavailable and Hermes supplied no recovery cursor. Status polling continues."
                            return
                        }
                        lastEventSequence = cursor
                        liveText = ""
                        liveOutputIncomplete = true
                        streamNotice = "Some earlier live events expired or were missed. Showing new events from the current server cursor; the final saved result will replace this partial view."
                    } catch {
                        streamNotice = "Could not recover the run event cursor: \(error.localizedDescription) Status polling continues."
                        return
                    }
                } else {
                    streamNotice = "Live run events unavailable: \(error.localizedDescription) Status polling continues."
                }
            }
            guard supportsEventReplay, generation == expected, !Task.isCancelled, status?.isTerminal != true else { return }
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
        } while !Task.isCancelled
    }

    func steer(_ text: String) async -> Bool {
        guard let id = runID, status?.status == "running", hasFreshStatus, !isWorking else { return false }
        return await control("send guidance", id: id) { try await self.client.steerRun(id: id, text: text) }
    }

    func decide(requestID: String, choice: String) async {
        guard let id = runID, status?.status == "waiting_for_approval", hasFreshStatus, !isWorking,
              status?.approval?.request_id == requestID, status?.approval?.offeredChoices.contains(choice) == true else { return }
        _ = await control("resolve approval \(requestID)", id: id) {
            try await self.client.approveRun(id: id, requestID: requestID, choice: choice)
        }
    }

    func stop() async {
        guard let id = runID, status?.isTerminal == false, hasFreshStatus, !isWorking else { return }
        _ = await control("stop the run", id: id) { try await self.client.stopRun(id: id) }
    }

    private func control(_ action: String, id: String, operation: () async throws -> Void) async -> Bool {
        let expected = generation
        isWorking = true
        operationFailure = nil
        defer { isWorking = false }
        do {
            try await operation()
            guard generation == expected else { return false }
            failure = nil
            await refresh(id: id, generation: expected)
            return true
        } catch {
            guard generation == expected else { return false }
            operationFailure = "Could not \(action): \(error.localizedDescription) Refresh status before retrying; a lost response does not prove the operation was rejected."
            return false
        }
    }
}
