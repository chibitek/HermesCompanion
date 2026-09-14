import XCTest
@testable import HermesCompanion

/// Opt-in integration against the operator's real gateway. Credentials arrive
/// through TEST_RUNNER_HERMES_LIVE_KEY, never a tracked configuration file.
final class LiveGatewayTests: XCTestCase {
    @MainActor
    func testRealGatewayQueuedFollowUpIsConfirmedOnceInOriginalConversation() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HERMES_DISPOSABLE_WORKSPACE"] == "1",
              let url = environment["HERMES_LIVE_URL"], let key = environment["HERMES_LIVE_KEY"] else {
            throw XCTSkip("Queue verification requires the disposable workspace runner.")
        }
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: url, apiKey: key, label: "Queue verification"))
        let options = try await client.getModelOptions()
        let session = try await client.createSession(title: "Queued follow-up verification", model: options.model, provider: options.provider)
        let store = AppStore(client: client)
        do {
            await store.selectSession(session)
            let firstText = "Queue verification only. Reply with exactly HERMES_QUEUE_FIRST. Do not use tools or take any actions."
            let followUp = "Follow-up verification only. Reply with exactly HERMES_QUEUE_SECOND. Do not use tools or take any actions."
            let sending = Task { await store.sendMessage(firstText) }
            defer { sending.cancel(); store.stopStreaming() }
            try await waitForLiveSync { store.isStreaming }
            XCTAssertTrue(store.queueMessage(followUp))
            XCTAssertEqual(store.queuedMessages.first?.sessionID, session.id)
            let answer = try await withTimeout(seconds: 90) { await sending.value }
            XCTAssertNotNil(answer)
            let deadline = ContinuousClock.now + .seconds(90)
            while !store.queuedMessages.isEmpty, store.error == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertNil(store.error, store.error?.message ?? "")
            XCTAssertTrue(store.queuedMessages.isEmpty, "A successful queue must receive confirmation before removing its entry")
            XCTAssertEqual(store.activeSession?.id, session.id)
            let history = try await client.getMessages(sessionId: session.id)
            XCTAssertEqual(history.filter(\.isUser).compactMap(\.content), [firstText, followUp])
            XCTAssertEqual(history.filter(\.isAssistant).count, 2)
        } catch {
            store.stopStreaming()
            try await client.deleteSession(sessionId: session.id)
            throw error
        }
        try await client.deleteSession(sessionId: session.id)
    }

    @MainActor
    func testRealGatewayStreamMatchesCanonicalAnswerWithoutJoiningWords() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HERMES_DISPOSABLE_WORKSPACE"] == "1",
              let url = environment["HERMES_LIVE_URL"], let key = environment["HERMES_LIVE_KEY"] else {
            throw XCTSkip("Stream fidelity verification requires the disposable workspace runner.")
        }
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: url, apiKey: key, label: "Stream fidelity"))
        let options = try await client.getModelOptions()
        let session = try await client.createSession(title: "Stream fidelity verification", model: options.model, provider: options.provider)
        do {
            let store = AppStore(client: client)
            await store.selectSession(session)
            var livePrefixes: [String] = []
            let observation = store.$streamingText.sink { text in
                if !text.isEmpty { livePrefixes.append(text) }
            }
            defer { observation.cancel() }
            let response = await store.sendMessage("Stream verification only. Reply with exactly: HERMES FIDELITY CHECK PASSED. Do not call tools or take any actions.")
            XCTAssertNil(store.error, store.error?.message ?? "")
            let answer = try XCTUnwrap(response?.content)
            XCTAssertTrue(answer.contains(" "), "The verification answer must exercise word spacing")
            XCTAssertGreaterThan(livePrefixes.count, 1, "Verify live deltas, not only a final response")
            for prefix in livePrefixes {
                XCTAssertTrue(answer.hasPrefix(prefix), "Every live prefix must retain the gateway's word boundaries")
            }
            let history = try await client.getMessages(sessionId: session.id)
            let persisted = try XCTUnwrap(history.last(where: \.isAssistant))
            XCTAssertEqual(answer, ChatDisplayMessage(from: persisted).content)
        } catch {
            try await client.deleteSession(sessionId: session.id)
            throw error
        }
        try await client.deleteSession(sessionId: session.id)
    }

    @MainActor
    func testRealGatewayTwoClientConversationAndRename() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["HERMES_LIVE_URL"],
              let key = environment["HERMES_LIVE_KEY"], !key.isEmpty else {
            throw XCTSkip("Set HERMES_LIVE_URL and HERMES_LIVE_KEY for a real gateway test.")
        }
        let config = ConnectionConfig(baseURL: url, apiKey: key, label: "Live verification")
        let phoneClient = HermesAPIClient(config: config)
        let otherClient = HermesAPIClient(config: config)
        let health = try await phoneClient.checkHealth()
        XCTAssertTrue(health.isHermesAPI)
        let options = try await phoneClient.getModelOptions()
        let session = try await phoneClient.createSession(title: "Companion sync verification \(UUID().uuidString)", model: options.model, provider: options.provider)
        do {
            let store = AppStore(client: phoneClient)
            await store.selectSession(session)
            let response = try await withTimeout(seconds: 90) { await store.sendMessage("Connection verification only. Reply with exactly HERMES_SYNC_CHECK. Do not use tools, access files, or take any actions.") }
            XCTAssertNil(store.error, store.error?.message ?? "")
            XCTAssertNotNil(response)
            let durable = try await otherClient.getMessages(sessionId: session.id)
            XCTAssertTrue(durable.contains { $0.isAssistant && ($0.content?.contains("HERMES_SYNC_CHECK") == true) })
            let liveSync = Task { await store.runLiveSync() }
            defer { liveSync.cancel() }
            try await waitForLiveSync { store.liveChangesAvailable }
            _ = try await otherClient.patchSession(sessionId: session.id, title: "Companion sync verified")
            try await waitForLiveSync { store.activeSession?.title == "Companion sync verified" }

            let remote = try await withTimeout(seconds: 90) { try await otherClient.sendChat(sessionId: session.id,
                message: "Second-client connection verification only. Reply with exactly HERMES_REMOTE_CHECK. Do not use tools or take actions.") }
            XCTAssertTrue(remote.message.content.contains("HERMES_REMOTE_CHECK"))
            try await waitForLiveSync {
                store.messages.contains { $0.isAssistant && $0.content.contains("HERMES_REMOTE_CHECK") }
            }
            XCTAssertNotNil(store.lastSyncedAt)
            XCTAssertNil(store.syncError)
        } catch {
            try await otherClient.deleteSession(sessionId: session.id)
            throw error
        }
        try await otherClient.deleteSession(sessionId: session.id)
    }

    @MainActor
    func testRealGatewayRunHasIndependentViewersAndReplay() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["HERMES_LIVE_URL"],
              let key = environment["HERMES_LIVE_KEY"], !key.isEmpty else {
            throw XCTSkip("Set HERMES_LIVE_URL and HERMES_LIVE_KEY for a real gateway test.")
        }
        let config = ConnectionConfig(baseURL: url, apiKey: key, label: "Live replay verification")
        let first = HermesAPIClient(config: config)
        let second = HermesAPIClient(config: config)
        let capabilities = try await first.getCapabilities()
        guard capabilities.features.runEventReplay?.supported == true,
              capabilities.features.runEventReplay?.fanout == true else {
            throw XCTSkip("This gateway does not advertise independent run event replay.")
        }
        let options = try await first.getModelOptions()
        let session = try await first.createSession(title: "Companion replay verification \(UUID().uuidString)", model: options.model, provider: options.provider)
        var runID: String?
        do {
            let accepted = try await first.submitRun(DurableRunRequest(
                input: "Connection verification only. Reply with exactly HERMES_REPLAY_CHECK. Do not use tools, access files, or take actions.",
                session_id: session.id, model: options.model, provider: options.provider), idempotencyKey: UUID().uuidString)
            runID = accepted.run_id
            async let one = collectRun(first, id: accepted.run_id)
            async let two = collectRun(second, id: accepted.run_id)
            let (a, b) = try await (one, two)
            XCTAssertFalse(a.isEmpty)
            XCTAssertEqual(a.map(\.sequence), b.map(\.sequence))
            XCTAssertEqual(a.compactMap(\.delta).joined(), b.compactMap(\.delta).joined())
            XCTAssertTrue(a.compactMap(\.delta).joined().contains("HERMES_REPLAY_CHECK"))
            XCTAssertEqual(a.last?.event, "run.completed")
            XCTAssertEqual(b.last?.event, "run.completed")
            let status = try await second.runStatus(id: accepted.run_id)
            XCTAssertEqual(status.status, "completed", status.error ?? "Unexpected run outcome")
            XCTAssertTrue(status.output?.contains("HERMES_REPLAY_CHECK") == true)
            let history = try await second.getMessages(sessionId: session.id)
            XCTAssertTrue(history.contains { $0.isAssistant && $0.content?.contains("HERMES_REPLAY_CHECK") == true })
            let cursor = try XCTUnwrap(a.last(where: { $0.event == "message.delta" })?.sequence)
            let replay = try await collectRun(second, id: accepted.run_id, after: cursor)
            XCTAssertFalse(replay.isEmpty)
            XCTAssertTrue(replay.allSatisfy { ($0.sequence ?? 0) > cursor })
            XCTAssertEqual(replay.last?.event, "run.completed")
        } catch {
            if let runID {
                let status = try await second.runStatus(id: runID)
                if !status.isTerminal {
                    try await second.stopRun(id: runID)
                    // Do not delete a transcript while its diagnostic run is still active.
                    for _ in 0..<20 {
                        if try await second.runStatus(id: runID).isTerminal { break }
                        try await Task.sleep(for: .milliseconds(250))
                    }
                    guard try await second.runStatus(id: runID).isTerminal else { throw error }
                }
            }
            try await second.deleteSession(sessionId: session.id)
            throw error
        }
        try await second.deleteSession(sessionId: session.id)
    }

    @MainActor
    func testRealGatewayBoardManagementAndLiveInvalidation() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HERMES_DISPOSABLE_WORKSPACE"] == "1",
              let url = environment["HERMES_LIVE_URL"], let key = environment["HERMES_LIVE_KEY"] else {
            throw XCTSkip("Board mutation verification requires the disposable workspace runner.")
        }
        let config = ConnectionConfig(baseURL: url, apiKey: key, label: "Board verification")
        let phone = HermesAPIClient(config: config)
        let desktop = HermesAPIClient(config: config)
        let slug = "verify-" + UUID().uuidString.lowercased()
        let store = AppStore(client: phone)
        let live = Task { await store.runLiveSync() }
        defer { live.cancel() }
        try await waitForLiveSync { store.liveChangesAvailable }
        var payload = ServerBoardWrite()
        payload.slug = slug
        payload.name = "Phone board"
        let created = try await phone.createWorkspaceBoard(payload: payload)
        XCTAssertEqual(created.board.slug, slug)
        do {
            let initialRevision = store.workspaceRevision
            var desktopEdit = ServerBoardWrite()
            desktopEdit.name = "Desktop rename"
            _ = try await desktop.updateWorkspaceBoard(slug: slug, payload: desktopEdit)
            try await waitForLiveSync { store.workspaceRevision > initialRevision }
            let boards = try await phone.workspaceBoards()
            XCTAssertEqual(boards.boards.first { $0.slug == slug }?.name, "Desktop rename")
            let retry = try await phone.createWorkspaceBoard(payload: payload)
            XCTAssertEqual(retry.already_exists, true)
            XCTAssertEqual(retry.board.name, "Desktop rename")
            try await phone.performWorkspaceBoardAction(slug: slug, archive: false)
            let active = try await desktop.workspaceBoards()
            XCTAssertEqual(active.current, slug)
        } catch {
            try await phone.performWorkspaceBoardAction(slug: slug, archive: true)
            throw error
        }
        try await phone.performWorkspaceBoardAction(slug: slug, archive: true)
        let remaining = try await desktop.workspaceBoards()
        XCTAssertFalse(remaining.boards.contains { $0.slug == slug })
        XCTAssertEqual(remaining.current, "default")
    }

    @MainActor
    private func waitForLiveSync(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                throw APIError.invalidEndpoint("Automatic live sync did not reflect the remote change within 10 seconds")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func collectRun(_ client: HermesAPIClient, id: String, after: Int? = nil) async throws -> [SSEEventPayload] {
        try await withTimeout(seconds: 120) {
            var result: [SSEEventPayload] = []
            let stream = try await client.runEvents(id: id, after: after)
            for try await event in stream {
                guard event.runId == id, event.sequence != nil else {
                    throw APIError.invalidEndpoint("Live run verification received an unsequenced or foreign event")
                }
                result.append(event)
                if ["run.completed", "run.failed", "run.cancelled", "run.interrupted"].contains(event.event) { break }
            }
            return result
        }
    }

}
