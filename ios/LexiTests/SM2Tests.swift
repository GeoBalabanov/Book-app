import XCTest
@testable import Lexi

/// Ported from web/tests/sm2.test.mjs.
final class SM2Tests: XCTestCase {
    private let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 10; c.hour = 12
        return Calendar.current.date(from: c)!
    }()

    private func days(_ s: SM2.State) -> Int {
        Int((SM2.startOfDay(s.due).timeIntervalSince(SM2.startOfDay(now)) / SM2.day).rounded())
    }

    func testNewCardIsDueImmediately() {
        let s = SM2.newState(now: now)
        XCTAssertEqual(s.ease, 2.5)
        XCTAssertTrue(SM2.isDueToday(s.due, now: now))
    }

    func testGoodOneDayThenSixThenIntervalTimesEase() {
        var s = SM2.review(SM2.newState(now: now), .good, now: now)
        XCTAssertEqual(s.interval, 1); XCTAssertEqual(s.repetitions, 1); XCTAssertEqual(s.ease, 2.5)
        XCTAssertEqual(days(s), 1)
        s = SM2.review(s, .good, now: now)
        XCTAssertEqual(s.interval, 6)
        s = SM2.review(s, .good, now: now)
        XCTAssertEqual(s.interval, 15) // round(6 × 2.5)
        XCTAssertFalse(SM2.isDueToday(s.due, now: now))
    }

    func testAgainResetsLowersEaseAndReturnsInTenMinutes() {
        var s = SM2.review(SM2.review(SM2.newState(now: now), .good, now: now), .good, now: now)
        s = SM2.review(s, .again, now: now)
        XCTAssertEqual(s.repetitions, 0)
        XCTAssertEqual(s.interval, 0)
        XCTAssertEqual(s.lapses, 1)
        XCTAssertEqual(s.due, now.addingTimeInterval(SM2.relearnDelay))
        XCTAssertEqual(s.ease, 1.96, accuracy: 1e-9) // 2.5 - 0.54
    }

    func testHardLowersEaseAndEasyRaisesIt() {
        let h = SM2.review(SM2.newState(now: now), .hard, now: now)
        XCTAssertEqual(h.ease, 2.36, accuracy: 1e-9)
        let e = SM2.review(SM2.newState(now: now), .easy, now: now)
        XCTAssertEqual(e.ease, 2.6, accuracy: 1e-9)
        XCTAssertEqual(e.interval, 4)
    }

    func testEaseNeverDropsBelowOnePointThree() {
        var s = SM2.newState(now: now)
        for _ in 0..<20 { s = SM2.review(s, .again, now: now) }
        XCTAssertEqual(s.ease, 1.3)
    }

    func testDueAtFourAmLocal() {
        let s = SM2.review(SM2.newState(now: now), .good, now: now)
        XCTAssertEqual(Calendar.current.component(.hour, from: s.due), 4)
    }

    func testFormatRelativeMatchesWeb() {
        XCTAssertEqual(SM2.formatRelative(0), "due")
        XCTAssertEqual(SM2.formatRelative(10 * 60), "10m")
        XCTAssertEqual(SM2.formatRelative(5 * 3600), "5h")
        XCTAssertEqual(SM2.formatRelative(6 * SM2.day), "6d")
        XCTAssertEqual(SM2.formatRelative(60 * SM2.day), "2mo")
    }
}
