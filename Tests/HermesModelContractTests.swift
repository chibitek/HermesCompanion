import XCTest
@testable import HermesCompanion

final class HermesModelContractTests: XCTestCase {
    func testBoardWritesValidateIdentityAndForwardNativeRefusal() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        defer { SessionHistoryURLProtocol.handler = nil }
        var payload = ServerBoardWrite()
        payload.slug = " MOBILE "
        SessionHistoryURLProtocol.handler = { request in
            XCTAssertEqual(request.request.httpMethod, "POST")
            XCTAssertNil(URLComponents(url: request.request.url!, resolvingAgainstBaseURL: false)?.query)
            request.succeed(body: #"{"board":{"slug":"mobile","name":"Desktop edit"},"already_exists":true}"#)
        }
        let existing = try await client.createWorkspaceBoard(payload: payload)
        XCTAssertEqual(existing.board.slug, "mobile")
        XCTAssertEqual(existing.already_exists, true)
        SessionHistoryURLProtocol.handler = { request in
            request.succeed(body: #"{"board":{"slug":"foreign"}}"#)
        }
        do {
            _ = try await client.updateWorkspaceBoard(slug: "mobile", payload: ServerBoardWrite())
            XCTFail("Foreign board receipt must not confirm an update")
        } catch { XCTAssertTrue(error.localizedDescription.contains("did not confirm this board")) }
        SessionHistoryURLProtocol.handler = { request in
            request.succeed(body: #"{"error":{"message":"The default board cannot be removed"}}"#, status: 400)
        }
        do {
            try await client.performWorkspaceBoardAction(slug: "default", archive: true)
            XCTFail("A native refusal must surface")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("default board cannot be removed"))
            XCTAssertTrue(error.localizedDescription.contains("/api/companion/board-archive"))
        }
    }

    func testBoardActionRejectsWrongActiveSelectionOrUnconfirmedArchive() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        defer { SessionHistoryURLProtocol.handler = nil }
        for archive in [true, false] {
            SessionHistoryURLProtocol.handler = { request in
                request.succeed(body: archive
                    ? #"{"slug":"mobile","action":"archived","current":"mobile"}"#
                    : #"{"slug":"mobile","action":"activated","current":"default"}"#)
            }
            do {
                try await client.performWorkspaceBoardAction(slug: "mobile", archive: archive)
                XCTFail("The receipt must verify the requested action and active board")
            } catch { XCTAssertTrue(error.localizedDescription.contains("did not confirm")) }
        }
    }

    private static let connectionHealth = #"{"status":"ok","platform":"hermes-agent","version":"0.21.2"}"#
    private static let connectionCapabilities = #"{"object":"capabilities","platform":"hermes-agent","model":"local","auth":{"type":"bearer","required":true},"features":{},"endpoints":{}}"#

    private func connectionClient(_ connection: ConnectionConfig) -> HermesAPIClient {
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [SessionHistoryURLProtocol.self]
        return HermesAPIClient(config: connection, session: URLSession(configuration: session))
    }

    private static func answerConnectionRequest(_ request: SessionHistoryURLProtocol) {
        switch request.request.url!.path {
        case "/health": request.succeed(body: connectionHealth)
        case "/v1/capabilities": request.succeed(body: connectionCapabilities)
        case "/v1/model-options": request.succeed(body: "{}", status: 404)
        default: request.succeed(body: #"{"object":"list","data":[]}"#)
        }
    }

    @MainActor
    func testFailedAutomaticConnectionRecoversOnSameServerWithoutRestart() async throws {
        let config = ConnectionConfig(baseURL: "https://selected.invalid", apiKey: "", label: "Selected")
        let client = connectionClient(config)
        let store = AppStore(client: client, clientFactory: { _ in client })
        store.connectionConfig = config
        store.savedConnections = [config, ConnectionConfig(baseURL: "https://unrelated.invalid", apiKey: "", label: "Other")]
        SessionHistoryURLProtocol.handler = { request in
            XCTAssertEqual(request.request.url!.host, "selected.invalid")
            request.client?.urlProtocol(request, didFailWithError: URLError(.timedOut))
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        await store.autoConnect()
        XCTAssertFalse(store.isConnected)
        XCTAssertFalse(store.isLoadingConnection)
        XCTAssertTrue(store.apiClient === client)
        XCTAssertEqual(store.connectionConfig, config)
        XCTAssertTrue(store.error?.message.contains("GET /health") == true)
        SessionHistoryURLProtocol.handler = Self.answerConnectionRequest
        await store.syncNow()
        XCTAssertTrue(store.isConnected)
        XCTAssertTrue(store.apiClient === client)
        XCTAssertNil(store.error)
        XCTAssertNil(store.syncError)
        XCTAssertNotNil(store.capabilities)
    }

    @MainActor
    func testRespondingHealthCannotRecoverRejectedGatewayCredentials() async {
        let config = ConnectionConfig(baseURL: "https://selected.invalid", apiKey: "", label: "Selected")
        let client = connectionClient(config)
        let store = AppStore(client: client, clientFactory: { _ in client })
        store.connectionConfig = config
        SessionHistoryURLProtocol.handler = { request in
            if request.request.url!.path == "/health" { request.succeed(body: Self.connectionHealth) }
            else { request.succeed(body: #"{"error":{"code":"gateway_auth_failed","message":"Invalid gateway API key"}}"#, status: 401) }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        await store.autoConnect()
        await store.syncNow()
        XCTAssertNotNil(store.lastServerResponseAt)
        XCTAssertFalse(store.isConnected)
        XCTAssertNil(store.capabilities)
        XCTAssertTrue(store.syncError?.contains("401") == true)
    }

    @MainActor
    func testSessionCatalogFailureRecoversWithoutStaleConnectionAlert() async {
        let config = ConnectionConfig(baseURL: "https://selected.invalid", apiKey: "", label: "Selected")
        let client = connectionClient(config)
        let store = AppStore(client: client, clientFactory: { _ in client })
        store.connectionConfig = config
        SessionHistoryURLProtocol.handler = { request in
            if request.request.url!.path == "/api/sessions" {
                request.client?.urlProtocol(request, didFailWithError: URLError(.timedOut))
            } else { Self.answerConnectionRequest(request) }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        await store.autoConnect()
        XCTAssertFalse(store.isConnected)
        XCTAssertNotNil(store.error)
        SessionHistoryURLProtocol.handler = Self.answerConnectionRequest
        await store.syncNow()
        XCTAssertTrue(store.isConnected)
        XCTAssertNil(store.error)
        XCTAssertNil(store.syncError)
    }

    @MainActor
    func testDelayedAutomaticConnectionCannotUndoDisconnect() async {
        let config = ConnectionConfig(baseURL: "https://selected.invalid", apiKey: "", label: "Selected")
        let client = connectionClient(config)
        let store = AppStore(client: client, clientFactory: { _ in client })
        store.connectionConfig = config
        let pending = expectation(description: "Connection health in flight")
        var health: SessionHistoryURLProtocol?
        SessionHistoryURLProtocol.handler = { request in
            Task { @MainActor in health = request; pending.fulfill() }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let connecting = Task { await store.autoConnect() }
        await fulfillment(of: [pending], timeout: 3)
        store.disconnect()
        health?.succeed(body: Self.connectionHealth)
        await connecting.value
        XCTAssertNil(store.apiClient)
        XCTAssertNil(store.connectionConfig)
        XCTAssertNil(store.capabilities)
        XCTAssertFalse(store.isLoadingConnection)
        XCTAssertFalse(store.isConnected)
    }

    @MainActor
    func testDelayedManualConnectionCannotUndoDisconnect() async {
        let config = ConnectionConfig(baseURL: "https://selected.invalid", apiKey: "", label: "Selected")
        let client = connectionClient(config)
        let store = AppStore(client: client, clientFactory: { _ in client })
        let pending = expectation(description: "Manual connection health in flight")
        var health: SessionHistoryURLProtocol?
        SessionHistoryURLProtocol.handler = { request in
            Task { @MainActor in health = request; pending.fulfill() }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let connecting = Task { await store.connect(config: config) }
        await fulfillment(of: [pending], timeout: 3)
        store.disconnect()
        health?.succeed(body: Self.connectionHealth)
        let connected = await connecting.value
        XCTAssertFalse(connected)
        XCTAssertNil(store.apiClient)
        XCTAssertNil(store.connectionConfig)
        XCTAssertFalse(store.isLoadingConnection)
    }

    @MainActor
    func testLateOldConnectionDoesNotFinishOrReplaceNewAttempt() async {
        let oldConfig = ConnectionConfig(baseURL: "https://old.invalid", apiKey: "", label: "Old")
        let newConfig = ConnectionConfig(baseURL: "https://new.invalid", apiKey: "", label: "New")
        let oldClient = connectionClient(oldConfig)
        let newClient = connectionClient(newConfig)
        let store = AppStore(client: oldClient, clientFactory: { $0 == oldConfig ? oldClient : newClient })
        store.connectionConfig = oldConfig
        let oldPending = expectation(description: "Old health pending")
        let newPending = expectation(description: "New health pending")
        var oldHealth: SessionHistoryURLProtocol?
        var newHealth: SessionHistoryURLProtocol?
        SessionHistoryURLProtocol.handler = { request in
            if request.request.url!.path == "/health" {
                Task { @MainActor in
                    if request.request.url!.host == "old.invalid" { oldHealth = request; oldPending.fulfill() }
                    else { newHealth = request; newPending.fulfill() }
                }
            } else { Self.answerConnectionRequest(request) }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let first = Task { await store.autoConnect() }
        await fulfillment(of: [oldPending], timeout: 3)
        store.disconnect()
        store.connectionConfig = newConfig
        let second = Task { await store.autoConnect() }
        await fulfillment(of: [newPending], timeout: 3)
        oldHealth?.succeed(body: Self.connectionHealth)
        await first.value
        XCTAssertTrue(store.isLoadingConnection)
        XCTAssertTrue(store.apiClient === newClient)
        XCTAssertNil(store.capabilities)
        newHealth?.succeed(body: Self.connectionHealth)
        await second.value
        XCTAssertTrue(store.isConnected)
        XCTAssertEqual(store.connectionConfig, newConfig)
    }

    @MainActor
    func testDuplicateAutomaticConnectionPreservesActiveConversation() async throws {
        let config = ConnectionConfig(baseURL: "https://selected.invalid", apiKey: "", label: "Selected")
        let client = connectionClient(config)
        var creations = 0
        let store = AppStore(client: client, clientFactory: { _ in creations += 1; return client })
        store.connectionConfig = config
        SessionHistoryURLProtocol.handler = Self.answerConnectionRequest
        defer { SessionHistoryURLProtocol.handler = nil }
        await store.autoConnect()
        store.activeSession = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"retained"}"#.utf8))
        await store.autoConnect()
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(store.activeSession?.id, "retained")
        XCTAssertTrue(store.isConnected)
    }

    @MainActor
    func testLiveWorkspaceFeedRecoversAfterBridgeInstallationWithoutRestart() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        let store = AppStore(client: client)
        let missing = expectation(description: "Old gateway has no bridge endpoint")
        let recovered = expectation(description: "The upgraded bridge is retried")
        var attempts = 0
        SessionHistoryURLProtocol.handler = { request in
            switch request.request.url!.path {
            case "/api/companion/changes":
                attempts += 1
                if attempts == 1 {
                    request.succeed(body: "{}", status: 404)
                    missing.fulfill()
                } else {
                    let response = HTTPURLResponse(url: request.request.url!, statusCode: 200,
                        httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
                    request.client?.urlProtocol(request, didReceive: response, cacheStoragePolicy: .notAllowed)
                    request.client?.urlProtocol(request, didLoad: Data("event: workspace.changed\ndata: {}\n\n".utf8))
                    recovered.fulfill()
                }
            case "/health":
                request.succeed(body: #"{"status":"ok","platform":"hermes-agent","version":"0.21.2"}"#)
            default:
                request.succeed(body: #"{"object":"list","data":[]}"#)
            }
        }
        let live = Task { await store.runLiveSync() }
        defer { live.cancel(); SessionHistoryURLProtocol.handler = nil }
        await fulfillment(of: [missing], timeout: 3)
        for _ in 0..<50 where store.liveChangesError == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(store.liveChangesError?.contains("retrying automatically") == true)
        await fulfillment(of: [recovered], timeout: 35)
        for _ in 0..<50 where store.workspaceRevision == 0 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(store.liveChangesAvailable)
        XCTAssertNil(store.liveChangesError)
        XCTAssertGreaterThan(store.workspaceRevision, 0)
        live.cancel()
        await live.value
    }

    func testCapabilityTimeoutIdentifiesEndpointWithoutPrivateURLDetails() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        SessionHistoryURLProtocol.handler = { request in
            request.client?.urlProtocol(request, didFailWithError: URLError(.timedOut))
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        do {
            _ = try await client.getCapabilities()
            XCTFail("Timeout must surface")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("GET /v1/capabilities"))
            XCTAssertTrue(error.localizedDescription.contains("20 seconds"))
            XCTAssertFalse(error.localizedDescription.contains("hermes.invalid"))
        }
        let request = URLRequest(url: URL(string: "https://private.invalid/api/sessions?private=value")!)
        let failure = TransportFailure(request: request, error: URLError(.timedOut), timeout: 20)
        XCTAssertFalse(failure.localizedDescription.contains("private"))
        XCTAssertFalse(failure.localizedDescription.contains("value"))
    }

    @MainActor
    func testHealthyServerWithFailedSessionSyncReportsFailureWithoutChatSyncStamp() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        let store = AppStore(client: client)
        SessionHistoryURLProtocol.handler = { request in
            if request.request.url?.path == "/health" {
                request.succeed(body: #"{"status":"ok","platform":"hermes-agent","version":"0.21.2"}"#)
            } else {
                request.client?.urlProtocol(request, didFailWithError: URLError(.timedOut))
            }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        await store.refreshSessions()
        XCTAssertTrue(store.syncError?.contains("GET /api/sessions") == true)
        await store.syncNow()
        XCTAssertNotNil(store.lastServerResponseAt)
        XCTAssertNil(store.lastSyncedAt)
        XCTAssertTrue(store.syncError?.contains("GET /api/sessions") == true)
        SessionHistoryURLProtocol.handler = { request in
            request.succeed(body: request.request.url?.path == "/health"
                ? #"{"status":"ok","platform":"hermes-agent","version":"0.21.2"}"#
                : #"{"object":"list","data":[]}"#)
        }
        await store.syncNow()
        XCTAssertNil(store.syncError)
        XCTAssertNil(store.lastSyncedAt, "Refreshing an empty session list must not claim that chat was synced")
    }

    @MainActor
    func testReattachedRunShowsWaitAndDoesNotCallInterruptionCompleted() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        let domain = "RunProgress-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: directory)
            SessionHistoryURLProtocol.handler = nil
        }
        let controller = DurableRunController(client: client, connectionScope: "test", defaults: defaults, pendingDirectory: directory)
        var interrupted = false
        SessionHistoryURLProtocol.handler = { request in
            XCTAssertFalse(request.request.url!.path.hasSuffix("/events"))
            request.succeed(body: interrupted
                ? #"{"run_id":"run_waiting","status":"interrupted","output":"Stopped before processing"}"#
                : #"{"run_id":"run_waiting","status":"running","last_event":"run.progress","progress_kind":"lifecycle","progress_message":"Another Hermes process is using this session; waiting for it to finish.","progress_at":1}"#)
        }
        await controller.attach("run_waiting")
        XCTAssertEqual(controller.activity, "Another Hermes process is using this session; waiting for it to finish.")
        XCTAssertNotNil(controller.lastResponseAt)
        XCTAssertFalse(controller.status!.isTerminal)
        interrupted = true
        await controller.monitor()
        XCTAssertEqual(controller.activity, "Interrupted")
        XCTAssertTrue(controller.status!.isTerminal)
        XCTAssertEqual(controller.status?.output, "Stopped before processing")
    }

    @MainActor
    func testLostRunAdmissionReusesKeyAndOriginalRequest() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        let domain = "RunAdmission-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let pendingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: pendingDirectory)
            SessionHistoryURLProtocol.handler = nil
        }
        let controller = DurableRunController(client: client, connectionScope: "test", supportsDurableAdmission: true, retentionSeconds: 60, defaults: defaults, pendingDirectory: pendingDirectory)
        var keys: [String] = []
        var bodies: [[String: Any]] = []
        SessionHistoryURLProtocol.handler = { request in
            keys.append(request.request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
            bodies.append((try? JSONSerialization.jsonObject(with: request.bodyData())) as? [String: Any] ?? [:])
            if keys.count == 1 { request.fail() }
            else { request.succeed(body: #"{"run_id":"run_original","status":"started","replayed":true}"#, status: 202) }
        }
        await controller.submit(input: "Original", sessionID: "session", model: nil, provider: nil)
        XCTAssertTrue(controller.submissionUncertain)
        let recovered = DurableRunController(client: client, connectionScope: "test", supportsDurableAdmission: true, retentionSeconds: 60, defaults: defaults, pendingDirectory: pendingDirectory)
        XCTAssertEqual(recovered.pendingInput, "Original")
        XCTAssertTrue(recovered.submissionUncertain)
        await recovered.submit(input: "Changed UI value must not replace original request", sessionID: "other", model: nil, provider: nil)
        XCTAssertEqual(keys.count, 2)
        XCTAssertFalse(keys[0].isEmpty)
        XCTAssertEqual(keys[0], keys[1])
        XCTAssertEqual(bodies.count, 2)
        XCTAssertTrue(bodies.allSatisfy { $0["input"] as? String == "Original" && $0["session_id"] as? String == "session" })
        XCTAssertEqual(recovered.runID, "run_original")
        XCTAssertFalse(recovered.submissionUncertain)
        let restored = DurableRunController(client: client, connectionScope: "test", supportsDurableAdmission: true, retentionSeconds: 60, defaults: defaults, pendingDirectory: pendingDirectory)
        XCTAssertEqual(restored.runID, "run_original")
        let other = DurableRunController(client: client, connectionScope: "other-server/p/second", defaults: defaults, pendingDirectory: pendingDirectory)
        XCTAssertNil(other.runID)
    }

    @MainActor
    func testRunApprovalUsesExactRequestAndRejectsStaleDecision() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        let domain = "RunApproval-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let pendingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: pendingDirectory)
            SessionHistoryURLProtocol.handler = nil
        }
        let controller = DurableRunController(client: client, connectionScope: "test", supportsDurableAdmission: true, retentionSeconds: 60, defaults: defaults, pendingDirectory: pendingDirectory)
        var controls = 0
        SessionHistoryURLProtocol.handler = { request in
            if request.request.httpMethod == "POST" {
                controls += 1
                let body = (try? JSONSerialization.jsonObject(with: request.bodyData())) as? [String: String]
                XCTAssertEqual(body, ["request_id": "approval_current", "choice": "once"])
                request.succeed(body: #"{"run_id":"run_selected","request_id":"approval_current","choice":"once","resolved":1}"#)
            } else {
                request.succeed(body: #"{"run_id":"run_selected","status":"waiting_for_approval","approval":{"request_id":"approval_current","command":"reviewed command","choices":["once","deny"]}}"#)
            }
        }
        await controller.attach("run_selected")
        await controller.decide(requestID: "approval_old", choice: "once")
        await controller.decide(requestID: "approval_current", choice: "always")
        XCTAssertEqual(controls, 0)
        await controller.decide(requestID: "approval_current", choice: "once")
        XCTAssertEqual(controls, 1)
    }

    func testRunStatusRejectsForeignRunAndUnsafeIdentifiers() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        var requests = 0
        SessionHistoryURLProtocol.handler = { request in
            requests += 1
            request.succeed(body: #"{"run_id":"run_other","status":"running"}"#)
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        do { _ = try await client.runStatus(id: "run_requested"); XCTFail("Foreign run must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("another run")) }
        do { _ = try await client.runStatus(id: "run_bad/../other"); XCTFail("Unsafe run ID must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Invalid Hermes run ID")) }
        XCTAssertEqual(requests, 1)
    }

    @MainActor
    func testReattachmentPollsStatusWithoutConsumingEventsAndKeepsControlError() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        let domain = "RunReconnect-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let pendingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: pendingDirectory)
            SessionHistoryURLProtocol.handler = nil
        }
        let controller = DurableRunController(client: client, connectionScope: "test", defaults: defaults, pendingDirectory: pendingDirectory)
        var attemptedSteer = false
        var eventReads = 0
        SessionHistoryURLProtocol.handler = { request in
            if request.request.url!.path.hasSuffix("/events") { eventReads += 1; request.fail(); return }
            if request.request.httpMethod == "POST" {
                attemptedSteer = true
                request.succeed(body: #"{"error":{"code":"run_not_accepting_steer","message":"Run settled before guidance arrived"}}"#, status: 409)
            } else {
                request.succeed(body: attemptedSteer ? #"{"run_id":"run_selected","status":"completed","output":"Final saved result"}"# : #"{"run_id":"run_selected","status":"running"}"#)
            }
        }
        await controller.attach("run_selected")
        let accepted = await controller.steer("Additional guidance")
        XCTAssertFalse(accepted)
        await controller.monitor()
        XCTAssertEqual(eventReads, 0)
        XCTAssertEqual(controller.status?.output, "Final saved result")
        XCTAssertTrue(controller.operationFailure?.contains("Run settled before guidance arrived") == true)
        controller.forgetBookmark()
        XCTAssertNil(controller.runID)
        XCTAssertNil(DurableRunController(client: client, connectionScope: "test", defaults: defaults, pendingDirectory: pendingDirectory).runID)
    }

    @MainActor
    func testExpiredPendingRunCannotBeReadmitted() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        let domain = "RunExpired-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory); SessionHistoryURLProtocol.handler = nil }
        var requests = 0
        SessionHistoryURLProtocol.handler = { request in requests += 1; request.fail() }
        let controller = DurableRunController(client: client, connectionScope: "test", supportsDurableAdmission: true, retentionSeconds: 60, defaults: defaults, pendingDirectory: directory)
        await controller.submit(input: "Original", sessionID: nil, model: nil, provider: nil)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let original = try JSONDecoder().decode(PendingDurableRun.self, from: Data(contentsOf: file))
        try JSONEncoder().encode(PendingDurableRun(payload: original.payload, key: original.key, createdAt: Date(timeIntervalSinceNow: -120))).write(to: file)
        let restored = DurableRunController(client: client, connectionScope: "test", supportsDurableAdmission: true, retentionSeconds: 60, defaults: defaults, pendingDirectory: directory)
        await restored.submit(input: "Original", sessionID: nil, model: nil, provider: nil)
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(restored.operationFailure?.contains("retention window") == true)
    }

    @MainActor
    func testReplayReconnectUsesLastCursorAndDoesNotDuplicateText() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        let domain = "RunReplay-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory); SessionHistoryURLProtocol.handler = nil }
        let controller = DurableRunController(client: client, connectionScope: "test", supportsEventReplay: true, defaults: defaults, pendingDirectory: directory)
        var cursors: [String] = []
        SessionHistoryURLProtocol.handler = { request in
            if request.request.url!.path.hasSuffix("/events") {
                cursors.append(request.request.value(forHTTPHeaderField: "Last-Event-ID") ?? "missing")
                let first = #"data: {"event":"message.delta","run_id":"run_selected","sequence":1,"delta":"A"}"# + "\n\n"
                let second = #"data: {"event":"message.delta","run_id":"run_selected","sequence":2,"delta":"B"}"# + "\n\n"
                let done = #"data: {"event":"run.completed","run_id":"run_selected","sequence":3}"# + "\n\n"
                request.succeed(body: cursors.count == 1 ? first : first + second + done, headers: ["Content-Type": "text/event-stream"])
            } else {
                Task { @MainActor in
                    request.succeed(body: controller.liveText == "AB" ? #"{"run_id":"run_selected","status":"completed","output":"AB"}"# : #"{"run_id":"run_selected","status":"running"}"#)
                }
            }
        }
        await controller.attach("run_selected")
        await controller.monitor()
        XCTAssertEqual(cursors, ["0", "1"])
        XCTAssertEqual(controller.liveText, "AB")
        XCTAssertEqual(controller.status?.output, "AB")
    }

    @MainActor
    func testReplayGapLabelsPartialOutputAndResumesFromServerCursor() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        let domain = "RunReplayGap-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory); SessionHistoryURLProtocol.handler = nil }
        let controller = DurableRunController(client: client, connectionScope: "test", supportsEventReplay: true, defaults: defaults, pendingDirectory: directory)
        var cursors: [String] = []
        SessionHistoryURLProtocol.handler = { request in
            if request.request.url!.path.hasSuffix("/events") {
                cursors.append(request.request.value(forHTTPHeaderField: "Last-Event-ID") ?? "missing")
                if cursors.count == 1 {
                    request.succeed(body: #"{"error":{"code":"run_replay_gap","message":"Replay expired"}}"#, status: 409)
                } else {
                    let delta = #"data: {"event":"message.delta","run_id":"run_selected","sequence":51,"delta":"tail"}"# + "\n\n"
                    let done = #"data: {"event":"run.completed","run_id":"run_selected","sequence":52}"# + "\n\n"
                    request.succeed(body: delta + done, headers: ["Content-Type": "text/event-stream"])
                }
            } else {
                Task { @MainActor in
                    request.succeed(body: controller.liveText == "tail" ? #"{"run_id":"run_selected","status":"completed","output":"Full saved result","event_cursor":52}"# : #"{"run_id":"run_selected","status":"running","event_cursor":50,"event_replay_floor":40}"#)
                }
            }
        }
        await controller.attach("run_selected")
        await controller.monitor()
        XCTAssertEqual(cursors, ["0", "50"])
        XCTAssertTrue(controller.liveOutputIncomplete)
        XCTAssertEqual(controller.liveText, "tail")
        XCTAssertEqual(controller.status?.output, "Full saved result")
    }

    func testApprovalWithoutExactIDCannotOfferDecisions() throws {
        let approval = try JSONDecoder().decode(DurableRunApproval.self, from: Data(#"{"choices":["once","always","deny"]}"#.utf8))
        XCTAssertTrue(approval.offeredChoices.isEmpty)
        let status = try JSONDecoder().decode(DurableRunStatus.self, from: Data(#"{"run_id":"run_done","status":"completed","pending_steer":"Not delivered"}"#.utf8))
        XCTAssertTrue(status.isTerminal)
        XCTAssertEqual(status.pending_steer, "Not delivered")
    }

    func testProjectPatchKeepsOtherFieldsAndCanClearMetadata() throws {
        let project = try JSONDecoder().decode(ManagedProject.self, from: Data(#"{"id":"p_one","slug":"project","name":"Project","description":"Details","icon":"folder","color":"blue","board_slug":"board","archived":false,"folders":[]}"#.utf8))
        let payload = ProjectWrite.changes(from: project, name: "Project", description: "", icon: "folder", color: "blue", board: "")
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: String])
        XCTAssertEqual(values, ["description": "", "board_slug": ""])
    }

    func testProjectWriteRejectsAnotherProfileAndNativeValidationIsActionable() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        SessionHistoryURLProtocol.handler = { request in
            XCTAssertEqual(request.request.httpMethod, "PATCH")
            let items = URLComponents(url: request.request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(items.first { $0.name == "profile" }?.value, "second")
            XCTAssertEqual(items.first { $0.name == "project_id" }?.value, "p_one")
            request.succeed(body: #"{"profile":"default","project":{"id":"p_one","slug":"project","name":"Project","archived":false,"folders":[]}}"#)
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        var payload = ProjectWrite()
        payload.name = "Revised"
        do {
            _ = try await client.saveProject(profile: "second", id: "p_one", payload: payload)
            XCTFail("A different profile must not confirm the save")
        } catch { XCTAssertTrue(error.localizedDescription.contains("different profile/project")) }
        SessionHistoryURLProtocol.handler = { request in
            request.succeed(body: #"{"error":{"code":"5063","message":"projects.create (5063): folder already belongs to project 'existing'"}}"#, status: 400)
        }
        do {
            _ = try await client.saveProject(profile: "second", id: nil, payload: payload)
            XCTFail("Native validation must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("folder already belongs"))
            XCTAssertTrue(error.localizedDescription.contains("5063"))
            XCTAssertTrue(error.localizedDescription.contains("/api/companion/projects-create"))
        }
    }

    func testTaskEditsOmitUnchangedFieldsAndPreserveExplicitClearing() throws {
        let task = try JSONDecoder().decode(ServerBoardTask.self, from: Data(#"{"id":"task","title":"Existing","body":"Description","status":"triage","assignee":"worker","priority":2}"#.utf8))
        let changes = ServerTaskWrite.changes(from: task, title: "Revised", body: "Description",
            assignee: "", priority: 2, status: "triage", result: "ignored", summary: "ignored", blockReason: "ignored")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(changes)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["title", "assignee"])
        XCTAssertEqual(body["assignee"] as? String, "")
        let completed = ServerTaskWrite.changes(from: task, title: "Existing", body: "Description",
            assignee: "worker", priority: 2, status: "done", result: "Delivered", summary: "Verified", blockReason: "ignored")
        let done = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(completed)) as? [String: Any])
        XCTAssertEqual(Set(done.keys), ["status", "result", "summary"])
    }

    func testTaskWriteRejectsForeignReceiptAndSurfacesNativeRefusal() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        SessionHistoryURLProtocol.handler = { request in
            XCTAssertEqual(request.request.httpMethod, "PATCH")
            let query = URLComponents(url: request.request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "board" }?.value, "engineering")
            XCTAssertEqual(query.first { $0.name == "task_id" }?.value, "task")
            request.succeed(body: #"{"board":"foreign","task":{"id":"task","title":"Title","status":"triage"}}"#)
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        var payload = ServerTaskWrite()
        payload.title = "Revised"
        do {
            _ = try await client.updateWorkspaceTask(board: "engineering", taskID: "task", payload: payload)
            XCTFail("Foreign board receipt must not confirm a write")
        } catch { XCTAssertTrue(error is APIError) }
        SessionHistoryURLProtocol.handler = { request in
            request.succeed(body: #"{"error":{"code":"task_operation_rejected","message":"Blocked by parent dependency"}}"#, status: 409)
        }
        do {
            _ = try await client.updateWorkspaceTask(board: "engineering", taskID: "task", payload: payload)
            XCTFail("Refused status must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Blocked by parent dependency"))
            XCTAssertTrue(error.localizedDescription.contains("/api/companion/task"))
        }
    }

    func testHTTPErrorRetainsServerReasonAndEndpointWithoutCredentials() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "private-test-key", label: "Test"), session: URLSession(configuration: config))
        SessionHistoryURLProtocol.handler = { request in
            request.succeed(body: #"{"error":{"code":"session_busy","message":"Active turn; Bearer private-test-key"}}"#, status: 409)
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        do {
            _ = try await client.getSession(sessionId: "current")
            XCTFail("Conflict must throw")
        } catch {
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("/api/sessions/current"))
            XCTAssertTrue(text.contains("409"))
            XCTAssertTrue(text.contains("session_busy"))
            XCTAssertFalse(text.contains("private-test-key"))
        }
    }

    func testMessagePaginationLoadsBeyondFiveHundred() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        SessionHistoryURLProtocol.handler = { request in
            let query = URLComponents(url: request.request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let offset = Int(query.first { $0.name == "offset" }!.value!)!
            let rows = (offset..<min(offset + 500, 601)).map { ["id": $0, "role": "user", "content": "Message \($0)"] as [String: Any] }
            let body: [String: Any] = ["object": "list", "data": rows,
                                      "pagination": ["offset": offset, "returned": rows.count]]
            request.succeed(body: String(data: try! JSONSerialization.data(withJSONObject: body), encoding: .utf8)!)
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let history = try await client.getMessages(sessionId: "long-chat")
        XCTAssertEqual(history.count, 601)
        XCTAssertEqual(history.first?.id, 0)
        XCTAssertEqual(history.last?.id, 600)
    }

    @MainActor
    func testHistoryStartedBeforeANewTurnCannotOverwriteItAfterTurnEnds() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        let store = AppStore(client: client)
        let session = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"current"}"#.utf8))
        store.activeSession = session
        let pending = expectation(description: "History read started")
        var request: SessionHistoryURLProtocol?
        SessionHistoryURLProtocol.handler = { value in
            Task { @MainActor in request = value; pending.fulfill() }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let refresh = Task { try await store.refreshActiveSessionMessages(session, client: client) }
        await fulfillment(of: [pending], timeout: 3)
        store.stopStreaming() // invalidates the turn even though isStreaming is now false
        store.messages = [ChatDisplayMessage(id: "new", role: "assistant", content: "Newer response", timestamp: Date())]
        request?.succeed()
        try await refresh.value
        XCTAssertEqual(store.messages.first?.content, "Newer response")
    }

    @MainActor
    func testIdleSyncPicksUpRemoteMessagesAndReportsReachability() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        let store = AppStore(client: client)
        store.activeSession = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"current"}"#.utf8))
        SessionHistoryURLProtocol.handler = { request in
            switch request.request.url!.path {
            case "/health": request.succeed(body: #"{"status":"ok","platform":"hermes-agent","version":"0.21.2"}"#)
            case "/api/sessions": request.succeed(body: #"{"object":"list","data":[{"id":"current"}]}"#)
            default: request.succeed(body: #"{"object":"list","data":[{"id":2,"role":"assistant","content":"Reply from Mac"}]}"#)
            }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        await store.syncNow()
        XCTAssertEqual(store.messages.last?.content, "Reply from Mac")
        XCTAssertNotNil(store.lastSyncedAt)
        XCTAssertNotNil(store.lastServerResponseAt)
        XCTAssertNil(store.syncError)
        SessionHistoryURLProtocol.handler = { $0.succeed(body: #"{"error":"Gateway restarting"}"#, status: 503) }
        await store.syncNow()
        XCTAssertTrue(store.syncError?.contains("503") == true)
        XCTAssertEqual(store.messages.last?.content, "Reply from Mac")
    }

    func testPinnedBackfillDoesNotSkipSessionPaginationWindow() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"), session: URLSession(configuration: config))
        SessionHistoryURLProtocol.handler = { request in
            let query = URLComponents(url: request.request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let offset = Int(query.first { $0.name == "offset" }!.value!)!
            let rows = (offset..<min(offset + 100, 201)).map { ["id": "session-\($0)"] } + [["id": "pin"]]
            let body: [String: Any] = ["object": "list", "data": rows, "limit": 100,
                                      "offset": offset, "has_more": offset < 200]
            request.succeed(body: String(data: try! JSONSerialization.data(withJSONObject: body), encoding: .utf8)!)
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let sessions = try await client.listSessions()
        XCTAssertEqual(sessions.count, 202)
        XCTAssertTrue(sessions.contains { $0.id == "session-100" })
        XCTAssertTrue(sessions.contains { $0.id == "session-200" })
    }

    func testConnectionConfigRequiresARealGateway() {
        let demo = ConnectionConfig(baseURL: "demo://local", apiKey: "demo", label: "Demo")
        let missingKey = ConnectionConfig(baseURL: "https://hermes.local:8642", apiKey: "", label: "Hermes")
        let valid = ConnectionConfig(baseURL: "https://hermes.local:8642", apiKey: "secret", label: "Hermes")
        XCTAssertFalse(demo.isValid)
        XCTAssertFalse(missingKey.isValid)
        XCTAssertTrue(valid.isValid)
    }

    @MainActor
    func testMissingActiveSessionIsClearedOnlyWhenDirectLookupReturnsNotFound() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        defer { SessionHistoryURLProtocol.handler = nil }
        for status in [404, 500, 200] {
            let store = AppStore(client: client)
            store.activeSession = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"current","model":"local"}"#.utf8))
            store.activeRuntime = SessionRuntime(provider: "local", model: "local", routeSource: nil, requested: nil, modelLock: nil)
            SessionHistoryURLProtocol.handler = { request in
                if request.request.url!.path.hasSuffix("/sessions") {
                    request.succeed(body: #"{"object":"list","total":0,"data":[]}"#)
                } else {
                    request.succeed(body: #"{"object":"session","session":{"id":"current"}}"#, status: status)
                }
            }
            await store.refreshSessions()
            XCTAssertEqual(store.activeSession == nil, status == 404)
            XCTAssertEqual(store.activeRuntime == nil, status == 404)
        }
    }

    @MainActor
    func testLateDeletionProbeCannotClearAnotherActiveSession() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        let store = AppStore(client: client)
        store.activeSession = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"old"}"#.utf8))
        let started = expectation(description: "Deletion probe pending")
        var probe: SessionHistoryURLProtocol?
        SessionHistoryURLProtocol.handler = { request in
            if request.request.url!.path.hasSuffix("/sessions") {
                request.succeed(body: #"{"object":"list","total":0,"data":[]}"#)
            } else {
                Task { @MainActor in probe = request; started.fulfill() }
            }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let refresh = Task { await store.refreshSessions() }
        await fulfillment(of: [started], timeout: 3)
        store.activeSession = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"new"}"#.utf8))
        probe?.succeed(body: "{}", status: 404)
        await refresh.value
        XCTAssertEqual(store.activeSession?.id, "new")
    }

    func testSessionPaginationKeepsHistoryBeyondTwoHundredWithOrWithoutTotal() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        for includeTotal in [true, false] {
            SessionHistoryURLProtocol.handler = { request in
                let query = URLComponents(url: request.request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                let offset = Int(query.first { $0.name == "offset" }!.value!)!
                let rows = (offset..<min(offset + 100, 252)).map { ["id": "session-\($0)"] }
                var payload: [String: Any] = ["object": "list", "data": rows]
                if includeTotal { payload["total"] = 252 }
                request.succeed(body: String(data: try! JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!)
            }
            let sessions = try await client.listSessions()
            XCTAssertEqual(sessions.count, 252)
            XCTAssertEqual(sessions.last?.id, "session-251")
        }
        SessionHistoryURLProtocol.handler = nil
    }

    func testRepeatingSessionPageFailsInsteadOfReportingPartialHistory() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        SessionHistoryURLProtocol.handler = { request in
            request.succeed(body: #"{"object":"list","total":250,"data":[{"id":"repeated"}]}"#)
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        do {
            _ = try await client.listSessions()
            XCTFail("A repeated page must not be accepted as a complete history")
        } catch {
            guard case APIError.invalidResponse = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testModelSourcesPreserveDuplicateIDsAcrossProviders() {
        let catalog = [ModelInfo(id: "shared", provider: "local"),
                       ModelInfo(id: "shared", provider: "hosted"),
                       ModelInfo(id: "shared", provider: "local")]
        let choices = ModelSourceChoice.choices(for: ["shared", "shared"], catalog: catalog,
                                                fallback: ["shared": ModelInfo(id: "shared", provider: "stale")])
        XCTAssertEqual(Set(choices), [ModelSourceChoice(model: "shared", provider: "local"),
                                     ModelSourceChoice(model: "shared", provider: "hosted")])
        XCTAssertEqual(choices.count, 2)
        XCTAssertEqual(Set(choices.map(\.id)).count, 2)
    }

    func testModelSourcesUseLegacyFallbackWithoutInventingProviderFromAuthor() {
        let choices = ModelSourceChoice.choices(for: ["legacy", "unknown"], catalog: [],
                                                fallback: ["legacy": ModelInfo(id: "legacy", ownedBy: "author", provider: "gateway")])
        XCTAssertEqual(choices, [ModelSourceChoice(model: "legacy", provider: "gateway"),
                                 ModelSourceChoice(model: "unknown", provider: nil)])
    }

    @MainActor
    func testPlatformSnapshotCannotOverwriteNewerSessionRefresh() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        let store = AppStore(client: client)
        store.activeSession = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"current","model":"initial"}"#.utf8))
        let platformStarted = expectation(description: "Platform sessions pending")
        let refreshStarted = expectation(description: "Newer sessions pending")
        var requests: [SessionHistoryURLProtocol] = []
        SessionHistoryURLProtocol.handler = { request in
            Task { @MainActor in
                guard request.request.url?.path.hasSuffix("/sessions") == true else {
                    request.fail()
                    return
                }
                requests.append(request)
                if requests.count == 1 { platformStarted.fulfill() }
                else { refreshStarted.fulfill() }
            }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let platform = Task { await store.refreshPlatform() }
        await fulfillment(of: [platformStarted], timeout: 3)
        let refresh = Task { await store.refreshSessions() }
        await fulfillment(of: [refreshStarted], timeout: 3)
        requests[1].succeed(body: #"{"object":"list","data":[{"id":"current","model":"latest","pinned":true}]}"#)
        await refresh.value
        requests[0].succeed(body: #"{"object":"list","data":[{"id":"current","model":"stale","pinned":false}]}"#)
        await platform.value
        XCTAssertEqual(store.effectiveCurrentModel, "latest")
        XCTAssertEqual(store.activeSession?.isPinned, true)
        XCTAssertEqual(store.sessions.first?.model, "latest")
        XCTAssertFalse(store.isLoadingPlatform)
    }

    @MainActor
    func testFailedModelLockPreservesConfirmedSelection() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        let store = AppStore(client: client)
        store.activeSession = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"current","model":"confirmed","provider":"local"}"#.utf8))
        store.preferredModel = "confirmed"
        store.preferredProvider = "local"
        let started = expectation(description: "Rejected model lock pending")
        var request: SessionHistoryURLProtocol?
        SessionHistoryURLProtocol.handler = { pending in
            Task { @MainActor in request = pending; started.fulfill() }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let locking = Task { await store.selectPreferredModel("unavailable", provider: "remote") }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(store.effectiveCurrentModel, "confirmed")
        XCTAssertEqual(store.preferredModel, "confirmed")
        request?.fail()
        await locking.value
        XCTAssertEqual(store.effectiveCurrentModel, "confirmed")
        XCTAssertEqual(store.effectiveCurrentProvider, "local")
        XCTAssertEqual(store.preferredModel, "confirmed")
        XCTAssertEqual(store.preferredProvider, "local")
        XCTAssertNil(store.sessionModelOverride)
        XCTAssertNotNil(store.error)
    }

    @MainActor
    func testAcknowledgedModelLockUsesServerNormalizedIdentity() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        let store = AppStore(client: client)
        store.activeSession = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"current"}"#.utf8))
        SessionHistoryURLProtocol.handler = { request in
            request.succeed(body: #"{"object":"session.model","session_id":"current","runtime":{"model":"canonical-model","provider":"custom:local"}}"#)
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        await store.selectPreferredModel("alias", provider: "custom")
        XCTAssertEqual(store.effectiveCurrentModel, "canonical-model")
        XCTAssertEqual(store.effectiveCurrentProvider, "custom:local")
        XCTAssertEqual(store.preferredModel, "canonical-model")
        XCTAssertEqual(store.preferredProvider, "custom:local")
        XCTAssertNil(store.error)
    }

    @MainActor
    func testOlderModelLockCannotOverwriteNewerSelection() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        let store = AppStore(client: client)
        store.activeSession = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"current"}"#.utf8))
        let firstStarted = expectation(description: "First model lock pending")
        let secondStarted = expectation(description: "Second model lock pending")
        var requests: [SessionHistoryURLProtocol] = []
        SessionHistoryURLProtocol.handler = { request in
            Task { @MainActor in
                requests.append(request)
                if requests.count == 1 { firstStarted.fulfill() }
                else { secondStarted.fulfill() }
            }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let first = Task { await store.selectPreferredModel("old", provider: "remote") }
        await fulfillment(of: [firstStarted], timeout: 3)
        let second = Task { await store.selectPreferredModel("current", provider: "local") }
        await fulfillment(of: [secondStarted], timeout: 3)
        requests[1].succeed(body: #"{"object":"session.model","session_id":"current","runtime":{"model":"current","provider":"local"}}"#)
        await second.value
        requests[0].succeed(body: #"{"object":"session.model","session_id":"current","runtime":{"model":"old","provider":"remote"}}"#)
        await first.value
        XCTAssertEqual(store.activeRuntime?.effectiveModel, "current")
        XCTAssertEqual(store.effectiveCurrentModel, "current")
        XCTAssertEqual(store.effectiveCurrentProvider, "local")
    }

    @MainActor
    func testModelLockCompletionCannotAffectDifferentSession() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        for fails in [false, true] {
            let store = AppStore(client: client)
            store.activeSession = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"old"}"#.utf8))
            let started = expectation(description: "Model lock pending")
            var request: SessionHistoryURLProtocol?
            SessionHistoryURLProtocol.handler = { pending in
                Task { @MainActor in request = pending; started.fulfill() }
            }
            let locking = Task { await store.selectPreferredModel("old-model", provider: "remote") }
            await fulfillment(of: [started], timeout: 3)
            store.activeSession = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"new"}"#.utf8))
            store.activeRuntime = SessionRuntime(provider: "local", model: "new-model", routeSource: nil, requested: nil, modelLock: nil)
            if fails { request?.fail() }
            else { request?.succeed(body: #"{"object":"session.model","session_id":"old","runtime":{"model":"old-model","provider":"remote"}}"#) }
            await locking.value
            XCTAssertEqual(store.activeRuntime?.effectiveModel, "new-model")
            XCTAssertNil(store.error)
            SessionHistoryURLProtocol.handler = nil
        }
    }

    func testJobRenameOmitsUntouchedRemoteFieldsButAllowsClearingSkills() throws {
        let original = try JSONDecoder().decode(HermesJob.self, from: Data(#"{"id":"job","name":"Original","prompt":"Existing prompt","schedule_display":"Every 2 hours","deliver":"local","skills":["review"]}"#.utf8))
        var draft = HermesJobWrite(name: "Renamed", schedule: nil, prompt: "Existing prompt", deliver: "local", skills: ["review"])
        let patch = draft.changes(comparedTo: original)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["name"])
        XCTAssertTrue(patch.hasChanges)
        draft.name = "Original"
        XCTAssertFalse(draft.changes(comparedTo: original).hasChanges)
        draft.skills = []
        let cleared = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft.changes(comparedTo: original))) as? [String: Any])
        XCTAssertEqual(Set(cleared.keys), ["skills"])
        XCTAssertEqual(cleared["skills"] as? [String], [])
    }

    @MainActor
    func testOlderSessionRefreshCannotOverwriteNewerModelAndPin() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        let store = AppStore(client: client)
        store.activeSession = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"current","model":"initial"}"#.utf8))
        let firstStarted = expectation(description: "First refresh pending")
        let secondStarted = expectation(description: "Second refresh pending")
        var requests: [SessionHistoryURLProtocol] = []
        SessionHistoryURLProtocol.handler = { request in
            Task { @MainActor in
                requests.append(request)
                if requests.count == 1 { firstStarted.fulfill() }
                else { secondStarted.fulfill() }
            }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let first = Task { await store.refreshSessions() }
        await fulfillment(of: [firstStarted], timeout: 3)
        let second = Task { await store.refreshSessions() }
        await fulfillment(of: [secondStarted], timeout: 3)
        requests[1].succeed(body: #"{"object":"list","data":[{"id":"current","model":"latest","pinned":true}]}"#)
        await second.value
        requests[0].succeed(body: #"{"object":"list","data":[{"id":"current","model":"stale","pinned":false}]}"#)
        await first.value
        XCTAssertEqual(store.effectiveCurrentModel, "latest")
        XCTAssertEqual(store.activeSession?.isPinned, true)
        XCTAssertEqual(store.sessions.first?.model, "latest")
    }

    @MainActor
    func testDeletedSessionCannotBeRepopulatedByPendingHistory() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        let store = AppStore(client: client)
        let session = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"current","model":"deleted-model"}"#.utf8))
        let started = expectation(description: "History pending")
        var history: SessionHistoryURLProtocol?
        SessionHistoryURLProtocol.handler = { request in
            Task { @MainActor in
                if request.request.httpMethod == "GET" {
                    history = request
                    started.fulfill()
                } else {
                    request.succeed(body: #"{"ok":true}"#)
                }
            }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let selection = Task { await store.selectSession(session) }
        await fulfillment(of: [started], timeout: 3)
        await store.deleteSession(session)
        try XCTUnwrap(history).succeed()
        await selection.value
        XCTAssertNil(store.activeSession)
        XCTAssertNil(store.activeRuntime)
        XCTAssertTrue(store.messages.isEmpty)
    }

    @MainActor
    func testDeletingActiveSessionStopsItsTransientStreamState() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        let store = AppStore(client: client)
        let session = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"current"}"#.utf8))
        store.activeSession = session
        store.sessions = [session]
        store.activeRuntime = SessionRuntime(provider: "old-provider", model: "old-model", routeSource: "test", requested: nil, modelLock: nil)
        store.isStreaming = true
        store.streamingText = "In-flight reply"
        store.queueMessage("Queued for this session")
        SessionHistoryURLProtocol.handler = { $0.succeed(body: #"{"ok":true}"#) }
        defer { SessionHistoryURLProtocol.handler = nil }
        await store.deleteSession(session)
        XCTAssertNil(store.activeSession)
        XCTAssertNil(store.activeRuntime)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertFalse(store.isStreaming)
        XCTAssertEqual(store.streamingText, "")
        XCTAssertTrue(store.queuedMessages.isEmpty)
    }

    func testUnchangedJobScheduleIsOmittedInsteadOfReparsed() throws {
        let schedule = HermesJobWrite.scheduleUpdate(edited: " Every 2 hours ", originalDisplay: "Every 2 hours")
        XCTAssertNil(schedule)
        let payload = HermesJobWrite(name: "Renamed job", schedule: schedule, prompt: "Existing prompt")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertNil(json["schedule"])
        XCTAssertEqual(json["name"] as? String, "Renamed job")
        XCTAssertEqual(HermesJobWrite.scheduleUpdate(edited: " 0 9 * * * ", originalDisplay: "Every 2 hours"), "0 9 * * *")
        XCTAssertEqual(HermesJobWrite.scheduleUpdate(edited: "30m", originalDisplay: nil), "30m")
    }

    func testBotHistoryRejectsResponsesForAnotherProfileOrPage() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(
            config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
            session: URLSession(configuration: config)
        )
        defer { SessionHistoryURLProtocol.handler = nil }
        for (profile, offset) in [("other", 0), ("assistant", 100)] {
            SessionHistoryURLProtocol.handler = { request in
                XCTAssertEqual(request.request.url?.path, "/api/companion/bot-history")
                request.succeed(body: """
                {"profile":"\(profile)","session_id":"chat","messages":[],"pagination":{"offset":\(offset),"limit":100,"returned":0}}
                """)
            }
            do {
                _ = try await client.botHistory(profile: "assistant", offset: 0)
                XCTFail("A foreign profile or page must not be displayed")
            } catch APIError.invalidResponse {
                // Expected: the response does not belong to this view.
            }
        }
    }

    func testDetailedHealthUsesServerPlatformKeysAsNames() throws {
        let data = Data(#"{"status":"ok","platforms":{"telegram":{"state":"connected"},"discord":{"state":"error","error_code":"unavailable"}}}"#.utf8)
        let health = try JSONDecoder().decode(PlatformHealthResponse.self, from: data)
        XCTAssertEqual(health.platforms?["telegram"]?.name, "telegram")
        XCTAssertEqual(health.platforms?["telegram"]?.state, "connected")
        XCTAssertEqual(health.platforms?["discord"]?.id, "discord")
        XCTAssertEqual(health.platforms?["discord"]?.errorCode, "unavailable")
    }

    func testCapabilitiesAcceptStructuredBrowserControl() throws {
        for enabled in [false, true] {
            let data = Data("""
            {"browser_extension_control":{"enabled":\(enabled),"protocol_version":"1","artifact_transport":{"upload":{"method":"POST","path":"/v1/artifacts/upload"}}},"session_chat":true}
            """.utf8)
            let features = try JSONDecoder().decode(CapabilitiesResponse.Features.self, from: data)
            XCTAssertEqual(features.browserExtensionControl, enabled)
            XCTAssertEqual(features.artifactTransport, enabled)
            XCTAssertTrue(features.sessionChat)
            XCTAssertFalse(features.runStop)
        }
    }

    func testCapabilitiesAcceptLegacyBooleanBrowserControl() throws {
        let data = Data(#"{"browser_extension_control":false,"artifact_transport":true}"#.utf8)
        let features = try JSONDecoder().decode(CapabilitiesResponse.Features.self, from: data)
        XCTAssertEqual(features.browserExtensionControl, false)
        XCTAssertEqual(features.artifactTransport, true)
    }

    func testUnresponsiveHealthRequestTimesOut() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(
            config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
            session: URLSession(configuration: config)
        )
        SessionHistoryURLProtocol.handler = { _ in }
        defer { SessionHistoryURLProtocol.handler = nil }
        let start = Date()
        do {
            _ = try await client.checkHealth()
            XCTFail("A health request that never responds must time out")
        } catch {
            guard case APIError.transport(let failure) = error else {
                return XCTFail("Expected endpoint-specific transport error, got \(error)")
            }
            XCTAssertEqual(failure.code, URLError.timedOut.rawValue)
            XCTAssertEqual(failure.endpoint, "/health")
            XCTAssertTrue(failure.localizedDescription.contains("5 seconds"))
            XCTAssertLessThan(Date().timeIntervalSince(start), 8)
        }
    }

    @MainActor
    func testSessionRefreshUpdatesOpenChatFromServerAfterStreamFinishes() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(
            config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
            session: URLSession(configuration: config)
        )
        let store = AppStore(client: client)
        store.activeSession = try JSONDecoder().decode(HermesSession.self, from: Data(
            #"{"id":"current","title":"Old title","model":"old-model","provider":"old-provider"}"#.utf8
        ))
        store.activeRuntime = SessionRuntime(provider: "old-provider", model: "old-model", routeSource: "stream", requested: nil, modelLock: nil)
        SessionHistoryURLProtocol.handler = { request in
            request.succeed(body:
                #"{"object":"list","data":[{"id":"current","title":"Updated on Mac","model":"qwen3.8:27b-mlx","provider":"local","pinned":true}]}"#
            )
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        store.isStreaming = true
        await store.refreshSessions()
        XCTAssertEqual(store.effectiveCurrentModel, "old-model")
        store.isStreaming = false
        await store.refreshSessions()
        XCTAssertEqual(store.effectiveCurrentModel, "qwen3.8:27b-mlx")
        XCTAssertEqual(store.effectiveCurrentProvider, "local")
        XCTAssertEqual(store.activeSession?.title, "Updated on Mac")
        XCTAssertEqual(store.activeSession?.isPinned, true)
        XCTAssertNil(store.activeRuntime)
    }

    @MainActor
    func testLateHistoryCannotReplaceNewSessionOrItsModel() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(
            config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
            session: URLSession(configuration: config)
        )
        let store = AppStore(client: client)
        let first = try JSONDecoder().decode(HermesSession.self, from: Data(
            #"{"id":"first","model":"old-model","provider":"old-provider"}"#.utf8
        ))
        let second = try JSONDecoder().decode(HermesSession.self, from: Data(
            #"{"id":"second","model":"local-model","provider":"local-provider"}"#.utf8
        ))
        let firstStarted = expectation(description: "First history pending")
        let secondStarted = expectation(description: "Second history pending")
        var requests: [String: SessionHistoryURLProtocol] = [:]
        SessionHistoryURLProtocol.handler = { request in
            Task { @MainActor in
                let path = request.request.url!.path
                requests[path] = request
                if path.contains("first") { firstStarted.fulfill() }
                else { secondStarted.fulfill() }
            }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let firstTask = Task { await store.selectSession(first) }
        await fulfillment(of: [firstStarted], timeout: 2)
        store.activeRuntime = SessionRuntime(provider: "old-provider", model: "old-model", routeSource: "test", requested: nil, modelLock: nil)
        let secondTask = Task { await store.selectSession(second) }
        await fulfillment(of: [secondStarted], timeout: 2)
        XCTAssertEqual(store.effectiveCurrentModel, "local-model")
        XCTAssertEqual(store.effectiveCurrentProvider, "local-provider")
        let secondRequest = try XCTUnwrap(requests.values.first { $0.request.url!.path.contains("second") })
        secondRequest.fail()
        await secondTask.value
        let currentError = store.error?.message
        let firstRequest = try XCTUnwrap(requests.values.first { $0.request.url!.path.contains("first") })
        firstRequest.succeed()
        await firstTask.value
        XCTAssertEqual(store.activeSession?.id, "second")
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.effectiveCurrentModel, "local-model")
        XCTAssertEqual(store.activeRuntime?.effectiveModel, "local-model")
        XCTAssertEqual(store.error?.message, currentError)
    }

    @MainActor
    func testPendingAutomaticSessionCreationCannotReplaceUserSelection() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        let store = AppStore(client: client)
        let selected = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"selected","model":"local-model"}"#.utf8))
        let creationStarted = expectation(description: "Creation pending")
        var creation: SessionHistoryURLProtocol?
        SessionHistoryURLProtocol.handler = { request in
            Task { @MainActor in
                if request.request.httpMethod == "POST" {
                    creation = request
                    creationStarted.fulfill()
                } else {
                    request.succeed(body: #"{"object":"list","data":[]}"#)
                }
            }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let send = Task { await store.sendMessage("Pending creation") }
        await fulfillment(of: [creationStarted], timeout: 3)
        await store.selectSession(selected)
        try XCTUnwrap(creation).succeed(body: #"{"object":"hermes.session","session":{"id":"late-created","model":"old-model"}}"#)
        let response = await send.value
        XCTAssertNil(response)
        XCTAssertEqual(store.activeSession?.id, "selected")
        XCTAssertFalse(store.sessions.contains { $0.id == "late-created" })
        XCTAssertNil(store.error)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertFalse(store.isStreaming)
    }

    @MainActor
    func testStopStreamingClearsTransientTextAndQueuedSends() {
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"))
        let store = AppStore(client: client)
        store.isStreaming = true
        store.streamingText = "Old response"
        store.streamingThinking = "Old reasoning"
        store.queueMessage("Do not send after stop")
        store.stopStreaming()
        XCTAssertFalse(store.isStreaming)
        XCTAssertEqual(store.streamingText, "")
        XCTAssertEqual(store.streamingThinking, "")
        XCTAssertTrue(store.queuedMessages.isEmpty)
    }

    @MainActor
    func testManualCreationCannotOverrideLaterSelection() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        let store = AppStore(client: client)
        let selected = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"selected","model":"local-model"}"#.utf8))
        let creationStarted = expectation(description: "Manual creation pending")
        var creation: SessionHistoryURLProtocol?
        SessionHistoryURLProtocol.handler = { request in
            Task { @MainActor in
                if request.request.httpMethod == "POST" {
                    creation = request
                    creationStarted.fulfill()
                } else {
                    request.succeed(body: #"{"object":"list","data":[]}"#)
                }
            }
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        let create = Task { await store.createSession(title: "New conversation") }
        await fulfillment(of: [creationStarted], timeout: 3)
        await store.selectSession(selected)
        try XCTUnwrap(creation).succeed(body: #"{"object":"hermes.session","session":{"id":"late-created","model":"old-model"}}"#)
        await create.value
        XCTAssertEqual(store.activeSession?.id, "selected")
        XCTAssertEqual(store.effectiveCurrentModel, "local-model")
        XCTAssertNil(store.error)
    }

    @MainActor
    func testEmptyChatResponseDoesNotReplayPreviousAssistantMessage() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        let store = AppStore(client: client)
        store.activeSession = try JSONDecoder().decode(HermesSession.self, from: Data(#"{"id":"current"}"#.utf8))
        store.messages = [ChatDisplayMessage(id: "previous", role: "assistant", content: "Previous answer", timestamp: Date())]
        SessionHistoryURLProtocol.handler = { request in
            request.succeed(body: #"{"object":"hermes.session.chat.completion","session_id":"current","message":{"role":"assistant","content":""}}"#)
        }
        defer { SessionHistoryURLProtocol.handler = nil }
        // Exercise the non-streaming attachment response path without contacting a server.
        let result = await store.sendMessage("New question", images: [Data([0])], skipPostReload: true)
        XCTAssertNil(result)
        XCTAssertEqual(store.messages.filter(\.isAssistant).map(\.content), ["Previous answer"])
        XCTAssertFalse(store.isStreaming)
    }

    func testDecodesFullModelOptionsCatalog() throws {
        let json = """
        {
          "providers": [
            {
              "slug": "nous",
              "name": "Nous Portal",
              "models": ["moonshotai/kimi-k3"],
              "is_current": true
            }
          ],
          "model": "moonshotai/kimi-k3",
          "provider": "nous"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ModelOptionsResponse.self, from: json)
        XCTAssertEqual(decoded.providers.count, 1)
        XCTAssertEqual(decoded.providers[0].slug, "nous")
        XCTAssertEqual(decoded.providers[0].models, ["moonshotai/kimi-k3"])
        XCTAssertEqual(decoded.provider, "nous")
    }

    @MainActor
    func testRefreshCapabilitiesLoadsProviderCatalog() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionHistoryURLProtocol.self]
        let client = HermesAPIClient(config: ConnectionConfig(baseURL: "https://hermes.invalid", apiKey: "", label: "Test"),
                                     session: URLSession(configuration: config))
        let store = AppStore(client: client)
        defer { SessionHistoryURLProtocol.handler = nil }
        SessionHistoryURLProtocol.handler = { request in
            if request.request.url!.path.hasSuffix("/api/model/options") {
                request.succeed(body: #"{"providers":[{"slug":"local","name":"Local","models":["qwen3.8:27b-mlx"],"is_current":true}],"model":"qwen3.8:27b-mlx","provider":"local"}"#)
            } else {
                request.fail()
            }
        }

        await store.refreshCapabilities()

        XCTAssertEqual(store.configuredProviders, ["local"])
        XCTAssertEqual(store.gatewayDefaultModel, "qwen3.8:27b-mlx")
        XCTAssertEqual(store.gatewayDefaultProvider, "local")
        XCTAssertEqual(store.availableModels, ["qwen3.8:27b-mlx"])
        XCTAssertEqual(store.modelCatalog.first?.provider, "local")
        XCTAssertNil(store.error)
    }

    func testDecodesSessionModelLockRuntime() throws {
        let json = """
        {
          "object": "hermes.session.model_lock",
          "session_id": "test-session",
          "runtime": {
            "provider": "nous",
            "model": "moonshotai/kimi-k3",
            "route_source": "raw_request",
            "requested": {"provider": "nous", "model": "moonshotai/kimi-k3"},
            "model_lock": "accepted"
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SessionModelLockResponse.self, from: json)
        XCTAssertEqual(decoded.runtime.effectiveModel, "moonshotai/kimi-k3")
        XCTAssertEqual(decoded.runtime.effectiveProvider, "nous")
        XCTAssertEqual(decoded.runtime.modelLock, "accepted")
    }

    func testRejectsWebhookEndpointWithClearMessage() {
        let health = HealthResponse(status: "ok", platform: "webhook", version: "1.0")
        XCTAssertFalse(health.isHermesAPI)
        XCTAssertEqual(
            AppStore.invalidHealthMessage(health),
            "That URL is the Hermes webhook endpoint. Use the API gateway on port 8642."
        )
    }

    func testDecodesServerSessionFlags() throws {
        let json = """
        {
          "id": "session-1",
          "title": "Pinned chat",
          "source": "api_server",
          "model": "moonshotai/kimi-k3",
          "pinned": true,
          "archived": false,
          "hidden": false
        }
        """.data(using: .utf8)!

        let session = try JSONDecoder().decode(HermesSession.self, from: json)
        XCTAssertEqual(session.isPinned, true)
        XCTAssertEqual(session.isArchived, false)
        XCTAssertEqual(session.isHidden, false)
    }

    func testSessionPatchOmitsUnsetFields() throws {
        let data = try JSONEncoder().encode(
            PatchSessionRequest(isArchived: true)
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json as? [String: Bool], ["archived": true])
    }

    func testFullCatalogCarriesGatewayDefaultRuntime() throws {
        let json = """
        {
          "providers": [
            {
              "slug": "custom:local-(localhost:11434)",
              "name": "Local (localhost:11434)",
              "models": ["qwen3.8:27b-mlx"],
              "is_current": true
            }
          ],
          "model": "qwen3.8:27b-mlx",
          "provider": "custom:local-(localhost:11434)"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ModelOptionsResponse.self, from: json)
        XCTAssertEqual(decoded.model, "qwen3.8:27b-mlx")
        XCTAssertEqual(decoded.provider, "custom:local-(localhost:11434)")
    }

    func testSessionProviderTakesPriorityOverStaleCatalog() throws {
        let json = """
        {
          "id": "session-1",
          "title": "Live provider",
          "source": "api_server",
          "model": "qwen3.8:27b-mlx",
          "provider": "custom:local-(localhost:11434)",
          "billing_provider": "custom:local-(localhost:11434)"
        }
        """.data(using: .utf8)!

        let session = try JSONDecoder().decode(HermesSession.self, from: json)
        XCTAssertEqual(session.provider, "custom:local-(localhost:11434)")
        XCTAssertEqual(session.billingProvider, "custom:local-(localhost:11434)")
    }
}

private final class SessionHistoryURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((SessionHistoryURLProtocol) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(self) }
    override func stopLoading() {}

    func succeed(body: String = #"{"object":"list","data":[{"id":1,"role":"assistant","content":"Old session reply"}]}"#, status: Int = 200, headers: [String: String]? = nil) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    func bodyData() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    func fail() {
        client?.urlProtocol(self, didFailWithError: NSError(
            domain: "SessionHistoryTest", code: 1,
            userInfo: [NSLocalizedDescriptionKey: request.url!.path]
        ))
    }
}
