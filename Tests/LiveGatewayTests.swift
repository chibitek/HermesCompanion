import XCTest
@testable import HermesCompanion

/// Opt-in integration against the operator's real gateway. Credentials arrive
/// through TEST_RUNNER_HERMES_LIVE_KEY, never a tracked configuration file.
final class LiveGatewayTests: XCTestCase {
    override func tearDown() async throws {
        let environment = ProcessInfo.processInfo.environment
        if environment["HERMES_DISPOSABLE_WORKSPACE"] == "1",
           let url = environment["HERMES_LIVE_URL"], let key = environment["HERMES_LIVE_KEY"] {
            let client = HermesAPIClient(config: ConnectionConfig(baseURL: url, apiKey: key, label: "Cleanup verification"))
            let remaining = try await client.listSessions()
            XCTAssertTrue(remaining.isEmpty, "Disposable gateway retained sessions after this test: \(remaining.map(\.id))")
        }
        try await super.tearDown()
    }

    @MainActor
    func testRealGatewayReasoningOverrideReachesAgentWithoutPersisting() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HERMES_DISPOSABLE_WORKSPACE"] == "1",
              let url = environment["HERMES_LIVE_URL"], let key = environment["HERMES_LIVE_KEY"] else {
            throw XCTSkip("Reasoning verification requires the disposable workspace runner.")
        }
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: url, apiKey: key, label: "Reasoning verification"))
        let capabilities = try await client.getCapabilities()
        XCTAssertEqual(capabilities.features.sessionChatReasoning, true)
        let options = try await client.getModelOptions()
        let session = try await client.createSession(title: "Reasoning verification", model: options.model, provider: options.provider)
        do {
            let baseline = try await client.sendChat(sessionId: session.id,
                message: "Connection check. Reply only READY. Do not use tools or take actions.")
            let stream = try await client.streamChat(sessionId: session.id,
                message: "Connection check. Reply only READY. Do not use tools or take actions.", reasoningEffort: "none")
            var streamedRuntime: SessionRuntime?
            for try await event in stream {
                if event.event == "error" { XCTFail(event.message ?? "Reasoning stream failed") }
                if event.event == "assistant.completed" { streamedRuntime = event.runtime }
            }
            XCTAssertEqual(streamedRuntime?.reasoning?.enabled, false)
            let low = try await client.sendChat(sessionId: session.id,
                message: "Connection check. Reply only READY. Do not use tools or take actions.", reasoningEffort: "low")
            XCTAssertEqual(low.runtime?.reasoning?.effort, "low")
            let secondClient = HermesAPIClient(config: ConnectionConfig(baseURL: url, apiKey: key, label: "Independent reasoning reader"))
            let restored = try await secondClient.sendChat(sessionId: session.id,
                message: "Connection check. Reply only READY. Do not use tools or take actions.")
            XCTAssertEqual(restored.runtime?.reasoning, baseline.runtime?.reasoning,
                           "Per-turn reasoning must not change another client's conversation default")
        } catch {
            try await client.deleteSession(sessionId: session.id)
            throw error
        }
        try await client.deleteSession(sessionId: session.id)
    }

    @MainActor
    func testRealGatewayActiveChatSteeringPreservesConsumedOrPendingGuidance() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HERMES_DISPOSABLE_WORKSPACE"] == "1",
              let url = environment["HERMES_LIVE_URL"], let key = environment["HERMES_LIVE_KEY"] else {
            throw XCTSkip("Active steering verification requires the disposable workspace runner.")
        }
        let config = ConnectionConfig(baseURL: url, apiKey: key, label: "Active steering verification")
        let client = HermesAPIClient(config: config)
        let otherClient = HermesAPIClient(config: config)
        let options = try await client.getModelOptions()
        let session = try await client.createSession(title: "Active steering verification", model: options.model, provider: options.provider)
        let store = AppStore(client: client)
        store.capabilities = try await client.getCapabilities()
        store.activeSession = session
        let guidance = "Additional guidance: include HERMES_ACTIVE_STEER_CHECK in your next response. Do not use tools or take actions."
        let externalGuidance = "Additional guidance from a second client: include HERMES_SECOND_STEER_CHECK in your next response. Do not use tools or take actions."
        let startedAt = Date()
        var firstActivitySeconds: Double?
        var acceptanceSeconds: Double?
        var externalSteerTask: Task<Void, Error>?
        var requested = false
        var accepted = false
        var runID: String?
        let streamObservation = store.$streamingText.sink { text in
            guard !requested, !text.isEmpty, store.canSteerCurrentChat else { return }
            requested = true
            runID = store.activeChatRunID
            firstActivitySeconds = Date().timeIntervalSince(startedAt)
            XCTAssertTrue(store.queueMessage(guidance))
            if let id = runID {
                externalSteerTask = Task { try await otherClient.steerRun(id: id, text: externalGuidance) }
            }
        }
        let queueObservation = store.$queuedMessages.sink { rows in
            if !accepted, rows.contains(where: { $0.guidanceAccepted == true }) {
                accepted = true
                acceptanceSeconds = Date().timeIntervalSince(startedAt)
            }
        }
        defer { streamObservation.cancel(); queueObservation.cancel() }
        do {
            _ = try await withTimeout(seconds: 120) {
                await store.sendMessage("For a connection verification, write six short paragraphs about the history of typography, about 300 words total. Do not use tools or take actions.")
            }
            await store.chatGuidanceTask?.value
            try await XCTUnwrap(externalSteerTask).value
            XCTAssertTrue(requested, "No steerable response activity was observed")
            XCTAssertNil(store.error)
            let id = try XCTUnwrap(runID)
            let status = try await otherClient.runStatus(id: id)
            XCTAssertEqual(status.status, "completed")
            XCTAssertTrue(accepted || status.pending_steer?.contains("HERMES_ACTIVE_STEER_CHECK") == true,
                          "The real gateway did not confirm steering acceptance")
            let history = try await otherClient.getMessages(sessionId: session.id)
            for marker in ["HERMES_ACTIVE_STEER_CHECK", "HERMES_SECOND_STEER_CHECK"] {
                if status.pending_steer?.contains(marker) == true {
                    XCTAssertTrue(store.queuedMessages.contains { $0.payload.contains(marker) && $0.state == .needsReview },
                                  "The server's pending guidance must be recoverable even when sent by another client")
                } else {
                    XCTAssertTrue(history.contains { $0.isUser && $0.content?.contains(marker) == true },
                                  "Accepted guidance must appear in canonical history or pending recovery")
                }
            }
            if status.pending_steer?.isEmpty != false { XCTAssertTrue(store.queuedMessages.isEmpty) }
            print("STEERING_TIMING first_activity_seconds=\(firstActivitySeconds ?? -1) acceptance_seconds=\(acceptanceSeconds ?? -1) total_seconds=\(Date().timeIntervalSince(startedAt))")
            XCTAssertFalse(store.isStreaming)
        } catch {
            store.stopStreaming(discardQueuedMessages: false)
            try await client.deleteSession(sessionId: session.id)
            throw error
        }
        try await client.deleteSession(sessionId: session.id)
    }

    @MainActor
    func testRealGatewayStructuredAcknowledgementMatchesCompletedMessage() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HERMES_DISPOSABLE_WORKSPACE"] == "1",
              let url = environment["HERMES_LIVE_URL"], let key = environment["HERMES_LIVE_KEY"] else {
            throw XCTSkip("Structured message verification requires the disposable workspace runner.")
        }
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: url, apiKey: key, label: "Message contract"))
        let options = try await client.getModelOptions()
        let session = try await client.createSession(title: "Structured acknowledgement verification", model: options.model, provider: options.provider)
        do {
            let events = try await withTimeout(seconds: 90) {
                var events: [SSEEventPayload] = []
                let stream = try await client.streamChat(sessionId: session.id,
                    message: "Message contract verification only. Reply with exactly HERMES_MESSAGE_CHECK. Do not use tools or take actions.")
                for try await event in stream { events.append(event) }
                return events
            }
            let started = try XCTUnwrap(events.first { $0.event == "message.started" })
            let message = try XCTUnwrap(started.structuredMessage)
            let messageID = try XCTUnwrap(message.id)
            XCTAssertEqual(message.role, "assistant")
            XCTAssertNil(started.message)
            let completed = try XCTUnwrap(events.first { $0.event == "assistant.completed" })
            XCTAssertEqual(completed.message_id, messageID)
            XCTAssertEqual(completed.sessionId, session.id)
            XCTAssertFalse(completed.content?.isEmpty ?? true)
            let store = AppStore(client: client)
            _ = await store.handleSSEEvent(started)
            XCTAssertEqual(store.responseActivity, "Hermes accepted the message")
            XCTAssertTrue(store.messages.isEmpty)
        } catch {
            try await client.deleteSession(sessionId: session.id)
            throw error
        }
        try await client.deleteSession(sessionId: session.id)
    }

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
    func testRealGatewayTasksRoundTripWithNativeDesktopAndAttachments() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HERMES_DISPOSABLE_WORKSPACE"] == "1",
              let url = environment["HERMES_LIVE_URL"], let key = environment["HERMES_LIVE_KEY"],
              let slug = environment["HERMES_LIVE_KANBAN_BOARD"] else {
            throw XCTSkip("Native task verification requires the disposable workspace runner.")
        }
        let config = ConnectionConfig(baseURL: url, apiKey: key, label: "Task verification")
        let phone = HermesAPIClient(config: config)
        let second = HermesAPIClient(config: config)
        let store = AppStore(client: phone)
        let live = Task { await store.runLiveSync() }
        defer { live.cancel() }
        try await waitForLiveSync { store.liveChangesAvailable }
        var board = ServerBoardWrite()
        board.slug = slug
        board.name = "Native task verification"
        _ = try await phone.createWorkspaceBoard(payload: board)
        do {
            var creation = ServerTaskWrite()
            creation.title = "Phone task verification"
            creation.body = "Phone description"
            creation.idempotency_key = UUID().uuidString
            let created = try await phone.createWorkspaceTask(board: slug, payload: creation)
            let taskID = created.task.id
            let retry = try await phone.createWorkspaceTask(board: slug, payload: creation)
            XCTAssertEqual(retry.task.id, taskID)
            let seenBySecond = try await second.workspaceTask(board: slug, id: taskID)
            XCTAssertEqual(seenBySecond.task.body, "Phone description")
            // Native child completion requires its parent dependency to be done.
            var completion = ServerTaskWrite()
            completion.status = "done"
            completion.result = "Phone completion result"
            completion.summary = "Phone completion summary"
            _ = try await phone.updateWorkspaceTask(board: slug, taskID: taskID, payload: completion)
            let revision = store.workspaceRevision
            try await phone.commentWorkspaceTask(board: slug, taskID: taskID, body: "Phone ready for desktop changes")
            let nativeDeadline = ContinuousClock.now + .seconds(20)
            var detail = try await phone.workspaceTask(board: slug, id: taskID)
            while detail.task.title != "Desktop task update", ContinuousClock.now < nativeDeadline {
                try await Task.sleep(for: .milliseconds(200))
                detail = try await phone.workspaceTask(board: slug, id: taskID)
            }
            XCTAssertEqual(detail.task.title, "Desktop task update")
            try await waitForLiveSync { store.workspaceRevision > revision }
            XCTAssertTrue(detail.comments.contains { $0.body == "Desktop comment arrived" && $0.author == "dashboard" })
            XCTAssertEqual(detail.links?.children.count, 1)
            XCTAssertEqual(detail.child_results?.first?.result, "Native child result")
            XCTAssertEqual(detail.child_results?.first?.latest_summary, "Native child summary")
            let attachment = try XCTUnwrap(detail.attachments?.first)
            let download = try await phone.downloadTaskAttachment(board: slug, taskID: taskID, attachment: attachment)
            defer { try? FileManager.default.removeItem(at: download.deletingLastPathComponent()) }
            XCTAssertEqual(try Data(contentsOf: download), Data("Hermes attachment round trip: café\n".utf8))
            var changes = ServerTaskWrite()
            changes.priority = 2
            _ = try await phone.updateWorkspaceTask(board: slug, taskID: taskID, payload: changes)
            let completed = try await second.workspaceTask(board: slug, id: taskID)
            XCTAssertEqual(completed.task.body, "Desktop body retained")
            XCTAssertEqual(completed.task.result, "Phone completion result")
            let removalRevision = store.workspaceRevision
            try await phone.commentWorkspaceTask(board: slug, taskID: taskID, body: "Phone verified desktop attachment")
            let removalDeadline = ContinuousClock.now + .seconds(20)
            detail = try await phone.workspaceTask(board: slug, id: taskID)
            while detail.task.title != "Desktop removal complete", ContinuousClock.now < removalDeadline {
                try await Task.sleep(for: .milliseconds(200))
                detail = try await phone.workspaceTask(board: slug, id: taskID)
            }
            XCTAssertEqual(detail.task.title, "Desktop removal complete")
            XCTAssertTrue(detail.attachments?.isEmpty == true)
            XCTAssertTrue(detail.links?.children.isEmpty == true)
            try await waitForLiveSync { store.workspaceRevision > removalRevision }
            do {
                let unexpected = try await phone.downloadTaskAttachment(board: slug, taskID: taskID, attachment: attachment)
                try? FileManager.default.removeItem(at: unexpected.deletingLastPathComponent())
                XCTFail("A removed attachment must not remain downloadable")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("Attachment is not in the selected task"))
            }
            var archive = ServerTaskWrite()
            archive.status = "archived"
            _ = try await phone.updateWorkspaceTask(board: slug, taskID: taskID, payload: archive)
            let archived = try await second.workspaceTask(board: slug, id: taskID)
            XCTAssertEqual(archived.task.status, "archived")
        } catch {
            try await phone.performWorkspaceBoardAction(slug: slug, archive: true)
            throw error
        }
        try await phone.performWorkspaceBoardAction(slug: slug, archive: true)
        let remaining = try await second.workspaceBoards()
        XCTAssertFalse(remaining.boards.contains { $0.slug == slug })
        live.cancel()
        await live.value
    }

    @MainActor
    func testRealGatewayProjectsSyncAcrossClientsAndRetainLinkedFiles() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HERMES_DISPOSABLE_WORKSPACE"] == "1",
              let url = environment["HERMES_LIVE_URL"], let key = environment["HERMES_LIVE_KEY"],
              let folder = environment["HERMES_LIVE_PROJECT_FOLDER"],
              let reference = environment["HERMES_LIVE_REFERENCE_FOLDER"] else {
            throw XCTSkip("Project lifecycle verification requires the disposable workspace runner.")
        }
        let config = ConnectionConfig(baseURL: url, apiKey: key, label: "Project verification")
        let phone = HermesAPIClient(config: config)
        let second = HermesAPIClient(config: config)
        let capabilities = try await phone.workspaceCapabilities()
        XCTAssertEqual(capabilities.project_manage, true)
        let store = AppStore(client: phone)
        let live = Task { await store.runLiveSync() }
        defer { live.cancel() }
        try await waitForLiveSync { store.liveChangesAvailable }
        let before = try await phone.managedProjects(profile: "default")
        XCTAssertTrue(before.projects.isEmpty)
        XCTAssertNil(before.active_id)
        var payload = ProjectWrite()
        payload.name = "Phone project verification"
        payload.folders = [folder]
        let creationRevision = store.workspaceRevision
        let created = try await phone.saveProject(profile: "default", id: nil, payload: payload)
        var deleted = false
        let startedAt = Date()
        do {
            try await waitForLiveSync { store.workspaceRevision > creationRevision }
            let read = try await second.managedProject(profile: "default", id: created.id)
            XCTAssertEqual(read.name, payload.name)
            XCTAssertEqual(read.primary_path, folder)
            let revision = store.workspaceRevision
            var edit = ProjectWrite()
            edit.name = "Second client project edit"
            edit.description = "Remote edit retained by the phone"
            _ = try await second.saveProject(profile: "default", id: created.id, payload: edit)
            try await waitForLiveSync { store.workspaceRevision > revision }
            let updated = try await phone.managedProject(profile: "default", id: created.id)
            XCTAssertEqual(updated.name, edit.name)
            XCTAssertEqual(updated.description, edit.description)
            _ = try await phone.changeProjectFolder(profile: "default", id: created.id, action: .add,
                payload: ProjectFolderWrite(path: reference, label: "Reference", is_primary: true))
            let linked = try await second.managedProject(profile: "default", id: created.id)
            XCTAssertEqual(linked.primary_path, reference)
            XCTAssertEqual(Set(linked.folders.map(\.path)), Set([folder, reference]))
            try await second.archiveProject(profile: "default", id: created.id, restore: false)
            let archived = try await phone.managedProject(profile: "default", id: created.id)
            XCTAssertTrue(archived.archived)
            try await phone.archiveProject(profile: "default", id: created.id, restore: true)
            let restored = try await second.managedProject(profile: "default", id: created.id)
            XCTAssertFalse(restored.archived)
            try await phone.activateProject(profile: "default", id: created.id)
            let active = try await second.managedProjects(profile: "default")
            XCTAssertEqual(active.active_id, created.id)
            do {
                try await second.deleteProject(profile: "default", id: created.id)
                XCTFail("Deleting an active project must be rejected")
            } catch let APIError.http(failure) {
                XCTAssertEqual(failure.status, 400)
                XCTAssertTrue(failure.errorDescription?.contains("active") == true)
            }
            let retained = try await phone.managedProject(profile: "default", id: created.id)
            XCTAssertEqual(retained.id, created.id)
            try await second.activateProject(profile: "default", id: nil)
            let deletionRevision = store.workspaceRevision
            try await phone.deleteProject(profile: "default", id: created.id)
            deleted = true
            try await waitForLiveSync { store.workspaceRevision > deletionRevision }
            let final = try await second.managedProjects(profile: "default")
            XCTAssertTrue(final.projects.isEmpty)
            XCTAssertNil(final.active_id)
            print("PROJECT_SYNC_TIMING lifecycle_seconds=\(Date().timeIntervalSince(startedAt))")
        } catch {
            if !deleted {
                try await phone.activateProject(profile: "default", id: nil)
                try await phone.deleteProject(profile: "default", id: created.id)
            }
            throw error
        }
    }

    @MainActor
    func testRealGatewayJobDeliveryFailureAndRecoverySyncDiagnostics() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HERMES_DISPOSABLE_WORKSPACE"] == "1",
              let url = environment["HERMES_LIVE_URL"], let key = environment["HERMES_LIVE_KEY"] else {
            throw XCTSkip("Delivery verification requires the disposable workspace runner.")
        }
        let config = ConnectionConfig(baseURL: url, apiKey: key, label: "Delivery verification")
        let phone = HermesAPIClient(config: config)
        let second = HermesAPIClient(config: config)
        let store = AppStore(client: phone)
        let live = Task { await store.runLiveSync() }
        defer { live.cancel() }
        try await waitForLiveSync { store.liveChangesAvailable }
        // API-created jobs have api_server/api as their origin. This unsupported
        // return channel fails locally; no external recipient is configured.
        let job = try await phone.createJob(HermesJobWrite(name: "Delivery recovery verification",
            schedule: "0 0 1 1 *", prompt: "Connection verification. Reply only READY. Do not use tools or take actions.", deliver: "origin", skills: []))
        do {
            try await second.runJob(jobId: job.id)
            let firstDeadline = ContinuousClock.now + .seconds(180)
            while store.platformJobs.first(where: { $0.id == job.id })?.lastStatus == nil,
                  ContinuousClock.now < firstDeadline { try await Task.sleep(for: .milliseconds(200)) }
            let failed = try XCTUnwrap(store.platformJobs.first(where: { $0.id == job.id }))
            XCTAssertEqual(failed.lastStatus, "delivery_failed")
            XCTAssertNil(failed.lastError, "Delivery failure must not invent an agent execution error")
            let reason = try XCTUnwrap(failed.lastDeliveryError)
            XCTAssertFalse(reason.isEmpty)
            XCTAssertEqual(failed.diagnostics.first(where: { $0.id == "delivery" })?.detail, reason)
            let failedAt = try XCTUnwrap(failed.lastRunAt)
            _ = try await second.updateJob(jobId: job.id, updates:
                HermesJobWrite(name: nil, schedule: nil, prompt: nil, deliver: "local", skills: nil))
            try await second.runJob(jobId: job.id)
            let recoveryDeadline = ContinuousClock.now + .seconds(180)
            while ContinuousClock.now < recoveryDeadline {
                if let current = store.platformJobs.first(where: { $0.id == job.id }),
                   current.lastRunAt != failedAt, current.lastStatus == "ok" { break }
                try await Task.sleep(for: .milliseconds(200))
            }
            let recovered = try XCTUnwrap(store.platformJobs.first(where: { $0.id == job.id }))
            XCTAssertEqual(recovered.lastStatus, "ok")
            XCTAssertNotEqual(recovered.lastRunAt, failedAt)
            XCTAssertNil(recovered.lastDeliveryError)
            XCTAssertTrue(recovered.diagnostics.isEmpty)
            let canonical = try await second.listJobs().first(where: { $0.id == job.id })
            XCTAssertEqual(canonical?.lastRunAt, recovered.lastRunAt)
            XCTAssertNil(canonical?.lastDeliveryError)
            let sessions = try await phone.listSessions().filter { $0.id.hasPrefix("cron_\(job.id)_") }
            XCTAssertEqual(sessions.count, 2)
            for session in sessions { try await phone.deleteSession(sessionId: session.id) }
        } catch {
            try await phone.pauseJob(jobId: job.id)
            try await phone.deleteJob(jobId: job.id)
            throw error
        }
        try await phone.deleteJob(jobId: job.id)
        try await waitForLiveSync { !store.platformJobs.contains(where: { $0.id == job.id }) }
    }

    @MainActor
    func testRealGatewayJobsSyncAcrossClients() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HERMES_DISPOSABLE_WORKSPACE"] == "1",
              let url = environment["HERMES_LIVE_URL"], let key = environment["HERMES_LIVE_KEY"] else {
            throw XCTSkip("Job lifecycle verification requires the disposable workspace runner.")
        }
        let config = ConnectionConfig(baseURL: url, apiKey: key, label: "Job verification")
        let phone = HermesAPIClient(config: config)
        let second = HermesAPIClient(config: config)
        let store = AppStore(client: phone)
        let live = Task { await store.runLiveSync() }
        defer { live.cancel() }
        try await waitForLiveSync { store.liveChangesAvailable }
        let before = try await phone.listJobs()
        XCTAssertTrue(before.isEmpty)
        let created = try await second.createJob(HermesJobWrite(name: "Two-client verification",
            schedule: "0 0 1 1 *", prompt: "Local connection verification. Reply READY.", deliver: "local", skills: []))
        var deleted = false
        do {
            try await waitForLiveSync { store.platformJobs.contains { $0.id == created.id } }
            var edit = HermesJobWrite(name: "Phone job edit", schedule: nil, prompt: nil, deliver: nil, skills: nil)
            _ = try await phone.updateJob(jobId: created.id, updates: edit)
            let afterEdit = try await second.listJobs()
            XCTAssertEqual(afterEdit.first?.name, edit.name)
            try await second.pauseJob(jobId: created.id)
            try await waitForLiveSync { store.platformJobs.first?.enabled == false }
            XCTAssertEqual(store.platformJobs.first?.state, "paused")
            try await phone.resumeJob(jobId: created.id)
            let resumed = try await second.listJobs()
            XCTAssertEqual(resumed.first?.enabled, true)
            XCTAssertEqual(resumed.first?.state, "scheduled")
            XCTAssertNotNil(resumed.first?.nextRunAt)
            edit.name = "Second client final edit"
            _ = try await second.updateJob(jobId: created.id, updates: edit)
            try await waitForLiveSync { store.platformJobs.first?.name == edit.name }
            try await second.deleteJob(jobId: created.id)
            deleted = true
            try await waitForLiveSync { store.platformJobs.isEmpty }
            let remaining = try await phone.listJobs()
            XCTAssertTrue(remaining.isEmpty)
        } catch {
            if !deleted { try await phone.deleteJob(jobId: created.id) }
            throw error
        }
    }

    @MainActor
    func testRealGatewayScheduledJobExecutionSyncsResult() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HERMES_DISPOSABLE_WORKSPACE"] == "1",
              let url = environment["HERMES_LIVE_URL"], let key = environment["HERMES_LIVE_KEY"] else {
            throw XCTSkip("Scheduler execution requires the disposable workspace runner.")
        }
        let config = ConnectionConfig(baseURL: url, apiKey: key, label: "Scheduler verification")
        let phone = HermesAPIClient(config: config)
        let second = HermesAPIClient(config: config)
        let store = AppStore(client: phone)
        let live = Task { await store.runLiveSync() }
        defer { live.cancel() }
        try await waitForLiveSync { store.liveChangesAvailable }
        let before = try await phone.listJobs()
        XCTAssertTrue(before.isEmpty)
        let job = try await phone.createJob(HermesJobWrite(name: "Local scheduler verification",
            schedule: "0 0 1 1 *", prompt: "Connection verification. Reply only READY. Do not use tools or take actions.", deliver: "local", skills: []))
        do {
            try await second.runJob(jobId: job.id)
            let deadline = ContinuousClock.now + .seconds(180)
            while store.platformJobs.first(where: { $0.id == job.id })?.lastStatus == nil,
                  ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(200))
            }
            let visible = try XCTUnwrap(store.platformJobs.first(where: { $0.id == job.id }))
            XCTAssertEqual(visible.lastStatus, "ok", visible.lastError ?? "Scheduler did not confirm successful execution")
            XCTAssertNotNil(visible.lastRunAt)
            let canonical = try await second.listJobs()
            XCTAssertEqual(canonical.first?.lastStatus, visible.lastStatus)
            XCTAssertEqual(canonical.first?.lastRunAt, visible.lastRunAt)
            let sessions = try await phone.listSessions()
            let owned = sessions.filter { $0.id.hasPrefix("cron_\(job.id)_") }
            XCTAssertEqual(owned.count, 1, "Exactly one scheduler conversation should be created")
            for session in owned {
                let messages = try await second.getMessages(sessionId: session.id)
                XCTAssertTrue(messages.contains { $0.isAssistant && ($0.content ?? "").uppercased().contains("READY") })
                try await phone.deleteSession(sessionId: session.id)
            }
        } catch {
            try await phone.pauseJob(jobId: job.id)
            try await phone.deleteJob(jobId: job.id)
            throw error
        }
        // The disposable runner verifies this job's persisted local output,
        // then deletes it through the native API and checks the empty catalog.
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
