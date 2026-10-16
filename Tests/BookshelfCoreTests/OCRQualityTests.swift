import XCTest
import Foundation
@testable import BookshelfCore

final class OCRQualityTests: XCTestCase {
    func testMinorQuartzRoundingDoesNotHideVisibleChanges() {
        let original = Data(repeating: 255, count: 720 * 937 * 4)
        var rounded = original
        rounded[0] = 248; rounded[16] = 250
        let rounding = OCRQualityCheck.comparePixels(original, rounded, page: 1)
        XCTAssertTrue(rounding.passed)
        XCTAssertEqual(rounding.changedPixels, 2)
        var changed = original
        changed[0] = 0
        XCTAssertFalse(OCRQualityCheck.comparePixels(original, changed, page: 1).passed)
        for pixel in 0..<100 { rounded[pixel * 4] = 250 }
        XCTAssertFalse(OCRQualityCheck.comparePixels(original, rounded, page: 1).passed)
    }
    func testSpacingDetectionPreservesWordBoundaries() {
        let text = String(repeating: "도서관에서 책을 읽고 공부합니다. ", count: 10)
        XCTAssertFalse(OCRQualityCheck.hasExcessSpacing(text))
        XCTAssertTrue(OCRQualityCheck.hasExcessSpacing(text.map(String.init).joined(separator: " ")))
    }
}
