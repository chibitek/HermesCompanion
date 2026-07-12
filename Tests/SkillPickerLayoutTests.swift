import XCTest
@testable import HermesCompanion

final class SkillPickerLayoutTests: XCTestCase {
    func testPickerUsesMostOfAvailableScreenHeight() {
        XCTAssertEqual(SkillPickerLayout.maximumHeight(availableHeight: 800), 600)
    }

    func testPickerKeepsComposerVisibleOnShortScreens() {
        XCTAssertEqual(SkillPickerLayout.maximumHeight(availableHeight: 500), 340)
    }

    func testPickerHasReadableMinimumHeight() {
        XCTAssertEqual(SkillPickerLayout.maximumHeight(availableHeight: 300), 280)
    }
}
