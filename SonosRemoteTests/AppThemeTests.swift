import XCTest
import SwiftUI
@testable import SonosRemote

final class AppThemeTests: XCTestCase {
    func testSystemThemeHasNoOverride() {
        XCTAssertNil(AppTheme.system.colorScheme)
    }

    func testLightAndDarkMapToTheirColorScheme() {
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
    }

    func testRawValueRoundTrip() {
        for theme in AppTheme.allCases {
            XCTAssertEqual(AppTheme(rawValue: theme.rawValue), theme)
        }
    }
}
