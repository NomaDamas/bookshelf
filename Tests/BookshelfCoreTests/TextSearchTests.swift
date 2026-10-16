import XCTest
@testable import BookshelfCore

final class TextSearchTests: XCTestCase {
    private func matched(_ query: String, in source: String, ignoreWhitespace: Bool = true) -> String? {
        TextSearchQuery(query, ignoreWhitespace: ignoreWhitespace).range(in: source).map { String(source[$0]) }
    }

    func testKoreanOCRSpacingMatchesWithoutChangingQuote() {
        let source = "앞부분입니다. 설 득 의\n심 리 학 을 읽습니다."
        XCTAssertEqual(matched("설득의 심리학", in: source), "설 득 의\n심 리 학")
        XCTAssertEqual(matched("설 득 의 심 리 학", in: "설득의 심리학"), "설득의 심리학")
        XCTAssertNil(matched("설득의 심리학", in: source, ignoreWhitespace: false))
    }

    func testEnglishCaseLineBreakAndUnicodeSpacing() {
        XCTAssertEqual(matched("Deep Learning", in: "a DE EP\tLEARN\nING example"), "DE EP\tLEARN\nING")
        XCTAssertEqual(matched("notebook", in: "note\u{00A0}b\u{3000}ook"), "note\u{00A0}b\u{3000}ook")
        XCTAssertEqual(matched("cooperate", in: "co\u{00AD}oper\u{200B}ate"), "co\u{00AD}oper\u{200B}ate")
    }

    func testOriginalOffsetsSurviveEmojiAndDecomposedUnicode() {
        let source = "📚 👩🏽‍💻 cafe\u{0301} 한 \n글 끝"
        XCTAssertEqual(matched("café 한글", in: source), "cafe\u{0301} 한 \n글")
        XCTAssertEqual(matched("📚한글", in: "앞 📚 한 글 뒤"), "📚 한 글")
    }

    func testExactSpacingOptionPreventsCrossWordFalsePositives() {
        XCTAssertEqual(matched("therapist", in: "the rapist"), "the rapist")
        XCTAssertNil(matched("therapist", in: "the rapist", ignoreWhitespace: false))
        XCTAssertNil(matched("cooperate", in: "co-operate"))
        XCTAssertNil(matched("hello", in: "he1lo"))
    }

    func testEmptyQueriesAndBoundaryMatches() {
        XCTAssertNil(matched(" \n\t\u{200B}", in: "anything"))
        XCTAssertNil(matched("word", in: ""))
        XCTAssertEqual(matched("처음", in: "처 음"), "처 음")
        XCTAssertEqual(matched("끝", in: "끝"), "끝")
        XCTAssertEqual(matched("normal", in: "normal text", ignoreWhitespace: false), "normal")
    }
}
