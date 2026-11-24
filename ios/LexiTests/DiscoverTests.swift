import XCTest
@testable import Lexi

@MainActor
final class GutenbergCatalogTests: XCTestCase {
    func testCatalogueLoadsAndSearches() async {
        let catalog = GutenbergCatalog.shared
        await catalog.load()
        XCTAssertGreaterThan(catalog.books.count, 60_000)
        XCTAssertEqual(catalog.book(id: 36)?.author, "H. G. Wells")

        let tm = await catalog.search("time machine")
        XCTAssertEqual(tm.first?.id, 35, "\(tm.prefix(3).map(\.title))")
        let austen = await catalog.search("austen pride")
        XCTAssertEqual(austen.first?.id, 1342)
        let accents = await catalog.search("bronte")          // matches "Brontë"
        XCTAssertTrue(accents.contains { $0.id == 1260 })
        let none = await catalog.search("zzqqxx")
        XCTAssertTrue(none.isEmpty)
    }

    func testShelvesPreferPopularAndExcludeOwned() async {
        let catalog = GutenbergCatalog.shared
        await catalog.load()
        let scifi = catalog.shelf(["Science-Fiction & Fantasy"], excluding: [36], limit: 10)
        XCTAssertEqual(scifi.count, 10)
        XCTAssertFalse(scifi.contains { $0.id == 36 })
        XCTAssertTrue(scifi.first?.isPopular == true)
        XCTAssertEqual(catalog.popular(limit: 3).map(\.id), [1342, 84, 11])
    }

    func testShortTitle() {
        let b = CatalogBook(id: 84, title: "Frankenstein; or, The modern Prometheus", author: "", categories: [], rank: 1)
        XCTAssertEqual(b.shortTitle, "Frankenstein")
    }
}

final class ReadingStatsTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func day(_ offset: Int, from now: Date) -> String {
        ReadingStats.key(for: cal.date(byAdding: .day, value: offset, to: now)!, calendar: cal)
    }

    func testStreakCountsBackFromTodayOrYesterday() {
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 9))!
        var s: [String: Double] = [day(-1, from: now): 400, day(-2, from: now): 300, day(-4, from: now): 999]
        // Today not done yet: the streak ending yesterday still counts.
        XCTAssertEqual(ReadingStats.currentStreak(seconds: s, goal: 5, now: now, calendar: cal), 2)
        s[day(0, from: now)] = 301
        XCTAssertEqual(ReadingStats.currentStreak(seconds: s, goal: 5, now: now, calendar: cal), 3)
        XCTAssertEqual(ReadingStats.currentStreak(seconds: [:], goal: 5, now: now, calendar: cal), 0)
    }

    func testFormat() {
        XCTAssertEqual(ReadingStats.format(0), "0:00")
        XCTAssertEqual(ReadingStats.format(247), "4:07")
        XCTAssertEqual(ReadingStats.format(3900), "1:05:00")
    }
}
