import XCTest
@testable import HermesCompanion

final class HermesModelContractTests: XCTestCase {
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

    func succeed(body: String = #"{"object":"list","data":[{"id":1,"role":"assistant","content":"Old session reply"}]}"#) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
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
