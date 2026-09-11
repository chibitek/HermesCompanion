import XCTest
@testable import HermesCompanion

final class HermesModelContractTests: XCTestCase {
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
}
