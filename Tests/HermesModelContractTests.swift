import XCTest
@testable import HermesCompanion

final class HermesModelContractTests: XCTestCase {
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
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
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

    func succeed(body: String = #"{"object":"list","data":[{"id":1,"role":"assistant","content":"Old session reply"}]}"#, status: Int = 200) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    func fail() {
        client?.urlProtocol(self, didFailWithError: NSError(
            domain: "SessionHistoryTest", code: 1,
            userInfo: [NSLocalizedDescriptionKey: request.url!.path]
        ))
    }
}
