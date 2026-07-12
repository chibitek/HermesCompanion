import XCTest
@testable import HermesCompanion

final class SkillCommandLogicTests: XCTestCase {
    private let skills = [
        Skill(name: "ios-swiftui-development", description: "Build SwiftUI apps", category: "software-development"),
        Skill(name: "hermes-agent", description: "Configure Hermes Agent", category: "autonomous-ai-agents"),
        Skill(name: "github-code-review", description: "Review pull requests", category: "github")
    ]

    func testSlashOpensSkillSuggestions() {
        XCTAssertTrue(SkillCommandLogic.shouldShowSuggestions(for: "/"))
        XCTAssertTrue(SkillCommandLogic.shouldShowSuggestions(for: "/skill "))
        XCTAssertFalse(SkillCommandLogic.shouldShowSuggestions(for: "hello"))
    }

    func testSuggestionsFilterByNameDescriptionAndCategory() {
        XCTAssertEqual(SkillCommandLogic.suggestions(for: "/skill swift", skills: skills).map(\.name), ["ios-swiftui-development"])
        XCTAssertEqual(SkillCommandLogic.suggestions(for: "/review", skills: skills).map(\.name), ["github-code-review"])
        XCTAssertEqual(SkillCommandLogic.suggestions(for: "/skill autonomous", skills: skills).map(\.name), ["hermes-agent"])
    }

    func testSelectingSkillCreatesExplicitSkillCommand() {
        XCTAssertEqual(
            SkillCommandLogic.textBySelecting(skills[0], currentText: "/skill ios"),
            "/skill ios-swiftui-development "
        )
    }

    func testCommandTransformsIntoAgentInstruction() {
        XCTAssertEqual(
            SkillCommandLogic.messagePayload(for: "/skill hermes-agent troubleshoot my gateway"),
            "Use the installed skill named \"hermes-agent\" for this request. Load it before acting and follow its instructions.\n\ntroubleshoot my gateway"
        )
    }

    func testCommandWithoutRequestStillActivatesSkill() {
        XCTAssertEqual(
            SkillCommandLogic.messagePayload(for: "/skill hermes-agent"),
            "Use the installed skill named \"hermes-agent\" for this request. Load it before acting and follow its instructions."
        )
    }

    func testOrdinaryMessageIsUnchanged() {
        XCTAssertEqual(SkillCommandLogic.messagePayload(for: "hello Hermes"), "hello Hermes")
    }
}
