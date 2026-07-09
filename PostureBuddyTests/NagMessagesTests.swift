import XCTest
@testable import PostureBuddy

final class NagMessagesTests: XCTestCase {
    func testAllMessagesAreNonEmpty() {
        XCTAssertFalse(NagMessages.all.isEmpty)
        for message in NagMessages.all {
            XCTAssertFalse(message.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    func testNeverRepeatsTheSameLineTwiceInARow() {
        var messages = NagMessages()
        var previous = messages.next()
        for _ in 0..<500 {
            let current = messages.next()
            XCTAssertNotEqual(current, previous, "A line repeated back-to-back")
            previous = current
        }
    }

    func testEveryLineIsReachable() {
        var messages = NagMessages()
        var seen = Set<String>()
        for _ in 0..<2000 { seen.insert(messages.next()) }
        XCTAssertEqual(seen, Set(NagMessages.all))
    }
}
