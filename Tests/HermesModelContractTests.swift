import XCTest
@testable import HermesCompanion

final class HermesModelContractTests: XCTestCase {
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

    func succeed() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(
            #"{"object":"list","data":[{"id":1,"role":"assistant","content":"Old session reply"}]}"#.utf8
        ))
        client?.urlProtocolDidFinishLoading(self)
    }

    func fail() {
        client?.urlProtocol(self, didFailWithError: NSError(
            domain: "SessionHistoryTest", code: 1,
            userInfo: [NSLocalizedDescriptionKey: request.url!.path]
        ))
    }
}
