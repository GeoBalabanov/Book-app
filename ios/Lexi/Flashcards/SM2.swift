import Foundation

/// SM-2 spaced repetition (SuperMemo 2, Wozniak 1990), ported exactly from
/// web/js/srs/sm2.js. The four buttons map to SM-2 quality grades:
/// Again=1, Hard=3, Good=4, Easy=5.
///
///   EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)),  EF >= 1.3
///   q < 3  → repetitions = 0, card comes back in 10 minutes (same session)
///   q >= 3 → interval: 1 day, then 6 days, then round(previous * EF)
/// Two small, common adjustments: Hard grows the interval by only 1.2×, and
/// Easy gets a 1.3× bonus.
enum SM2 {
    enum Grade: String, CaseIterable, Identifiable {
        case again, hard, good, easy
        var id: String { rawValue }
        var quality: Int { switch self { case .again: 1; case .hard: 3; case .good: 4; case .easy: 5 } }
        var label: String { rawValue.capitalized }
    }

    struct State: Equatable {
        var ease: Double = 2.5
        var interval: Double = 0          // days
        var repetitions: Int = 0
        var lapses: Int = 0
        var due: Date
        var lastReviewed: Date? = nil
    }

    static let day: TimeInterval = 24 * 60 * 60
    static let relearnDelay: TimeInterval = 10 * 60

    /// Review state of a brand-new card: due immediately.
    static func newState(now: Date = .now) -> State { State(due: now) }

    /// Apply one review. Returns the new state.
    static func review(_ s: State, _ grade: Grade, now: Date = .now, calendar: Calendar = .current) -> State {
        let q = Double(grade.quality)
        var ease = s.ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
        ease = max(1.3, (ease * 1000).rounded() / 1000)

        if q < 3 {
            return State(ease: ease, interval: 0, repetitions: 0, lapses: s.lapses + 1,
                         due: now.addingTimeInterval(relearnDelay), lastReviewed: now)
        }

        var interval: Double
        if s.repetitions == 0 { interval = grade == .easy ? 4 : 1 }
        else if s.repetitions == 1 { interval = grade == .hard ? 3 : 6 }
        else if grade == .hard { interval = s.interval * 1.2 }
        else { interval = s.interval * ease }
        if grade == .easy && s.repetitions > 0 { interval *= 1.3 }
        interval = max(1, jsRound(interval))

        // Due at 4 a.m. local time, `interval` days from today.
        let due = startOfDay(now, calendar).addingTimeInterval(interval * day + 4 * 60 * 60)
        return State(ease: ease, interval: interval, repetitions: s.repetitions + 1, lapses: s.lapses,
                     due: due, lastReviewed: now)
    }

    /// Time until the card would be due after each grade (for button captions).
    static func previewIntervals(_ s: State, now: Date = .now) -> [Grade: TimeInterval] {
        Dictionary(uniqueKeysWithValues: Grade.allCases.map { ($0, review(s, $0, now: now).due.timeIntervalSince(now)) })
    }

    static func startOfDay(_ d: Date, _ calendar: Calendar = .current) -> Date { calendar.startOfDay(for: d) }

    static func endOfDay(_ d: Date, _ calendar: Calendar = .current) -> Date {
        startOfDay(d, calendar).addingTimeInterval(day - 0.001)
    }

    /// Cards due by the end of today (local time).
    static func isDueToday(_ due: Date, now: Date = .now) -> Bool { due <= endOfDay(now) }

    /// JavaScript's Math.round: halves round up (toward +∞).
    private static func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

    /// "10m", "4h", "6d", "2mo", "1.2y" — same as formatRelativeDue in web/js/util.js.
    static func formatRelative(_ interval: TimeInterval) -> String {
        if interval <= 0 { return "due" }
        let min = interval / 60
        if min < 60 { return "\(max(1, Int(jsRound(min))))m" }
        let hrs = min / 60
        if hrs < 24 { return "\(Int(jsRound(hrs)))h" }
        let days = hrs / 24
        if days < 30 { return "\(Int(jsRound(days)))d" }
        let months = days / 30
        if months < 12 { return "\(Int(jsRound(months)))mo" }
        return String(format: "%.1fy", days / 365)
    }
}

extension SavedWord {
    var reviewState: SM2.State {
        get { SM2.State(ease: ease, interval: interval, repetitions: repetitions, lapses: lapses, due: due, lastReviewed: lastReviewed) }
        set {
            ease = newValue.ease
            interval = newValue.interval
            repetitions = newValue.repetitions
            lapses = newValue.lapses
            due = newValue.due
            lastReviewed = newValue.lastReviewed
        }
    }

    var isNew: Bool { lastReviewed == nil }
}
