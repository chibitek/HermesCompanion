import XCTest
@testable import HermesCompanion

final class BotChatAccessTests: XCTestCase {
    func testBotConnectionRequiresExactOwningProfileAndUsesItsSavedCredential() throws {
        let root = ConnectionConfig(baseURL: "https://hermes.local/gateway", apiKey: "root-test-key", label: "Root")
        let owner = ConnectionConfig(baseURL: "https://HERMES.local:443/gateway/p/assistant/", apiKey: "profile-test-key", label: "Assistant")
        let foreign = ConnectionConfig(baseURL: "https://another.local/gateway/p/assistant", apiKey: "foreign-test-key", label: "Other server")
        XCTAssertEqual(try BotChatAccess.connection(root: root, profile: "assistant", saved: [root, foreign, owner]), owner)
        XCTAssertEqual(try BotChatAccess.connection(root: root, profile: "default", saved: []), root)
        for path in ["https://hermes.local/gateway/p/Assistant", "http://hermes.local/gateway/p/assistant",
                     "https://hermes.local:8642/gateway/p/assistant", "https://hermes.local/p/assistant",
                     "https://hermes.local/gateway/p/assistant?token=ignored", "https://hermes.local/gateway/p/assistant#fragment"] {
            let wrong = ConnectionConfig(baseURL: path, apiKey: "test-key", label: "Wrong route")
            XCTAssertThrowsError(try BotChatAccess.connection(root: root, profile: "assistant", saved: [root, foreign, wrong]))
        }
        XCTAssertThrowsError(try BotChatAccess.connection(root: root, profile: "assistant", saved: [owner, owner]))
        for profile in ["../default", "", "assistant/child", "assistant?other", "café"] {
            XCTAssertThrowsError(try BotChatAccess.expectedURL(root: root, profile: profile))
        }
        for path in ["https://hermes.local/p/other", "https://user:secret@hermes.local", "https://hermes.local?key=secret"] {
            let invalid = ConnectionConfig(baseURL: path, apiKey: "test-key", label: "Invalid root")
            XCTAssertThrowsError(try BotChatAccess.expectedURL(root: invalid, profile: "assistant")) { error in
                XCTAssertFalse(error.localizedDescription.contains("secret"))
            }
        }
    }

    func testBotSessionRejectsUnrelatedArchivedOrRenamedConversation() throws {
        let canonical = BotSession(id: "canonical", title: "Bot Chat", preview: nil)
        func detail(id: String = "canonical", title: String = "Bot Chat", archived: Bool = false) throws -> SessionDetail {
            try JSONDecoder().decode(SessionDetail.self, from: JSONSerialization.data(withJSONObject: [
                "id": id, "title": title, "archived": archived, "model": "saved-model", "provider": "saved-provider"
            ]))
        }
        let session = try BotChatAccess.session(detail(), canonical: canonical, profile: "assistant")
        XCTAssertEqual(session.id, "canonical")
        XCTAssertEqual(session.model, "saved-model")
        XCTAssertEqual(session.provider, "saved-provider")
        for wrong in [try detail(id: "other"), try detail(title: "Other conversation"), try detail(archived: true)] {
            XCTAssertThrowsError(try BotChatAccess.session(wrong, canonical: canonical, profile: "assistant")) { error in
                XCTAssertTrue(error.localizedDescription.contains("assistant"))
                XCTAssertTrue(error.localizedDescription.contains("canonical"))
            }
        }
    }
}
